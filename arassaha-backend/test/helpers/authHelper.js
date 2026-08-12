// RBAC korumalı endpoint'leri test ederken kullanılacak JWT üretimi.
require('../setup');

// server.js'i (yan etki amaçlı) require etmek, .env'deki JWT_SECRET'in
// process.env'e yüklenmesini TETİKLER (bkz. server.js üst kısmı) — bu,
// aşağıdaki `require('../../middleware/auth')` çağrılmadan ÖNCE olmalı,
// aksi halde middleware/auth.js kendi JWT_SECRET sabitini (modül top-level'ında,
// yalnızca bir kere okunur) undefined ile önbelleğe alır ve üretilen token'lar
// verifyToken tarafından reddedilir. Test dosyaları zaten `app`'i de bu
// dosyadan önce require ediyor olsa da (bkz. örnek testler), bu satır sıraya
// bağımlı olmadan doğruluğu garanti eder.
require('../../server');

const jwt = require('jsonwebtoken');
const db = require('../../database');
const { JWT_SECRET } = require('../../middleware/auth');

// getTestToken(role): verilen role sahip, VERİTABANINDA GERÇEKTEN var olan
// (seedMinimalTestData ile eklenmiş) bir test kullanıcısı için geçerli bir
// JWT üretir. Kullanıcıyı DB'den okur (uydurma bir id değil) çünkü bazı
// endpoint'ler (örn. GET /api/auth/me, dispeçer hiyerarşi sorguları) token'daki
// id'nin gerçekten users tablosunda karşılığı olmasını varsayar.
function getTestToken(role) {
  const user = db.prepare('SELECT id, role FROM users WHERE role = ? ORDER BY id LIMIT 1').get(role);
  if (!user) {
    throw new Error(
      `getTestToken('${role}'): bu role sahip bir test kullanıcısı bulunamadı. ` +
        'Token istemeden önce resetTestDatabase() + seedMinimalTestData() çağrıldığından emin olun.'
    );
  }
  return jwt.sign({ id: user.id, role: user.role }, JWT_SECRET, { expiresIn: '1h' });
}

module.exports = { getTestToken };
