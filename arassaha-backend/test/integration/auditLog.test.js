// GET /api/audit-log — bkz. routes/auditLog.js. Bu dosya HTTP katmanını
// (RBAC, query parametre doğrulaması, response şekli) test eder; birleştirme
// SQL'inin doğruluğu zaten test/integration/auditLogAggregator.test.js'te
// kapsamlı şekilde kanıtlanmıştır (bkz. o dosya).
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const request = require('supertest');
const app = require('../../server');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');
const { getTestToken } = require('../helpers/authHelper');

describe('GET /api/audit-log', () => {
  let seeded;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
  });

  describe('RBAC — yalnızca yönetici', () => {
    it('teknisyen erişemez (403)', async () => {
      const token = getTestToken('teknisyen');
      const response = await request(app).get('/api/audit-log').set('Authorization', `Bearer ${token}`);
      assert.strictEqual(response.status, 403);
    });

    it('dispeçer erişemez (403)', async () => {
      const token = getTestToken('dispecer');
      const response = await request(app).get('/api/audit-log').set('Authorization', `Bearer ${token}`);
      assert.strictEqual(response.status, 403);
    });

    it('yönetici erişebilir (200)', async () => {
      const token = getTestToken('yonetici');
      const response = await request(app).get('/api/audit-log').set('Authorization', `Bearer ${token}`);
      assert.strictEqual(response.status, 200);
    });
  });

  describe('response şekli', () => {
    it('boş sistemde bile doğru şekli (entries/total_count/page/has_more) döner', async () => {
      const token = getTestToken('yonetici');
      const response = await request(app).get('/api/audit-log').set('Authorization', `Bearer ${token}`);

      assert.strictEqual(response.status, 200);
      assert.ok(Array.isArray(response.body.entries));
      assert.strictEqual(typeof response.body.total_count, 'number');
      assert.strictEqual(response.body.page, 1);
      assert.strictEqual(typeof response.body.has_more, 'boolean');
    });

    it('gerçek bir işlem (kullanıcı pasifleştirme) sonrası audit log\'da GERÇEKTEN görünür', async () => {
      const managerToken = getTestToken('yonetici');
      await request(app)
        .delete(`/api/users/${seeded.users.teknisyenId}`)
        .set('Authorization', `Bearer ${managerToken}`);

      const response = await request(app)
        .get('/api/audit-log?category=kullanici_yonetimi')
        .set('Authorization', `Bearer ${managerToken}`);

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.entries.length, 1);
      assert.strictEqual(response.body.entries[0].action_type, 'pasiflestirildi');
      assert.strictEqual(response.body.entries[0].actor_name, 'Test Yönetici');
    });
  });

  describe('query parametre doğrulaması', () => {
    it('geçersiz category: 400', async () => {
      const token = getTestToken('yonetici');
      const response = await request(app)
        .get('/api/audit-log?category=gecersiz_kategori')
        .set('Authorization', `Bearer ${token}`);
      assert.strictEqual(response.status, 400);
    });

    it('geçersiz (sayısal olmayan) actor_id: 400', async () => {
      const token = getTestToken('yonetici');
      const response = await request(app)
        .get('/api/audit-log?actor_id=abc')
        .set('Authorization', `Bearer ${token}`);
      assert.strictEqual(response.status, 400);
    });

    it('geçersiz page (0 veya negatif): 400', async () => {
      const token = getTestToken('yonetici');
      const response = await request(app)
        .get('/api/audit-log?page=0')
        .set('Authorization', `Bearer ${token}`);
      assert.strictEqual(response.status, 400);
    });

    it('geçersiz limit: 400', async () => {
      const token = getTestToken('yonetici');
      const response = await request(app)
        .get('/api/audit-log?limit=-5')
        .set('Authorization', `Bearer ${token}`);
      assert.strictEqual(response.status, 400);
    });

    it('geçerli from/to (ISO tarih) ile 200 döner ve doğru filtrelenir', async () => {
      db.prepare(
        'INSERT INTO login_attempts (sicil_no, ip_address, success, created_at) VALUES (?, ?, ?, ?)'
      ).run('1001', '10.0.0.1', 1, '2026-01-01T00:00:00.000Z');
      db.prepare(
        'INSERT INTO login_attempts (sicil_no, ip_address, success, created_at) VALUES (?, ?, ?, ?)'
      ).run('1001', '10.0.0.1', 0, '2026-06-01T00:00:00.000Z');

      const token = getTestToken('yonetici');
      const response = await request(app)
        .get('/api/audit-log?category=giris&from=2026-03-01T00:00:00.000Z')
        .set('Authorization', `Bearer ${token}`);

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.entries.length, 1);
      assert.strictEqual(response.body.entries[0].action_type, 'giris_basarisiz');
    });
  });

  describe('50\'den fazla kayıtta sayfalama', () => {
    it('60 login denemesi seed edilince ilk sayfa 50 döner, has_more=true; ikinci sayfa kalan 10\'u döner, has_more=false', async () => {
      const insertLogin = db.prepare(
        'INSERT INTO login_attempts (sicil_no, ip_address, success, created_at) VALUES (?, ?, ?, ?)'
      );
      for (let i = 0; i < 60; i++) {
        insertLogin.run('1001', '10.0.0.1', 1, new Date(Date.UTC(2026, 0, 1, 0, i)).toISOString());
      }

      const token = getTestToken('yonetici');

      const page1 = await request(app)
        .get('/api/audit-log?category=giris&page=1')
        .set('Authorization', `Bearer ${token}`);
      assert.strictEqual(page1.body.entries.length, 50, 'varsayılan limit 50 olmalı');
      assert.strictEqual(page1.body.total_count, 60);
      assert.strictEqual(page1.body.has_more, true);

      const page2 = await request(app)
        .get('/api/audit-log?category=giris&page=2')
        .set('Authorization', `Bearer ${token}`);
      assert.strictEqual(page2.body.entries.length, 10);
      assert.strictEqual(page2.body.has_more, false);
    });
  });
});
