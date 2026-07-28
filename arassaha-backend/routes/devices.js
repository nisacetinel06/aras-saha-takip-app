// Cihaz Yönetimi (MDM) modülüne ait endpoint'ler.
//
// ÖNEMLİ: "Kilitle", "Kilidi Aç", "Hesabı Sil" bu backend'in kendi
// veritabanındaki (managed_devices) durumu değiştirir; UZAKTAN gerçek bir
// cihaza komut GÖNDERMEZ (bunun için Google Android Management API gibi bir
// MDM altyapısı gerekir, bkz. DESIGN_SYSTEM.md "Cihaz Yönetimi Modülü" notu).
// "Zorla Senkronize Et" ise farklı yönde çalışır: ArasSaha uygulamasının o an
// çalıştığı cihaz kendi GERÇEK pil/model/OS bilgisini bu backend'e gönderir
// (device→server telemetri raporu — gerçek MDM ajanlarının çalışma şekliyle
// aynı prensip).
const express = require('express');
const db = require('../database');

const router = express.Router();

// Cihaz satırlarına atanan kullanıcının ad/rol bilgisini gömen ortak SELECT.
const SELECT_DEVICE_WITH_USER = `
  SELECT
    d.*,
    u.id AS assigned_user_id_join,
    u.name AS assigned_user_name,
    u.role AS assigned_user_role
  FROM managed_devices d
  LEFT JOIN users u ON u.id = d.assigned_user_id
`;

function mapDeviceRow(row) {
  const { assigned_user_id_join, assigned_user_name, assigned_user_role, is_locked, ...device } = row;
  return {
    ...device,
    is_locked: Boolean(is_locked),
    assigned_user: assigned_user_id_join
      ? { id: assigned_user_id_join, name: assigned_user_name, role: assigned_user_role }
      : null,
  };
}

function logAction(deviceId, actionType, performedBy) {
  db.prepare(
    'INSERT INTO device_action_logs (device_id, action_type, performed_by, created_at) VALUES (?, ?, ?, ?)'
  ).run(deviceId, actionType, performedBy, new Date().toISOString());
}

// Şimdilik gerçek bir oturum/kimlik doğrulama akışı yok; işlemi yapan kişi
// sabit "Yönetici" olarak kaydedilir (bkz. ARCHITECTURE.md Bölüm 8 — rol
// bazlı yetkilendirme henüz uygulanmadı, bu alan onun yerini tutuyor).
const PERFORMED_BY = 'Yönetici';

// GET /api/devices
router.get('/', (req, res) => {
  try {
    const rows = db.prepare(`${SELECT_DEVICE_WITH_USER} ORDER BY d.device_name`).all();
    res.json(rows.map(mapDeviceRow));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Cihazlar listelenirken bir hata oluştu.' });
  }
});

// GET /api/devices/:id — cihaz detayı + işlem geçmişi
router.get('/:id', (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz cihaz id değeri.' });
    }

    const row = db.prepare(`${SELECT_DEVICE_WITH_USER} WHERE d.id = ?`).get(id);
    if (!row) {
      return res.status(404).json({ error: 'Cihaz bulunamadı.' });
    }

    const logs = db
      .prepare('SELECT * FROM device_action_logs WHERE device_id = ? ORDER BY created_at DESC')
      .all(id);

    res.json({ ...mapDeviceRow(row), logs });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Cihaz detayı alınırken bir hata oluştu.' });
  }
});

// GET /api/devices/:id/logs
router.get('/:id/logs', (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz cihaz id değeri.' });
    }

    const device = db.prepare('SELECT id FROM managed_devices WHERE id = ?').get(id);
    if (!device) {
      return res.status(404).json({ error: 'Cihaz bulunamadı.' });
    }

    const logs = db
      .prepare('SELECT * FROM device_action_logs WHERE device_id = ? ORDER BY created_at DESC')
      .all(id);
    res.json(logs);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'İşlem geçmişi alınırken bir hata oluştu.' });
  }
});

// Ortak aksiyon iskeleti: id doğrulama + cihaz var mı kontrolü + verilen
// güncellemeyi uygulama + log kaydı + güncel cihazı dönme.
function handleAction(actionType, buildUpdate) {
  return (req, res) => {
    try {
      const id = Number(req.params.id);
      if (!Number.isInteger(id)) {
        return res.status(400).json({ error: 'Geçersiz cihaz id değeri.' });
      }

      const existing = db.prepare('SELECT id FROM managed_devices WHERE id = ?').get(id);
      if (!existing) {
        return res.status(404).json({ error: 'Cihaz bulunamadı.' });
      }

      buildUpdate(id, req);
      logAction(id, actionType, PERFORMED_BY);

      const updated = db.prepare(`${SELECT_DEVICE_WITH_USER} WHERE d.id = ?`).get(id);
      res.json(mapDeviceRow(updated));
    } catch (err) {
      console.error(err);
      res.status(500).json({ error: 'İşlem gerçekleştirilirken bir hata oluştu.' });
    }
  };
}

// POST /api/devices/:id/actions/lock — SİMÜLASYON: is_locked=1 yapar, gerçek cihaza komut gitmez.
router.post(
  '/:id/actions/lock',
  handleAction('kilitle', (id) => {
    db.prepare('UPDATE managed_devices SET is_locked = 1 WHERE id = ?').run(id);
  })
);

// POST /api/devices/:id/actions/unlock — SİMÜLASYON: is_locked=0 yapar.
router.post(
  '/:id/actions/unlock',
  handleAction('kilit_ac', (id) => {
    db.prepare('UPDATE managed_devices SET is_locked = 0 WHERE id = ?').run(id);
  })
);

// POST /api/devices/:id/actions/wipe — SİMÜLASYON: enrollment_status='kayit_disi' yapar
// (gerçek MDM'de bu, cihazdaki kurumsal hesap/verinin uzaktan silinmesi komutudur).
router.post(
  '/:id/actions/wipe',
  handleAction('hesap_sil', (id) => {
    db.prepare("UPDATE managed_devices SET enrollment_status = 'kayit_disi' WHERE id = ?").run(id);
  })
);

// POST /api/devices/:id/actions/force-sync
// Body (opsiyonel): { battery_level, device_model, os_version }
//
// Bu alanlar gönderilirse — yani istek, ArasSaha uygulamasının o an GERÇEKTEN
// çalıştığı bir cihazdan geliyorsa — GERÇEK değerler kaydedilir (fiziksel
// cihazın kendi pil/model/OS bilgisi, bkz. Flutter tarafı
// DeviceTelemetryService). Gönderilmezse (örn. bir admin panelinden ya da
// curl ile, o an fiziksel bir cihaz bağlı değilken tetiklenirse) yalnızca
// last_sync_at güncellenir — pil/model o anki son bilinen değerinde kalır.
router.post(
  '/:id/actions/force-sync',
  handleAction('senkron_zorla', (id, req) => {
    const { battery_level, device_model, os_version } = req.body || {};

    const fields = ['last_sync_at = ?'];
    const values = [new Date().toISOString()];

    if (Number.isInteger(battery_level) && battery_level >= 0 && battery_level <= 100) {
      fields.push('battery_level = ?');
      values.push(battery_level);
    }
    if (typeof device_model === 'string' && device_model.trim()) {
      fields.push('device_model = ?');
      values.push(device_model.trim());
    }
    if (typeof os_version === 'string' && os_version.trim()) {
      fields.push('os_version = ?');
      values.push(os_version.trim());
    }

    values.push(id);
    db.prepare(`UPDATE managed_devices SET ${fields.join(', ')} WHERE id = ?`).run(...values);
  })
);

module.exports = router;
