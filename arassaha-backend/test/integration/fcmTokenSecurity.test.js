// TEST-16: POST /api/auth/register-fcm-token (Push Bildirim/FCM, Modül 7) —
// sahiplik (mass assignment), girdi doğrulama, overwrite ve bilgi ifşası testleri.
//
// ADIM 0 BULGUSU: routes/auth.js'teki register-fcm-token GÜNCELLEMESİ ZATEN
// SADECE req.user.id (doğrulanmış JWT'den, verifyToken middleware'i tarafından
// set edilir) kullanıyordu — body'den herhangi bir user_id/target_id ASLA
// okunmuyordu. Kod incelemesiyle DOĞRULANDI, mass-assignment açığı YOKTU,
// düzeltme GEREKMEDİ. Bu dosya bunu GERÇEK bir enjeksiyon denemesiyle (SEC-02/
// TEST-09 tarzı) kanıtlıyor.
//
// Bu görevde BULUNAN VE DÜZELTİLEN iki küçük eksiklik:
//   1) Girdi doğrulama: fcm_token boş string ('') veya aşırı uzun (>500
//      karakter) gönderildiğinde ÖNCEDEN hiçbir kontrol yoktu (yalnızca
//      tip kontrolü vardı: null veya string). DÜZELTME: boş string ve 500
//      karakteri aşan değerler artık 400 ile reddediliyor.
//   2) Logout sonrası fcm_token temizliği: normal akışta bunu ZATEN Flutter
//      tarafı yapıyor (AuthProvider.logout, backend'e POST /logout'tan ÖNCE
//      POST /register-fcm-token'a `fcm_token: null` gönderir — bkz. o dosyanın
//      dosya başı yorumu). Ama POST /api/auth/logout (kasıtlı olarak
//      verifyToken KULLANMAZ, süresi dolmuş access token'la bile
//      çalışabilmeli) bunu KENDİSİ garanti etmiyordu — istemci tarafındaki
//      adım herhangi bir nedenle atlanırsa (ör. PushNotificationService
//      hatası, uygulama kapanması), fcm_token DB'de kalır ve çıkış yapmış bir
//      kullanıcıya push bildirimi gönderilmeye DEVAM EDİLİRDİ. DÜZELTME:
//      /logout artık ilişkili refresh_token kaydından (zaten DB'de doğrulanmış
//      olan record.user_id) kullanıcının fcm_token'ını da NULL'a çekiyor —
//      savunma derinliği, istemci tarafı davranışını DEĞİŞTİRMEZ.
//
// Bilgi ifşası (madde 6): GET /api/users/:id ve GET /api/users response'ları
// (routes/users.js FULL_FIELDS/PICKER_FIELDS) fcm_token'ı ZATEN içermiyordu —
// kod incelemesiyle DOĞRULANDI, düzeltme GEREKMEDİ. Bu dosya bunu response
// body'sinde `fcm_token` anahtarının HİÇ olmadığını doğrulayarak kanıtlıyor.
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const request = require('supertest');
const app = require('../../server');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');
const { getTestToken } = require('../helpers/authHelper');
const { issueRefreshToken } = require('../../utils/refreshToken');

function getUserFromDb(id) {
  return db.prepare('SELECT * FROM users WHERE id = ?').get(id);
}

