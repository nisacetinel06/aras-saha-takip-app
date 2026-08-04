// Basit Kullanım Analitiği (UX standardizasyonu turu, bölüm E).
//
// ÖNEMLİ AYRIM: Bu, ücretli/harici bir davranış analizi aracının (Hotjar,
// Firebase Analytics vb.) YERİNE geçen, kasıtlı olarak BASİT bir alternatif —
// bir ısı haritası/oturum kaydı DEĞİLDİR, yalnızca "hangi ekran ne sıklıkla
// açıldı, hangi buton ne sıklıkla tıklandı" sorusuna cevap veren bir sayaç.
const express = require('express');
const db = require('../database');
const { requireRole } = require('../middleware/auth');

const router = express.Router();

const VALID_EVENT_TYPES = ['screen_view', 'button_tap'];

const insertLog = db.prepare(`
  INSERT INTO usage_logs (user_id, event_type, screen_name, element_name, created_at)
  VALUES (@user_id, @event_type, @screen_name, @element_name, @created_at)
`);

// POST /api/analytics/log
// Body: { event_type, screen_name, element_name? }
// Flutter tarafı bu isteği "fire and forget" olarak atar (bkz.
// services/analytics_service.dart) — bu yüzden burada da kullanıcı deneyimini
// YAVAŞLATACAK hiçbir şey yapılmaz: tek bir senkron INSERT (node:sqlite zaten
// senkron ve yerel bir dosya olduğu için bu, ağ gecikmesi dışında anlık bir
// işlemdir) ve hemen 201 dönülür.
router.post('/log', (req, res) => {
  try {
    const { event_type, screen_name, element_name } = req.body || {};

    if (!VALID_EVENT_TYPES.includes(event_type)) {
      return res.status(400).json({ error: `Geçersiz event_type. Geçerli değerler: ${VALID_EVENT_TYPES.join(', ')}` });
    }
    if (!screen_name || !String(screen_name).trim()) {
      return res.status(400).json({ error: 'screen_name alanı zorunludur.' });
    }

    insertLog.run({
      user_id: req.user?.id ?? null,
      event_type,
      screen_name: String(screen_name).trim(),
      element_name: element_name ? String(element_name).trim() : null,
      created_at: new Date().toISOString(),
    });

    res.status(201).json({ success: true });
  } catch (err) {
    // Bir analitik logunun başarısız olması uygulamanın asıl işlevini
    // ETKİLEMEMELİ — burada bile hata 500 olarak dönse de Flutter tarafı
    // bunu sessizce yutar (bkz. AnalyticsService), kullanıcı hiçbir şey görmez.
    console.error(err);
    res.status(500).json({ error: 'Kullanım logu kaydedilirken bir hata oluştu.' });
  }
});

// GET /api/analytics/summary — yalnızca yönetici.
// En çok ziyaret edilen 5 ekranı ve en çok tıklanan 5 butonu, sayıya göre
// azalan sırada döner.
router.get('/summary', requireRole('yonetici'), (req, res) => {
  try {
    const topScreens = db
      .prepare(
        `SELECT screen_name, COUNT(*) AS view_count
         FROM usage_logs
         WHERE event_type = 'screen_view'
         GROUP BY screen_name
         ORDER BY view_count DESC
         LIMIT 5`
      )
      .all();

    const topButtons = db
      .prepare(
        `SELECT screen_name, element_name, COUNT(*) AS tap_count
         FROM usage_logs
         WHERE event_type = 'button_tap' AND element_name IS NOT NULL
         GROUP BY screen_name, element_name
         ORDER BY tap_count DESC
         LIMIT 5`
      )
      .all();

    res.json({ top_screens: topScreens, top_buttons: topButtons });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Kullanım analitiği özeti alınırken bir hata oluştu.' });
  }
});

module.exports = router;
