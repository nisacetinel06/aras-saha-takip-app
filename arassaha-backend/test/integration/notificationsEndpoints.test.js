// TEST-10: Bildirimler (Modül 6) salt-okunur endpoint'leri.
//
// ADIM 0 BULGUSU: routes/notifications.js'teki HER sorgu zaten `WHERE
// user_id = ?` (req.user.id) ile sınırlı — kod incelemesiyle DOĞRULANDI,
// düzeltme GEREKMEDİ. Bu dosya bunu GERÇEK çapraz-kullanıcı veriyle (SEC-02
// tarzı) kanıtlıyor: Kullanıcı A'nın isteğinde Kullanıcı B'ye ait TEK BİR
// bildirim id'si bile görünmemeli.
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const request = require('supertest');
const app = require('../../server');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');
const { getTestToken } = require('../helpers/authHelper');
const { assertArraySchema, assertSchema } = require('../helpers/assertSchema');

function insertNotification(userId, message, isRead = 0) {
  db.prepare(
    `INSERT INTO notifications (user_id, message, related_type, related_id, is_read, created_at) VALUES (?, ?, 'work_order', 1, ?, ?)`
  ).run(userId, message, isRead, new Date().toISOString());
}

describe('GET /api/notifications', () => {
  let seeded;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
  });

  it('token olmadan 401 döner', async () => {
    const response = await request(app).get('/api/notifications');
    assert.strictEqual(response.status, 401);
  });

  it('response schema doğru: her bildirim id/message/is_read/created_at içerir', async () => {
    insertNotification(seeded.users.teknisyenId, 'Test bildirimi');
    const token = getTestToken('teknisyen');

    const response = await request(app).get('/api/notifications').set('Authorization', `Bearer ${token}`);

    assert.strictEqual(response.status, 200);
    assertArraySchema(response.body, { id: 'number', message: 'string', is_read: 'boolean', created_at: 'string' });
  });

  it('CROSS-USER SIZINTI KONTROLÜ (SEC-02 tarzı): Kullanıcı A, Kullanıcı B\'nin bildirimlerini ASLA görmemeli', async () => {
    const userAId = seeded.users.teknisyenId;
    const userBId = seeded.users.otherTeknisyenId;

    insertNotification(userAId, 'A için bildirim 1');
    insertNotification(userAId, 'A için bildirim 2');
    insertNotification(userBId, 'B için GİZLİ bildirim 1');
    insertNotification(userBId, 'B için GİZLİ bildirim 2');
    insertNotification(userBId, 'B için GİZLİ bildirim 3');

    const tokenA = getTestToken('teknisyen'); // seedMinimalTestData'da userAId = teknisyenId
    const responseA = await request(app).get('/api/notifications').set('Authorization', `Bearer ${tokenA}`);

    assert.strictEqual(responseA.status, 200);
    assert.strictEqual(responseA.body.length, 2, 'A yalnızca KENDİ 2 bildirimini görmeli');
    assert.ok(
      responseA.body.every((n) => n.message.startsWith('A için')),
      'A\'nın listesinde B\'ye ait TEK BİR bildirim bile görünmemeli'
    );

    // Doğrudan DB'den B'nin bildirim id'lerini alıp, A'nın yanıtında bu
    // id'lerden HİÇBİRİNİN olmadığını kanıtla (mesaj metnine değil, id'ye
    // dayalı en kesin kontrol).
    const userBNotificationIds = db.prepare('SELECT id FROM notifications WHERE user_id = ?').all(userBId).map((r) => r.id);
    const returnedIds = responseA.body.map((n) => n.id);
    for (const bId of userBNotificationIds) {
      assert.ok(!returnedIds.includes(bId), `B'nin bildirim id'si (${bId}) A'nın yanıtında SIZMIŞ`);
    }
  });

  it('filtreleme: ?unread_only=true yalnızca okunmamışları döner, is_read=1 olan hiçbir kayıt listede olmaz', async () => {
    insertNotification(seeded.users.teknisyenId, 'Okunmamış 1', 0);
    insertNotification(seeded.users.teknisyenId, 'Okunmamış 2', 0);
    insertNotification(seeded.users.teknisyenId, 'Okunmuş 1', 1);
    const token = getTestToken('teknisyen');

    const response = await request(app).get('/api/notifications?unread_only=true').set('Authorization', `Bearer ${token}`);

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.length, 2);
    assert.ok(response.body.every((n) => n.is_read === false), 'is_read=true olan hiçbir kayıt listede olmamalı');
  });

  it('boş veri durumu: hiç bildirim yokken hata değil, boş dizi döner', async () => {
    const token = getTestToken('teknisyen');
    const response = await request(app).get('/api/notifications').set('Authorization', `Bearer ${token}`);
    assert.strictEqual(response.status, 200);
    assert.deepStrictEqual(response.body, []);
  });
});

describe('GET /api/notifications/unread-count', () => {
  let seeded;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
  });

  it('token olmadan 401 döner', async () => {
    const response = await request(app).get('/api/notifications/unread-count');
    assert.strictEqual(response.status, 401);
  });

  it('response schema doğru: { count: number }', async () => {
    const token = getTestToken('teknisyen');
    const response = await request(app).get('/api/notifications/unread-count').set('Authorization', `Bearer ${token}`);
    assert.strictEqual(response.status, 200);
    assertSchema(response.body, { count: 'number' });
  });

  it('CROSS-USER: Kullanıcı A\'nın sayısı yalnızca KENDİ okunmamışlarını içerir, B\'ninkini değil', async () => {
    insertNotification(seeded.users.teknisyenId, 'A - 1', 0);
    insertNotification(seeded.users.otherTeknisyenId, 'B - 1', 0);
    insertNotification(seeded.users.otherTeknisyenId, 'B - 2', 0);
    insertNotification(seeded.users.otherTeknisyenId, 'B - 3', 0);

    const tokenA = getTestToken('teknisyen');
    const response = await request(app).get('/api/notifications/unread-count').set('Authorization', `Bearer ${tokenA}`);

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.count, 1, 'A\'nın sayısı B\'nin 3 bildirimini İÇERMEMELİ');
  });

  it('boş veri durumu: hiç bildirim yokken count: 0 döner (hata/null DEĞİL)', async () => {
    const token = getTestToken('teknisyen');
    const response = await request(app).get('/api/notifications/unread-count').set('Authorization', `Bearer ${token}`);
    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.count, 0);
  });
});
