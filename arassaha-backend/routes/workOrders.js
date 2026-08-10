// İş Emri / Arıza Yönetimi modülüne ait tüm endpoint'ler.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const express = require('express');
const multer = require('multer');
const db = require('../database');
const { requireRole } = require('../middleware/auth');
const { createNotification } = require('../utils/notify');
const { classifyImageForDamage } = require('../utils/damageDetection');

const router = express.Router();

const VALID_STATUSES = ['acik', 'yolda', 'sahada', 'cozuldu'];
const VALID_PRIORITIES = ['acil', 'normal', 'dusuk'];

const UPLOADS_DIR = path.join(__dirname, '..', 'uploads');

// Fotoğraflar gerçekten bu klasöre yazılır ve server.js tarafından
// /uploads/<dosya> statik yolu üzerinden servis edilir (bkz. ARCHITECTURE.md Bölüm 11.2).
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, UPLOADS_DIR),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname) || '.jpg';
    const uniqueName = `${Date.now()}-${crypto.randomBytes(8).toString('hex')}${ext}`;
    cb(null, uniqueName);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    if (!file.mimetype.startsWith('image/')) {
      return cb(new Error('Yalnızca resim dosyaları yüklenebilir.'));
    }
    cb(null, true);
  },
});

// İş emri satırlarına atanan kullanıcının ad/rol bilgisini ve (varsa) bağlı
// ekipmanın QR kodu + tipini gömen ortak SELECT. `equipment_id` iş emri
// Modül 4'e gerçek bir FK ile bağlıdır (bkz. database.js); ekranda gösterilen
// `equipment_ref`/`equipment_type` ise bu FK üzerinden JOIN edilen ekipmanın
// alanlarıdır — iş emri detayından ekipmana giden (Modül 4'ün ekipman
// detayından iş emrine giden bağlantısının tersi) iki yönlü bağlantı için.
const SELECT_WORK_ORDER_WITH_USER = `
  SELECT
    wo.*,
    u.id AS assigned_user_id_join,
    u.name AS assigned_user_name,
    u.role AS assigned_user_role,
    e.qr_code AS equipment_qr_code,
    e.equipment_type AS equipment_type_join
  FROM work_orders wo
  LEFT JOIN users u ON u.id = wo.assigned_user_id
  LEFT JOIN equipment e ON e.id = wo.equipment_id
`;

function mapWorkOrderRow(row) {
  const {
    assigned_user_id_join,
    assigned_user_name,
    assigned_user_role,
    equipment_qr_code,
    equipment_type_join,
    ...workOrder
  } = row;
  return {
    ...workOrder,
    assigned_user: assigned_user_id_join
      ? { id: assigned_user_id_join, name: assigned_user_name, role: assigned_user_role }
      : null,
    // Modül 4 (Ekipman) ile geriye dönük uyumluluk: Flutter tarafı bu alanı
    // QR kodu göstermek için okur; `equipment_id` ise Ekipman Detayı'na
    // gitmek için ayrıca üstte (workOrder spread'i içinde) yer alır.
    equipment_ref: equipment_qr_code || '',
    equipment_type: equipment_type_join || null,
  };
}

// Hiyerarşik görünürlük kuralı (Modül 7 devamı — bkz. ARCHITECTURE.md):
// - teknisyen: yalnızca kendine atanan işler
// - dispeçer: yalnızca KENDİ EKİBİNDEKİ (supervisor_id = kendi id'si)
//   teknisyenlere atanan işler — başka bir dispeçerin ekibini görmez
// - yönetici: tüm işler (filtre yok)
// Bu, hem iş emri listesinde hem haritada hem dashboard özetinde aynı
// mantıkla uygulanır ki "amirin panelinde sadece kendi ekibi görünsün" kuralı
// her ekranda tutarlı olsun.
function applyVisibilityFilter(req, conditions, params) {
  if (req.user.role === 'teknisyen') {
    conditions.push('wo.assigned_user_id = ?');
    params.push(req.user.id);
  } else if (req.user.role === 'dispecer') {
    conditions.push('wo.assigned_user_id IN (SELECT id FROM users WHERE supervisor_id = ?)');
    params.push(req.user.id);
  }
  // yönetici: ek filtre yok, tümünü görür.
}

