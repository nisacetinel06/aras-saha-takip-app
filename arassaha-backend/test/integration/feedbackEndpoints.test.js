// Öneri / Şikayet Kutusu (Modül 17) — routes/feedback.js. İSG Bildirimi
// (Modül 5) testleriyle (isgStatusRbac.test.js, isgValidation.test.js) AYNI
// desenleri takip eder; buradaki EK odak noktaları:
//   1) GET / görünürlük filtresi: teknisyen/dispeçer SADECE KENDİ
//      gönderdiklerini görür, yönetici HEPSİNİ görür.
//   2) SEC-02 IDOR dersi: GET /:id, sahibi olmayan bir kullanıcıya 404 döner
//      (403 DEĞİL — kaydın varlığını bile açık etmez).
//   3) Anonim Gönderim dengesi: response'ta submitted_by gizlenir AMA
//      veritabanındaki submitted_by_user_id her zaman gerçek kalır.
//   4) Fotoğraf OPSİYONEL — İSG'nin aksine fotoğrafsız gönderim başarılı olmalı.
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const request = require('supertest');
const app = require('../../server');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');
const { getTestToken } = require('../helpers/authHelper');
const { generateValidToken } = require('../helpers/tokenHelper');
const { assertSchema } = require('../helpers/assertSchema');
const { runInputValidationMatrix, assertAllRejected } = require('../helpers/inputValidationMatrix');

const VALID_JPEG_BUFFER = fs.readFileSync(path.join(__dirname, '..', 'fixtures', 'valid-test-image.jpg'));
const FILE_ATTACHMENT = { field: 'photo', buffer: VALID_JPEG_BUFFER, filename: 'test.jpg', contentType: 'image/jpeg' };

function getFeedbackRow(id) {
  return db.prepare('SELECT * FROM feedback_items WHERE id = ?').get(id);
}

function insertFeedback({ userId, category = 'sikayet', description = 'Test bildirimi', isAnonymous = 0, status = 'bekliyor' }) {
  const now = new Date().toISOString();
  const info = db
    .prepare(
      `INSERT INTO feedback_items (submitted_by_user_id, category, description, is_anonymous, status, created_at)
       VALUES (?, ?, ?, ?, ?, ?)`
    )
    .run(userId, category, description, isAnonymous ? 1 : 0, status, now);
  return info.lastInsertRowid;
}

