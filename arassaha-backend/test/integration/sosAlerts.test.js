// Acil Durum / SOS Bildirimi Modülü (bkz. routes/sosAlerts.js) — üç ayrı
// güvenlik/tasarım iddiası burada kanıtlanıyor:
//
// 1) SIK TEKRARLANAN SOS FARKINDALIĞI (Konu 1): kısa sürede art arda gelen
//    SOS bildirimleri ASLA reddedilmez/bloklanmaz — yalnızca is_frequent_pattern
//    ile işaretlenir ve bildirim mesajına bir uyarı notu eklenir. Bu, hayati
//    bir özellikte "önce engelle, sonra sorgula" yaklaşımının BİLEREK
//    seçilmediğinin kanıtı (bkz. database.js sos_alerts migrasyon yorumu).
// 2) RBAC: PATCH /:id/acknowledge ve /:id/close SADECE dispeçer/yönetici.
// 3) GÖRÜNÜRLÜK: GET / — teknisyen SADECE KENDİ SOS bildirimlerini görür
//    (Modül 1 iş emri görünürlük deseniyle tutarlı, SEC-02 IDOR dersi),
//    dispeçer/yönetici TÜM bildirimleri görür.
//
// TEST-15 doğrulama notu: managerMessages.test.js'teki TEST-14 notuyla AYNI
// gerekçe — repoda literal bir "kritik yol tablosu" (README/dokümantasyon)
// yok, TEST-13/14/15 aslında test dosyalarına inline yazılan bir coverage-
// bulgusu yorum konvansiyonu. routes/sosAlerts.js coverage: %81.02 satır
// (kapsanmayan satırlar: PATCH /:id/note endpoint'i — bu görevin kapsamı
// DIŞINDA — ve 500 catch blokları/geçersiz-id 400 dalları).
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const request = require('supertest');
const app = require('../../server');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');
const { getTestToken } = require('../helpers/authHelper');
const { generateValidToken } = require('../helpers/tokenHelper');

function sendSos(token, lat = 39.9086, lng = 41.2769) {
  return request(app).post('/api/sos-alerts').set('Authorization', `Bearer ${token}`).send({ lat, lng });
}