// GET /api/workorders?status=acik&q=trafo&sort=desc&limit=15&offset=0
// Tüm iş emirlerini listeler. `status` dışındaki dört parametre (q, sort,
// limit, offset) opsiyoneldir ve geriye dönük uyumluluk için BİLİNÇLİ olarak
// hiçbiri gönderilmediğinde davranış birebir eskisiyle aynıdır (tüm liste,
// created_at DESC) — İş Emirleri sekmesi/Harita/Dashboard gibi bu endpoint'i
// zaten kullanan hiçbir ekran bir şey değiştirmeden çalışmaya devam eder.
//
// Bu dört parametre "Tamamlanan İş Emirlerim" bölümü (Ana Sayfa, teknisyen
// rolü) için eklendi: bir teknisyenin tamamladığı iş emri sayısı zamanla
// büyüyebileceğinden TÜM geçmişi tek seferde çekmek yerine sunucu tarafında
// arama + sıralama + sayfalama yapılır (bkz. arassaha_flutter
// completed_work_orders_provider.dart).
//   - q: title/description/location_name/ekipman QR kodu/iş emri no üzerinde
//     LIKE araması (SQLite'ın varsayılan case-insensitive LIKE'ı — Türkçe
//     büyük/küçük harf dönüşümü için özel bir işlem yapılmaz, uygulamanın
//     diğer arama alanlarıyla aynı sınırlamayı taşır).
//   - sort: 'asc' | 'desc' — verilirse wo.updated_at'e göre sıralar (bir iş
//     emri 'cozuldu' durumuna geçtiğinde updated_at GERÇEK tamamlanma anını
//     taşır, bkz. PATCH /:id/status'taki last_maintenance_date güncelleme
//     yorumu); verilmezse eski varsayılan (created_at DESC) korunur.
//   - limit/offset: 1-100 arası; limit verilmezse sayfalama hiç uygulanmaz
//     (eski davranış). İstemci, dönen kayıt sayısı `limit`'e eşitse "daha
//     fazla kayıt olabilir" varsayar ve bir sonraki offset'i ister — ayrı bir
//     "toplam sayı" alanı YOK, çünkü bu, res.json'un HER ZAMAN düz bir dizi
//     döndürdüğü (ve mevcut tüm çağıranların bunu böyle beklediği) sözleşmeyi
//     bozmadan en basit çözüm.
// Rol bazlı görünürlük backend'de zorunlu kılınır (bkz. applyVisibilityFilter);
// Flutter tarafı ekstra bir şey göndermez, token'daki role/id üzerinden
// otomatik uygulanır — teknisyen `q`/`sort`/`limit` ne gönderirse göndersin,
// asla kendisine atanmamış bir iş emrini bu listede göremez.
router.get('/', (req, res) => {
  try {
    const { status, q, sort, limit, offset } = req.query;

    if (status && !VALID_STATUSES.includes(status)) {
      return res.status(400).json({
        error: `Geçersiz status değeri. Geçerli değerler: ${VALID_STATUSES.join(', ')}`,
      });
    }
    if (sort !== undefined && sort !== 'asc' && sort !== 'desc') {
      return res.status(400).json({ error: "Geçersiz sort değeri. 'asc' veya 'desc' olmalı." });
    }
    let limitNum;
    let offsetNum = 0;
    if (limit !== undefined) {
      limitNum = Number(limit);
      if (!Number.isInteger(limitNum) || limitNum < 1 || limitNum > 100) {
        return res.status(400).json({ error: 'Geçersiz limit değeri (1-100 arası olmalı).' });
      }
      if (offset !== undefined) {
        offsetNum = Number(offset);
        if (!Number.isInteger(offsetNum) || offsetNum < 0) {
          return res.status(400).json({ error: 'Geçersiz offset değeri.' });
        }
      }
    }

    const conditions = [];
    const params = [];
    if (status) {
      conditions.push('wo.status = ?');
      params.push(status);
    }
    if (q && q.trim()) {
      const term = `%${q.trim()}%`;
      conditions.push(
        '(wo.title LIKE ? OR wo.description LIKE ? OR wo.location_name LIKE ? OR e.qr_code LIKE ? OR CAST(wo.id AS TEXT) LIKE ?)'
      );
      params.push(term, term, term, term, term);
    }
    applyVisibilityFilter(req, conditions, params);
    const whereClause = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';

    const orderClause = sort
      ? `ORDER BY wo.updated_at ${sort === 'asc' ? 'ASC' : 'DESC'}`
      : 'ORDER BY wo.created_at DESC';

    let limitOffsetClause = '';
    if (limitNum !== undefined) {
      limitOffsetClause = 'LIMIT ? OFFSET ?';
      params.push(limitNum, offsetNum);
    }

    const rows = db
      .prepare(`${SELECT_WORK_ORDER_WITH_USER} ${whereClause} ${orderClause} ${limitOffsetClause}`)
      .all(...params);

    res.json(rows.map(mapWorkOrderRow));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'İş emirleri listelenirken bir hata oluştu.' });
  }
});

