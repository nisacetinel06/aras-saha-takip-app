// TEST-09: routes/workOrders.js'teki yazma (POST/PATCH) endpoint'lerinin
// beklenmeyen/hatalı girdi karşısında tutarlı ve güvenli davrandığını
// doğrular — bkz. test/helpers/inputValidationMatrix.js (ortak matris) ve
// ADIM 0 envanteri için test/integration/INPUT_VALIDATION_INVENTORY.md.
//
// ADIM 0 SIRASINDA BULUNAN VE DÜZELTİLEN BUG'LAR (routes/workOrders.js):
//   1) `if (!title || !title.trim())` — title SAYI gibi truthy-ama-string-
//      OLMAYAN bir değer olduğunda (`!title` false olduğu için) `.trim()`
//      çağrısı TypeError fırlatıyor, dış try/catch bunu YAKALAYIP 500
//      dönüyordu. DÜZELTME: `typeof title !== 'string'` kontrolü eklendi.
//   2) Aynı desen `description: description ? description.trim() : ''`
//      satırında da vardı (description opsiyonel olsa da truthy-ama-string-
//      olmayan bir değerle çökebilirdi) — aynı şekilde düzeltildi.
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const request = require('supertest');
const app = require('../../server');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');
const { getTestToken } = require('../helpers/authHelper');
const { runInputValidationMatrix, assertAllRejected } = require('../helpers/inputValidationMatrix');
const fs = require('fs');
const path = require('path');

const VALID_JPEG_BUFFER = fs.readFileSync(path.join(__dirname, '..', 'fixtures', 'valid-test-image.jpg'));

function getWorkOrder(id) {
  return db.prepare('SELECT * FROM work_orders WHERE id = ?').get(id);
}