describe('POST /api/feedback', () => {
  let seeded;
  let technicianToken;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
    technicianToken = getTestToken('teknisyen');
  });

  it('token olmadan 401 döner', async () => {
    const response = await request(app).post('/api/feedback').field('description', 'x').field('category', 'oneri');
    assert.strictEqual(response.status, 401);
  });

  it('fotoğrafSIZ bir şikayet gönderimi başarıyla tamamlanır (İSG\'nin aksine fotoğraf zorunlu değil)', async () => {
    const response = await request(app)
      .post('/api/feedback')
      .set('Authorization', `Bearer ${technicianToken}`)
      .field('description', 'Molalar çok kısa, uzatılmasını rica ediyorum.')
      .field('category', 'sikayet');

    assert.strictEqual(response.status, 201, JSON.stringify(response.body));
    assert.strictEqual(response.body.photo_path, null);
    assert.strictEqual(response.body.status, 'bekliyor');

    const row = getFeedbackRow(response.body.id);
    assert.strictEqual(row.photo_path, null, 'DB\'de de photo_path NULL olmalı');
  });

  it('fotoğraflı bir gönderim de başarıyla tamamlanır (photo opsiyonel — verilmişse yine kabul edilir)', async () => {
    const response = await request(app)
      .post('/api/feedback')
      .set('Authorization', `Bearer ${technicianToken}`)
      .field('description', 'Bu alanda aydınlatma yetersiz.')
      .field('category', 'oneri')
      .attach('photo', VALID_JPEG_BUFFER, { filename: 'x.jpg', contentType: 'image/jpeg' });

    assert.strictEqual(response.status, 201, JSON.stringify(response.body));
    assert.ok(response.body.photo_path, 'photo_path dolu olmalı');
    assert.ok(response.body.photo_path.startsWith('/uploads/feedback/'));
  });

  it('MASS ASSIGNMENT: submitted_by_user_id enjekte edilse bile bildirim GERÇEK giriş yapan kullanıcıya atanmalı', async () => {
    const response = await request(app)
      .post('/api/feedback')
      .set('Authorization', `Bearer ${technicianToken}`)
      .field('description', 'Sahte submitted_by_user_id denemesi')
      .field('category', 'diger')
      .field('submitted_by_user_id', String(seeded.users.yoneticiId));

    assert.strictEqual(response.status, 201, JSON.stringify(response.body));
    assert.strictEqual(response.body.submitted_by.id, seeded.users.teknisyenId);

    const row = getFeedbackRow(response.body.id);
    assert.strictEqual(row.submitted_by_user_id, seeded.users.teknisyenId);
  });

  describe('girdi doğrulama matrisi (500 ASLA)', () => {
    it('description/category için kötü girdi varyasyonları 4xx dönmeli', async () => {
      const results = await runInputValidationMatrix({
        app,
        method: 'post',
        path: '/api/feedback',
        authToken: technicianToken,
        multipart: true,
        validPayload: { description: 'Test bildirimi', category: 'oneri' },
        fields: [
          { name: 'description', type: 'string', required: true },
          { name: 'category', type: 'enum', required: true, enumValues: ['oneri', 'sikayet', 'diger'] },
        ],
      });

      assertAllRejected(results, 'POST /api/feedback');
    });
  });
});

describe('Anonim Gönderim — response\'ta gizli, DB\'de gerçek (madde 1-3)', () => {
  let seeded;
  let technicianToken;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
    technicianToken = getTestToken('teknisyen');
  });

  it('1) anonim OLMAYAN bir öneri: yönetici listesinde gönderenin adı doğru görünür', async () => {
    const submit = await request(app)
      .post('/api/feedback')
      .set('Authorization', `Bearer ${technicianToken}`)
      .field('description', 'Kantin menüsü çeşitlendirilebilir.')
      .field('category', 'oneri')
      .field('is_anonymous', 'false');
    assert.strictEqual(submit.status, 201, JSON.stringify(submit.body));
    assert.strictEqual(submit.body.is_anonymous, false);
    assert.strictEqual(submit.body.submitted_by.id, seeded.users.teknisyenId);
    assert.strictEqual(submit.body.submitted_by.name, 'Test Teknisyen');

    const managerToken = getTestToken('yonetici');
    const list = await request(app).get('/api/feedback').set('Authorization', `Bearer ${managerToken}`);
    const item = list.body.find((f) => f.id === submit.body.id);
    assert.ok(item, 'yönetici listesinde bu bildirim görünmeli');
    assert.strictEqual(item.submitted_by.name, 'Test Teknisyen', 'anonim OLMAYAN bir bildirimde gönderenin adı GÖRÜNMELİ');
  });

  it('2) anonim bir şikayet: yönetici listesinde submitted_by null döner, gerçek isim response\'ta YOK', async () => {
    const submit = await request(app)
      .post('/api/feedback')
      .set('Authorization', `Bearer ${technicianToken}`)
      .field('description', 'Yönetim tarzıyla ilgili bir kaygım var, isim vermeden bildirmek istiyorum.')
      .field('category', 'sikayet')
      .field('is_anonymous', 'true');
    assert.strictEqual(submit.status, 201, JSON.stringify(submit.body));
    assert.strictEqual(submit.body.is_anonymous, true);
    assert.strictEqual(submit.body.submitted_by, null, 'oluşturma response\'unda BİLE anonimse submitted_by gizlenmeli');

    const managerToken = getTestToken('yonetici');
    const list = await request(app).get('/api/feedback').set('Authorization', `Bearer ${managerToken}`);
    const item = list.body.find((f) => f.id === submit.body.id);
    assert.ok(item);
    assert.strictEqual(item.submitted_by, null, 'anonim bir bildirimde submitted_by yöneticiye dahi GÖSTERİLMEMELİ');
    assert.strictEqual(JSON.stringify(item).includes('Test Teknisyen'), false, 'gerçek isim response JSON\'unda hiçbir yerde YOK olmalı');

    const detail = await request(app).get(`/api/feedback/${submit.body.id}`).set('Authorization', `Bearer ${managerToken}`);
    assert.strictEqual(detail.status, 200);
    assert.strictEqual(detail.body.submitted_by, null, 'detay endpoint\'inde de aynı gizleme uygulanmalı');
  });

  it('3) anonim kayıt bile veritabanında GERÇEK submitted_by_user_id\'yi taşır (tamamen izsiz DEĞİL)', async () => {
    const submit = await request(app)
      .post('/api/feedback')
      .set('Authorization', `Bearer ${technicianToken}`)
      .field('description', 'İzsiz olmadığını kanıtlayan test.')
      .field('category', 'sikayet')
      .field('is_anonymous', 'true');
    assert.strictEqual(submit.status, 201);

    const row = getFeedbackRow(submit.body.id);
    assert.strictEqual(
      row.submitted_by_user_id,
      seeded.users.teknisyenId,
      'is_anonymous=1 olsa bile DB satırındaki submitted_by_user_id GERÇEK kullanıcıya işaret etmeli'
    );
    assert.strictEqual(row.is_anonymous, 1);
  });
});