// POST /api/workorders
// Yeni iş emri oluşturur (yalnızca dispeçer/yönetici — bkz. requireRole).
// Body: { title, description, priority, assigned_user_id, equipment_id }
// Oluşturulan kaydın status'ü her zaman 'acik'tir.
//
// KONUM TUTARLILIĞI (bilinçli tasarım kararı): location_name/lat/lng/il/
// ilce/mahalle artık bu endpoint'e HİÇ parametre olarak alınmaz. Konumun
// TEK gerçek kaynağı (single source of truth) equipment kaydıdır — iş emri
// yalnızca equipment_id'yi taşır, konumu HER ZAMAN o kayıttan türetir/kopyalar.
// İstemciden (Flutter'dan) bir konum değeri gelse bile BİLEREK YOK SAYILIR:
// aksi halde (1) istemci tarafında bir hata/eski state, iş emrinin ekipmanla
// tutarsız görünmesine yol açabilirdi ("iş emri X mahallesinde ama bağlı
// olduğu trafo Y mahallesinde görünüyor" — tam da bu sorunu daha önce
// seed verisinde yaşadık, bkz. seed.js), (2) istemci taraflı manipülasyona
// karşı veri bütünlüğünü de garanti altına alır. Konumu değiştirmenin tek
// yolu, iş emrinin equipment_id'sini (dolayısıyla hangi ekipmana bağlı
// olduğunu) değiştirmektir.
router.post('/', requireRole('dispecer', 'yonetici'), (req, res) => {
  try {
    const { title, description, priority, assigned_user_id, equipment_id } = req.body;
    const assignedUserId = Number(assigned_user_id);
    const equipmentId = Number(equipment_id);

    if (!title || !title.trim()) {
      return res.status(400).json({ error: 'title alanı zorunludur.' });
    }
    if (!priority || !VALID_PRIORITIES.includes(priority)) {
      return res.status(400).json({
        error: `Geçersiz priority değeri. Geçerli değerler: ${VALID_PRIORITIES.join(', ')}`,
      });
    }
    if (!Number.isInteger(assignedUserId)) {
      return res.status(400).json({ error: 'assigned_user_id alanı zorunludur.' });
    }
    if (!equipment_id || !Number.isInteger(equipmentId)) {
      return res.status(400).json({ error: 'Bir ekipman seçilmeli.' });
    }

    const assignedUser = db
      .prepare('SELECT id, role, supervisor_id, is_active FROM users WHERE id = ?')
      .get(assignedUserId);
    if (!assignedUser || assignedUser.role !== 'teknisyen') {
      return res.status(400).json({ error: 'assigned_user_id geçerli bir teknisyene ait olmalı.' });
    }
    if (!assignedUser.is_active) {
      return res.status(400).json({ error: 'assigned_user_id pasif bir teknisyene ait olamaz.' });
    }
    // Dispeçer yalnızca KENDİ ekibindeki teknisyene iş emri atayabilir; başka
    // bir dispeçerin teknisyenine atama yapamaz. Yönetici için bu kısıtlama
    // yoktur (herhangi bir teknisyene atayabilir).
    if (req.user.role === 'dispecer' && assignedUser.supervisor_id !== req.user.id) {
      return res.status(403).json({ error: 'assigned_user_id sizin ekibinizdeki bir teknisyene ait olmalı.' });
    }

    const equipment = db.prepare('SELECT * FROM equipment WHERE id = ?').get(equipmentId);
    if (!equipment) {
      return res.status(404).json({ error: 'Seçilen ekipman bulunamadı.' });
    }

    const now = new Date().toISOString();
    const info = db
      .prepare(
        `INSERT INTO work_orders
           (title, description, status, priority, il, ilce, mahalle, location_name, lat, lng, assigned_user_id, equipment_id, created_at, updated_at)
         VALUES
           (@title, @description, 'acik', @priority, @il, @ilce, @mahalle, @location_name, @lat, @lng, @assigned_user_id, @equipment_id, @created_at, @updated_at)`
      )
      .run({
        title: title.trim(),
        description: description ? description.trim() : '',
        priority,
        // Konum, İSTEMCİDEN DEĞİL doğrudan equipment kaydından — bkz. yukarıdaki not.
        il: equipment.il,
        ilce: equipment.ilce,
        mahalle: equipment.mahalle,
        location_name: equipment.location_name,
        lat: equipment.lat,
        lng: equipment.lng,
        assigned_user_id: assignedUserId,
        equipment_id: equipmentId,
        created_at: now,
        updated_at: now,
      });

    const created = db.prepare(`${SELECT_WORK_ORDER_WITH_USER} WHERE wo.id = ?`).get(info.lastInsertRowid);

    // Bildirim Sistemi (Modül 6) — atanan teknisyene yeni iş emrini bildir.
    createNotification(
      assignedUserId,
      `Size yeni bir iş emri atandı: "${title.trim()}"`,
      'work_order',
      info.lastInsertRowid
    );

    res.status(201).json(mapWorkOrderRow(created));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'İş emri oluşturulurken bir hata oluştu.' });
  }
});

