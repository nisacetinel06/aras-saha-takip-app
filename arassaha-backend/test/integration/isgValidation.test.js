// TEST-09: routes/isg.js'teki yazma endpoint'lerinin girdi doğrulama
// matrisi + özel senaryolar (mass assignment, geçersiz id, çok multipart-özel
// nüanslar).
//
// ADIM 0 BULGULARI VE DÜZELTMELER (routes/isg.js):
//   1) `if (!description || !description.trim())` — description truthy-ama-
//      string-olmayan bir değer (örn. multipart'ta aynı alan adı iki kez
//      gönderilip busboy bunu bir DİZİYE çevirdiğinde) verildiğinde `.trim()`
//      TypeError fırlatıp 500 dönüyordu. DÜZELTME: `typeof !== 'string'`
//      kontrolü eklendi.
//   2) `Number.isNaN(latNum) || Number.isNaN(lngNum)` kontrolü, lat/lng boş
//      string ('') olarak gönderildiğinde YAKALAMIYORDU — `Number('')` 0'a
//      düşüyor (NaN değil), bu da boş bırakılmış bir form alanının GEÇERLİ
//      bir (0,0) GPS konumu gibi kabul edilmesine yol açıyordu. DÜZELTME:
//      lat/lng için ayrıca boş/eksik kontrolü eklendi.
//   3) MASS ASSIGNMENT kontrolü: reported_by_user_id zaten req.user.id'den
//      dolduruluyordu (istemciden hiç okunmuyordu) — bu dosyada bunun
//      GERÇEKTEN bypass edilemediği doğrulanıyor (açık bulunmadı).
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

const VALID_JPEG_BUFFER = fs.readFileSync(path.join(__dirname, '..', 'fixtures', 'valid-test-image.jpg'));
const FILE_ATTACHMENT = { field: 'photo', buffer: VALID_JPEG_BUFFER, filename: 'test.jpg', contentType: 'image/jpeg' };

function getIsgReport(id) {
  return db.prepare('SELECT * FROM isg_reports WHERE id = ?').get(id);
}

