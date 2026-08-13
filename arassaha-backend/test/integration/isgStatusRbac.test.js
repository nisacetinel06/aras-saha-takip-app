// GÜVENLİK: PATCH /api/isg-reports/:id/status şu an (fix'ten ÖNCE) rol
// kontrolü YAPMIYOR — herhangi bir giriş yapmış kullanıcı (teknisyen dahil)
// bir İSG bildiriminin durumunu "incelendi"/"cozuldu" yapabiliyor. Modül 5'in
// tasarımına göre bu YÖNETİMSEL bir aksiyon (bildirimi inceleyen dispeçer/
// yönetici), bildiren teknisyenin kendisi DEĞİL — bkz. routes/workOrders.js'teki
// benzer ayrım: PATCH /api/workorders/:id/status requireRole('teknisyen',
// 'dispecer') (işi yapan teknisyen kendi ilerlemesini günceller) ama POST /
// (yeni iş emri açma) requireRole('dispecer', 'yonetici') (yönetimsel).
// İSG'de POST / (bildirim oluşturma) teknisyene AÇIK kalmalı (sahada gören
// odur) ama PATCH /:id/status (inceleme kararı) dispeçer/yönetici'ye
// KISITLANMALI.
//
// Bu dosya BİLEREK fix'ten ÖNCE yazıldı: aşağıdaki "[GÜVENLİK AÇIĞI KANITI]"
// testi ilk çalıştırmada KIRMIZI olmalı (403 bekleniyor, gerçek kod 200
// dönüyor) — bu, açığın gerçekten var olduğunun kanıtı. routes/isg.js'e
// requireRole('dispecer', 'yonetici') eklendikten SONRA aynı test YEŞİL
// olmalı.
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const request = require('supertest');
const app = require('../../server');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');
const { getTestToken } = require('../helpers/authHelper');
const { generateInvalidSignatureToken } = require('../helpers/tokenHelper');

// 1x1 saydam PNG — multer'ın fileFilter'ı (yalnızca image/jpeg|image/png)
// geçsin diye gerçek (geçerli) bir PNG byte dizisi kullanılıyor, sahte bir
// uzantı değil.
const MINIMAL_PNG_BUFFER = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  'base64'
);

describe('PATCH /api/isg-reports/:id/status — RBAC', () => {
  let seed;
  let isgReportId;

  beforeEach(() => {
    resetTestDatabase();
    seed = seedMinimalTestData();

    const now = new Date().toISOString();
    const info = db
      .prepare(
        `INSERT INTO isg_reports (reported_by_user_id, description, category, lat, lng, status, created_at)
         VALUES (?, 'Test İSG bildirimi', 'tehlikeli_durum', 39.9086, 41.2769, 'bekliyor', ?)`
      )
      .run(seed.users.teknisyenId, now);
    isgReportId = info.lastInsertRowid;
  });

  it('[GÜVENLİK AÇIĞI KANITI] teknisyen rolü İSG durumunu güncelleyebilmemeli', async () => {
    const technicianToken = getTestToken('teknisyen');

    const response = await request(app)
      .patch(`/api/isg-reports/${isgReportId}/status`)
      .set('Authorization', `Bearer ${technicianToken}`)
      .send({ status: 'incelendi' });

    assert.strictEqual(response.status, 403); // BEKLENEN güvenli davranış

    // Durum GERÇEKTEN değişmemiş olmalı (reddedilen istek yan etki bırakmamalı).
    const row = db.prepare('SELECT status FROM isg_reports WHERE id = ?').get(isgReportId);
    assert.strictEqual(row.status, 'bekliyor');
  });

  it('dispeçer rolü İSG durumunu güncelleyebilmeli, DB\'de gerçekten güncellenmeli', async () => {
    const dispatcherToken = getTestToken('dispecer');

    const response = await request(app)
      .patch(`/api/isg-reports/${isgReportId}/status`)
      .set('Authorization', `Bearer ${dispatcherToken}`)
      .send({ status: 'incelendi' });

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.status, 'incelendi');

    const row = db.prepare('SELECT status FROM isg_reports WHERE id = ?').get(isgReportId);
    assert.strictEqual(row.status, 'incelendi', 'DB\'den tekrar okunan durum güncellenmiş olmalı');
  });

  it('yönetici rolü İSG durumunu güncelleyebilmeli, DB\'de gerçekten güncellenmeli', async () => {
    const managerToken = getTestToken('yonetici');

    const response = await request(app)
      .patch(`/api/isg-reports/${isgReportId}/status`)
      .set('Authorization', `Bearer ${managerToken}`)
      .send({ status: 'cozuldu' });

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.status, 'cozuldu');

    const row = db.prepare('SELECT status FROM isg_reports WHERE id = ?').get(isgReportId);
    assert.strictEqual(row.status, 'cozuldu');
  });

  it('token olmadan 401 dönmeli', async () => {
    const response = await request(app).patch(`/api/isg-reports/${isgReportId}/status`).send({ status: 'incelendi' });

    assert.strictEqual(response.status, 401);
  });

  it('geçersiz (yanlış secret ile imzalanmış) token ile 401 dönmeli', async () => {
    const invalidToken = generateInvalidSignatureToken({ id: seed.users.dispecerId, role: 'dispecer' });

    const response = await request(app)
      .patch(`/api/isg-reports/${isgReportId}/status`)
      .set('Authorization', `Bearer ${invalidToken}`)
      .send({ status: 'incelendi' });

    assert.strictEqual(response.status, 401);
  });
});

describe('routes/isg.js diğer endpoint\'lerle tutarlılık (yalnızca PATCH /:id/status kısıtlanmalı)', () => {
  beforeEach(() => {
    resetTestDatabase();
    seedMinimalTestData();
  });

  it('teknisyen POST /api/isg-reports ile hâlâ yeni bildirim oluşturabilmeli (regresyon olmamalı)', async () => {
    const technicianToken = getTestToken('teknisyen');

    const response = await request(app)
      .post('/api/isg-reports')
      .set('Authorization', `Bearer ${technicianToken}`)
      .field('description', 'Test — teknisyen bildirim oluşturuyor')
      .field('category', 'tehlikeli_durum')
      .field('lat', '39.9086')
      .field('lng', '41.2769')
      .attach('photo', MINIMAL_PNG_BUFFER, { filename: 'test.png', contentType: 'image/png' });

    assert.strictEqual(response.status, 201, `beklenmedik yanıt: ${JSON.stringify(response.body)}`);
    assert.strictEqual(response.body.status, 'bekliyor');
  });

  it('teknisyen GET /api/isg-reports ile hâlâ listeyi görebilmeli (regresyon olmamalı)', async () => {
    const technicianToken = getTestToken('teknisyen');

    const response = await request(app).get('/api/isg-reports').set('Authorization', `Bearer ${technicianToken}`);

    assert.strictEqual(response.status, 200);
    assert.ok(Array.isArray(response.body));
  });
});