describe('POST /api/sos-alerts — sık tekrar farkındalığı (Konu 1)', () => {
  let seeded;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
  });

  it('token olmadan 401 döner', async () => {
    const response = await request(app).post('/api/sos-alerts').send({ lat: 39.9, lng: 41.2 });
    assert.strictEqual(response.status, 401);
  });

  it('geçerli konumla herhangi bir rol (teknisyen dahil) SOS gönderebilmeli: 201 döner', async () => {
    const token = getTestToken('teknisyen');
    const response = await sendSos(token);
    assert.strictEqual(response.status, 201);
    assert.strictEqual(response.body.is_frequent_pattern, false);
  });

  it('lat/lng eksik veya sayı değilse 400 döner', async () => {
    const token = getTestToken('teknisyen');
    const response = await request(app)
      .post('/api/sos-alerts')
      .set('Authorization', `Bearer ${token}`)
      .send({ lat: 'kırk', lng: 41.2 });
    assert.strictEqual(response.status, 400);
  });

  it('REGRESYON (ISO/SQLite datetime string karşılaştırma hatası): 10 dakikadan ESKİ bir SOS "son 10 dakika" sayılmamalı', async () => {
    // 10 dakikalık pencerenin DIŞINDA (15 dakika önce) 5 eski kayıt elle eklenir —
    // eğer sayaç bunları "son 10 dakika" sanırsa 6. (yeni, gerçek) istek yanlışlıkla
    // is_frequent_pattern=1 ile işaretlenirdi.
    const fifteenMinutesAgo = new Date(Date.now() - 15 * 60 * 1000).toISOString();
    const insertOld = db.prepare(
      `INSERT INTO sos_alerts (triggered_by_user_id, lat, lng, status, created_at) VALUES (?, ?, ?, 'aktif', ?)`
    );
    for (let i = 0; i < 5; i++) {
      insertOld.run(seeded.users.teknisyenId, 39.9, 41.2, fifteenMinutesAgo);
    }

    const token = getTestToken('teknisyen');
    const response = await sendSos(token);

    assert.strictEqual(response.status, 201);
    assert.strictEqual(
      response.body.is_frequent_pattern,
      false,
      '15 dakika önceki kayıtlar "son 10 dakika" sayılmamalı — yalnızca gerçekten pencere içindeki (bu istek dahil 1) kayıt sayılmalı'
    );
  });

  it('[KRİTİK GÜVENLİK/CAN GÜVENLİĞİ KANITI] aynı kullanıcı 10 dakika içinde 6 SOS gönderdiğinde: HİÇBİRİ reddedilmez, 6.\'sı da 201 döner ve is_frequent_pattern=1 işaretlenir', async () => {
    const token = getTestToken('teknisyen');

    const responses = [];
    for (let i = 0; i < 6; i++) {
      // eslint-disable-next-line no-await-in-loop
      responses.push(await sendSos(token));
    }

    // Hiçbiri reddedilmedi — hepsi 201. Bu görevin en kritik doğrulaması:
    // yoğun/tekrarlanan bir acil durum bildirimi ASLA bloklanmıyor.
    for (const response of responses) {
      assert.strictEqual(response.status, 201, 'Hiçbir SOS isteği reddedilmemeli — sadece işaretlenmeli');
    }

    // DB'de gerçekten 6 ayrı satır oluşmuş olmalı (hiçbiri "engellenip" sessizce atlanmamış).
    const totalCount = db
      .prepare('SELECT COUNT(*) AS c FROM sos_alerts WHERE triggered_by_user_id = ?')
      .get(seeded.users.teknisyenId).c;
    assert.strictEqual(totalCount, 6, 'Tüm 6 SOS bildirimi DB\'ye gerçekten yazılmış olmalı');

    // İlk 5'i işaretlenmemiş (recentCount kendisi dahil <= 5), 6.'sı işaretlenmiş olmalı.
    const firstFive = responses.slice(0, 5);
    for (const response of firstFive) {
      assert.strictEqual(response.body.is_frequent_pattern, false);
    }
    const sixth = responses[5];
    assert.strictEqual(sixth.body.is_frequent_pattern, true, '6. SOS is_frequent_pattern=1 ile işaretlenmeli');

    const sixthRow = db.prepare('SELECT is_frequent_pattern FROM sos_alerts WHERE id = ?').get(sixth.body.id);
    assert.strictEqual(sixthRow.is_frequent_pattern, 1, 'DB\'de is_frequent_pattern gerçekten 1 olmalı');

    // Dispeçer/yöneticiye giden bildirim mesajı 6. SOS için uyarı notu İÇERMELİ,
    // önceki 5 SOS için İÇERMEMELİ.
    const notifications = db
      .prepare(
        `SELECT message FROM notifications
         WHERE related_type = 'sos_alert' AND related_id = ? AND user_id = ?`
      )
      .all(sixth.body.id, seeded.users.dispecerId);
    assert.ok(notifications.length > 0, 'Dispeçere 6. SOS için bir bildirim gitmiş olmalı');
    assert.ok(
      notifications[0].message.includes('son 10 dakikada'),
      'Bildirim mesajı sık tekrar uyarısını İÇERMELİ'
    );

    const firstNotifications = db
      .prepare(
        `SELECT message FROM notifications
         WHERE related_type = 'sos_alert' AND related_id = ? AND user_id = ?`
      )
      .all(responses[0].body.id, seeded.users.dispecerId);
    assert.ok(firstNotifications.length > 0);
    assert.ok(
      !firstNotifications[0].message.includes('son 10 dakikada'),
      'İlk SOS bildiriminde uyarı notu OLMAMALI'
    );
  });
});

