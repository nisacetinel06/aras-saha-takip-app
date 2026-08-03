// Ekipman / Envanter (QR Kod) modülüne ait tüm endpoint'ler (Modül 4).
//
// ÖNEMLİ: `equipment` tablosundaki install_date/last_maintenance_date gibi
// alanlar bilinçli olarak buradadır — ileride eklenecek Arıza Risk Tahmini
// (Makine Öğrenmesi) modülü bu alanları (ve equipment_id üzerinden sayılacak
// geçmiş iş emri adedini) doğrudan girdi/feature olarak kullanacaktır.
// Bkz. database.js'teki şema yorumu ve ARCHITECTURE.md.
const express = require('express');
const db = require('../database');
const { VALID_ILLER } = require('../utils/location');

const router = express.Router();

const VALID_TYPES = ['trafo', 'direk', 'kesici', 'sayac'];
const VALID_STATUSES = ['aktif', 'bakimda', 'devre_disi'];

// Ekipman Seçici (widgets/equipment_picker_field.dart) gibi arama tabanlı
// akışlar için — kullanıcı yazdıkça daralan, performanslı bir liste dönmek
// üzere sonuç sayısı sınırlanır. `search` verilmediğinde (örn. Ekipman Listesi
// ekranının tip/durum/il filtreleri) bu limit UYGULANMAZ — o ekranın tüm
// eşleşen kayıtları görmesi gerekir.
const SEARCH_RESULT_LIMIT = 20;

// equipment_risk_scores 1:1 (equipment_id UNIQUE) olduğu için basit bir LEFT
// JOIN yeterli — Modül 9 (Arıza Risk Tahmini) risk_score/risk_level'ı liste
// ve detay yanıtlarına, Flutter tarafında ekstra bir istek atmaya gerek
// kalmadan (N+1 önlenir) gömer. Hiç hesaplanmamışsa (henüz refresh
// çalışmadıysa) her ikisi de null döner.
const SELECT_EQUIPMENT_WITH_RISK = `
  SELECT e.*, r.risk_score AS risk_score, r.risk_level AS risk_level
  FROM equipment e
  LEFT JOIN equipment_risk_scores r ON r.equipment_id = e.id
`;

// GET /api/equipment?type=trafo&status=aktif&il=Erzurum&search=TR-2024
//
// `search`: EquipmentPickerField (İş Emri Oluştur formu) gibi typeahead
// akışları için — qr_code, il, ilce, mahalle alanlarında LIKE araması yapar
// ve sonucu SEARCH_RESULT_LIMIT ile sınırlar. Diğer filtrelerle (type/status/
// il) birlikte de kullanılabilir; hepsi AND ile birleşir.
router.get('/', (req, res) => {
  try {
    const { type, status, il, search } = req.query;

    if (type && !VALID_TYPES.includes(type)) {
      return res.status(400).json({
        error: `Geçersiz type değeri. Geçerli değerler: ${VALID_TYPES.join(', ')}`,
      });
    }
    if (status && !VALID_STATUSES.includes(status)) {
      return res.status(400).json({
        error: `Geçersiz status değeri. Geçerli değerler: ${VALID_STATUSES.join(', ')}`,
      });
    }
    if (il && !VALID_ILLER.includes(il)) {
      return res.status(400).json({
        error: `Geçersiz il değeri. Geçerli değerler: ${VALID_ILLER.join(', ')}`,
      });
    }

    const conditions = [];
    const params = [];
    if (type) {
      conditions.push('e.equipment_type = ?');
      params.push(type);
    }
    if (status) {
      conditions.push('e.status = ?');
      params.push(status);
    }
    if (il) {
      conditions.push('e.il = ?');
      params.push(il);
    }
    if (search && search.trim()) {
      conditions.push('(e.qr_code LIKE ? OR e.il LIKE ? OR e.ilce LIKE ? OR e.mahalle LIKE ?)');
      const term = `%${search.trim()}%`;
      params.push(term, term, term, term);
    }
    const whereClause = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
    const limitClause = search && search.trim() ? 'LIMIT ?' : '';
    if (limitClause) params.push(SEARCH_RESULT_LIMIT);

    const rows = db
      .prepare(`${SELECT_EQUIPMENT_WITH_RISK} ${whereClause} ORDER BY e.install_date DESC ${limitClause}`)
      .all(...params);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Ekipmanlar listelenirken bir hata oluştu.' });
  }
});

// GET /api/equipment/qr/:qrCode
// Ana sorgulama yöntemi: QR tarama ya da manuel kod girişiyle çağrılır.
// Eşleşme yoksa 404 + Flutter tarafında doğrudan gösterilebilecek net bir mesaj döner.
router.get('/qr/:qrCode', (req, res) => {
  try {
    const { qrCode } = req.params;
    const row = db.prepare(`${SELECT_EQUIPMENT_WITH_RISK} WHERE e.qr_code = ?`).get(qrCode);

    if (!row) {
      return res.status(404).json({ error: 'Bu QR koda ait ekipman bulunamadı.' });
    }

    res.json(row);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Ekipman aranırken bir hata oluştu.' });
  }
});

// GET /api/equipment/:id — harita/liste üzerinden gelindiğinde kullanılır.
router.get('/:id', (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz ekipman id değeri.' });
    }

    const row = db.prepare(`${SELECT_EQUIPMENT_WITH_RISK} WHERE e.id = ?`).get(id);
    if (!row) {
      return res.status(404).json({ error: 'Ekipman bulunamadı.' });
    }

    res.json(row);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Ekipman detayı alınırken bir hata oluştu.' });
  }
});

// GET /api/equipment/:id/history
// Bu ekipmana bağlı geçmiş iş emirlerini (arıza kayıtlarını) work_orders
// tablosundan JOIN ile getirir.
router.get('/:id/history', (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz ekipman id değeri.' });
    }

    const equipment = db.prepare('SELECT id FROM equipment WHERE id = ?').get(id);
    if (!equipment) {
      return res.status(404).json({ error: 'Ekipman bulunamadı.' });
    }

    const history = db
      .prepare(
        `SELECT id, title, status, priority, created_at, updated_at
         FROM work_orders
         WHERE equipment_id = ?
         ORDER BY created_at DESC`
      )
      .all(id);

    res.json(history);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Ekipman geçmişi alınırken bir hata oluştu.' });
  }
});

module.exports = router;