describe('GET /api/feedback — görünürlük filtresi (teknisyen/dispeçer own-only, yönetici hepsi)', () => {
  let seeded;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
  });

  it('token olmadan 401 döner', async () => {
    const response = await request(app).get('/api/feedback');
    assert.strictEqual(response.status, 401);
  });

  it('teknisyen SADECE KENDİ gönderdiklerini görür, başkasınınkini görmez', async () => {
    const ownId = insertFeedback({ userId: seeded.users.teknisyenId, description: 'Kendi bildirimim' });
    insertFeedback({ userId: seeded.users.otherTeknisyenId, description: 'Başkasının bildirimi' });
    insertFeedback({ userId: seeded.users.dispecerId, description: 'Dispeçerin bildirimi' });

    const technicianToken = getTestToken('teknisyen');
    const response = await request(app).get('/api/feedback').set('Authorization', `Bearer ${technicianToken}`);

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.length, 1);
    assert.strictEqual(response.body[0].id, ownId);
  });

  it('dispeçer SADECE KENDİ gönderdiklerini görür — Modül 1\'deki iş emri deseninden FARKLI olarak, dispeçer BAŞKASININ da göremez (tablo: yalnızca yönetici hepsini görür)', async () => {
    const ownId = insertFeedback({ userId: seeded.users.dispecerId, description: 'Dispeçerin kendi bildirimi' });
    insertFeedback({ userId: seeded.users.teknisyenId, description: 'Teknisyenin bildirimi' });

    const dispatcherToken = getTestToken('dispecer');
    const response = await request(app).get('/api/feedback').set('Authorization', `Bearer ${dispatcherToken}`);

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.length, 1);
    assert.strictEqual(response.body[0].id, ownId);
  });

  it('yönetici HEPSİNİ görür', async () => {
    insertFeedback({ userId: seeded.users.teknisyenId });
    insertFeedback({ userId: seeded.users.otherTeknisyenId });
    insertFeedback({ userId: seeded.users.dispecerId });

    const managerToken = getTestToken('yonetici');
    const response = await request(app).get('/api/feedback').set('Authorization', `Bearer ${managerToken}`);

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.length, 3, 'yönetici TÜM kullanıcıların bildirimlerini görmeli');
  });

  it('?status=bekliyor filtresi doğru çalışır', async () => {
    insertFeedback({ userId: seeded.users.teknisyenId, status: 'bekliyor' });
    insertFeedback({ userId: seeded.users.teknisyenId, status: 'kapatildi' });

    const technicianToken = getTestToken('teknisyen');
    const response = await request(app).get('/api/feedback?status=bekliyor').set('Authorization', `Bearer ${technicianToken}`);

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.length, 1);
    assert.strictEqual(response.body[0].status, 'bekliyor');
  });

  it('geçersiz status değeri 400 döner', async () => {
    const technicianToken = getTestToken('teknisyen');
    const response = await request(app).get('/api/feedback?status=GECERSIZ').set('Authorization', `Bearer ${technicianToken}`);
    assert.strictEqual(response.status, 400);
  });

  it('boş veri durumu: hiç bildirim yokken hata değil, boş dizi döner', async () => {
    const managerToken = getTestToken('yonetici');
    const response = await request(app).get('/api/feedback').set('Authorization', `Bearer ${managerToken}`);
    assert.strictEqual(response.status, 200);
    assert.deepStrictEqual(response.body, []);
  });

  it('response schema doğru', async () => {
    insertFeedback({ userId: seeded.users.teknisyenId });
    const technicianToken = getTestToken('teknisyen');
    const response = await request(app).get('/api/feedback').set('Authorization', `Bearer ${technicianToken}`);
    assert.strictEqual(response.status, 200);
    assertSchema(response.body[0], {
      id: 'number',
      category: 'string',
      description: 'string',
      is_anonymous: 'boolean',
      status: 'string',
      created_at: 'string',
    });
  });
});