// GET /api/workorders/map?status=acik
// Harita ekranı için hafif alan seti döner: id, title, status, priority, lat, lng.
// (Bu route, ":id" route'undan ÖNCE tanımlanmalı; aksi halde Express "map" değerini
// bir id parametresi sanıp o route'a düşer.)
// lat/lng değeri olmayan kayıtlar haritada gösterilemeyeceği için sonuca dahil edilmez.
router.get('/map', (req, res) => {
  try {
    const { status } = req.query;

    if (status && !VALID_STATUSES.includes(status)) {
      return res.status(400).json({
        error: `Geçersiz status değeri. Geçerli değerler: ${VALID_STATUSES.join(', ')}`,
      });
    }

    // equipment_id dahil edilir ki harita bilgi balonunda (varsa) "Ekipman
    // Detayını Gör" bağlantısı gösterilebilsin (bkz. map_screen.dart).
    const conditions = ['lat IS NOT NULL', 'lng IS NOT NULL'];
    const params = [];
    if (status) {
      conditions.push('status = ?');
      params.push(status);
    }
    if (req.user.role === 'teknisyen') {
      conditions.push('assigned_user_id = ?');
      params.push(req.user.id);
    } else if (req.user.role === 'dispecer') {
      conditions.push('assigned_user_id IN (SELECT id FROM users WHERE supervisor_id = ?)');
      params.push(req.user.id);
    }

    const rows = db
      .prepare(
        `SELECT id, title, status, priority, lat, lng, equipment_id FROM work_orders WHERE ${conditions.join(' AND ')} ORDER BY id`
      )
      .all(...params);

    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Harita verileri alınırken bir hata oluştu.' });
  }
});

