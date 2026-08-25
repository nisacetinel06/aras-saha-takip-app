// Kişiler / Profil / Kullanıcı Yönetimi modüllerine ait endpoint'ler.
// "Kişiler" listesi hiçbir zaman kodda sabit tutulmaz; her zaman bu route üzerinden
// gerçek `users` tablosundan okunur (bkz. ARCHITECTURE.md Bölüm 11.1).
const path = require('path');
const crypto = require('crypto');
const express = require('express');
const multer = require('multer');
const bcrypt = require('bcrypt');
const db = require('../database');
const { requireRole } = require('../middleware/auth');
const validateImageContent = require('../middleware/validateImageContent');

const router = express.Router();

const VALID_ROLES = ['teknisyen', 'dispecer', 'yonetici'];

const PROFILE_UPLOADS_DIR = path.join(__dirname, '..', 'uploads', 'profiles');

// Profil fotoğrafları gerçekten uploads/profiles/ klasörüne yazılır ve
// server.js tarafından /uploads statik yolu üzerinden servis edilir (bkz.
// work_orders/:id/photos ve isg-reports ile aynı, kanıtlanmış desen). Dosya
// adı user_id + zaman damgası olarak istenmişti; bu hem çakışmayı önler hem
// de hangi kullanıcıya ait olduğunu dosya adından okunabilir kılar.
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, PROFILE_UPLOADS_DIR),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname) || '.jpg';
    cb(null, `${req.params.id}-${Date.now()}${ext}`);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 5 * 1024 * 1024 }, // 5 MB
  fileFilter: (req, file, cb) => {
    if (!file.mimetype.startsWith('image/')) {
      return cb(new Error('Yalnızca resim dosyaları yüklenebilir.'));
    }
    cb(null, true);
  },
});

// "Kişi seçici" (iş emri atama, İSG bildiren personel vb.) alanları — tüm
// rollerin erişebildiği hafif SELECT.
const PICKER_FIELDS = 'id, name, role, sicil_no';

// Kullanıcı Yönetimi paneli / Profil ekranı için tam alan seti. password_hash
// KESİNLİKLE dönülmez.
// totp_enabled DAHİL (Ayarlar ekranının "2FA etkin mi?" durumunu bilmesi
// için — bkz. routes/twoFactor.js) ama totp_secret ASLA DAHİL DEĞİL — bu
// alan hiçbir response'ta (bu dahil) dışarı sızmaz.
const FULL_FIELDS = 'id, name, role, sicil_no, phone, email, il, photo_path, is_active, supervisor_id, totp_enabled';

function mapFullUser(row) {
  if (!row) return row;
  const { is_active, totp_enabled, ...rest } = row;
  return { ...rest, is_active: Boolean(is_active), totp_enabled: Boolean(totp_enabled) };
}

// Kullanıcı Yönetimi işlem geçmişi (hesap verebilirlik) — device_action_logs
// ile AYNI desen. `performedByUserId`, isteği atan yöneticinin token'daki
// id'sidir; log'a okunabilir olması için o anki ADI yazılır (isim daha sonra
// değişse bile geçmiş kaydı o anki performans/kişiyi doğru yansıtsın diye).
function logUserAction(targetUserId, actionType, performedByUserId) {
  const performer = db.prepare('SELECT name FROM users WHERE id = ?').get(performedByUserId);
  db.prepare(
    'INSERT INTO user_action_logs (target_user_id, action_type, performed_by, created_at) VALUES (?, ?, ?, ?)'
  ).run(targetUserId, actionType, performer ? performer.name : 'Bilinmiyor', new Date().toISOString());
}

// Yönetici panelinden teknisyen<->dispeçer ilişkisini yönetmek (atama,
// değiştirme, kaldırma) için ortak doğrulama. `rawValue`:
// - undefined  -> çağıran yer bu alanı hiç göndermemiş (değiştirme yok)
// - null       -> teknisyenin dispeçerini KALDIR (bkz. PATCH /:id)
// - bir id     -> o id'nin GERÇEKTEN bir dispeçere ait olduğu doğrulanır
function resolveSupervisorId(rawValue) {
  if (rawValue === null) return { ok: true, value: null };

  const id = Number(rawValue);
  if (!Number.isInteger(id)) {
    return { ok: false, error: 'Geçersiz supervisor_id değeri.' };
  }
  const supervisor = db.prepare('SELECT id, role FROM users WHERE id = ?').get(id);
  if (!supervisor || supervisor.role !== 'dispecer') {
    return { ok: false, error: 'supervisor_id geçerli bir dispeçere ait olmalı.' };
  }
  return { ok: true, value: id };
}

