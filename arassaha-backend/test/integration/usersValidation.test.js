// TEST-09: routes/users.js'teki yazma endpoint'lerinin girdi doğrulama
// matrisi + özel senaryolar.
//
// ADIM 0 BULGULARI VE DÜZELTMELER (routes/users.js):
//   1) POST /api/users — `if (!name || !name.trim())`: name truthy-ama-
//      string-olmayan (örn. sayı) bir değer olduğunda `.trim()` TypeError
//      fırlatıp 500 dönüyordu. DÜZELTME: `typeof !== 'string'` eklendi.
//   2) POST /api/users VE PATCH /:id/reset-password — `if (!password ||
//      password.length < 4)`: password bir SAYI olarak gönderildiğinde
//      `.length` undefined döner, `undefined < 4` HER ZAMAN false'tur —
//      yani kontrol YANLIŞLIKLA GEÇİYORDU ve sayısal password doğrudan
//      `bcrypt.hashSync(sayı, 10)`'a gidiyordu; bcrypt string olmayan veri
//      için THROW ediyor → 500. DÜZELTME: `typeof !== 'string'` eklendi.
//   3) PATCH /:id — `name` alanı boş string olarak gönderildiğinde HİÇBİR
//      doğrulama yoktu (POST'ta vardı, PATCH'te yoktu) — DÜZELTME: POST ile
//      TUTARLI boş-string reddi eklendi.
//   4) MASS ASSIGNMENT: bu dosyada teknisyenin `role` alanını PATCH /:id
//      üzerinden değiştirmeye çalışması (kendi profili DAHİL) test edildi —
//      endpoint zaten `requireRole('yonetici')` ile korunuyor, RBAC bu
//      "yan kapıyı" da kapatıyor (açık bulunmadı).
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const request = require('supertest');
const app = require('../../server');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');
const { getTestToken } = require('../helpers/authHelper');
const { runInputValidationMatrix, assertAllRejected } = require('../helpers/inputValidationMatrix');

const VALID_ROLES = ['teknisyen', 'dispecer', 'yonetici'];
const VALID_JPEG_BUFFER = fs.readFileSync(path.join(__dirname, '..', 'fixtures', 'valid-test-image.jpg'));

function getUser(id) {
  return db.prepare('SELECT * FROM users WHERE id = ?').get(id);
}

