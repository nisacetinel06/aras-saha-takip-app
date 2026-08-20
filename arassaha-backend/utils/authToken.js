// Tam yetkili (giriş sonrası) JWT üretimi — routes/auth.js login akışı VE
// routes/twoFactor.js POST /2fa/verify (2FA doğrulaması BAŞARILI olduktan
// SONRAKİ "gerçek" token) tarafından paylaşılır. Tek bir yerde tutulur ki
// token claim'leri/ömrü (id, role, 7 gün) iki ayrı yerde birbirinden
// bağımsız kopyalanıp zamanla farklılaşmasın.
const jwt = require('jsonwebtoken');
const { JWT_SECRET } = require('../middleware/auth');

function generateFullAuthToken(user) {
  return jwt.sign({ id: user.id, role: user.role }, JWT_SECRET, { expiresIn: '7d' });
}

module.exports = { generateFullAuthToken };