describe('routes/isg.js — girdi doğrulama matrisi + özel senaryolar', () => {
  let seeded;
  let technicianToken;
  let dispatcherToken;
  let isgReportId;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
    technicianToken = getTestToken('teknisyen');
    dispatcherToken = getTestToken('dispecer');

    const now = new Date().toISOString();
    const info = db
      .prepare(
        `INSERT INTO isg_reports (reported_by_user_id, description, category, lat, lng, status, created_at)
         VALUES (?, 'Test bildirimi', 'tehlikeli_durum', 39.9086, 41.2769, 'bekliyor', ?)`
      )
      .run(seeded.users.teknisyenId, now);
    isgReportId = info.lastInsertRowid;
  });

  describe('POST /api/isg-reports — matris (multipart)', () => {
    it('description/category/lat/lng için kötü girdi varyasyonları 4xx dönmeli (500 ASLA)', async () => {
      const results = await runInputValidationMatrix({
        app,
        method: 'post',
        path: '/api/isg-reports',
        authToken: technicianToken,
        multipart: true,
        fileAttachment: FILE_ATTACHMENT,
        validPayload: {
          description: 'Test bildirimi',
          category: 'ekipman_arizasi',
          lat: '39.9',
          lng: '41.27',
        },
        fields: [
          { name: 'description', type: 'string', required: true },
          { name: 'category', type: 'enum', required: true, enumValues: ['ekipman_arizasi', 'tehlikeli_durum', 'is_kazasi_riski', 'diger'] },
          // lat/lng: coğrafi koordinatlarda NEGATİF değer geçerlidir (güney
          // yarımküre/batı meridyeni) — skipNegative:true.
          { name: 'lat', type: 'number', required: true, skipNegative: true },
          { name: 'lng', type: 'number', required: true, skipNegative: true },
        ],
      });

      assertAllRejected(results, 'POST /api/isg-reports');
    });

    // lat/lng 'number' tipinde olduğu için matrisin "empty string" adımı
    // (yalnızca string/enum alanlara uygulanır) bunları test ETMEZ — Adım 0
    // bulgusu #2'yi (boş string → sessizce 0'a düşme) doğrudan doğrulamak
    // için elle yazıldı.
    it('lat/lng boş string olarak gönderilirse 400 dönmeli (sessizce (0,0) KABUL EDİLMEMELİ)', async () => {
      const response = await request(app)
        .post('/api/isg-reports')
        .set('Authorization', `Bearer ${technicianToken}`)
        .field('description', 'Test')
        .field('category', 'ekipman_arizasi')
        .field('lat', '')
        .field('lng', '')
        .attach('photo', VALID_JPEG_BUFFER, { filename: 'x.jpg', contentType: 'image/jpeg' });

      assert.strictEqual(response.status, 400, JSON.stringify(response.body));

      const count = db.prepare('SELECT COUNT(*) AS c FROM isg_reports WHERE lat = 0 AND lng = 0').get().c;
      assert.strictEqual(count, 0, '(0,0) konumuyla sahte bir kayıt oluşmamalı');
    });

    it('MASS ASSIGNMENT: reported_by_user_id enjekte edilse bile bildirim GERÇEK giriş yapan kullanıcıya atanmalı', async () => {
      const response = await request(app)
        .post('/api/isg-reports')
        .set('Authorization', `Bearer ${technicianToken}`)
        .field('description', 'Sahte reported_by_user_id denemesi')
        .field('category', 'tehlikeli_durum')
        .field('lat', '39.9')
        .field('lng', '41.27')
        .field('reported_by_user_id', String(seeded.users.yoneticiId)) // başka birinin id'si — istemcinin kötü niyetli enjeksiyonu
        .attach('photo', VALID_JPEG_BUFFER, { filename: 'x.jpg', contentType: 'image/jpeg' });

      assert.strictEqual(response.status, 201, JSON.stringify(response.body));
      assert.strictEqual(
        response.body.reported_by.id,
        seeded.users.teknisyenId,
        'enjekte edilen reported_by_user_id YOK SAYILMALI, gerçek giriş yapan kullanıcı (teknisyen) kullanılmalı'
      );

      const row = getIsgReport(response.body.id);
      assert.strictEqual(row.reported_by_user_id, seeded.users.teknisyenId, 'DB\'de de gerçek giriş yapan kullanıcı olmalı');
    });
  });

  describe('PATCH /api/isg-reports/:id/status — matris', () => {
    it('status alanı için kötü girdi varyasyonları 4xx dönmeli (500 ASLA)', async () => {
      const results = await runInputValidationMatrix({
        app,
        method: 'patch',
        path: `/api/isg-reports/${isgReportId}/status`,
        authToken: dispatcherToken,
        validPayload: { status: 'incelendi' },
        fields: [{ name: 'status', type: 'enum', required: true, enumValues: ['bekliyor', 'incelendi', 'cozuldu'] }],
      });

      assertAllRejected(results, 'PATCH /api/isg-reports/:id/status');
    });
  });

  describe('Geçersiz ID (path parametresi)', () => {
    it('PATCH /:id/status — sayısal olmayan id ("abc") → 400, ASLA 500', async () => {
      const response = await request(app)
        .patch('/api/isg-reports/abc/status')
        .set('Authorization', `Bearer ${dispatcherToken}`)
        .send({ status: 'incelendi' });
      assert.strictEqual(response.status, 400);
    });

    it('PATCH /:id/status — negatif id (-1) → 404, ASLA 500', async () => {
      const response = await request(app)
        .patch('/api/isg-reports/-1/status')
        .set('Authorization', `Bearer ${dispatcherToken}`)
        .send({ status: 'incelendi' });
      assert.strictEqual(response.status, 404);
    });

    it('PATCH /:id/status — aşırı büyük id → çökmeden 4xx döner', async () => {
      const response = await request(app)
        .patch('/api/isg-reports/999999999999999999999/status')
        .set('Authorization', `Bearer ${dispatcherToken}`)
        .send({ status: 'incelendi' });
      assert.ok(response.status >= 400 && response.status < 500, `beklenmedik status ${response.status}`);
    });

    it('POST /api/isg-reports/:id/photos gibi bir alt-kaynak YOK (fotoğraf yalnızca oluşturmada eklenir) — bu route için ekstra id testi gerekmiyor', () => {
      // Bilgi amaçlı: routes/isg.js'te POST /:id/photos endpoint'i yok,
      // fotoğraf yalnızca POST / (oluşturma) sırasında eklenir — bkz. Adım 0 envanteri.
      assert.ok(true);
    });
  });
});