// GET /api/users/me — giriş yapmış herkes kendi TAM profilini görür (Profil
// ekranı, Modül 8). ":id" route'undan ÖNCE tanımlanmalı; aksi halde Express
// "me" değerini bir id parametresi sanır.
router.get('/me', (req, res) => {
  try {
    const user = db.prepare(`SELECT ${FULL_FIELDS} FROM users WHERE id = ?`).get(req.user.id);
    if (!user) {
      return res.status(404).json({ error: 'Kullanıcı bulunamadı.' });
    }
    res.json(mapFullUser(user));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Profil bilgisi alınırken bir hata oluştu.' });
  }
});

// GET /api/users/me/supervisor — giriş yapmış herkes, KENDİ bağlı olduğu
// dispeçer/yöneticinin ad+telefonunu görür. Acil Durum (SOS) Modülü için:
// "Yöneticimi Ara" butonunun aranacak numarayı bulabilmesi gerekir, ama
// PICKER_FIELDS (bkz. yukarısı) BİLİNÇLİ olarak telefon İÇERMEZ ve tam
// telefon FULL_FIELDS'i (GET /:id) yalnızca yöneticiye açıktır. Bu, dar bir
// GÜVENLİK İSTİSNASI: yalnızca arayan kullanıcının KENDİ supervisor_id'sine
// ait kayıt döner, başka hiçbir kullanıcının telefonu açığa çıkmaz.
router.get('/me/supervisor', (req, res) => {
  try {
    const me = db.prepare('SELECT supervisor_id FROM users WHERE id = ?').get(req.user.id);
    if (!me || !me.supervisor_id) {
      return res.status(404).json({ error: 'Bağlı bir yönetici/dispeçer bulunamadı.' });
    }

    const supervisor = db.prepare('SELECT id, name, phone FROM users WHERE id = ?').get(me.supervisor_id);
    if (!supervisor) {
      return res.status(404).json({ error: 'Bağlı bir yönetici/dispeçer bulunamadı.' });
    }

    res.json(supervisor);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Yönetici bilgisi alınırken bir hata oluştu.' });
  }
});

// GET /api/users?role=teknisyen&active=true
// İKİ FARKLI TÜKETİCİSİ var, bu yüzden rolüne göre farklı davranır:
// 1) "Kişi seçici" kullanımı (iş emri atama, İSG bildiren personel) — TÜM
//    roller erişebilir, dispeçer kendi ekibiyle sınırlanır (bkz.
//    ARCHITECTURE.md Modül 7 — hiyerarşik yetkilendirme), yalnızca hafif
//    alanlar (PICKER_FIELDS) döner — telefon/e-posta/fotoğraf gibi özlük
//    bilgisi sızdırılmaz.
// 2) Yönetici için: Kullanıcı Yönetimi paneli TÜM kullanıcıları TAM alan
//    setiyle (FULL_FIELDS) görür — bu yüzden bu endpoint yönetici için ayrı
//    bir route'a bölünmek yerine aynı yerde zenginleştirilmiş yanıt döner.
// `active=true` filtresi: iş emri atama/yeniden atama dropdown'larının
// PASİF bir teknisyeni hiç listelememesi için (bkz. ARCHITECTURE.md Modül 8
// devamı) — Flutter tarafı bu filtreyi teknisyen seçicilerinde her zaman gönderir.
router.get('/', (req, res) => {
  try {
    const { role, active, il } = req.query;
    const isAdmin = req.user.role === 'yonetici';

    const conditions = [];
    const params = [];
    if (role) {
      conditions.push('role = ?');
      params.push(role);
    }
    if (active !== undefined) {
      conditions.push('is_active = ?');
      params.push(active === 'true' || active === '1' ? 1 : 0);
    }
    // Yöneticiden Çalışana Duyuru/Mesaj Sistemi — "Şu İldeki Herkes" toplu
    // gönderim kısayolu için (bkz. routes/managerMessages.js). il yalnızca
    // FULL_FIELDS ile döndüğünden bu filtre pratikte sadece yönetici
    // çağrılarında anlamlıdır, ama diğer roller de gönderirse zararsızdır.
    if (il) {
      conditions.push('il = ?');
      params.push(il);
    }
    if (req.user.role === 'dispecer') {
      conditions.push('(supervisor_id = ? OR id = ?)');
      params.push(req.user.id, req.user.id);
    }
    const whereClause = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';

    if (isAdmin) {
      const users = db
        .prepare(`SELECT ${FULL_FIELDS} FROM users ${whereClause} ORDER BY name`)
        .all(...params);
      return res.json(users.map(mapFullUser));
    }

    const users = db
      .prepare(`SELECT ${PICKER_FIELDS} FROM users ${whereClause} ORDER BY name`)
      .all(...params);
    res.json(users);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Kişiler listelenirken bir hata oluştu.' });
  }
});

