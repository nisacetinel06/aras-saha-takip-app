// Raporlar / Analitik Sayfası (Modül 14).
//
// Bu router, Modül 9'un (equipment_risk_scores) ve Modül 11'in
// (meter_anomaly_scores) ürettiği verileri, ham iş emri/malzeme kayıtlarıyla
// birlikte YÖNETİCİYE özel bir dizi özet/kırılım halinde sunar. Kendisi hiçbir
// yeni hesaplama/model içermez — yalnızca zaten var olan tabloları GROUP BY
// ile özetler (Dashboard'daki visibilityClause/withClause gibi bir filtre
// katmanı da yok, çünkü bu bir yönetim raporudur, teknisyen/dispeçer görünürlük
// kısıtlaması burada anlamsız — zaten tüm endpoint'ler requireRole('yonetici')).
//
// TÜM endpoint'ler yalnızca yönetici rolüne açıktır (bkz. PROMPT "Genel
// Kurallar" #3) — router'ın tamamına router.use(requireRole('yonetici')) ile
// tek seferde uygulanır.
const express = require('express');
const db = require('../database');
const { requireRole } = require('../middleware/auth');

const router = express.Router();

router.use(requireRole('yonetici'));

// Risk Yoğunluk Haritası (bkz. Flutter reports_screen.dart Sekme 1) için il
// merkez koordinatları.
//
// MİMARİ NOT (bubble map vs. choropleth): Gerçek bir coğrafi ısı haritası
// (choropleth — il sınırlarını dolduran harita) il/ilçe sınır poligonlarına
// (GeoJSON) ihtiyaç duyar; bu veri elimizde yok ve temin etmek bu kapsamda
// gereksiz karmaşıklık katardı. Bunun yerine her ilin merkezinde büyüklüğü
// ekipman sayısına, rengi ortalama riske göre değişen bir DAİRE (bubble)
// çizilir — görsel olarak "ısı haritası" hissi verir, teknik olarak çok daha
// basittir.
//
// SABİT vs. DİNAMİK merkez seçimi: equipment.lat/lng ortalamasıyla dinamik bir
// "ağırlık merkezi" de hesaplanabilirdi, ama bu prototipte SABİT il merkezi
// BİLİNÇLİ olarak tercih edildi — dinamik ortalama, bir ildeki ekipman sayısı
// azken (örn. 2-3 kayıt) o ilin coğrafi olarak yanlış/anlamsız bir noktada
// (örn. iki ekipmanın tam ortasında, bir dağın üzerinde) görünmesine yol
// açabilir; sabit il merkezi her zaman tanıdık, doğru bir referans noktasıdır.
// Koordinatlar seed.js'teki "Merkez" ilçe kayıtlarıyla AYNI (bkz. seed.js
// LOCATIONS) — haritadaki bubble'lar o ildeki gerçek ekipman pinleriyle
// tutarlı bir bölgede görünsün diye.
const REGION_CENTERS = [
  { il: 'Erzurum', center_lat: 39.9086, center_lng: 41.2769 },
  { il: 'Erzincan', center_lat: 39.75, center_lng: 39.49 },
  { il: 'Ağrı', center_lat: 39.7191, center_lng: 43.0503 },
  { il: 'Kars', center_lat: 40.6013, center_lng: 43.0975 },
  { il: 'Iğdır', center_lat: 39.9167, center_lng: 44.0448 },
  { il: 'Ardahan', center_lat: 41.1105, center_lng: 42.7022 },
  { il: 'Bayburt', center_lat: 40.2552, center_lng: 40.2249 },
];

function round(value, decimals = 0) {
  const factor = 10 ** decimals;
  return Math.round(value * factor) / factor;
}

// GET /api/reports/regional-risk-summary
// 7 hizmet ili İÇİN SABİT olarak döner (equipment tablosunda o ilde hiç kayıt
// olmasa bile) — böylece Flutter tarafı haritada her zaman 7 bubble çizer;
// veri yoksa equipment_count=0/avg_risk_score=null ile "veri yok" durumu net
// bir şekilde ayırt edilebilir (bkz. Flutter tarafı boş/gri daire davranışı).
router.get('/regional-risk-summary', (req, res) => {
  try {
    const perIlStmt = db.prepare(
      `SELECT COUNT(e.id) AS equipment_count,
              AVG(r.risk_score) AS avg_risk_score,
              SUM(CASE WHEN r.risk_level = 'yuksek' THEN 1 ELSE 0 END) AS high_risk_count
       FROM equipment e
       LEFT JOIN equipment_risk_scores r ON r.equipment_id = e.id
       WHERE e.il = ?`
    );

    const result = REGION_CENTERS.map((region) => {
      const row = perIlStmt.get(region.il);
      return {
        il: region.il,
        center_lat: region.center_lat,
        center_lng: region.center_lng,
        equipment_count: row.equipment_count,
        avg_risk_score: row.avg_risk_score != null ? round(row.avg_risk_score) : null,
        high_risk_count: row.high_risk_count ?? 0,
      };
    });

    res.json(result);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Bölgesel risk özeti alınırken bir hata oluştu.' });
  }
});