// GET /api/workorders/:id
// Tek bir iş emrinin detayını, atanan kişi ve ilişkili fotoğraflarıyla birlikte döner.
// Bu endpoint hangi kullanıcı/cihazdan çağrılırsa çağrılsın aynı kalıcı veriyi döner
// (örn. saha amiri kendi ekranından açtığında teknisyenin eklediği fotoğrafı görür).
router.get('/:id', (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz iş emri id değeri.' });
    }

    const row = db.prepare(`${SELECT_WORK_ORDER_WITH_USER} WHERE wo.id = ?`).get(id);
    if (!row) {
      return res.status(404).json({ error: 'İş emri bulunamadı.' });
    }

    const photos = db
      .prepare('SELECT * FROM work_order_photos WHERE work_order_id = ? ORDER BY created_at DESC')
      .all(id);

    res.json({ ...mapWorkOrderRow(row), photos });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'İş emri detayı alınırken bir hata oluştu.' });
  }
});

// PATCH /api/workorders/:id/status — yalnızca teknisyen/dispeçer.
// Body: { "status": "yolda", "client_action_id"?: "<uuid>" }
// Yönetici bu işi SAHADA yapmadığı için durumu bizzat değiştiremez; onun
// rolü yalnızca takip/raporlamadır (Flutter tarafında da bu ekranda "Durum
// Güncelle" aksiyonu yöneticiye hiç gösterilmez — bkz. work_order_detail_screen.dart).
//
// İDEMPOTENCY (Modül 17 — Çevrimdışı Yazma Kuyruğu): client_action_id yalnızca
// çevrimdışı kuyruktan senkronize edilen istekler tarafından gönderilir (bkz.
// offline_queue_service.dart); normal, çevrimiçi güncellemeler bu alanı hiç
// göndermez ve aşağıdaki kontrol atlanır. Bir client_action_id daha önce
// işlenmişse (processed_client_actions'da varsa), işlem TEKRAR UYGULANMAZ —
// ilk seferki kaydedilmiş yanıt aynen döner. Bu, "kuyruktaki işlem ağ hatası
// nedeniyle iki kez gönderilirse aynı durum güncellemesi veritabanına iki kez
// yazılır (örn. iki bildirim gider)" riskini önler.
router.patch('/:id/status', requireRole('teknisyen', 'dispecer'), (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz iş emri id değeri.' });
    }

    const { status, client_action_id: clientActionId } = req.body;
    if (!status || !VALID_STATUSES.includes(status)) {
      return res.status(400).json({
        error: `Geçersiz status değeri. Geçerli değerler: ${VALID_STATUSES.join(', ')}`,
      });
    }

    if (clientActionId) {
      const alreadyProcessed = db
        .prepare('SELECT response_json FROM processed_client_actions WHERE client_action_id = ?')
        .get(clientActionId);
      if (alreadyProcessed) {
        return res.status(200).json(JSON.parse(alreadyProcessed.response_json));
      }
    }

    const existing = db.prepare('SELECT id, equipment_id FROM work_orders WHERE id = ?').get(id);
    if (!existing) {
      return res.status(404).json({ error: 'İş emri bulunamadı.' });
    }

    const updatedAt = new Date().toISOString();
    db.prepare('UPDATE work_orders SET status = ?, updated_at = ? WHERE id = ?').run(status, updatedAt, id);

    // Bir arızaya sahada müdahale edip 'cozuldu' durumuna getirmek, fiilen bir
    // bakım/onarım işlemidir — bu yüzden bağlı ekipmanın last_maintenance_date'i
    // bu tarihe güncellenir. Önceden bu alan yalnızca seed sırasında bir kez
    // yazılıp bir daha hiç değişmiyordu; Arıza Risk Tahmini (Modül 9) de
    // "son bakımdan bu yana geçen süre" özelliğini bu alandan türettiği için
    // (bkz. routes/risk.js calculateMonthsSinceMaintenance) bu güncelleme
    // olmadan risk skoru, gerçekte çözülmüş arızalardan habersiz kalıyordu.
    //
    // TAM zaman damgası (yalnızca YYYY-MM-DD DEĞİL) yazılır: seed.js'teki
    // diğer last_maintenance_date değerleri (yıllar/aylar önceki bakımlar)
    // yalnızca tarih hassasiyetinde yeterliyken, BURADA gerçek zamanlı bir
    // olay kaydediliyor. Yalnızca tarih (saat 00:00 kabul edilerek) yazılırsa
    // Flutter'daki formatRelativeTime (bkz. widgets/work_order_card.dart),
    // günün başlangıcından bu yana geçen süreyi hesaplar — örn. saat 10:00'da
    // çözülen bir arıza "Az önce" yerine yanıltıcı biçimde "10 saat önce"
    // gösterilirdi.
    if (status === 'cozuldu' && existing.equipment_id) {
      db.prepare('UPDATE equipment SET last_maintenance_date = ? WHERE id = ?').run(
        updatedAt,
        existing.equipment_id
      );
    }

    const updated = db.prepare(`${SELECT_WORK_ORDER_WITH_USER} WHERE wo.id = ?`).get(id);
    const responseBody = mapWorkOrderRow(updated);

    if (clientActionId) {
      db.prepare(
        'INSERT INTO processed_client_actions (client_action_id, response_json, created_at) VALUES (?, ?, ?)'
      ).run(clientActionId, JSON.stringify(responseBody), updatedAt);
    }

    res.json(responseBody);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'İş emri durumu güncellenirken bir hata oluştu.' });
  }
});