// POST /api/users — yeni kullanıcı oluşturur (Kullanıcı Yönetimi paneli).
// Body: { name, sicil_no, password, role, phone?, email?, supervisor_id? }
// supervisor_id verilirse (yeni bir teknisyeni doğrudan bir dispeçere
// bağlamak için), GERÇEKTEN bir dispeçere ait olduğu doğrulanır.
router.post('/', requireRole('yonetici'), (req, res) => {
  try {
    const { name, sicil_no, password, role, phone, email, il } = req.body;

    if (!name || typeof name !== 'string' || !name.trim()) {
      return res.status(400).json({ error: 'name alanı zorunludur.' });
    }
    if (!sicil_no || !String(sicil_no).trim()) {
      return res.status(400).json({ error: 'sicil_no alanı zorunludur.' });
    }
    if (!password || typeof password !== 'string' || password.length < 4) {
      return res.status(400).json({ error: 'password alanı en az 4 karakter olmalıdır.' });
    }
    if (!role || !VALID_ROLES.includes(role)) {
      return res.status(400).json({ error: `Geçersiz role değeri. Geçerli değerler: ${VALID_ROLES.join(', ')}` });
    }

    let supervisorId = null;
    if (req.body.supervisor_id !== undefined && req.body.supervisor_id !== null) {
      const resolved = resolveSupervisorId(req.body.supervisor_id);
      if (!resolved.ok) {
        return res.status(400).json({ error: resolved.error });
      }
      supervisorId = resolved.value;
    }

    const existing = db.prepare('SELECT id FROM users WHERE sicil_no = ?').get(String(sicil_no).trim());
    if (existing) {
      return res.status(409).json({ error: 'Bu sicil no ile kayıtlı bir kullanıcı zaten var.' });
    }

    const password_hash = bcrypt.hashSync(password, 10);
    const info = db
      .prepare(
        `INSERT INTO users (name, role, sicil_no, password_hash, phone, email, il, supervisor_id, is_active)
         VALUES (@name, @role, @sicil_no, @password_hash, @phone, @email, @il, @supervisor_id, 1)`
      )
      .run({
        name: name.trim(),
        role,
        sicil_no: String(sicil_no).trim(),
        password_hash,
        phone: phone ? String(phone).trim() : null,
        email: email ? String(email).trim() : null,
        il: il ? String(il).trim() : null,
        supervisor_id: supervisorId,
      });

    logUserAction(info.lastInsertRowid, 'olusturuldu', req.user.id);

    const created = db.prepare(`SELECT ${FULL_FIELDS} FROM users WHERE id = ?`).get(info.lastInsertRowid);
    res.status(201).json(mapFullUser(created));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Kullanıcı oluşturulurken bir hata oluştu.' });
  }
});

// GET /api/users/:id — yalnızca yönetici, tam kullanıcı detayı + işlem
// geçmişi (device_action_logs/ManagedDevice ile AYNI desen — bkz.
// routes/devices.js: detay yanıtına `logs` gömülür, Flutter tarafı ekstra
// bir istek atmadan Kullanıcı Düzenleme ekranındaki geçmiş bölümünü doldurur).
router.get('/:id', requireRole('yonetici'), (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz kullanıcı id değeri.' });
    }

    const user = db.prepare(`SELECT ${FULL_FIELDS} FROM users WHERE id = ?`).get(id);
    if (!user) {
      return res.status(404).json({ error: 'Kullanıcı bulunamadı.' });
    }

    const logs = db
      .prepare('SELECT * FROM user_action_logs WHERE target_user_id = ? ORDER BY created_at DESC')
      .all(id);

    res.json({ ...mapFullUser(user), logs });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Kullanıcı bilgisi alınırken bir hata oluştu.' });
  }
});

