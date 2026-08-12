// GET /api/workorders — Modül 7'nin en kritik davranışı: hiyerarşik
// görünürlük (bkz. routes/workOrders.js applyVisibilityFilter). Bir
// teknisyenin YALNIZCA kendisine atanan iş emirlerini görebildiğini, başka
// bir teknisyenin işlerini asla göremediğini doğrular.
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const request = require('supertest');
const app = require('../../server');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');
const { getTestToken } = require('../helpers/authHelper');

describe('GET /api/workorders — rol bazlı görünürlük (RBAC)', () => {
  let seeded;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
  });

  it('token olmadan çağrılırsa 401 dönmeli', async () => {
    const response = await request(app).get('/api/workorders');
    assert.strictEqual(response.status, 401);
  });

  it('teknisyen yalnızca KENDİSİNE atanan iş emirlerini görmeli', async () => {
    const token = getTestToken('teknisyen');

    const response = await request(app).get('/api/workorders').set('Authorization', `Bearer ${token}`);

    assert.strictEqual(response.status, 200);
    assert.ok(Array.isArray(response.body));
    assert.strictEqual(response.body.length, 1);
    assert.strictEqual(response.body[0].id, seeded.workOrders.ownWorkOrderId);
    assert.strictEqual(response.body[0].assigned_user.id, seeded.users.teknisyenId);

    // Kritik negatif kontrol: başka teknisyenin iş emri listede KESİNLİKLE
    // yer almamalı — RBAC filtresinin gerçekten çalıştığının kanıtı.
    const returnedIds = response.body.map((wo) => wo.id);
    assert.ok(!returnedIds.includes(seeded.workOrders.otherWorkOrderId));
  });

  it('dispeçer, KENDİ EKİBİNDEKİ tüm teknisyenlerin iş emirlerini görmeli', async () => {
    const token = getTestToken('dispecer');

    const response = await request(app).get('/api/workorders').set('Authorization', `Bearer ${token}`);

    assert.strictEqual(response.status, 200);
    const returnedIds = response.body.map((wo) => wo.id).sort();
    assert.deepStrictEqual(
      returnedIds,
      [seeded.workOrders.ownWorkOrderId, seeded.workOrders.otherWorkOrderId].sort()
    );
  });

  it('yönetici filtresiz tüm iş emirlerini görmeli', async () => {
    const token = getTestToken('yonetici');

    const response = await request(app).get('/api/workorders').set('Authorization', `Bearer ${token}`);

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.length, 2);
  });

  it('geçersiz bir status filtresiyle 400 dönmeli', async () => {
    const token = getTestToken('yonetici');

    const response = await request(app)
      .get('/api/workorders')
      .query({ status: 'olmayan_bir_durum' })
      .set('Authorization', `Bearer ${token}`);

    assert.strictEqual(response.status, 400);
  });
});