describe('POST /api/auth/register-fcm-token — güvenlik + doğrulama', () => {
  let seeded;
  let userAToken;
  let userA;
  let userB;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
    // seedMinimalTestData iki teknisyen üretir (teknisyenId = A, otherTeknisyenId
    // = B) — mass-assignment testinin "başka bir kullanıcı" hedefi için ikinci
    // bir kullanıcı gerekir.
    userA = getUserFromDb(seeded.users.teknisyenId);
    userB = getUserFromDb(seeded.users.otherTeknisyenId);
    userAToken = getTestToken('teknisyen'); // getTestToken en küçük id'yi seçer -> userA
  });

  it('[GÜVENLİK KANITI] kullanıcı SADECE kendi fcm_token\'ını güncelleyebilmeli, body\'de başka bir id gönderse bile', async () => {
    const response = await request(app)
      .post('/api/auth/register-fcm-token')
      .set('Authorization', `Bearer ${userAToken}`)
      .send({ fcm_token: 'sahte-token-A', user_id: userB.id, id: userB.id, target_id: userB.id });

    assert.strictEqual(response.status, 200);

    const userAFromDb = getUserFromDb(userA.id);
    const userBFromDb = getUserFromDb(userB.id);

    assert.strictEqual(userAFromDb.fcm_token, 'sahte-token-A');
    assert.notStrictEqual(userBFromDb.fcm_token, 'sahte-token-A');
    assert.strictEqual(userBFromDb.fcm_token, null, 'B\'nin token\'ı hiç dokunulmamış (null) kalmalı');
  });

  it('token olmadan istek 401 dönmeli', async () => {
    const response = await request(app).post('/api/auth/register-fcm-token').send({ fcm_token: 'test' });
    assert.strictEqual(response.status, 401);
  });

  it('eksik fcm_token reddedilmeli', async () => {
    const response = await request(app)
      .post('/api/auth/register-fcm-token')
      .set('Authorization', `Bearer ${userAToken}`)
      .send({});
    assert.strictEqual(response.status, 400);
  });

  it('boş string fcm_token reddedilmeli', async () => {
    const response = await request(app)
      .post('/api/auth/register-fcm-token')
      .set('Authorization', `Bearer ${userAToken}`)
      .send({ fcm_token: '' });
    assert.strictEqual(response.status, 400);
  });

  it('aşırı uzun bir fcm_token reddedilmeli (gerçek FCM token\'ları makul bir uzunlukta olur)', async () => {
    const tooLong = 'a'.repeat(5000);
    const response = await request(app)
      .post('/api/auth/register-fcm-token')
      .set('Authorization', `Bearer ${userAToken}`)
      .send({ fcm_token: tooLong });
    assert.strictEqual(response.status, 400);
  });

  it('null fcm_token KABUL EDİLMELİ (Flutter çıkış akışının kasıtlı "temizle" sinyali)', async () => {
    await request(app)
      .post('/api/auth/register-fcm-token')
      .set('Authorization', `Bearer ${userAToken}`)
      .send({ fcm_token: 'bir-token' });

    const response = await request(app)
      .post('/api/auth/register-fcm-token')
      .set('Authorization', `Bearer ${userAToken}`)
      .send({ fcm_token: null });

    assert.strictEqual(response.status, 200);
    assert.strictEqual(getUserFromDb(userA.id).fcm_token, null);
  });

  it('yeni bir token kaydı eskisinin üzerine yazmalı (tek cihaz varsayımı)', async () => {
    await request(app)
      .post('/api/auth/register-fcm-token')
      .set('Authorization', `Bearer ${userAToken}`)
      .send({ fcm_token: 'ilk-token' });
    await request(app)
      .post('/api/auth/register-fcm-token')
      .set('Authorization', `Bearer ${userAToken}`)
      .send({ fcm_token: 'ikinci-token' });

    assert.strictEqual(getUserFromDb(userA.id).fcm_token, 'ikinci-token');
  });

  it('[TEST-16 savunma derinliği] POST /api/auth/logout, ilişkili kullanıcının fcm_token\'ını da temizlemeli', async () => {
    // İstemci adımını (register-fcm-token null) BİLİNÇLİ olarak ATLAYIP,
    // sunucunun logout içinde KENDİ BAŞINA temizlediğini kanıtlıyoruz —
    // gerçek akışta bu zaten Flutter tarafından da yapılır, burada sadece
    // sunucu tarafı garantisi test ediliyor.
    await request(app)
      .post('/api/auth/register-fcm-token')
      .set('Authorization', `Bearer ${userAToken}`)
      .send({ fcm_token: 'test-token' });
    assert.strictEqual(getUserFromDb(userA.id).fcm_token, 'test-token');

    const refreshToken = issueRefreshToken(userA.id);
    const logoutResponse = await request(app).post('/api/auth/logout').send({ refresh_token: refreshToken });

    assert.strictEqual(logoutResponse.status, 200);
    assert.strictEqual(getUserFromDb(userA.id).fcm_token, null);
  });

  it('geçersiz/bilinmeyen bir refresh_token ile logout yine 200 döner (idempotent) ve BAŞKA kullanıcının fcm_token\'ına DOKUNMAZ', async () => {
    await request(app)
      .post('/api/auth/register-fcm-token')
      .set('Authorization', `Bearer ${userAToken}`)
      .send({ fcm_token: 'dokunulmamali' });

    const response = await request(app).post('/api/auth/logout').send({ refresh_token: 'gecersiz-bir-token' });

    assert.strictEqual(response.status, 200);
    assert.strictEqual(getUserFromDb(userA.id).fcm_token, 'dokunulmamali');
  });
});

describe('fcm_token bilgi ifşası kontrolü (routes/users.js)', () => {
  let seeded;
  let managerToken;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
    managerToken = getTestToken('yonetici');

    db.prepare('UPDATE users SET fcm_token = ? WHERE id = ?').run('gizli-fcm-degeri', seeded.users.teknisyenId);
  });

  it('GET /api/users/:id (yönetici, FULL_FIELDS) response\'unda fcm_token anahtarı BULUNMAMALI', async () => {
    const response = await request(app)
      .get(`/api/users/${seeded.users.teknisyenId}`)
      .set('Authorization', `Bearer ${managerToken}`);

    assert.strictEqual(response.status, 200);
    assert.strictEqual(
      Object.prototype.hasOwnProperty.call(response.body, 'fcm_token'),
      false,
      'GET /api/users/:id yanıtı fcm_token sızdırıyor'
    );
  });

  it('GET /api/users (yönetici listesi, FULL_FIELDS) response\'unda HİÇBİR kullanıcı için fcm_token anahtarı BULUNMAMALI', async () => {
    const response = await request(app).get('/api/users').set('Authorization', `Bearer ${managerToken}`);

    assert.strictEqual(response.status, 200);
    assert.ok(response.body.length > 0);
    for (const user of response.body) {
      assert.strictEqual(
        Object.prototype.hasOwnProperty.call(user, 'fcm_token'),
        false,
        `GET /api/users yanıtı (id=${user.id}) fcm_token sızdırıyor`
      );
    }
  });
});