describe('routes/users.js — girdi doğrulama matrisi + özel senaryolar', () => {
  let seeded;
  let managerToken;
  let technicianToken;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
    managerToken = getTestToken('yonetici');
    technicianToken = getTestToken('teknisyen');
  });

  describe('POST /api/users — matris', () => {
    it('name/sicil_no/password/role için kötü girdi varyasyonları 4xx dönmeli (500 ASLA)', async () => {
      const results = await runInputValidationMatrix({
        app,
        method: 'post',
        path: '/api/users',
        authToken: managerToken,
        validPayload: { name: 'Yeni Kullanıcı', sicil_no: '9001', password: 'gizli123', role: 'teknisyen' },
        fields: [
          { name: 'name', type: 'string', required: true },
          // sicil_no String(sicil_no).trim() ile sarmalanır — sayısal bir
          // değer BİLİNÇLİ olarak stringe coerce edilip kabul edilir.
          { name: 'sicil_no', type: 'string', required: true, skipWrongType: true },
          { name: 'password', type: 'string', required: true },
          { name: 'role', type: 'enum', required: true, enumValues: VALID_ROLES },
        ],
      });

      assertAllRejected(results, 'POST /api/users');
    });

    it('aynı sicil_no ile ikinci kullanıcı oluşturulamaz (409, ASLA 500)', async () => {
      await request(app)
        .post('/api/users')
        .set('Authorization', `Bearer ${managerToken}`)
        .send({ name: 'A', sicil_no: '7777', password: 'gizli123', role: 'teknisyen' });

      const response = await request(app)
        .post('/api/users')
        .set('Authorization', `Bearer ${managerToken}`)
        .send({ name: 'B', sicil_no: '7777', password: 'gizli123', role: 'teknisyen' });

      assert.strictEqual(response.status, 409);
    });

    it('teknisyen rolü POST /api/users çağıramaz (RBAC, matris dışı regresyon)', async () => {
      const response = await request(app)
        .post('/api/users')
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ name: 'X', sicil_no: '1234', password: 'gizli123', role: 'teknisyen' });
      assert.strictEqual(response.status, 403);
    });
  });

  describe('PATCH /api/users/:id — matris', () => {
    it('name/role için kötü girdi varyasyonları 4xx dönmeli (500 ASLA)', async () => {
      const results = await runInputValidationMatrix({
        app,
        method: 'patch',
        path: `/api/users/${seeded.users.otherTeknisyenId}`,
        authToken: managerToken,
        validPayload: { name: 'Güncellenmiş İsim', role: 'teknisyen' },
        fields: [
          { name: 'name', type: 'string', required: false },
          { name: 'role', type: 'enum', required: false, enumValues: VALID_ROLES },
        ],
      });

      assertAllRejected(results, 'PATCH /api/users/:id');
    });

    it('ADIM 0 DÜZELTMESİ: name boş string olarak gönderilirse 400 dönmeli (önceden sessizce kabul ediliyordu)', async () => {
      const before = getUser(seeded.users.otherTeknisyenId).name;
      const response = await request(app)
        .patch(`/api/users/${seeded.users.otherTeknisyenId}`)
        .set('Authorization', `Bearer ${managerToken}`)
        .send({ name: '' });
      assert.strictEqual(response.status, 400);
      assert.strictEqual(getUser(seeded.users.otherTeknisyenId).name, before);
    });

    it('MASS ASSIGNMENT / RBAC: teknisyen KENDİ profilinde role:\'yonetici\' enjekte etmeye çalışırsa 403 (endpoint zaten yalnızca yöneticiye açık)', async () => {
      const response = await request(app)
        .patch(`/api/users/${seeded.users.teknisyenId}`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ role: 'yonetici' });

      assert.strictEqual(response.status, 403);
      assert.strictEqual(getUser(seeded.users.teknisyenId).role, 'teknisyen', 'rol DEĞİŞMEMİŞ olmalı');
    });

    it('GÜVENLİK (regresyon): yönetici bile KENDİ rolünü PATCH ile değiştiremez', async () => {
      const response = await request(app)
        .patch(`/api/users/${seeded.users.yoneticiId}`)
        .set('Authorization', `Bearer ${managerToken}`)
        .send({ role: 'teknisyen' });

      assert.strictEqual(response.status, 400);
      assert.strictEqual(getUser(seeded.users.yoneticiId).role, 'yonetici');
    });
  });

  describe('PATCH /api/users/:id/reset-password — matris', () => {
    it('password alanı için kötü girdi varyasyonları 4xx dönmeli (500 ASLA)', async () => {
      const results = await runInputValidationMatrix({
        app,
        method: 'patch',
        path: `/api/users/${seeded.users.teknisyenId}/reset-password`,
        authToken: managerToken,
        validPayload: { password: 'yenisifre123' },
        fields: [{ name: 'password', type: 'string', required: true }],
      });

      assertAllRejected(results, 'PATCH /api/users/:id/reset-password');
    });
  });

  describe('Geçersiz ID (path parametresi)', () => {
    const idEndpoints = [
      { label: 'PATCH /:id', method: 'patch', build: (id) => `/api/users/${id}`, body: { name: 'x' } },
      { label: 'PATCH /:id/reset-password', method: 'patch', build: (id) => `/api/users/${id}/reset-password`, body: { password: 'yenisifre123' } },
      { label: 'PATCH /:id/reactivate', method: 'patch', build: (id) => `/api/users/${id}/reactivate`, body: {} },
      { label: 'POST /:id/photo', method: 'post', build: (id) => `/api/users/${id}/photo`, body: null, attachFile: true },
    ];

    function buildIdRequest(ep, id) {
      let req = request(app)[ep.method](ep.build(id)).set('Authorization', `Bearer ${managerToken}`);
      if (ep.attachFile) req = req.attach('photo', VALID_JPEG_BUFFER, { filename: 'x.jpg', contentType: 'image/jpeg' });
      else req = req.send(ep.body);
      return req;
    }

    for (const ep of idEndpoints) {
      it(`${ep.label}: sayısal olmayan id ("abc") → 400, ASLA 500`, async () => {
        const response = await buildIdRequest(ep, 'abc');
        assert.strictEqual(response.status, 400, `${ep.label}: ${JSON.stringify(response.body)}`);
      });

      it(`${ep.label}: negatif id (-1) → 404, ASLA 500`, async () => {
        const response = await buildIdRequest(ep, -1);
        assert.strictEqual(response.status, 404, `${ep.label}: ${JSON.stringify(response.body)}`);
      });

      it(`${ep.label}: aşırı büyük id → çökmeden 4xx döner`, async () => {
        const response = await buildIdRequest(ep, '999999999999999999999');
        assert.ok(response.status >= 400 && response.status < 500, `${ep.label}: beklenmedik status ${response.status}`);
      });
    }
  });
});
