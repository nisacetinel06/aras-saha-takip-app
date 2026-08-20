// Refresh Token yönetimi — bkz. database.js refresh_tokens tablosu,
// routes/auth.js POST /refresh (rotasyon + yeniden kullanım tespiti) ve
// POST /logout (sunucu taraflı iptal).
//
// GERÇEKLİK NOTU: Görev taslağı issueRefreshToken'ı `async function` olarak
// öneriyordu — ama bu projede DB katmanı (node:sqlite DatabaseSync) TAMAMEN
// SENKRON çalışır (bkz. database.js ve tüm routes/*.js) ve burada bcrypt
// gibi bilerek yavaş/asenkron bir işlem de YOK (SHA-256 anlıktır). Bu
// yüzden fonksiyonlar BİLEREK senkron bırakıldı — bu, projenin geri
// kalanıyla tutarlılığı korur, gereksiz Promise sarmalamaya gerek bırakmaz.
const crypto = require('crypto');
const db = require('../database');

const REFRESH_TOKEN_EXPIRY_DAYS = 30;

function generateRefreshToken() {
  return crypto.randomBytes(32).toString('hex');
}

// GÜVENLİK NOTU — neden bcrypt DEĞİL, SHA-256: password_hash'teki (bcrypt,
// BİLEREK yavaş) yaklaşımdan FARKLI bir karar burada. Şifreler İNSAN
// TARAFINDAN SEÇİLİR — kısa, tahmin edilebilir kalıplar taşıyabilir; bu
// yüzden çalınmış bir hash'ten düz metni "deneyerek bulmayı" YAVAŞLATMAK
// (bcrypt'in tüm amacı) burada anlamlı bir savunmadır. Refresh token ise
// crypto.randomBytes(32) ile üretilen 256 bitlik, TAMAMEN rastgele bir
// değerdir — insan tahmini/kalıp arama burada işe yaramaz, 2^256 olasılık
// arasından brute-force ile bulmak zaten pratikte imkânsızdır. bcrypt'in
// yavaşlığı burada HİÇBİR ek güvenlik sağlamadan yalnızca her /refresh
// isteğine gereksiz bir CPU maliyeti (bcrypt ~100ms+) katardı — SHA-256
// (mikrosaniyeler) burada doğru ve yeterli tercihtir.
function hashToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

/**
 * Yeni bir refresh token üretir, yalnızca HASH'ini DB'ye yazar, HAM
 * (plaintext) halini döner — bu, ham token'ın var olduğu TEK andır; bir
 * daha asla geri okunamaz/gösterilemez (bkz. database.js şema notu).
 */
function issueRefreshToken(userId) {
  const rawToken = generateRefreshToken();
  const tokenHash = hashToken(rawToken);
  const now = new Date();
  const expiresAt = new Date(
    now.getTime() + REFRESH_TOKEN_EXPIRY_DAYS * 24 * 60 * 60 * 1000
  ).toISOString();

  db.prepare(
    `INSERT INTO refresh_tokens (user_id, token_hash, created_at, expires_at, revoked)
     VALUES (?, ?, ?, ?, 0)`
  ).run(userId, tokenHash, now.toISOString(), expiresAt);

  return rawToken;
}

function findRefreshTokenByHash(tokenHash) {
  return db.prepare('SELECT * FROM refresh_tokens WHERE token_hash = ?').get(tokenHash);
}

/** Tek bir refresh token'ı iptal eder — rotasyonda (yenisiyle değiştirilirken,
 * [replacedByTokenHash] doldurulur) ya da logout'ta (null kalır) kullanılır. */
function revokeRefreshToken(id, replacedByTokenHash = null) {
  db.prepare(
    'UPDATE refresh_tokens SET revoked = 1, replaced_by_token_hash = ? WHERE id = ?'
  ).run(replacedByTokenHash, id);
}

/** Bir kullanıcının TÜM refresh token'larını iptal eder — yeniden kullanım
 * tespiti (bkz. routes/auth.js POST /refresh) tetiklendiğinde "her yerden
 * zorla çıkış" için kullanılan savunmacı tepki. */
function revokeAllRefreshTokensForUser(userId) {
  db.prepare('UPDATE refresh_tokens SET revoked = 1 WHERE user_id = ?').run(userId);
}

module.exports = {
  REFRESH_TOKEN_EXPIRY_DAYS,
  generateRefreshToken,
  hashToken,
  issueRefreshToken,
  findRefreshTokenByHash,
  revokeRefreshToken,
  revokeAllRefreshTokensForUser,
};