describe('PATCH /api/sos-alerts/:id/acknowledge ve /close — RBAC (Konu 2)', () => {
  let seeded;
  let alertId;

  beforeEach(async () => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
    const teknisyenToken = getTestToken('teknisyen');
    const created = await sendSos(teknisyenToken);
    alertId = created.body.id;
  });

  it('token olmadan acknowledge çağrısı 401 döner', async () => {
    const response = await request(app).patch(`/api/sos-alerts/${alertId}/acknowledge`);
    assert.strictEqual(response.status, 401);
  });

  it('KRİTİK RBAC: teknisyen bir SOS bildirimini acknowledge edememeli (403)', async () => {
    const technicianToken = getTestToken('teknisyen');
    const response = await request(app)
      .patch(`/api/sos-alerts/${alertId}/acknowledge`)
      .set('Authorization', `Bearer ${technicianToken}`);
    assert.strictEqual(response.status, 403);

    const row = db.prepare('SELECT status FROM sos_alerts WHERE id = ?').get(alertId);
    assert.strictEqual(row.status, 'aktif', 'Reddedilen istek durumu DEĞİŞTİRMEMİŞ olmalı');
  });

  it('KRİTİK RBAC: teknisyen bir SOS bildirimini close edememeli (403)', async () => {
    const technicianToken = getTestToken('teknisyen');
    const response = await request(app)
      .patch(`/api/sos-alerts/${alertId}/close`)
      .set('Authorization', `Bearer ${technicianToken}`)
      .send({ closed_note: 'test' });
    assert.strictEqual(response.status, 403);

    const row = db.prepare('SELECT status FROM sos_alerts WHERE id = ?').get(alertId);
    assert.strictEqual(row.status, 'aktif');
  });

  it('dispeçer acknowledge yapabilmeli, DB gerçekten güncellenmeli', async () => {
    const dispatcherToken = getTestToken('dispecer');
    const response = await request(app)
      .patch(`/api/sos-alerts/${alertId}/acknowledge`)
      .set('Authorization', `Bearer ${dispatcherToken}`);
    assert.strictEqual(response.status, 200);

    const row = db.prepare('SELECT status, acknowledged_by_user_id FROM sos_alerts WHERE id = ?').get(alertId);
    assert.strictEqual(row.status, 'onaylandi');
    assert.strictEqual(row.acknowledged_by_user_id, seeded.users.dispecerId);
  });

  it('yönetici close yapabilmeli, DB gerçekten güncellenmeli', async () => {
    const managerToken = getTestToken('yonetici');
    const response = await request(app)
      .patch(`/api/sos-alerts/${alertId}/close`)
      .set('Authorization', `Bearer ${managerToken}`)
      .send({ closed_note: 'çözüldü' });
    assert.strictEqual(response.status, 200);

    const row = db.prepare('SELECT status, closed_note, closed_by_user_id FROM sos_alerts WHERE id = ?').get(alertId);
    assert.strictEqual(row.status, 'kapatildi');
    assert.strictEqual(row.closed_note, 'çözüldü');
    assert.strictEqual(row.closed_by_user_id, seeded.users.yoneticiId);
  });
});

describe('GET /api/sos-alerts — görünürlük (Konu 3)', () => {
  let seeded;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
  });

  it('token olmadan 401 döner', async () => {
    const response = await request(app).get('/api/sos-alerts');
    assert.strictEqual(response.status, 401);
  });

  it('teknisyen sadece KENDİ SOS bildirimlerini görmeli, başkasınınkini görmemeli (IDOR kontrolü)', async () => {
    const tokenA = generateValidToken({ id: seeded.users.teknisyenId, role: 'teknisyen' });
    const tokenB = generateValidToken({ id: seeded.users.otherTeknisyenId, role: 'teknisyen' });

    await sendSos(tokenA);
    const secretResponse = await sendSos(tokenB);
    const secretAlertId = secretResponse.body.id;

    const responseAsA = await request(app).get('/api/sos-alerts').set('Authorization', `Bearer ${tokenA}`);
    assert.strictEqual(responseAsA.status, 200);
    assert.strictEqual(responseAsA.body.length, 1, 'A yalnızca KENDİ 1 bildirimini görmeli');
    assert.strictEqual(responseAsA.body[0].triggered_by_user_id, seeded.users.teknisyenId);
    const returnedIds = responseAsA.body.map((r) => r.id);
    assert.ok(!returnedIds.includes(secretAlertId), 'B\'nin SOS bildirimi A\'nın yanıtında SIZMIŞ');
  });

  it('dispeçer/yönetici TÜM SOS bildirimlerini görmeli (önceki davranış korunur)', async () => {
    const tokenA = generateValidToken({ id: seeded.users.teknisyenId, role: 'teknisyen' });
    const tokenB = generateValidToken({ id: seeded.users.otherTeknisyenId, role: 'teknisyen' });
    await sendSos(tokenA);
    await sendSos(tokenB);

    const dispatcherToken = getTestToken('dispecer');
    const responseAsDispatcher = await request(app)
      .get('/api/sos-alerts')
      .set('Authorization', `Bearer ${dispatcherToken}`);
    assert.strictEqual(responseAsDispatcher.status, 200);
    assert.strictEqual(responseAsDispatcher.body.length, 2);

    const managerToken = getTestToken('yonetici');
    const responseAsManager = await request(app)
      .get('/api/sos-alerts')
      .set('Authorization', `Bearer ${managerToken}`);
    assert.strictEqual(responseAsManager.status, 200);
    assert.strictEqual(responseAsManager.body.length, 2);
  });

  it('teknisyen hiç SOS göndermemişse boş dizi döner (hata değil)', async () => {
    const token = getTestToken('teknisyen');
    const response = await request(app).get('/api/sos-alerts').set('Authorization', `Bearer ${token}`);
    assert.strictEqual(response.status, 200);
    assert.deepStrictEqual(response.body, []);
  });
});
