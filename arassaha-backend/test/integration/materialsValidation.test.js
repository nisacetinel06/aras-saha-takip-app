// TEST-09: routes/materials.js'teki yazma endpoint'lerinin girdi doğrulama
// matrisi + özel senaryolar.
//
// ADIM 0 BULGULARI VE DÜZELTMELER (routes/materials.js):
//   1) PATCH /materials/:id — `name` alanı boş string olarak gönderildiğinde
//      HİÇBİR doğrulama yoktu (POST /materials'ta vardı, PATCH'te yoktu) —
//      DÜZELTME: POST ile TUTARLI boş-string reddi eklendi.
//   2) POST /materials VE PATCH /materials/:id — `unit_cost` HİÇ
//      doğrulanmıyordu (negatif bir birim maliyet sessizce kabul
//      ediliyordu). PATCH /materials/:id'de ayrıca `min_stock_threshold` da
//      hiç doğrulanmıyordu (POST'ta vardı, PATCH'te YOKTU). DÜZELTME: her iki
//      endpoint'e de TUTARLI negatif-reddi eklendi.
//   3) Mass assignment: POST /materials/:id/restock ve POST .../materials
//      gibi endpoint'lerde stok yalnızca ilgili hareket (ikmal/kullanım)
//      üzerinden değişiyor; PATCH /materials/:id, `stock_quantity` alanını
//      HİÇ okumuyor (bilinçli tasarım, bkz. route içi yorum) — bu dosyada bu
//      korumanın gerçekten bypass edilemediği doğrulanıyor.
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const request = require('supertest');
const app = require('../../server');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');
const { getTestToken } = require('../helpers/authHelper');
const { seedTestMaterial } = require('../helpers/materialFixtures');
const { runInputValidationMatrix, assertAllRejected } = require('../helpers/inputValidationMatrix');

const VALID_CATEGORIES = ['kablo', 'sigorta', 'izolator', 'konnektor', 'diger'];
const VALID_UNITS = ['adet', 'metre', 'kg'];

function getMaterial(id) {
  return db.prepare('SELECT * FROM materials WHERE id = ?').get(id);
}