// PATCH /api/users/:id — yalnızca yönetici.
// Body: { name?, phone?, email?, role?, supervisor_id? }
// supervisor_id ÜÇ işlemi de tek alanla karşılar (Kullanıcı Yönetimi
// panelinden): bir id verilirse ATAMA/DEĞİŞTİRME (teknisyeni o dispeçere
// bağlar — hedefin GERÇEKTEN bir dispeçer olduğu doğrulanır), `null`
// verilirse dispeçer bağını SİLME (teknisyen artık hiçbir dispeçere bağlı
// değil — bu, gerçek bir DELETE değil, ilişkiyi kaldıran bir güncellemedir).
// Alan hiç gönderilmezse (undefined) dokunulmaz.
// NOT: is_active bu endpoint'ten YÖNETİLMEZ — aktifleştirme/pasifleştirme
// yalnızca ayrı, loglanan endpoint'ler üzerinden yapılır (bkz. DELETE /:id
// ve PATCH /:id/reactivate); tek bir yerden yönetilsin, sessizce (log'suz)
// değişmesin diye kasıtlı olarak buradan çıkarıldı.
//
// GÜVENLİK: Bir kullanıcı (yönetici bile olsa) API'ye doğrudan istek atarak
// KENDİ rolünü değiştiremez — Flutter arayüzü zaten bunu göstermez ama
// backend'de de zorunlu kılınır (bkz. ARCHITECTURE.md Modül 8 devamı,
// madde 10).
router.patch('/:id', requireRole('yonetici'), (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz kullanıcı id değeri.' });
    }

    const existing = db.prepare('SELECT id, role FROM users WHERE id = ?').get(id);
    if (!existing) {
      return res.status(404).json({ error: 'Kullanıcı bulunamadı.' });
    }

    const { name, phone, email, il, role, supervisor_id } = req.body;
    if (name !== undefined && (typeof name !== 'string' || !name.trim())) {
      return res.status(400).json({ error: 'name alanı boş olamaz.' });
    }
    if (role !== undefined && !VALID_ROLES.includes(role)) {
      return res.status(400).json({ error: `Geçersiz role değeri. Geçerli değerler: ${VALID_ROLES.join(', ')}` });
    }
    if (role !== undefined && id === req.user.id) {
      return res.status(400).json({ error: 'Kendi rolünüzü değiştiremezsiniz.' });
    }

    let resolvedSupervisorId;
    if (supervisor_id !== undefined) {
      const resolved = resolveSupervisorId(supervisor_id);
      if (!resolved.ok) {
        return res.status(400).json({ error: resolved.error });
      }
      resolvedSupervisorId = resolved.value;
    }

    const fields = [];
    const params = [];
    if (name !== undefined) {
      fields.push('name = ?');
      params.push(String(name).trim());
    }
    if (phone !== undefined) {
      fields.push('phone = ?');
      params.push(phone ? String(phone).trim() : null);
    }
    if (email !== undefined) {
      fields.push('email = ?');
      params.push(email ? String(email).trim() : null);
    }
    if (il !== undefined) {
      fields.push('il = ?');
      params.push(il ? String(il).trim() : null);
    }
    if (role !== undefined) {
      fields.push('role = ?');
      params.push(role);
    }
    if (supervisor_id !== undefined) {
      fields.push('supervisor_id = ?');
      params.push(resolvedSupervisorId);
    }

    if (fields.length > 0) {
      params.push(id);
      db.prepare(`UPDATE users SET ${fields.join(', ')} WHERE id = ?`).run(...params);
      // Rol değişikliği ayrı bir aksiyon tipi olarak loglanır (hesap
      // verebilirlik açısından diğer alan güncellemelerinden ayırt edilebilsin).
      logUserAction(id, role !== undefined && role !== existing.role ? 'rol_degistirildi' : 'guncellendi', req.user.id);
    }

    const updated = db.prepare(`SELECT ${FULL_FIELDS} FROM users WHERE id = ?`).get(id);
    res.json(mapFullUser(updated));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Kullanıcı güncellenirken bir hata oluştu.' });
  }
});

