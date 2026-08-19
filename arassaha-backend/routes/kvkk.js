// KVKK (6698 sayılı Kişisel Verilerin Korunması Kanunu) Uyum Modülü.
//
// KAVRAMSAL ÇERÇEVE — SİLME mi, ANONİMLEŞTİRME mi? (KVKK madde 7)
// Bu modülde İKİ farklı veri kategorisine İKİ farklı işlem uygulanır:
//   1) Kişisel KİMLİK bilgileri (ad-soyad, telefon, e-posta, profil fotoğrafı)
//      → GERÇEKTEN anonimleştirilir/temizlenir (bkz. anonymizeUser()).
//   2) OPERASYONEL kayıtlar (iş emirleri, İSG bildirimleri) → SİLİNMEZ. Bu
//      kayıtlar iş sağlığı/güvenliği ve denetim amaçlı saklanması
//      gerekebilecek kayıtlardır — "ne olmuş, ne zaman olmuş, hangi
//      ekipmanda" bilgisinin kaybolması hem operasyonel hem yasal bir
//      kayıptır. Yalnızca o kayıtların GÖRSEL/kişisel verisi (fotoğraflar)
//      diskten silinir; "kim yaptı" FK'si (isg_reports.reported_by_user_id,
//      work_orders.assigned_user_id) TEKNİK olarak kalır — ama artık
//      anonimleştirilmiş users kaydına işaret ettiği için sorgulandığında
//      gerçek isim değil "Silinmiş Kullanıcı #<id>" görünür.
const fs = require('fs');
const path = require('path');
const express = require('express');
const db = require('../database');
const { requireRole } = require('../middleware/auth');

const router = express.Router();

const VALID_REQUEST_TYPES = ['profil_fotografi_sil', 'tum_kisisel_verilerimi_sil'];
const UPLOADS_ROOT = path.resolve(__dirname, '..', 'uploads');

// [TASLAK] Aydınlatma metni — kaynağı Görev talimatındaki taslak. Hukuk/KVKK
// uyum birimi onayına kadar bu metin RESMİ olarak kullanılmamalıdır; bu uyarı
// hem burada (draft_warning alanı) hem de Flutter tarafında (bkz.
// screens/kvkk/my_data_screen.dart) korunmalı, kaldırılmamalıdır.
const AYDINLATMA_METNI = `KİŞİSEL VERİLERİN İŞLENMESİNE İLİŞKİN AYDINLATMA METNİ (TASLAK)

Aras Elektrik Dağıtım A.Ş. ("Şirket") olarak, ArasSaha uygulaması kapsamında
işlediğimiz kişisel verileriniz hakkında 6698 sayılı Kişisel Verilerin
Korunması Kanunu ("KVKK") uyarınca sizi bilgilendirmek isteriz.

1. İŞLENEN KİŞİSEL VERİLER
   - Kimlik bilgileri: ad-soyad, sicil numarası
   - İletişim bilgileri: telefon, e-posta
   - Görsel veriler: profil fotoğrafı, iş emri/İSG bildirimi fotoğrafları
   - Konum verileri: İSG bildirimi ve saha operasyonu konum bilgileri
   - İşlem güvenliği bilgileri: giriş kayıtları, IP adresi

2. İŞLEME AMAÇLARI
   - Saha operasyonlarının (arıza/bakım) yürütülmesi ve takibi
   - İş sağlığı ve güvenliği süreçlerinin yönetimi
   - Şirket içi yetkilendirme ve erişim kontrolü
   - Yasal yükümlülüklerin yerine getirilmesi

3. VERİ SAKLAMA SÜRELERİ (TASLAK — HUKUK BİRİMİ ONAYI GEREKİR)
   - Kimlik/iletişim bilgileri: istihdam ilişkisi süresince + [X] yıl
   - İSG bildirimleri: [yasal asgari süre — İK/hukuk birimi belirleyecek]
   - Konum verileri: [X] ay

4. HAKLARINIZ (KVKK Madde 11)
   Kişisel verilerinizin işlenip işlenmediğini öğrenme, işlenmişse buna ilişkin
   bilgi talep etme, işlenme amacını öğrenme, yurt içi/yurt dışında aktarıldığı
   üçüncü kişileri bilme, eksik/yanlış işlenmişse düzeltilmesini isteme, silinmesini
   veya yok edilmesini isteme, düzeltme/silme işlemlerinin aktarıldığı üçüncü
   kişilere bildirilmesini isteme, işlenen verilerin münhasıran otomatik sistemler
   vasıtasıyla analiz edilmesi suretiyle aleyhinize bir sonucun ortaya çıkmasına
   itiraz etme, kanuna aykırı işleme nedeniyle zarara uğramanız hâlinde zararın
   giderilmesini talep etme haklarına sahipsiniz.

5. BAŞVURU
   Yukarıdaki haklarınızı kullanmak için uygulama içindeki "Veri Silme Talebi"
   ekranını kullanabilir veya [Şirket KVKK başvuru kanalı] üzerinden bize
   ulaşabilirsiniz.

[BU METİN BİR TASLAKTIR, ŞİRKETİN HUKUK/KVKK UYUM BİRİMİ TARAFINDAN
GÖZDEN GEÇİRİLİP ONAYLANMADAN RESMİ OLARAK KULLANILMAMALIDIR.]`;