// PATCH /api/workorders/:id/assign — yalnızca dispeçer/yönetici.
// Body: { assigned_user_id }
// Var olan, açık bir iş emrinin atanan kişisini değiştirir (Modül 7'de
// yalnızca OLUŞTURMA sırasında atama yapılıyordu — bu, sonradan yeniden
// atama akışını tamamlar). Aynı doğrulamalar POST / ile birebir aynıdır:
// hedef GERÇEKTEN bir teknisyen olmalı, AKTİF olmalı (pasif bir teknisyene
// yeni iş yüklenmez) ve dispeçer yalnızca KENDİ ekibine atayabilir.
router.patch('/:id/assign', requireRole('dispecer', 'yonetici'), (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz iş emri id değeri.' });
    }

    const existing = db.prepare('SELECT id FROM work_orders WHERE id = ?').get(id);
    if (!existing) {
      return res.status(404).json({ error: 'İş emri bulunamadı.' });
    }

    const assignedUserId = Number(req.body.assigned_user_id);
    if (!Number.isInteger(assignedUserId)) {
      return res.status(400).json({ error: 'assigned_user_id alanı zorunludur.' });
    }

    const assignedUser = db
      .prepare('SELECT id, role, supervisor_id, is_active FROM users WHERE id = ?')
      .get(assignedUserId);
    if (!assignedUser || assignedUser.role !== 'teknisyen') {
      return res.status(400).json({ error: 'assigned_user_id geçerli bir teknisyene ait olmalı.' });
    }
    if (!assignedUser.is_active) {
      return res.status(400).json({ error: 'assigned_user_id pasif bir teknisyene ait olamaz.' });
    }
    if (req.user.role === 'dispecer' && assignedUser.supervisor_id !== req.user.id) {
      return res.status(403).json({ error: 'assigned_user_id sizin ekibinizdeki bir teknisyene ait olmalı.' });
    }

    const updatedAt = new Date().toISOString();
    db.prepare('UPDATE work_orders SET assigned_user_id = ?, updated_at = ? WHERE id = ?').run(
      assignedUserId,
      updatedAt,
      id
    );

    const updated = db.prepare(`${SELECT_WORK_ORDER_WITH_USER} WHERE wo.id = ?`).get(id);

    // Bildirim Sistemi (Modül 6) — yeniden atanan teknisyene bildir.
    createNotification(
      assignedUserId,
      `Size yeni bir iş emri atandı: "${updated.title}"`,
      'work_order',
      id
    );

    res.json(mapWorkOrderRow(updated));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'İş emri ataması değiştirilirken bir hata oluştu.' });
  }
});