// POST /api/users/:id/photo — yalnızca yönetici, multipart/form-data, dosya alanı adı: "photo".
// Dosya gerçekten uploads/profiles/ klasörüne yazılır; work_orders/:id/photos
// ile aynı ilke — kalıcı bir URL kaydedilir, herkes (yetkiliyse) görebilir.
router.post('/:id/photo', requireRole('yonetici'), (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) {
    return res.status(400).json({ error: 'Geçersiz kullanıcı id değeri.' });
  }

  const existing = db.prepare('SELECT id FROM users WHERE id = ?').get(id);
  if (!existing) {
    return res.status(404).json({ error: 'Kullanıcı bulunamadı.' });
  }

  upload.single('photo')(req, res, (err) => {
    if (err) {
      return res.status(400).json({ error: err.message || 'Fotoğraf yüklenirken bir hata oluştu.' });
    }

    if (!req.file) {
      return res.status(400).json({ error: 'photo alanı (dosya) zorunludur.' });
    }

    // Dosya İÇERİĞİ (magic number) doğrulaması — mimetype/uzantı YALNIZCA
    // istemcinin beyanıdır, sahtelenebilir (bkz. middleware/validateImageContent.js).
    validateImageContent(req, res, () => {
      try {
        const photoPath = `/uploads/profiles/${req.file.filename}`;
        db.prepare('UPDATE users SET photo_path = ? WHERE id = ?').run(photoPath, id);

        const updated = db.prepare(`SELECT ${FULL_FIELDS} FROM users WHERE id = ?`).get(id);
        res.json(mapFullUser(updated));
      } catch (innerErr) {
        console.error(innerErr);
        res.status(500).json({ error: 'Fotoğraf kaydedilirken bir hata oluştu.' });
      }
    });
  });
});

// PATCH /api/users/:id/reset-password — yalnızca yönetici. Body: { password }
// Teknisyen/dispeçer kendi şifresini değiştiremediği için (profil ekranı
// yalnızca görüntüleme), şifresini unutan bir kullanıcının şifresi buradan
// yönetici tarafından sıfırlanır.
router.patch('/:id/reset-password', requireRole('yonetici'), (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz kullanıcı id değeri.' });
    }

    const existing = db.prepare('SELECT id FROM users WHERE id = ?').get(id);
    if (!existing) {
      return res.status(404).json({ error: 'Kullanıcı bulunamadı.' });
    }

    const { password } = req.body;
    if (!password || typeof password !== 'string' || password.length < 4) {
      return res.status(400).json({ error: 'password alanı en az 4 karakter olmalıdır.' });
    }

    const password_hash = bcrypt.hashSync(password, 10);
    db.prepare('UPDATE users SET password_hash = ? WHERE id = ?').run(password_hash, id);
    logUserAction(id, 'sifre_sifirlandi', req.user.id);

    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Şifre sıfırlanırken bir hata oluştu.' });
  }
});

// PATCH /api/users/:id/reactivate — yalnızca yönetici. is_active=1 yapar
// (DELETE /:id'nin tersi — bkz. aşağıda).
router.patch('/:id/reactivate', requireRole('yonetici'), (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz kullanıcı id değeri.' });
    }

    const existing = db.prepare('SELECT id FROM users WHERE id = ?').get(id);
    if (!existing) {
      return res.status(404).json({ error: 'Kullanıcı bulunamadı.' });
    }

    db.prepare('UPDATE users SET is_active = 1 WHERE id = ?').run(id);
    logUserAction(id, 'aktiflestirildi', req.user.id);

    const updated = db.prepare(`SELECT ${FULL_FIELDS} FROM users WHERE id = ?`).get(id);
    res.json(mapFullUser(updated));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Kullanıcı aktif hale getirilirken bir hata oluştu.' });
  }
});

// DELETE /api/users/:id — yalnızca yönetici. GERÇEK silme yapılmaz (geçmiş iş
// emirleri/İSG bildirimleri FK ile bu kullanıcıya bağlı olabilir); yalnızca
// is_active=0 yapılır (soft delete).
// GÜVENLİK: Bir yönetici KENDİ hesabını pasifleştiremez (kendi kendini
// kilitleyip sistemden dışlaması engellenir).
router.delete('/:id', requireRole('yonetici'), (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz kullanıcı id değeri.' });
    }

    if (id === req.user.id) {
      return res.status(400).json({ error: 'Kendi hesabınızı pasifleştiremezsiniz.' });
    }

    const existing = db.prepare('SELECT id FROM users WHERE id = ?').get(id);
    if (!existing) {
      return res.status(404).json({ error: 'Kullanıcı bulunamadı.' });
    }

    db.prepare('UPDATE users SET is_active = 0 WHERE id = ?').run(id);
    logUserAction(id, 'pasiflestirildi', req.user.id);

    const updated = db.prepare(`SELECT ${FULL_FIELDS} FROM users WHERE id = ?`).get(id);
    res.json(mapFullUser(updated));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Kullanıcı pasif hale getirilirken bir hata oluştu.' });
  }
});

module.exports = router;