describe('GET /api/feedback/:id — sahiplik kontrolü (SEC-02 IDOR dersi, madde 4)', () => {
  let seeded;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
  });

  it('token olmadan 401 döner', async () => {
    const id = insertFeedback({ userId: seeded.users.teknisyenId });
    const response = await request(app).get(`/api/feedback/${id}`);
    assert.strictEqual(response.status, 401);
  });

  it('sahibi kendi kaydını görebilir', async () => {
    const id = insertFeedback({ userId: seeded.users.teknisyenId });
    const technicianToken = getTestToken('teknisyen');
    const response = await request(app).get(`/api/feedback/${id}`).set('Authorization', `Bearer ${technicianToken}`);
    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.id, id);
  });

  it('yönetici HERHANGİ bir kaydı görebilir', async () => {
    const id = insertFeedback({ userId: seeded.users.teknisyenId });
    const managerToken = getTestToken('yonetici');
    const response = await request(app).get(`/api/feedback/${id}`).set('Authorization', `Bearer ${managerToken}`);
    assert.strictEqual(response.status, 200);
  });

  it('[SEC-02] Kullanıcı B, kendisine ait olmayan bir şikayetin ID\'sini tahmin ederek erişmeye çalışırsa 404 alır (403 DEĞİL)', async () => {
    const id = insertFeedback({ userId: seeded.users.teknisyenId, description: 'Kullanıcı A\'nın gizli şikayeti' });

    const otherToken = generateValidToken({ id: seeded.users.otherTeknisyenId, role: 'teknisyen' });
    const response = await request(app).get(`/api/feedback/${id}`).set('Authorization', `Bearer ${otherToken}`);

    assert.strictEqual(response.status, 404, 'sahibi olmayan bir kullanıcı 404 almalı, kaydın varlığı sızdırılmamalı');
  });

  it('dispeçer de (yönetici olmadığı için) başkasının kaydına 404 ile karşılaşır', async () => {
    const id = insertFeedback({ userId: seeded.users.teknisyenId });
    const dispatcherToken = getTestToken('dispecer');
    const response = await request(app).get(`/api/feedback/${id}`).set('Authorization', `Bearer ${dispatcherToken}`);
    assert.strictEqual(response.status, 404);
  });

  it('var olmayan bir id için 404 döner', async () => {
    const managerToken = getTestToken('yonetici');
    const response = await request(app).get('/api/feedback/999999').set('Authorization', `Bearer ${managerToken}`);
    assert.strictEqual(response.status, 404);
  });

  it('sayısal olmayan id için 400 döner (500 ASLA)', async () => {
    const managerToken = getTestToken('yonetici');
    const response = await request(app).get('/api/feedback/abc').set('Authorization', `Bearer ${managerToken}`);
    assert.strictEqual(response.status, 400);
  });
});

