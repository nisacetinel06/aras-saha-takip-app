// Login brute-force koruması — sicil_no + IP kombinasyonu bazında izleme,
// LOCK_THRESHOLD (5) başarısız denemeden sonra kısa süreli kilit (429).
//
// SECURITY_NOTES.md "Login endpoint'inde rate limiting / brute-force koruması
// yok (TEST-06)" maddesinin çözümü — bkz. middleware/loginRateLimit.js,
// database.js (login_attempts tablosu) ve routes/auth.js.
//
// Adım 0'daki ilk test ([GÜVENLİK AÇIĞI KANITI]) fix'ten ÖNCE çalıştırılıp
// gerçekten 401 döndüğü (yani sınırsız deneme yapılabildiği) doğrulandı —
// bkz. görev raporu. Fix uygulandıktan sonra bu dosyadaki assert 429'a
// güncellendi (kırmızı->yeşil geçiş).
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const request = require('supertest');
const app = require('../../server');
const { resetTestDatabase } = require('../helpers/testDb');
const { AUTH_TEST_USERS, seedAuthTestUsers } = require('../helpers/authFixtures');
const { LOCK_THRESHOLD } = require('../../middleware/loginRateLimit');

describe('POST /api/auth/login — brute-force koruması (sicil_no + IP kilidi)', () => {
  beforeEach(() => {
    resetTestDatabase();
    seedAuthTestUsers();
  });

  it('[GÜVENLİK AÇIĞI KANITI -> DÜZELTME] LOCK_THRESHOLD başarısız denemeden sonra sonraki deneme 429 döner', async () => {
    for (let i = 0; i < 10; i++) {
      await request(app)
        .post('/api/auth/login')
        .send({ sicil_no: AUTH_TEST_USERS.activeUser.sicil_no, password: 'yanlis-sifre' });
    }
    // Fix ÖNCESİ: bu 401 dönüyordu (sınırsız deneme mümkündü, hiçbir kilit yoktu).
    // Fix SONRASI (BEKLENEN, bu assert): 429 — LOCK_THRESHOLD (5) çoktan aşıldığı için.
    const response = await request(app)
      .post('/api/auth/login')
      .send({ sicil_no: AUTH_TEST_USERS.activeUser.sicil_no, password: 'yanlis-sifre' });
    assert.strictEqual(response.status, 429);
    assert.strictEqual(typeof response.body.error, 'string');
  });

  it('tam olarak LOCK_THRESHOLD kadar başarısız deneme + hemen sonraki DOĞRU şifreyle giriş: yine 429 (kilit doğru şifreyi de reddeder)', async () => {
    for (let i = 0; i < LOCK_THRESHOLD; i++) {
      const r = await request(app)
        .post('/api/auth/login')
        .send({ sicil_no: AUTH_TEST_USERS.activeUser.sicil_no, password: 'yanlis-sifre' });
      assert.strictEqual(r.status, 401, `${i + 1}. deneme eşiğe henüz ulaşmamış olmalı (401)`);
    }

    const response = await request(app)
      .post('/api/auth/login')
      .send({ sicil_no: AUTH_TEST_USERS.activeUser.sicil_no, password: AUTH_TEST_USERS.activeUser.plainPassword });

    assert.strictEqual(response.status, 429, 'eşiğe ulaşıldıktan sonra DOĞRU şifre bile işe yaramamalı');
    assert.strictEqual(response.body.access_token, undefined);
  });

  it('farklı IP\'den aynı sicil_no: bir IP kilitlense de farklı bir IP\'nin kendi sayacı temiz kalır (IP+sicil_no kombinasyonu)', async () => {
    const IP_A = '10.0.0.1';
    const IP_B = '10.0.0.2';

    for (let i = 0; i < LOCK_THRESHOLD; i++) {
      const r = await request(app)
        .post('/api/auth/login')
        .set('X-Forwarded-For', IP_A)
        .send({ sicil_no: AUTH_TEST_USERS.activeUser.sicil_no, password: 'yanlis-sifre' });
      assert.strictEqual(r.status, 401);
    }

    const lockedResponse = await request(app)
      .post('/api/auth/login')
      .set('X-Forwarded-For', IP_A)
      .send({ sicil_no: AUTH_TEST_USERS.activeUser.sicil_no, password: AUTH_TEST_USERS.activeUser.plainPassword });
    assert.strictEqual(lockedResponse.status, 429, 'IP-A kilitli olmalı');

    const otherIpResponse = await request(app)
      .post('/api/auth/login')
      .set('X-Forwarded-For', IP_B)
      .send({ sicil_no: AUTH_TEST_USERS.activeUser.sicil_no, password: AUTH_TEST_USERS.activeUser.plainPassword });
    assert.strictEqual(otherIpResponse.status, 200, 'IP-B hiç denemedi, kendi sayacı temiz olduğu için başarılı olmalı');
    assert.strictEqual(typeof otherIpResponse.body.access_token, 'string');
  });

  it('farklı sicil_no aynı IP: bir sicil_no kilitlense de aynı IP\'den farklı bir sicil_no\'nun kendi sayacı temiz kalır', async () => {
    for (let i = 0; i < LOCK_THRESHOLD; i++) {
      const r = await request(app)
        .post('/api/auth/login')
        .send({ sicil_no: AUTH_TEST_USERS.activeUser.sicil_no, password: 'yanlis-sifre' });
      assert.strictEqual(r.status, 401);
    }

    const lockedResponse = await request(app)
      .post('/api/auth/login')
      .send({ sicil_no: AUTH_TEST_USERS.activeUser.sicil_no, password: AUTH_TEST_USERS.activeUser.plainPassword });
    assert.strictEqual(lockedResponse.status, 429, AUTH_TEST_USERS.activeUser.sicil_no + ' kilitli olmalı');

    const otherUserResponse = await request(app)
      .post('/api/auth/login')
      .send({ sicil_no: AUTH_TEST_USERS.inactiveUser.sicil_no, password: AUTH_TEST_USERS.inactiveUser.plainPassword });
    // inactiveUser is_active=0 olduğu için 403 döner (login_attempts'a değil,
    // rate-limit sayacına bakıyoruz) — kilitlenmediğini (429 DEĞİL) kanıtlamak yeterli.
    assert.notStrictEqual(otherUserResponse.status, 429, AUTH_TEST_USERS.inactiveUser.sicil_no + ' kendi sayacı temiz olduğu için kilitlenmemeli');
    assert.strictEqual(otherUserResponse.status, 403);
  });

  it('var olmayan bir sicil_no da AYNI şekilde kilitlenir (user enumeration önleme)', async () => {
    const NON_EXISTENT_SICIL_NO = '99999';

    for (let i = 0; i < LOCK_THRESHOLD; i++) {
      const r = await request(app)
        .post('/api/auth/login')
        .send({ sicil_no: NON_EXISTENT_SICIL_NO, password: 'her-hangi-bir-sifre' });
      assert.strictEqual(r.status, 401);
    }

    const response = await request(app)
      .post('/api/auth/login')
      .send({ sicil_no: NON_EXISTENT_SICIL_NO, password: 'her-hangi-bir-sifre' });
    assert.strictEqual(response.status, 429, 'var olmayan sicil_no da var olan sicil_no ile AYNI şekilde kilitlenmeli');
  });
});
