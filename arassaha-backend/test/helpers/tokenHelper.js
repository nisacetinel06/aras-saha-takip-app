// Test için JWT üretimi. Gerçek jsonwebtoken kütüphanesini kullanır (mock'lanmaz)
// — imzalama/doğrulama mantığının kendisi de dolaylı olarak test edilmiş olur.
//
// server.js .env dosyasını `process.loadEnvFile` ile yükler (bkz. server.js
// üst kısmı), ama bu test dosyası kasıtlı olarak server.js'i (dolayısıyla
// database.js'i) IMPORT ETMEZ — saf bir unit test katmanı olması gerekiyor
// (bkz. TEST-02, authMiddleware.test.js). Bu yüzden AYNI yükleme adımını
// burada tekrarlıyoruz. Üretim/CI ortamında .env dosyası yoksa (JWT_SECRET
// zaten ortam değişkeni olarak sağlanmışsa) sessizce devam edilir — server.js
// ile birebir aynı davranış.
const path = require('node:path');
try {
  process.loadEnvFile(path.join(__dirname, '..', '..', '.env'));
} catch {
  // .env yoksa sorun değil, bkz. yukarısı.
}

const jwt = require('jsonwebtoken');
// process.env.JWT_SECRET'i burada TEKRAR okumak yerine middleware/auth.js'in
// kendi export ettiği sabiti kullanıyoruz: middleware/auth.js bu sabiti kendi
// modülü ilk require edildiğinde (yukarıdaki loadEnvFile'dan SONRA, module
// cache sayesinde) bir kere okuyup dondurur. Aynı sabiti burada da kullanmak,
// testin imzaladığı token'ların middleware'in doğruladığı secret'la HER
// ZAMAN birebir aynı olmasını garanti eder (ayrı bir process.env okuması,
// yükleme sırası değişirse sessizce farklılaşabilirdi).
const { JWT_SECRET } = require('../../middleware/auth');

function generateValidToken(payload = { id: 1, role: 'teknisyen' }) {
  return jwt.sign(payload, JWT_SECRET, { expiresIn: '1h' });
}

function generateExpiredToken(payload = { id: 1, role: 'teknisyen' }) {
  return jwt.sign(payload, JWT_SECRET, { expiresIn: '-10s' }); // zaten süresi dolmuş
}

function generateInvalidSignatureToken(payload = { id: 1, role: 'teknisyen' }) {
  return jwt.sign(payload, 'yanlis-bir-secret', { expiresIn: '1h' }); // farklı secret'la imzalanmış, geçersiz
}

module.exports = { generateValidToken, generateExpiredToken, generateInvalidSignatureToken, JWT_SECRET };
