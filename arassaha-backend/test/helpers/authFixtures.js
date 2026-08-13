// TEST-06: routes/auth.js login akışı için sabit/bilinen kimlik bilgilerine
// sahip test kullanıcıları. TEST-02'deki seedMinimalTestData() genel amaçlı
// (RBAC/iş emri senaryoları için) olduğundan ve sicil_no/şifre kalıbı bu
// görevin ihtiyacı olan "aktif" + "pasif" karşılaştırmasını içermediğinden,
// burada AYRI ve bu göreve özel bir seed fonksiyonu tanımlanır.
require('../setup');
const bcrypt = require('bcrypt');
const db = require('../../database');

// routes/users.js'teki kullanıcı oluşturma koduyla (bkz. POST /api/users,
// bcrypt.hashSync(password, 10)) BİREBİR aynı hash'leme çağrısı — testin
// gerçek uygulama davranışını doğrulaması için farklı bir mantık uydurulmadı.
const BCRYPT_SALT_ROUNDS = 10;

const AUTH_TEST_USERS = {
  activeUser: {
    sicil_no: '9001',
    plainPassword: 'TestSifre123!',
    name: 'Test Aktif Kullanıcı',
    role: 'teknisyen',
    is_active: 1,
  },
  inactiveUser: {
    sicil_no: '9002',
    plainPassword: 'TestSifre123!',
    name: 'Test Pasif Kullanıcı',
    role: 'teknisyen',
    is_active: 0,
  },
};

// seedAuthTestUsers(): AUTH_TEST_USERS içindeki kullanıcıları test DB'sine
// ekler, id'lerini döner. resetTestDatabase() ile birlikte (ondan SONRA)
// çağrılmalı ki her test temiz bir başlangıçtan başlasın.
function seedAuthTestUsers() {
  const insertUser = db.prepare(
    'INSERT INTO users (name, role, sicil_no, password_hash, supervisor_id, is_active) VALUES (@name, @role, @sicil_no, @password_hash, NULL, @is_active)'
  );

  const ids = {};
  for (const [key, u] of Object.entries(AUTH_TEST_USERS)) {
    const password_hash = bcrypt.hashSync(u.plainPassword, BCRYPT_SALT_ROUNDS);
    const info = insertUser.run({
      name: u.name,
      role: u.role,
      sicil_no: u.sicil_no,
      password_hash,
      is_active: u.is_active,
    });
    ids[key] = info.lastInsertRowid;
  }

  return ids;
}

module.exports = { AUTH_TEST_USERS, seedAuthTestUsers };