// POST /api/workorders/:id/photos
// multipart/form-data, dosya alanı adı: "photo"
// Dosya gerçekten backend'in diskindeki uploads/ klasörüne yazılır ve
// work_order_photos.photo_path alanına /uploads/<dosya> statik URL'i kaydedilir.
// Böylece başka bir cihazdan bağlanan kullanıcı (örn. saha amiri) bu fotoğrafı
// GET /api/workorders/:id üzerinden gerçekten görüntüleyebilir.
router.post('/:id/photos', (req, res) => {
  upload.single('photo')(req, res, async (err) => {
    if (err) {
      return res.status(400).json({ error: err.message || 'Fotoğraf yüklenirken bir hata oluştu.' });
    }

    try {
      const id = Number(req.params.id);
      if (!Number.isInteger(id)) {
        return res.status(400).json({ error: 'Geçersiz iş emri id değeri.' });
      }

      if (!req.file) {
        return res.status(400).json({ error: 'photo alanı (dosya) zorunludur.' });
      }

      const workOrder = db.prepare('SELECT id FROM work_orders WHERE id = ?').get(id);
      if (!workOrder) {
        return res.status(404).json({ error: 'İş emri bulunamadı.' });
      }

      const photoPath = `/uploads/${req.file.filename}`;
      const createdAt = new Date().toISOString();

      // Görüntü Tabanlı Hasar Tespiti (Modül 15) — routes/isg.js POST / ile
      // AYNI desen: fotoğraf diske yazıldıktan hemen sonra, INSERT'ten önce
      // çağrılır; ML servisi kapalıysa/hata dönerse cv_* alanları null kalır,
      // fotoğraf eklenmesi hiçbir şekilde engellenmez/bloklanmaz.
      const photoBuffer = fs.readFileSync(req.file.path);
      const { cv_is_damaged, cv_damage_probability } = await classifyImageForDamage(
        photoBuffer,
        req.file.originalname,
        req.file.mimetype
      );

      const info = db
        .prepare(
          `INSERT INTO work_order_photos (work_order_id, photo_path, created_at, cv_is_damaged, cv_damage_probability)
           VALUES (?, ?, ?, ?, ?)`
        )
        .run(id, photoPath, createdAt, cv_is_damaged, cv_damage_probability);

      const photo = db.prepare('SELECT * FROM work_order_photos WHERE id = ?').get(info.lastInsertRowid);
      res.status(201).json(photo);
    } catch (innerErr) {
      console.error(innerErr);
      res.status(500).json({ error: 'Fotoğraf eklenirken bir hata oluştu.' });
    }
  });
});

module.exports = router;
// AI Asistan (Modül 16) — services/assistantIntents.js kendi enum kopyasını
// tutmak yerine buradaki TEK gerçek kaynağı içe aktarır (bkz. risk.js'teki
// module.exports.refreshAllRiskScores ile AYNI "router objesine ek statik
// alan ekleme" deseni — routing davranışını etkilemez).
module.exports.VALID_STATUSES = VALID_STATUSES;
module.exports.VALID_PRIORITIES = VALID_PRIORITIES;
