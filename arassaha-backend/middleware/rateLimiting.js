// "Art arda başarısız denemeden sonra kilitle" deseninin GENEL fabrikası —
// middleware/loginRateLimit.js (Login, sicil_no+IP) ve routes/twoFactor.js
// (2FA doğrulama, user_id+IP) BİREBİR AYNI mantığı kullanır: son N dakikada
// aynı (kimlik, IP) çiftinden M başarısız deneme varsa 429 döndür. Bu dosya
// o mantığı TEK bir yerde tutar; iki ayrı kopyanın zamanla birbirinden
// (örn. bir tanesi düzeltilip diğeri unutulup) sapmasını önler.
const db = require('../database');

/**
 * @param {object} config
 * @param {string} config.table - denemelerin kaydedildiği tablo adı (yalnızca
 *   bu dosyanın İÇİNDE, sabit/hardcoded çağrı yerlerinden gelir — asla
 *   kullanıcı girdisinden değil; SQL enjeksiyonu riski yoktur).
 * @param {string} config.identifierColumn - kilidin ikinci anahtarı olan sütun
 *   (örn. 'sicil_no', 'user_id') — ip_address ile BİRLİKTE bileşik anahtarı oluşturur.
 * @param {(req: import('express').Request) => (string|number|null|undefined)} config.getIdentifier -
 *   req'ten kimlik değerini çıkarır; null/undefined dönerse kontrol tamamen
 *   ATLANIR (örn. sicil_no hiç gönderilmemişse, zaten aşağıdaki normal
 *   validasyon 400 dönecektir — rate limit'e gerek yok).
 * @param {number} [config.threshold=5] - ardışık başarısız deneme sayısı.
 * @param {number} [config.windowMinutes=15] - bu süre içindeki denemeler sayılır.
 * @param {number} [config.lockDurationMinutes=15] - kilit mesajında gösterilen süre.
 * @returns {import('express').RequestHandler}
 */
function createAttemptRateLimiter({
  table,
  identifierColumn,
  getIdentifier,
  threshold = 5,
  windowMinutes = 15,
  lockDurationMinutes = 15,
}) {
  return function checkAttemptRateLimit(req, res, next) {
    const identifier = getIdentifier(req);
    if (identifier === null || identifier === undefined) return next();

    const ip = req.ip;
    const windowStart = new Date(Date.now() - windowMinutes * 60 * 1000).toISOString();

    const recentFailures = db
      .prepare(
        `SELECT COUNT(*) as count FROM ${table}
         WHERE ${identifierColumn} = ? AND ip_address = ? AND success = 0 AND created_at > ?`
      )
      .get(identifier, ip, windowStart);

    if (recentFailures.count >= threshold) {
      return res.status(429).json({
        error: `Çok fazla başarısız deneme. Lütfen ${lockDurationMinutes} dakika sonra tekrar deneyin.`,
      });
    }

    next();
  };
}

module.exports = { createAttemptRateLimiter };