describe('routes/workOrders.js — girdi doğrulama matrisi + özel senaryolar', () => {
  let seeded;
  let dispatcherToken;
  let technicianToken;
  let managerToken;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
    dispatcherToken = getTestToken('dispecer');
    technicianToken = getTestToken('teknisyen');
    managerToken = getTestToken('yonetici');
  });

  describe('POST /api/workorders — matris', () => {
    it('tüm alanlar için kötü girdi varyasyonları 4xx dönmeli (500 ASLA)', async () => {
      const results = await runInputValidationMatrix({
        app,
        method: 'post',
        path: '/api/workorders',
        authToken: dispatcherToken,
        validPayload: {
          title: 'Test İş Emri',
          description: 'açıklama',
          priority: 'normal',
          assigned_user_id: seeded.users.teknisyenId,
          equipment_id: seeded.equipmentId,
        },
        fields: [
          { name: 'title', type: 'string', required: true },
          { name: 'priority', type: 'enum', required: true, enumValues: ['acil', 'normal', 'dusuk'] },
          // assigned_user_id/equipment_id: Number.isInteger geçse bile (0/-1
          // dahil) DB'de karşılığı olmayan bir kullanıcı/ekipman her zaman
          // reddedilir (bkz. dosya içi "geçerli bir teknisyene/ekipmana ait
          // olmalı" kontrolleri) — rejectsZero:true bu davranışı doğrular.
          { name: 'assigned_user_id', type: 'number', required: true, rejectsZero: true },
          { name: 'equipment_id', type: 'number', required: true, rejectsZero: true },
        ],
      });

      assertAllRejected(results, 'POST /api/workorders');
    });

    // description opsiyoneldir ve eksik/null olduğunda güvenli bir
    // varsayılana (boş string) düşer — bu yüzden yukarıdaki matrise DAHİL
    // EDİLMEDİ (matrisin "her zaman reddedilir" varsayımı bu alan için
    // geçerli değil). Yine de crash-güvenliği (Adım 0 bulgusu #2) burada
    // ayrıca doğrulanıyor.
    it('description SAYI olarak gönderilirse 500 DEĞİL, 201 ile (boş stringe düşerek) kabul edilmeli', async () => {
      const response = await request(app)
        .post('/api/workorders')
        .set('Authorization', `Bearer ${dispatcherToken}`)
        .send({
          title: 'Test',
          description: 12345,
          priority: 'normal',
          assigned_user_id: seeded.users.teknisyenId,
          equipment_id: seeded.equipmentId,
        });

      assert.notStrictEqual(response.status, 500, `500 DÖNMEMELİ: ${JSON.stringify(response.body)}`);
      assert.strictEqual(response.status, 201);
    });

    it('MASS ASSIGNMENT: istek gövdesine status enjekte edilse bile yeni iş emri her zaman "acik" ile başlamalı', async () => {
      const response = await request(app)
        .post('/api/workorders')
        .set('Authorization', `Bearer ${dispatcherToken}`)
        .send({
          title: 'Sahte durumla iş emri',
          priority: 'normal',
          assigned_user_id: seeded.users.teknisyenId,
          equipment_id: seeded.equipmentId,
          status: 'cozuldu', // İSTEMCİNİN kötü niyetli/hatalı enjeksiyonu
        });

      assert.strictEqual(response.status, 201);
      assert.strictEqual(response.body.status, 'acik', 'status enjeksiyonu YOK SAYILMALI, her zaman acik ile başlamalı');

      const row = getWorkOrder(response.body.id);
      assert.strictEqual(row.status, 'acik', 'DB\'de de gerçekten acik olmalı');
    });

    it('teknisyen rolü POST /api/workorders çağıramaz (RBAC, matris dışı regresyon)', async () => {
      const response = await request(app)
        .post('/api/workorders')
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ title: 'x', priority: 'normal', assigned_user_id: seeded.users.teknisyenId, equipment_id: seeded.equipmentId });
      assert.strictEqual(response.status, 403);
    });
  });

  describe('PATCH /api/workorders/:id/status — matris', () => {
    it('status alanı için kötü girdi varyasyonları 4xx dönmeli (500 ASLA)', async () => {
      const results = await runInputValidationMatrix({
        app,
        method: 'patch',
        path: `/api/workorders/${seeded.workOrders.ownWorkOrderId}/status`,
        authToken: technicianToken,
        validPayload: { status: 'yolda' },
        fields: [{ name: 'status', type: 'enum', required: true, enumValues: ['acik', 'yolda', 'sahada', 'cozuldu'] }],
      });

      assertAllRejected(results, 'PATCH /api/workorders/:id/status');
      // Matristeki HİÇBİR senaryo gerçekten geçerli bir geçiş göndermedi
      // (hepsi status alanının kendisini bozuyordu) — iş emri hâlâ 'acik'
      // olmalı, matris çalışırken yanlışlıkla ilerlememiş olmalı.
      assert.strictEqual(getWorkOrder(seeded.workOrders.ownWorkOrderId).status, 'acik');
    });
  });

  describe('PATCH /api/workorders/:id/assign — matris', () => {
    it('assigned_user_id alanı için kötü girdi varyasyonları 4xx dönmeli (500 ASLA)', async () => {
      const results = await runInputValidationMatrix({
        app,
        method: 'patch',
        path: `/api/workorders/${seeded.workOrders.ownWorkOrderId}/assign`,
        authToken: dispatcherToken,
        validPayload: { assigned_user_id: seeded.users.teknisyenId },
        fields: [{ name: 'assigned_user_id', type: 'number', required: true, rejectsZero: true }],
      });

      assertAllRejected(results, 'PATCH /api/workorders/:id/assign');
    });
  });

  describe('Geçersiz ID (path parametresi) — :id alan TÜM POST/PATCH endpoint\'ler', () => {
    // POST /:id/photos: `!req.file` kontrolü id doğrulamasından SONRA ama
    // work order varlık kontrolünden ÖNCE çalışıyor — bu yüzden -1/aşırı
    // büyük id senaryolarının GERÇEKTEN "kayıt yok" (404) dalına ulaşabilmesi
    // için geçerli bir dosya EKLENMESİ gerekiyor, aksi halde her zaman
    // "photo alanı zorunludur" (400) ile erken döner (bu da 4xx, ama id
    // doğrulamasının kendisini test etmez).
    const idEndpoints = [
      { label: 'PATCH /:id/status', method: 'patch', build: (id) => `/api/workorders/${id}/status`, token: () => technicianToken, body: { status: 'yolda' } },
      { label: 'PATCH /:id/assign', method: 'patch', build: (id) => `/api/workorders/${id}/assign`, token: () => dispatcherToken, body: { assigned_user_id: 1 } },
      { label: 'POST /:id/photos', method: 'post', build: (id) => `/api/workorders/${id}/photos`, token: () => technicianToken, body: null, attachFile: true },
    ];

    function buildIdRequest(ep, id) {
      let req = request(app)[ep.method](ep.build(id)).set('Authorization', `Bearer ${ep.token()}`);
      if (ep.body) req = req.send(ep.body);
      if (ep.attachFile) req = req.attach('photo', VALID_JPEG_BUFFER, { filename: 'x.jpg', contentType: 'image/jpeg' });
      return req;
    }

    for (const ep of idEndpoints) {
      it(`${ep.label}: sayısal olmayan id ("abc") → 400, ASLA 500`, async () => {
        const response = await buildIdRequest(ep, 'abc');
        assert.strictEqual(response.status, 400, `${ep.label}: ${JSON.stringify(response.body)}`);
      });

      it(`${ep.label}: negatif id (-1) → 404 (kayıt yok), ASLA 500`, async () => {
        const response = await buildIdRequest(ep, -1);
        assert.strictEqual(response.status, 404, `${ep.label}: ${JSON.stringify(response.body)}`);
      });

      it(`${ep.label}: aşırı büyük id (integer taşması) → çökmeden 4xx döner`, async () => {
        const response = await buildIdRequest(ep, '999999999999999999999');
        assert.ok(response.status >= 400 && response.status < 500, `${ep.label}: beklenmedik status ${response.status}`);
      });
    }
  });

  // TEST-13 (coverage analizi) bulgusu: GET /:id yukarıdaki matrise dahil
  // değildi (matris kasıtlı olarak yalnızca POST/PATCH'i kapsıyor) — bu
  // yüzden satır 360-361 (`!Number.isInteger(id)` → 400 dalı) hiç
  // kapsanmıyordu. IDOR koruması (SEC-02, aynı handler) zaten test
  // ediliyordu, ama id doğrulamasının kendisi eksikti.
  describe('Geçersiz ID (path parametresi) — GET /:id', () => {
    it('sayısal olmayan id ("abc") → 400, ASLA 500', async () => {
      const response = await request(app)
        .get('/api/workorders/abc')
        .set('Authorization', `Bearer ${technicianToken}`);
      assert.strictEqual(response.status, 400, JSON.stringify(response.body));
    });
  });
});
