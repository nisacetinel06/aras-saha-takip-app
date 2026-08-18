// SEC-03 Kısım B: work_orders.assigned_by_user_id — "bu işi bana kim verdi"
// şeffaflığı. POST /api/workorders ve PATCH /:id/assign, bu alanı HER ZAMAN
// req.user.id'den doldurur; istemciden gelen bir değer ASLA kabul edilmez
// (TEST-09'daki mass assignment dersiyle tutarlı). GET /:id, users tablosuna
// JOIN ile atayanın { id, name, role } bilgisini döner; eski (bu özellik
// öncesi) kayıtlarda alan NULL olabilir — bu durumda assigned_by_user: null
// döner, hata FIRLATILMAZ.
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const request = require('supertest');
const app = require('../../server');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');
const { getTestToken } = require('../helpers/authHelper');
const { generateValidToken } = require('../helpers/tokenHelper');

function getWorkOrder(id) {
  return db.prepare('SELECT * FROM work_orders WHERE id = ?').get(id);
}

describe('work_orders.assigned_by_user_id — "atayan" bilgisi', () => {
  let seeded;
  let dispatcherToken;
  let secondManagerId;
  let secondManagerToken;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
    dispatcherToken = getTestToken('dispecer');

    // "Yeniden atama" senaryosunun (Adım 3) anlamlı olması için (bkz. görev
    // kartı: "farklı bir yönetici token'ıyla yeniden ata") seedMinimalTestData
    // yalnızca TEK bir yönetici sağladığı için, burada İKİNCİ, bağımsız bir
    // yönetici eklenir.
    secondManagerId = db
      .prepare("INSERT INTO users (name, role, sicil_no, password_hash) VALUES (?, 'yonetici', ?, ?)")
      .run('İkinci Test Yöneticisi', 'test-9002', 'x').lastInsertRowid;
    secondManagerToken = generateValidToken({ id: secondManagerId, role: 'yonetici' });
  });

  it('yeni iş emri oluşturulunca assigned_by_user, GERÇEKTEN oluşturan dispeçer olmalı', async () => {
    const response = await request(app)
      .post('/api/workorders')
      .set('Authorization', `Bearer ${dispatcherToken}`)
      .send({
        title: 'Test İş Emri — Atayan Testi',
        description: 'açıklama',
        priority: 'normal',
        assigned_user_id: seeded.users.teknisyenId,
        equipment_id: seeded.equipmentId,
      });

    assert.strictEqual(response.status, 201, JSON.stringify(response.body));
    assert.ok(response.body.assigned_by_user, 'yanıt assigned_by_user içermeli');
    assert.strictEqual(response.body.assigned_by_user.id, seeded.users.dispecerId);
    assert.strictEqual(response.body.assigned_by_user.role, 'dispecer');

    // GET /:id ile de aynı bilgi tutarlı dönmeli.
    const getResponse = await request(app)
      .get(`/api/workorders/${response.body.id}`)
      .set('Authorization', `Bearer ${dispatcherToken}`);
    assert.strictEqual(getResponse.body.assigned_by_user.id, seeded.users.dispecerId);

    const row = getWorkOrder(response.body.id);
    assert.strictEqual(row.assigned_by_user_id, seeded.users.dispecerId, "DB'de de gerçek dispeçerin id'si olmalı");
  });

  it('MASS ASSIGNMENT: istemci assigned_by_user_id\'yi manuel gönderse bile YOK SAYILIR, her zaman req.user.id kullanılır', async () => {
    const response = await request(app)
      .post('/api/workorders')
      .set('Authorization', `Bearer ${dispatcherToken}`)
      .send({
        title: 'Test İş Emri — Mass Assignment',
        priority: 'normal',
        assigned_user_id: seeded.users.teknisyenId,
        equipment_id: seeded.equipmentId,
        // Enjeksiyon denemesi: başka (var olan) bir kullanıcı, "atayan" olarak beyan ediliyor.
        assigned_by_user_id: seeded.users.yoneticiId,
      });

    assert.strictEqual(response.status, 201, JSON.stringify(response.body));
    assert.strictEqual(
      response.body.assigned_by_user.id,
      seeded.users.dispecerId,
      'enjekte edilen assigned_by_user_id YOK SAYILMALI, gerçek giriş yapan kullanıcı (dispeçer) kullanılmalı'
    );

    const row = getWorkOrder(response.body.id);
    assert.strictEqual(row.assigned_by_user_id, seeded.users.dispecerId, "DB'de de enjekte edilen değer DEĞİL gerçek dispeçer olmalı");
  });

  it('yeniden atama (PATCH /:id/assign) yapan farklı bir yönetici, assigned_by_user\'ı GÜNCELLER', async () => {
    // Önce dispeçer oluşturur (assigned_by_user = dispeçer).
    const createResponse = await request(app)
      .post('/api/workorders')
      .set('Authorization', `Bearer ${dispatcherToken}`)
      .send({
        title: 'Test İş Emri — Yeniden Atama',
        priority: 'normal',
        assigned_user_id: seeded.users.teknisyenId,
        equipment_id: seeded.equipmentId,
      });
    const workOrderId = createResponse.body.id;
    assert.strictEqual(createResponse.body.assigned_by_user.id, seeded.users.dispecerId);

    // İKİNCİ yönetici, işi AYNI (veya farklı) teknisyene yeniden atar.
    const reassignResponse = await request(app)
      .patch(`/api/workorders/${workOrderId}/assign`)
      .set('Authorization', `Bearer ${secondManagerToken}`)
      .send({ assigned_user_id: seeded.users.otherTeknisyenId });

    assert.strictEqual(reassignResponse.status, 200, JSON.stringify(reassignResponse.body));
    assert.strictEqual(
      reassignResponse.body.assigned_by_user.id,
      secondManagerId,
      'yeniden atama sonrası assigned_by_user artık İKİNCİ yönetici olmalı — en son kim atadıysa o'
    );
    assert.notStrictEqual(
      reassignResponse.body.assigned_by_user.id,
      seeded.users.dispecerId,
      'eski atayan (ilk dispeçer) artık görünmemeli'
    );

    const row = getWorkOrder(workOrderId);
    assert.strictEqual(row.assigned_by_user_id, secondManagerId, "DB'de de en son atayan güncellenmiş olmalı");
  });

  it('eski kayıt (assigned_by_user_id NULL): GET /:id çökmeden assigned_by_user: null döner', async () => {
    // Bu özellik eklenmeden ÖNCE oluşturulmuş bir kaydı simüle eder — doğrudan
    // SQL ile, assigned_by_user_id HİÇ verilmeden (NULL kalır) eklenir.
    const now = new Date().toISOString();
    const legacyId = db
      .prepare(
        `INSERT INTO work_orders
           (title, description, status, priority, assigned_user_id, equipment_id, created_at, updated_at)
         VALUES (?, ?, 'acik', 'normal', ?, ?, ?, ?)`
      )
      .run('Eski Kayıt (migration öncesi)', 'assigned_by_user_id sütunu eklenmeden önce oluşturuldu', seeded.users.teknisyenId, seeded.equipmentId, now, now).lastInsertRowid;

    const response = await request(app)
      .get(`/api/workorders/${legacyId}`)
      .set('Authorization', `Bearer ${dispatcherToken}`);

    assert.strictEqual(response.status, 200, JSON.stringify(response.body));
    assert.strictEqual(response.body.assigned_by_user, null, 'eski kayıtta assigned_by_user null olmalı, hata FIRLATILMAMALI');
    // assigned_user (atanan kişi) hâlâ doğru dönmeli — yalnızca "atayan" bilgisi eksik.
    assert.ok(response.body.assigned_user, 'assigned_user hâlâ dolu olmalı');
  });
});