const DRAFT_WARNING =
  'BU METİN BİR TASLAKTIR, ŞİRKETİN HUKUK/KVKK UYUM BİRİMİ TARAFINDAN GÖZDEN GEÇİRİLİP ONAYLANMADAN RESMİ OLARAK KULLANILMAMALIDIR.';

// photo_path DB'de her zaman "/uploads/<klasör>/<dosya>" biçiminde saklanır
// (bkz. users.js POST /:id/photo, isg.js POST /, workOrders.js POST /:id/photos).
// routes/uploads.js'teki AYNI path traversal savunması (path.basename +
// UPLOADS_ROOT içinde kalma kontrolü) burada da uygulanır — photo_path DB
// kökenli olsa da saldırgan-bitişik bir değer olarak ele alınır.
function safeUnlinkPhoto(photoPath) {
  if (!photoPath) return;
  const relative = String(photoPath).replace(/^\/?uploads\//, '');
  const [folder, ...rest] = relative.split('/');
  const filename = path.basename(rest.join('/'));
  if (!folder || !filename) return;

  const resolvedPath = path.resolve(UPLOADS_ROOT, folder, filename);
  if (!resolvedPath.startsWith(UPLOADS_ROOT)) return;

  try {
    fs.unlinkSync(resolvedPath);
  } catch (err) {
    // ENOENT (dosya zaten yok) sessizce yutulur — anonimleştirmenin GERÇEK
    // amacı (DB'de artık referans kalmaması) zaten transaction'da sağlandı;
    // dosyanın kendisi başka bir sebeple zaten silinmiş olabilir.
    if (err.code !== 'ENOENT') {
      console.error(`KVKK: dosya silinemedi (${resolvedPath}):`, err);
    }
  }
}

// GET /api/kvkk/aydinlatma-metni — giriş yapmış herkes. Sabit metni backend'de
// tutmak (Flutter'da hardcode etmek yerine) ileride hukuk birimi onayı sonrası
// güncelleme yapıldığında uygulama sürümünü güncellemeye gerek bırakmaz.
router.get('/aydinlatma-metni', (req, res) => {
  res.json({
    title: 'Kişisel Verilerin İşlenmesine İlişkin Aydınlatma Metni',
    is_draft: true,
    draft_warning: DRAFT_WARNING,
    content: AYDINLATMA_METNI,
  });
});

// GET /api/kvkk/my-data-summary — giriş yapmış herkes, KENDİ verisinin
// SAYISAL özeti ("sistemde benim hakkımda ne var?"). Tüm iş emri/İSG
// detaylarını dökmek gerekmiyor — bkz. görev talimatı.
router.get('/my-data-summary', (req, res) => {
  try {
    const user = db
      .prepare('SELECT name, sicil_no, phone, email, photo_path FROM users WHERE id = ?')
      .get(req.user.id);
    if (!user) {
      return res.status(404).json({ error: 'Kullanıcı bulunamadı.' });
    }

    const submittedIsgReportsCount = db
      .prepare('SELECT COUNT(*) AS c FROM isg_reports WHERE reported_by_user_id = ?')
      .get(req.user.id).c;
    const assignedWorkOrdersCount = db
      .prepare('SELECT COUNT(*) AS c FROM work_orders WHERE assigned_user_id = ?')
      .get(req.user.id).c;

    // work_order_photos'un kendi bir "kim yükledi" sütunu YOK (bkz.
    // database.js şeması) — bu yüzden burada da, anonimleştirme akışıyla
    // (approve endpoint'i, aşağıda) TUTARLI bir yorumla, kullanıcıya ATANMIŞ
    // iş emirlerindeki fotoğraflar "kendi fotoğrafları" sayılır.
    const isgPhotoCount = db
      .prepare('SELECT COUNT(*) AS c FROM isg_reports WHERE reported_by_user_id = ? AND photo_path IS NOT NULL')
      .get(req.user.id).c;
    const workOrderPhotoCount = db
      .prepare(
        `SELECT COUNT(*) AS c FROM work_order_photos wop
         JOIN work_orders wo ON wo.id = wop.work_order_id
         WHERE wo.assigned_user_id = ?`
      )
      .get(req.user.id).c;

    res.json({
      profile: {
        name: user.name,
        sicil_no: user.sicil_no,
        phone: user.phone,
        email: user.email,
        has_photo: Boolean(user.photo_path),
      },
      submitted_isg_reports_count: submittedIsgReportsCount,
      assigned_work_orders_count: assignedWorkOrdersCount,
      uploaded_photos_count: (user.photo_path ? 1 : 0) + isgPhotoCount + workOrderPhotoCount,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Kişisel veri özeti alınırken bir hata oluştu.' });
  }
});

// POST /api/kvkk/deletion-requests — giriş yapmış herkes. Yalnızca KENDİ
// adına talep açabilir; user_id İSTEMCİDEN ALINMAZ (isg.js'teki
// reported_by_user_id deseniyle AYNI ilke — req.user.id, JWT'den gelir).
router.post('/deletion-requests', (req, res) => {
  try {
    const { request_type, reason } = req.body;
    if (!request_type || !VALID_REQUEST_TYPES.includes(request_type)) {
      return res.status(400).json({
        error: `Geçersiz request_type değeri. Geçerli değerler: ${VALID_REQUEST_TYPES.join(', ')}`,
      });
    }

    const info = db
      .prepare(
        `INSERT INTO data_deletion_requests (user_id, request_type, reason, status, created_at)
         VALUES (?, ?, ?, 'beklemede', ?)`
      )
      .run(req.user.id, request_type, reason ? String(reason).trim() : null, new Date().toISOString());

    const created = db.prepare('SELECT * FROM data_deletion_requests WHERE id = ?').get(info.lastInsertRowid);
    res.status(201).json(created);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Silme talebi oluşturulurken bir hata oluştu.' });
  }
});

// GET /api/kvkk/deletion-requests — yalnızca yönetici. Tüm talepler (durum
// ayrımı yok — panel Flutter tarafında filtrelenir/gruplanır).
router.get('/deletion-requests', requireRole('yonetici'), (req, res) => {
  try {
    const rows = db
      .prepare(
        `SELECT
           ddr.*,
           u.name AS user_name, u.sicil_no AS user_sicil_no,
           rv.name AS reviewed_by_name
         FROM data_deletion_requests ddr
         JOIN users u ON u.id = ddr.user_id
         LEFT JOIN users rv ON rv.id = ddr.reviewed_by_user_id
         ORDER BY ddr.created_at DESC`
      )
      .all();

    res.json(
      rows.map((row) => {
        const { user_name, user_sicil_no, reviewed_by_name, ...request } = row;
        return {
          ...request,
          user: { id: request.user_id, name: user_name, sicil_no: user_sicil_no },
          reviewed_by: request.reviewed_by_user_id
            ? { id: request.reviewed_by_user_id, name: reviewed_by_name }
            : null,
        };
      })
    );
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Silme talepleri listelenirken bir hata oluştu.' });
  }
});

// PATCH /api/kvkk/deletion-requests/:id/approve — yalnızca yönetici. Talebi
// onaylar VE anonimleştirmeyi AYNI istekte, senkron olarak tetikler (ayrı bir
// arka plan işi/kuyruk YOK — bu bir staj/prototip projesi kapsamında
// gereksiz karmaşıklık katardı, iş hacmi de bunu gerektirmiyor).
router.patch('/deletion-requests/:id/approve', requireRole('yonetici'), (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz talep id değeri.' });
    }

    const request = db.prepare('SELECT * FROM data_deletion_requests WHERE id = ?').get(id);
    if (!request) {
      return res.status(404).json({ error: 'Silme talebi bulunamadı.' });
    }
    if (request.status !== 'beklemede') {
      return res.status(400).json({
        error: `Bu talep zaten işlenmiş (durum: ${request.status}); tekrar onaylanamaz.`,
      });
    }

    const targetUser = db.prepare('SELECT * FROM users WHERE id = ?').get(request.user_id);
    if (!targetUser) {
      return res.status(404).json({ error: 'Talebe ait kullanıcı bulunamadı.' });
    }

    // GÜVENLİK: routes/users.js DELETE /:id'deki "bir yönetici kendi hesabını
    // pasifleştiremez" kuralıyla AYNI gerekçe — 'tum_kisisel_verilerimi_sil'
    // onayı is_active=0 sonucu doğurur; bir yöneticinin KENDİ talebini
    // onaylayıp kendini (ve tek yöneticiyse tüm onay yetkisini) sistemden
    // dışlaması engellenir.
    if (request.request_type === 'tum_kisisel_verilerimi_sil' && targetUser.id === req.user.id) {
      return res.status(400).json({ error: 'Kendi hesabınıza ait bir silme talebini onaylayamazsınız.' });
    }

    const now = new Date().toISOString();
    // Transaction COMMIT'ten SONRA diskten silinecek dosya yolları — bkz.
    // routes/materials.js'teki AYNI disiplin (dosya yolları toplanır, gerçek
    // fs.unlinkSync çağrıları COMMIT başarılı olduktan SONRA yapılır). Böylece
    // transaction geri alınırsa (ROLLBACK) diskte gerçekten silinmiş ama DB'de
    // hâlâ referans verilen bir dosya durumu ASLA oluşmaz.
    const filesToDelete = [];

    db.exec('BEGIN');
    try {
      if (request.request_type === 'profil_fotografi_sil') {
        if (targetUser.photo_path) filesToDelete.push(targetUser.photo_path);
        db.prepare('UPDATE users SET photo_path = NULL WHERE id = ?').run(targetUser.id);
      } else if (request.request_type === 'tum_kisisel_verilerimi_sil') {
        if (targetUser.photo_path) filesToDelete.push(targetUser.photo_path);

        // İSG bildirimleri: KAYIT kalır (reported_by_user_id DEĞİŞMEZ),
        // yalnızca fotoğraf temizlenir — bkz. dosya başı not.
        const isgPhotos = db
          .prepare('SELECT photo_path FROM isg_reports WHERE reported_by_user_id = ? AND photo_path IS NOT NULL')
          .all(targetUser.id);
        filesToDelete.push(...isgPhotos.map((r) => r.photo_path));
        db.prepare('UPDATE isg_reports SET photo_path = NULL WHERE reported_by_user_id = ?').run(targetUser.id);

        // İş emri fotoğrafları: work_order_photos'un kendi bir uploader
        // sütunu olmadığı için (bkz. database.js), "kullanıcının fotoğrafları"
        // burada kullanıcıya ATANMIŞ iş emirlerinin fotoğrafları olarak ele
        // alınır — GET /my-data-summary'deki SAYIMLA TUTARLI, şemanın izin
        // verdiği en doğru eşleme. work_orders KAYDININ KENDİSİ silinmez.
        const workOrderPhotos = db
          .prepare(
            `SELECT wop.photo_path FROM work_order_photos wop
             JOIN work_orders wo ON wo.id = wop.work_order_id
             WHERE wo.assigned_user_id = ? AND wop.photo_path IS NOT NULL`
          )
          .all(targetUser.id);
        filesToDelete.push(...workOrderPhotos.map((r) => r.photo_path));
        db.prepare(
          `UPDATE work_order_photos SET photo_path = NULL
           WHERE photo_path IS NOT NULL
             AND work_order_id IN (SELECT id FROM work_orders WHERE assigned_user_id = ?)`
        ).run(targetUser.id);

        // Kimlik bilgileri burada GERÇEKTEN anonimleştirilir. sicil_no ve
        // password_hash BİLİNÇLİ olarak DOKUNULMAZ: is_active=0 zaten girişi
        // engeller (bkz. middleware/auth ve login akışı — "pasif kullanıcı"
        // kontrolü), sicil_no'yu silmek geçmiş kayıtlardaki dolaylı
        // referansları (örn. raporlarda sicil no ile arama) bozardı.
        db.prepare(
          `UPDATE users SET name = ?, phone = NULL, email = NULL, photo_path = NULL, is_active = 0 WHERE id = ?`
        ).run(`Silinmiş Kullanıcı #${targetUser.id}`, targetUser.id);
      } else {
        // POST /deletion-requests zaten geçersiz bir request_type'ı reddeder;
        // buraya normalde asla ulaşılmaz — savunma amaçlı.
        throw new Error(`Bilinmeyen request_type: ${request.request_type}`);
      }

      db.prepare(
        `UPDATE data_deletion_requests
         SET status = 'tamamlandi', reviewer_note = ?, reviewed_by_user_id = ?, reviewed_at = ?, completed_at = ?
         WHERE id = ?`
      ).run(req.body.reviewer_note ? String(req.body.reviewer_note).trim() : null, req.user.id, now, now, id);

      db.exec('COMMIT');
    } catch (txErr) {
      db.exec('ROLLBACK');
      throw txErr;
    }

    for (const photoPath of filesToDelete) {
      safeUnlinkPhoto(photoPath);
    }

    const updated = db.prepare('SELECT * FROM data_deletion_requests WHERE id = ?').get(id);
    res.json(updated);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Silme talebi onaylanırken bir hata oluştu.' });
  }
});

// PATCH /api/kvkk/deletion-requests/:id/reject — yalnızca yönetici.
// reviewer_note (red gerekçesi) ZORUNLUDUR — kullanıcının "neden reddedildi"
// sorusuna her zaman somut bir cevabı olmalı (bkz. görev talimatı).
router.patch('/deletion-requests/:id/reject', requireRole('yonetici'), (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz talep id değeri.' });
    }

    const { reviewer_note } = req.body;
    if (!reviewer_note || typeof reviewer_note !== 'string' || !reviewer_note.trim()) {
      return res.status(400).json({ error: 'reviewer_note (red gerekçesi) zorunludur.' });
    }

    const request = db.prepare('SELECT * FROM data_deletion_requests WHERE id = ?').get(id);
    if (!request) {
      return res.status(404).json({ error: 'Silme talebi bulunamadı.' });
    }
    if (request.status !== 'beklemede') {
      return res.status(400).json({
        error: `Bu talep zaten işlenmiş (durum: ${request.status}); tekrar reddedilemez.`,
      });
    }

    const now = new Date().toISOString();
    db.prepare(
      `UPDATE data_deletion_requests
       SET status = 'reddedildi', reviewer_note = ?, reviewed_by_user_id = ?, reviewed_at = ?
       WHERE id = ?`
    ).run(reviewer_note.trim(), req.user.id, now, id);

    const updated = db.prepare('SELECT * FROM data_deletion_requests WHERE id = ?').get(id);
    res.json(updated);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Silme talebi reddedilirken bir hata oluştu.' });
  }
});

module.exports = router;
