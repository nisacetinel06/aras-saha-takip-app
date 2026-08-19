// POST /api/auth/login brute-force koruması — sicil_no + IP kombinasyonu
// bazında izleme (bkz. database.js login_attempts tablosu, routes/auth.js
// her denemenin kaydedilmesi). SECURITY_NOTES.md "Login endpoint'inde rate
// limiting / brute-force koruması yok (TEST-06)" maddesinin çözümü.
//
// Yalnızca IP ya da yalnızca sicil_no bazlı sınırlama tek başına yetersiz:
// aynı IP'yi paylaşan meşru kullanıcılar birbirini kilitlememeli, aynı zamanda
// bir saldırgan IP değiştirerek (VPN/proxy rotasyonu) aynı hesabı sınırsız
// deneyememeli. İkisinin kombinasyonu ("bu IP'den bu sicil no'ya yapılan
// denemeler") bu iki riski birlikte kapatır.
const db = require('../database');

const LOCK_THRESHOLD = 5; // ardışık başarısız deneme sayısı
const LOCK_WINDOW_MINUTES = 15; // bu süre içindeki denemeler sayılır
const LOCK_DURATION_MINUTES = 15; // kilit süresi

// Kullanıcı numaralandırmayı önleme: bu kontrol sicil_no'nun DB'de gerçekten
// var olup olmadığına BAKMAKSIZIN uygulanır. Yalnızca var olan hesaplar
// kilitlenip olmayanlar kilitlenmeseydi, bir saldırgan "kilitlendi mi
// kilitlenmedi mi" farkına bakarak hangi sicil no'ların gerçek olduğunu
// anlayabilirdi (TEST-06'daki user enumeration bulgusuyla aynı kategori).
function checkLoginRateLimit(req, res, next) {
  const { sicil_no } = req.body;
  const ip = req.ip;

  if (!sicil_no) return next(); // sicil_no yoksa zaten normal validasyon 400 dönecek

  const windowStart = new Date(Date.now() - LOCK_WINDOW_MINUTES * 60 * 1000).toISOString();

  const recentFailures = db
    .prepare(
      `SELECT COUNT(*) as count FROM login_attempts
       WHERE sicil_no = ? AND ip_address = ? AND success = 0 AND created_at > ?`
    )
    .get(String(sicil_no), ip, windowStart);

  if (recentFailures.count >= LOCK_THRESHOLD) {
    return res.status(429).json({
      error: `Çok fazla başarısız deneme. Lütfen ${LOCK_DURATION_MINUTES} dakika sonra tekrar deneyin.`,
    });
  }

  next();
}

module.exports = { checkLoginRateLimit, LOCK_THRESHOLD, LOCK_WINDOW_MINUTES, LOCK_DURATION_MINUTES };
