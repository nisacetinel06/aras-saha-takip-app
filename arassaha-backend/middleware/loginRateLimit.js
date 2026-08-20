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
//
// Gerçek kilit mantığı artık middleware/rateLimiting.js'teki GENEL fabrikada
// (createAttemptRateLimiter) — 2FA doğrulama görevinde (routes/twoFactor.js)
// AYNI "N dakikada M başarısız deneme -> kilitle" deseni tekrar gerektiği
// için oraya taşındı/genelleştirildi. Bu dosya artık yalnızca LOGIN'e özgü
// sabitleri ve kimlik çıkarma mantığını (sicil_no) tanımlar.
const { createAttemptRateLimiter } = require('./rateLimiting');

const LOCK_THRESHOLD = 5; // ardışık başarısız deneme sayısı
const LOCK_WINDOW_MINUTES = 15; // bu süre içindeki denemeler sayılır
const LOCK_DURATION_MINUTES = 15; // kilit süresi

// Kullanıcı numaralandırmayı önleme: bu kontrol sicil_no'nun DB'de gerçekten
// var olup olmadığına BAKMAKSIZIN uygulanır. Yalnızca var olan hesaplar
// kilitlenip olmayanlar kilitlenmeseydi, bir saldırgan "kilitlendi mi
// kilitlenmedi mi" farkına bakarak hangi sicil no'ların gerçek olduğunu
// anlayabilirdi (TEST-06'daki user enumeration bulgusuyla aynı kategori).
const checkLoginRateLimit = createAttemptRateLimiter({
  table: 'login_attempts',
  identifierColumn: 'sicil_no',
  // sicil_no yoksa zaten normal validasyon 400 dönecek — rate limit'e gerek
  // yok (getIdentifier null dönünce createAttemptRateLimiter next() çağırır).
  getIdentifier: (req) => (req.body && req.body.sicil_no ? String(req.body.sicil_no) : null),
  threshold: LOCK_THRESHOLD,
  windowMinutes: LOCK_WINDOW_MINUTES,
  lockDurationMinutes: LOCK_DURATION_MINUTES,
});

module.exports = { checkLoginRateLimit, LOCK_THRESHOLD, LOCK_WINDOW_MINUTES, LOCK_DURATION_MINUTES };
