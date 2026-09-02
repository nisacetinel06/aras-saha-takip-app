// POST /api/auth/forgot-password — Giriş ekranındaki "Şifremi Unuttum" ucu.
//
// Bu, GERÇEK bir e-posta/SMS ile self-service şifre sıfırlama DEĞİLDİR (bkz.
// routes/auth.js dosya başı dokümantasyonu — projede bunun için bir gönderim
// altyapısı yok). Burada doğrulanan asıl davranış: (1) sicil_no'ya karşılık
// gelen aktif bir kullanıcı varsa TÜM yöneticilere bir 'password_reset_request'
// bildirimi düşer, (2) sicil_no bulunamasa/pasif olsa BİLE giriş ekranındaki
// login akışıyla AYNI ilkeyle (user enumeration önleme) her zaman aynı genel
// mesaj döner, (3) aynı kullanıcı için kısa sürede tekrar tekrar tetiklenirse
// yöneticiler spam bildirimle boğulmaz (15 dakikalık tekilleştirme).
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const request = require('supertest');
const app = require('../../server');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');

const GENERIC_MESSAGE =
  'İsteğiniz alındı. Yöneticiniz sizinle iletişime geçip yeni bir şifre belirleyecektir.';

describe('POST /api/auth/forgot-password', () => {
  let seeded;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
  });

  it('sicil_no eksikse 400 döner', async () => {
    const response = await request(app).post('/api/auth/forgot-password').send({});
    assert.strictEqual(response.status, 400);
  });

  it('var olan aktif kullanıcı için 200 + genel mesaj döner ve yöneticiye bildirim düşer', async () => {
    const response = await request(app)
      .post('/api/auth/forgot-password')
      .send({ sicil_no: '1001' }); // seedMinimalTestData teknisyeni

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.message, GENERIC_MESSAGE);

    const notifications = db
      .prepare(
        `SELECT * FROM notifications WHERE related_type = 'password_reset_request' AND related_id = ?`
      )
      .all(seeded.users.teknisyenId);

    assert.strictEqual(notifications.length, 1);
    assert.strictEqual(notifications[0].user_id, seeded.users.yoneticiId);
    assert.ok(notifications[0].message.includes('Test Teknisyen'));
    assert.ok(notifications[0].message.includes('1001'));
  });

  it('olmayan sicil no için de AYNI genel mesajla 200 döner (user enumeration önlenmiş), bildirim oluşturulmaz', async () => {
    const response = await request(app)
      .post('/api/auth/forgot-password')
      .send({ sicil_no: '9999999' });

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.message, GENERIC_MESSAGE);

    const count = db.prepare(`SELECT COUNT(*) AS count FROM notifications`).get().count;
    assert.strictEqual(count, 0);
  });

  it('pasif kullanıcı için de AYNI genel mesajla 200 döner, bildirim oluşturulmaz', async () => {
    db.prepare('UPDATE users SET is_active = 0 WHERE id = ?').run(seeded.users.teknisyenId);

    const response = await request(app)
      .post('/api/auth/forgot-password')
      .send({ sicil_no: '1001' });

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.message, GENERIC_MESSAGE);

    const count = db.prepare(`SELECT COUNT(*) AS count FROM notifications`).get().count;
    assert.strictEqual(count, 0);
  });

  it('tekilleştirme: aynı kullanıcı için art arda iki talep yalnızca 1 bildirim üretir', async () => {
    await request(app).post('/api/auth/forgot-password').send({ sicil_no: '1001' });
    await request(app).post('/api/auth/forgot-password').send({ sicil_no: '1001' });

    const count = db
      .prepare(
        `SELECT COUNT(*) AS count FROM notifications WHERE related_type = 'password_reset_request' AND related_id = ?`
      )
      .get(seeded.users.teknisyenId).count;

    assert.strictEqual(count, 1);
  });

  it('birden fazla aktif yönetici varsa HEPSİNE bildirim gider', async () => {
    const secondManagerId = db
      .prepare(
        `INSERT INTO users (name, role, sicil_no, password_hash, is_active) VALUES (?, 'yonetici', ?, ?, 1)`
      )
      .run('İkinci Yönetici', '3002', 'x').lastInsertRowid;

    await request(app).post('/api/auth/forgot-password').send({ sicil_no: '1001' });

    const recipientIds = db
      .prepare(
        `SELECT user_id FROM notifications WHERE related_type = 'password_reset_request' AND related_id = ?`
      )
      .all(seeded.users.teknisyenId)
      .map((row) => row.user_id)
      .sort();

    assert.deepStrictEqual(recipientIds.sort(), [seeded.users.yoneticiId, secondManagerId].sort());
  });
});
