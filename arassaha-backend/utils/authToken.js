// Access token (kısa ömürlü JWT) + refresh token (uzun ömürlü, sunucu
// tarafında iptal edilebilir — bkz. utils/refreshToken.js) çiftinin
// üretimi. routes/auth.js login akışı VE routes/twoFactor.js POST
// /2fa/verify (2FA doğrulaması BAŞARILI olduktan SONRAKİ "gerçek" token)
// tarafından paylaşılır — tek bir yerde tutulur ki token claim'leri/ömrü
// iki ayrı yerde birbirinden bağımsız kopyalanıp zamanla farklılaşmasın.
//
// GÜVENLİK NOTU: access token ömrü 7 günden 15 dakikaya düşürüldü —
// çalınan bir access token artık YALNIZCA çok kısa bir pencerede işe
// yarar. Uzun ömürlü oturum artık refresh_token (30 gün) üzerinden,
// sunucu tarafında İZLENEBİLİR/İPTAL EDİLEBİLİR şekilde sağlanır (bkz.
// "Güvenli Token Saklama" görevindeki orijinal 7 günlük stateless JWT
// kısıtının çözümü).
const jwt = require('jsonwebtoken');
const { JWT_SECRET } = require('../middleware/auth');
const { issueRefreshToken } = require('./refreshToken');

// ACCESS_TOKEN_EXPIRES_IN_OVERRIDE: yalnızca YEREL/manuel cihaz testleri için
// (bkz. DB_PATH/PURGE_TEST_UPLOADS_ROOT ile AYNI "ortam değişkeni ile test-only
// geçiş" deseni) — 15 dakika gerçek zamanlı beklemeden sessiz yenileme (silent
// refresh) davranışını GERÇEK bir cihazda GERÇEK zamanla kanıtlamak için. Railway
// production ortamında bu değişken HİÇ tanımlı DEĞİL, bu yüzden production
// davranışı ETKİLENMEZ; yalnızca bilinçli olarak ayarlandığında devreye girer.
const ACCESS_TOKEN_EXPIRES_IN =
  process.env.ACCESS_TOKEN_EXPIRES_IN_OVERRIDE || '15m';

/**
 * @param {{id: number, role: string}} user
 * @param {object} [options]
 * @param {string} [options.expiresIn] - YALNIZCA testler için: gerçek
 *   ömrü geçici olarak kısaltıp (örn. '2s') süre dolumu davranışını
 *   hızlıca test edebilmek için bir çıkış kapısı. Hiçbir API isteğiyle
 *   (query/body parametresi DEĞİL, yalnızca sunucu tarafı kod çağrısı)
 *   kontrol edilemez — production'a asla sızamaz.
 */
function generateAccessToken(user, { expiresIn = ACCESS_TOKEN_EXPIRES_IN } = {}) {
  return jwt.sign({ id: user.id, role: user.role }, JWT_SECRET, { expiresIn });
}

/**
 * Login/2FA doğrulaması BAŞARILI olduktan sonra döndürülecek TAM token
 * çifti. [accessTokenExpiresIn] yalnızca testler içindir (bkz. generateAccessToken).
 */
function issueTokenPair(user, { accessTokenExpiresIn } = {}) {
  return {
    accessToken: generateAccessToken(user, { expiresIn: accessTokenExpiresIn }),
    refreshToken: issueRefreshToken(user.id),
  };
}

module.exports = { generateAccessToken, issueTokenPair, ACCESS_TOKEN_EXPIRES_IN };