describe('PATCH /api/feedback/:id/status — yalnızca dispeçer/yönetici (madde 6)', () => {
  let seeded;
  let feedbackId;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
    feedbackId = insertFeedback({ userId: seeded.users.teknisyenId });
  });

  it('token olmadan 401 döner', async () => {
    const response = await request(app).patch(`/api/feedback/${feedbackId}/status`).send({ status: 'incelendi' });
    assert.strictEqual(response.status, 401);
  });

  it('teknisyen kendi bildiriminin durumunu DAHİ güncelleyemez (403)', async () => {
    const technicianToken = getTestToken('teknisyen');
    const response = await request(app)
      .patch(`/api/feedback/${feedbackId}/status`)
      .set('Authorization', `Bearer ${technicianToken}`)
      .send({ status: 'incelendi' });
    assert.strictEqual(response.status, 403);

    const row = getFeedbackRow(feedbackId);
    assert.strictEqual(row.status, 'bekliyor', 'reddedilen istek yan etki bırakmamalı');
  });

  it('dispeçer/yönetici bir şikayeti "İncelendi" yapıp not ekler — bunun doğru kaydedildiğini doğrular (madde 6)', async () => {
    const dispatcherToken = getTestToken('dispecer');
    const response = await request(app)
      .patch(`/api/feedback/${feedbackId}/status`)
      .set('Authorization', `Bearer ${dispatcherToken}`)
      .send({ status: 'incelendi', reviewer_note: 'İnceledim, ilgili birime iletiyorum.' });

    assert.strictEqual(response.status, 200, JSON.stringify(response.body));
    assert.strictEqual(response.body.status, 'incelendi');
    assert.strictEqual(response.body.reviewer_note, 'İnceledim, ilgili birime iletiyorum.');
    assert.strictEqual(response.body.reviewed_by.id, seeded.users.dispecerId);
    assert.ok(response.body.reviewed_at);

    const row = getFeedbackRow(feedbackId);
    assert.strictEqual(row.status, 'incelendi', 'DB\'den tekrar okunan durum güncellenmiş olmalı');
    assert.strictEqual(row.reviewer_note, 'İnceledim, ilgili birime iletiyorum.');
    assert.strictEqual(row.reviewed_by_user_id, seeded.users.dispecerId);
    assert.ok(row.reviewed_at);
  });

  it('yönetici bir şikayeti "Kapatıldı" yapabilir', async () => {
    const managerToken = getTestToken('yonetici');
    const response = await request(app)
      .patch(`/api/feedback/${feedbackId}/status`)
      .set('Authorization', `Bearer ${managerToken}`)
      .send({ status: 'kapatildi' });

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.status, 'kapatildi');
  });

  it('var olmayan bir id için 404 döner', async () => {
    const managerToken = getTestToken('yonetici');
    const response = await request(app)
      .patch('/api/feedback/999999/status')
      .set('Authorization', `Bearer ${managerToken}`)
      .send({ status: 'incelendi' });
    assert.strictEqual(response.status, 404);
  });

  it('girdi doğrulama matrisi: status için kötü girdi varyasyonları 4xx dönmeli', async () => {
    const managerToken = getTestToken('yonetici');
    const results = await runInputValidationMatrix({
      app,
      method: 'patch',
      path: `/api/feedback/${feedbackId}/status`,
      authToken: managerToken,
      validPayload: { status: 'incelendi' },
      fields: [{ name: 'status', type: 'enum', required: true, enumValues: ['bekliyor', 'incelendi', 'kapatildi'] }],
    });
    assertAllRejected(results, 'PATCH /api/feedback/:id/status');
  });
});