// GET /api/reports/fault-by-region
// İl bazında iş emri (arıza) sayısı — çubuk grafik için azalan sırada. Hiç iş
// emri olmayan iller (örn. seed verisinde Iğdır) listede HİÇ görünmez — sıfır
// değerli bir çubuk çizmek yerine Flutter tarafı yalnızca dönen kayıtları çizer.
router.get('/fault-by-region', (req, res) => {
  try {
    const rows = db
      .prepare(
        `SELECT il, COUNT(*) AS fault_count
         FROM work_orders
         WHERE il IS NOT NULL
         GROUP BY il
         ORDER BY fault_count DESC`
      )
      .all();
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Bölgeye göre arıza dağılımı alınırken bir hata oluştu.' });
  }
});

// GET /api/reports/fault-by-equipment-type
// Ekipmana BAĞLI iş emirlerinin equipment_type kırılımı — ekipmana bağlı
// olmayan (equipment_id NULL) iş emirleri bu kırılımın dışında kalır, çünkü
// "hangi ekipman tipinde daha çok arıza oluyor" sorusu yalnızca bir ekipmana
// bağlı kayıtlar için anlamlıdır.
router.get('/fault-by-equipment-type', (req, res) => {
  try {
    const rows = db
      .prepare(
        `SELECT e.equipment_type, COUNT(*) AS fault_count
         FROM work_orders wo
         JOIN equipment e ON e.id = wo.equipment_id
         GROUP BY e.equipment_type
         ORDER BY fault_count DESC`
      )
      .all();
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Ekipman tipine göre arıza dağılımı alınırken bir hata oluştu.' });
  }
});

// GET /api/reports/fault-trend?months=6
// Son N ayın (varsayılan 6, 1-12 arası) arıza sayısını, veri OLMAYAN aylar da
// dahil (0 ile doldurularak) kronolojik sırada döner — dashboard.js'teki
// statusBreakdown/priorityBreakdown "sabit anahtarlarla başlat, GROUP BY
// sonucunu üzerine yaz" deseniyle AYNI mantık: aksi halde çizgi grafikte
// hiç arıza olmayan aylar sessizce ATLANIR ve trend yanıltıcı görünür.
router.get('/fault-trend', (req, res) => {
  try {
    const months = Math.min(Math.max(Number(req.query.months) || 6, 1), 12);

    const now = new Date();
    const monthKeys = [];
    for (let i = months - 1; i >= 0; i--) {
      const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
      monthKeys.push(`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`);
    }

    const rows = db
      .prepare(
        `SELECT strftime('%Y-%m', created_at) AS year_month, COUNT(*) AS fault_count
         FROM work_orders
         WHERE created_at >= ?
         GROUP BY year_month`
      )
      .all(new Date(now.getFullYear(), now.getMonth() - (months - 1), 1).toISOString());

    const countByMonth = Object.fromEntries(rows.map((r) => [r.year_month, r.fault_count]));

    res.json(monthKeys.map((year_month) => ({ year_month, fault_count: countByMonth[year_month] ?? 0 })));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Aylık arıza trendi alınırken bir hata oluştu.' });
  }
});

// GET /api/reports/anomaly-by-region
// İl bazında şüpheli sayaç sayısı ve oranı. total_meters=0 olan iller
// (o ilde hiç sayaç yoksa) sonuçta yer almaz — 0/0 oranı anlamsız olurdu.
router.get('/anomaly-by-region', (req, res) => {
  try {
    const rows = db
      .prepare(
        `SELECT e.il,
                COUNT(*) AS total_meters,
                SUM(CASE WHEN a.is_suspicious = 1 THEN 1 ELSE 0 END) AS suspicious_count
         FROM equipment e
         LEFT JOIN meter_anomaly_scores a ON a.equipment_id = e.id
         WHERE e.equipment_type = 'sayac' AND e.il IS NOT NULL
         GROUP BY e.il
         HAVING total_meters > 0
         ORDER BY suspicious_count DESC`
      )
      .all();

    res.json(
      rows.map((row) => ({
        il: row.il,
        total_meters: row.total_meters,
        suspicious_count: row.suspicious_count,
        suspicious_ratio: round(row.suspicious_count / row.total_meters, 4),
      }))
    );
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Bölgeye göre anomali dağılımı alınırken bir hata oluştu.' });
  }
});

// GET /api/reports/material-usage-top?limit=10
// En çok kullanılan malzemeler (SUM(quantity_used) azalan sırada). limit
// 5-10 arası sınırlanır (bkz. PROMPT "en çok kullanılan 5-10 malzeme").
router.get('/material-usage-top', (req, res) => {
  try {
    const limit = Math.min(Math.max(Number(req.query.limit) || 10, 5), 10);
    const rows = db
      .prepare(
        `SELECT m.id, m.name, m.unit, m.category, SUM(wom.quantity_used) AS total_used
         FROM work_order_materials wom
         JOIN materials m ON m.id = wom.material_id
         GROUP BY m.id
         ORDER BY total_used DESC
         LIMIT ?`
      )
      .all(limit);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'En çok kullanılan malzemeler alınırken bir hata oluştu.' });
  }
});

module.exports = router;