describe('routes/materials.js — girdi doğrulama matrisi + özel senaryolar', () => {
  let seeded;
  let managerToken;
  let technicianToken;
  let materialId;
  let workOrderId;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
    managerToken = getTestToken('yonetici');
    technicianToken = getTestToken('teknisyen');
    materialId = seedTestMaterial({ stock_quantity: 20, min_stock_threshold: 5 });
    workOrderId = seeded.workOrders.ownWorkOrderId;
  });

  describe('POST /api/materials — matris', () => {
    it('name/category/unit/stock_quantity/min_stock_threshold/unit_cost için kötü girdi varyasyonları 4xx dönmeli (500 ASLA)', async () => {
      const results = await runInputValidationMatrix({
        app,
        method: 'post',
        path: '/api/materials',
        authToken: managerToken,
        validPayload: {
          name: 'Yeni Malzeme',
          category: 'kablo',
          unit: 'adet',
          stock_quantity: 10,
          min_stock_threshold: 2,
          unit_cost: 50,
          compatible_equipment_types: ['trafo'],
        },
        fields: [
          // name String(name).trim() ile sarmalanır — sayısal bir değer
          // (örn. 12345) BİLİNÇLİ olarak "12345" stringine coerce edilip
          // KABUL edilir (users.js'teki sicil_no ile AYNI desen) — bu yüzden
          // skipWrongType:true.
          { name: 'name', type: 'string', required: true, skipWrongType: true },
          { name: 'category', type: 'enum', required: true, enumValues: VALID_CATEGORIES },
          { name: 'unit', type: 'enum', required: true, enumValues: VALID_UNITS },
          // stock_quantity/min_stock_threshold/unit_cost OPSİYONELDİR ve
          // null/eksik verildiğinde `?? varsayılan` deseniyle GÜVENLİ bir
          // varsayılana düşer (skipNull) — ama GEÇERSİZ bir değer (yanlış
          // tip/negatif) verildiğinde reddedilmesi gerekir.
          { name: 'stock_quantity', type: 'number', required: false, skipNull: true },
          { name: 'min_stock_threshold', type: 'number', required: false, skipNull: true },
          { name: 'unit_cost', type: 'number', required: false, skipNull: true },
        ],
      });

      assertAllRejected(results, 'POST /api/materials');
    });

    // compatible_equipment_types bir DİZİdir — matrisin string/number/enum
    // tip sistemine uymuyor, bu yüzden elle test edildi.
    it('compatible_equipment_types eksikse/boşsa/dizi değilse/geçersiz tip içeriyorsa 400 dönmeli', async () => {
      const base = { name: 'X', category: 'kablo', unit: 'adet' };
      const scenarios = [
        { label: 'eksik', payload: base },
        { label: 'boş dizi', payload: { ...base, compatible_equipment_types: [] } },
        { label: 'dizi değil (string)', payload: { ...base, compatible_equipment_types: 'trafo' } },
        { label: 'geçersiz tip içeriyor', payload: { ...base, compatible_equipment_types: ['gecersiz_tip_xyz'] } },
      ];

      for (const scenario of scenarios) {
        const response = await request(app).post('/api/materials').set('Authorization', `Bearer ${managerToken}`).send(scenario.payload);
        assert.ok(
          response.status >= 400 && response.status < 500,
          `compatible_equipment_types ${scenario.label}: beklenmedik status ${response.status} — ${JSON.stringify(response.body)}`
        );
      }
    });

    it('geçerli compatible_equipment_types ile 201 döner (pozitif kontrol — fix meşru kullanımı kırmamış)', async () => {
      const response = await request(app)
        .post('/api/materials')
        .set('Authorization', `Bearer ${managerToken}`)
        .send({ name: 'Geçerli Malzeme', category: 'kablo', unit: 'adet', compatible_equipment_types: ['trafo', 'direk'] });
      assert.strictEqual(response.status, 201, JSON.stringify(response.body));
    });

    it('teknisyen rolü POST /api/materials çağıramaz (RBAC, matris dışı regresyon)', async () => {
      const response = await request(app)
        .post('/api/materials')
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ name: 'X', category: 'kablo', unit: 'adet', compatible_equipment_types: ['trafo'] });
      assert.strictEqual(response.status, 403);
    });
  });

  describe('PATCH /api/materials/:id — matris', () => {
    it('name/category/unit/min_stock_threshold/unit_cost için kötü girdi varyasyonları 4xx dönmeli (500 ASLA)', async () => {
      const results = await runInputValidationMatrix({
        app,
        method: 'patch',
        path: `/api/materials/${materialId}`,
        authToken: managerToken,
        validPayload: {
          name: 'Güncellenmiş İsim',
          category: 'sigorta',
          unit: 'metre',
          min_stock_threshold: 3,
          unit_cost: 20,
        },
        fields: [
          { name: 'name', type: 'string', required: false },
          { name: 'category', type: 'enum', required: false, enumValues: VALID_CATEGORIES },
          { name: 'unit', type: 'enum', required: false, enumValues: VALID_UNITS },
          // PATCH'te null AÇIKÇA "sıfırla" anlamına gelir (min_stock_threshold
          // Number(null)=0'a düşer, unit_cost null'ı olduğu gibi kabul eder) —
          // ikisi de GEÇERLİ bir durumdur, skipNull:true.
          { name: 'min_stock_threshold', type: 'number', required: false, skipNull: true },
          { name: 'unit_cost', type: 'number', required: false, skipNull: true },
        ],
      });

      assertAllRejected(results, 'PATCH /api/materials/:id');
    });

    it('ADIM 0 DÜZELTMESİ: name boş string olarak gönderilirse 400 dönmeli (önceden sessizce kabul ediliyordu)', async () => {
      const response = await request(app)
        .patch(`/api/materials/${materialId}`)
        .set('Authorization', `Bearer ${managerToken}`)
        .send({ name: '' });
      assert.strictEqual(response.status, 400);
      assert.notStrictEqual(getMaterial(materialId).name, '');
    });

    it('ADIM 0 DÜZELTMESİ: min_stock_threshold negatif gönderilirse 400 dönmeli (önceden sessizce kabul ediliyordu)', async () => {
      const before = getMaterial(materialId).min_stock_threshold;
      const response = await request(app)
        .patch(`/api/materials/${materialId}`)
        .set('Authorization', `Bearer ${managerToken}`)
        .send({ min_stock_threshold: -5 });
      assert.strictEqual(response.status, 400);
      assert.strictEqual(getMaterial(materialId).min_stock_threshold, before, 'negatif değer DB\'ye yazılmamış olmalı');
    });

    it('ADIM 0 DÜZELTMESİ: unit_cost negatif gönderilirse 400 dönmeli (önceden sessizce kabul ediliyordu)', async () => {
      const response = await request(app)
        .patch(`/api/materials/${materialId}`)
        .set('Authorization', `Bearer ${managerToken}`)
        .send({ unit_cost: -100 });
      assert.strictEqual(response.status, 400);
    });

    it('MASS ASSIGNMENT: stock_quantity PATCH gövdesine eklense bile stok DEĞİŞMEMELİ (yalnızca kullanım/ikmal hareketleriyle değişir)', async () => {
      const before = getMaterial(materialId).stock_quantity;
      const response = await request(app)
        .patch(`/api/materials/${materialId}`)
        .set('Authorization', `Bearer ${managerToken}`)
        .send({ name: 'Yine Aynı İsim Değil Ama Stoğu Kaçırmaya Çalışıyor', stock_quantity: 99999 });

      assert.strictEqual(response.status, 200, JSON.stringify(response.body));
      assert.strictEqual(response.body.stock_quantity, before, 'stock_quantity enjeksiyonu YOK SAYILMALI');
      assert.strictEqual(getMaterial(materialId).stock_quantity, before, 'DB\'de de değişmemiş olmalı');
    });
  });

  describe('POST /api/materials/:id/restock — matris', () => {
    it('quantity_added için kötü girdi varyasyonları 4xx dönmeli (500 ASLA)', async () => {
      const results = await runInputValidationMatrix({
        app,
        method: 'post',
        path: `/api/materials/${materialId}/restock`,
        authToken: managerToken,
        validPayload: { quantity_added: 5 },
        fields: [{ name: 'quantity_added', type: 'number', required: true, rejectsZero: true }],
      });

      assertAllRejected(results, 'POST /api/materials/:id/restock');
      assert.strictEqual(getMaterial(materialId).stock_quantity, 20, 'hiçbir geçersiz senaryo stoğu değiştirmemiş olmalı');
    });
  });

  describe('POST /api/workorders/:workOrderId/materials — matris', () => {
    it('material_id/quantity_used için kötü girdi varyasyonları 4xx dönmeli (500 ASLA)', async () => {
      const results = await runInputValidationMatrix({
        app,
        method: 'post',
        path: `/api/workorders/${workOrderId}/materials`,
        authToken: technicianToken,
        validPayload: { material_id: materialId, quantity_used: 2 },
        fields: [
          { name: 'material_id', type: 'number', required: true, rejectsZero: true },
          { name: 'quantity_used', type: 'number', required: true, rejectsZero: true },
        ],
      });

      assertAllRejected(results, 'POST /api/workorders/:workOrderId/materials');
      assert.strictEqual(getMaterial(materialId).stock_quantity, 20, 'hiçbir geçersiz senaryo stoğu değiştirmemiş olmalı (TEST-07 ile tutarlı)');
    });

    it('veri bütünlüğü: mevcut stoktan FAZLA kullanım 400 döner, stok DEĞİŞMEZ (TEST-07 ile genişletilmiş kapsam çakışması bilinçli)', async () => {
      const before = getMaterial(materialId).stock_quantity;
      const response = await request(app)
        .post(`/api/workorders/${workOrderId}/materials`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ material_id: materialId, quantity_used: before + 1000 });

      assert.strictEqual(response.status, 400);
      assert.strictEqual(getMaterial(materialId).stock_quantity, before);
    });
  });

  describe('Geçersiz ID (path parametresi)', () => {
    const idEndpoints = [
      { label: 'PATCH /materials/:id', method: 'patch', build: (id) => `/api/materials/${id}`, token: () => managerToken, body: { name: 'x' } },
      { label: 'POST /materials/:id/restock', method: 'post', build: (id) => `/api/materials/${id}/restock`, token: () => managerToken, body: { quantity_added: 1 } },
      { label: 'POST /workorders/:workOrderId/materials', method: 'post', build: (id) => `/api/workorders/${id}/materials`, token: () => technicianToken, body: { material_id: 1, quantity_used: 1 } },
    ];

    for (const ep of idEndpoints) {
      it(`${ep.label}: sayısal olmayan id ("abc") → 400, ASLA 500`, async () => {
        const response = await request(app)[ep.method](ep.build('abc')).set('Authorization', `Bearer ${ep.token()}`).send(ep.body);
        assert.strictEqual(response.status, 400, `${ep.label}: ${JSON.stringify(response.body)}`);
      });

      it(`${ep.label}: negatif id (-1) → 404, ASLA 500`, async () => {
        const response = await request(app)[ep.method](ep.build(-1)).set('Authorization', `Bearer ${ep.token()}`).send(ep.body);
        assert.strictEqual(response.status, 404, `${ep.label}: ${JSON.stringify(response.body)}`);
      });

      it(`${ep.label}: aşırı büyük id → çökmeden 4xx döner`, async () => {
        const response = await request(app)[ep.method](ep.build('999999999999999999999')).set('Authorization', `Bearer ${ep.token()}`).send(ep.body);
        assert.ok(response.status >= 400 && response.status < 500, `${ep.label}: beklenmedik status ${response.status}`);
      });
    }
  });
});
