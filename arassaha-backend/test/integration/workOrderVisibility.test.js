// SEC-02: IDOR (Insecure Direct Object Reference) — GET /api/workorders/:id
// ve PATCH /api/workorders/:id/status. GET /api/workorders (liste) zaten
// applyVisibilityFilter ile rol bazlı filtreleniyor (bkz. routes/workOrders.js,
// test/integration/workOrders.test.js), ama TEK KAYDI ID üzerinden çeken/
// güncelleyen bu iki endpoint aynı sahiplik kontrolünü YAPMIYORDU — bir
// teknisyen, kendisine atanmamış bir iş emrinin ID'sini bilerek/deneyerek
// (1, 2, 3, ...) doğrudan görebiliyor VE durumunu değiştirebiliyordu.
//
// SEC-03 GENİŞLETMESİ: aynı açığın POST /api/workorders/:id/photos'ta da
// var olduğu tespit edildi — bu endpoint SEC-02 kapsamı dışında kalmıştı,
// hiçbir sahiplik (hatta hiçbir rol) kontrolü yapmıyordu. Kod tekrarını
// önlemek için ortak kural artık utils/workOrderAccess.js'teki TEK bir
// fonksiyonda (assertWorkOrderAccessible) — üç endpoint de (GET /:id,
// PATCH /:id/status, POST /:id/photos) bunu kullanıyor. Bu dosyaya yeni bir
// dosya AÇILMADI, mevcut SEC-02 dosyası büyütüldü (aşağıdaki
// "POST /:id/photos" describe bloğu).
//
// Kapsam netleştirmesi (kod incelemesi):
// - GET /:id            → sahiplik kontrolü YOKTU (BULGU — SEC-02)
// - PATCH /:id/status   → sahiplik kontrolü YOKTU (BULGU — SEC-02, ayrıca bir
//                         VERİ DEĞİŞTİRME riski, salt okuma değil)
// - POST /:id/photos    → sahiplik kontrolü YOKTU (BULGU — SEC-03, bu dosyanın
//                         yeni bölümü)
// - GET /:id/photos (ayrı bir endpoint olarak) → YOK — fotoğraflar zaten
//                         GET /:id yanıtının bir parçası (`photos` alanı),
//                         bu yüzden "fotoğraf listeleme" IDOR koruması
//                         yukarıdaki GET /:id testleriyle ZATEN kapsanıyor,
//                         ayrı bir test gerekmiyor.
// - PATCH /:id/assign   → zaten requireRole('dispecer','yonetici') ile ROL
//                         bazlı korunuyor; teknisyen bu endpoint'e hiç
//                         erişemiyor (403) — SAHİPLİK bazlı bir kontrol değil,
//                         bu görevin kapsamı DIŞINDA, dokunulmadı.
// - POST /              → zaten requireRole('dispecer','yonetici'), kapsam dışı.
// - GET / (liste)       → zaten applyVisibilityFilter ile filtreli; bu dosyada
//                         yalnızca REGRESYON kontrolü için tekrar doğrulanıyor
//                         (Adım 5).
//
// HTTP status kararı: sahiplik başarısız olduğunda 404 (403 DEĞİL) — 403,
// "kayıt var ama senin değil" bilgisini sızdırır (ID enumeration'a yardımcı
// olur); 404 kaydın var olup olmadığını gizler. Kod tabanında bu tür bir
// (kaynağı isteyenin KENDİSİ için) sahiplik kontrolü daha önce hiçbir yerde
// yoktu (yalnızca requireRole tabanlı rol kontrolleri ve POST/assign'daki
// "hedef kullanıcı senin ekibinde mi" body-validasyonu 403 kullanıyor, o
// farklı bir kategori) — çakışan bir konvansiyon YOK, bu yüzden 404 ile
// ilerlendi.
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

const NON_EXISTENT_ID = 99999;
const VALID_JPEG_BUFFER = fs.readFileSync(path.join(__dirname, '..', 'fixtures', 'valid-test-image.jpg'));

describe('GET/PATCH /api/workorders/:id — IDOR / sahiplik kontrolü', () => {
  let seeded;
  let workOrderXId; // "İş Emri X" — Kullanıcı A'ya (teknisyenId) atanmış.
  let userAToken; // Kullanıcı A: seedMinimalTestData'daki teknisyenId (sicil '1001') — İş Emri X'in SAHİBİ.
  let userBToken; // Kullanıcı B: seedMinimalTestData'daki otherTeknisyenId (sicil '1002') — A'dan FARKLI, AYNI dispeçerin ekibinde İKİNCİ bir teknisyen.
  let dispatcherToken;
  let managerToken;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();

    workOrderXId = seeded.workOrders.ownWorkOrderId;
    userAToken = getTestToken('teknisyen'); // id'ye göre ilk teknisyen = teknisyenId (bkz. testDb.js insert sırası)
    userBToken = generateValidToken({ id: seeded.users.otherTeknisyenId, role: 'teknisyen' });
    dispatcherToken = getTestToken('dispecer');
    managerToken = getTestToken('yonetici');
  });

  describe('[GÜVENLİK AÇIĞI KANITI] cross-user erişim engellenmeli', () => {
    it("Kullanıcı B, Kullanıcı A'ya atanmış iş emrinin DETAYINA erişememeli", async () => {
      const response = await request(app)
        .get(`/api/workorders/${workOrderXId}`)
        .set('Authorization', `Bearer ${userBToken}`);

      assert.strictEqual(response.status, 404); // BEKLENEN güvenli davranış
    });

    it("Kullanıcı B, Kullanıcı A'ya atanmış iş emrinin DURUMUNU güncelleyememeli (ve DB'de gerçekten değişmemeli)", async () => {
      const beforeRow = db.prepare('SELECT status, updated_at FROM work_orders WHERE id = ?').get(workOrderXId);

      const response = await request(app)
        .patch(`/api/workorders/${workOrderXId}/status`)
        .set('Authorization', `Bearer ${userBToken}`)
        .send({ status: 'yolda' });

      assert.strictEqual(response.status, 404); // BEKLENEN güvenli davranış

      // Salt bir "bilgi sızıntısı" değil, yetkisiz bir VERİ DEĞİŞTİRME açığı
      // olup olmadığını kanıtlamak için DB'den TEKRAR okunuyor.
      const afterRow = db.prepare('SELECT status, updated_at FROM work_orders WHERE id = ?').get(workOrderXId);
      assert.strictEqual(afterRow.status, beforeRow.status, "durum Kullanıcı B tarafından DEĞİŞTİRİLMEMİŞ olmalı");
      assert.strictEqual(
        afterRow.updated_at,
        beforeRow.updated_at,
        "updated_at Kullanıcı B'nin reddedilen isteğiyle DEĞİŞMEMİŞ olmalı"
      );
    });
  });

  describe('pozitif kontroller (fix meşru erişimi kısıtlamamalı — regresyon olmamalı)', () => {
    it('dispeçer İş Emri X\'in detayına erişebilmeli (200)', async () => {
      const response = await request(app)
        .get(`/api/workorders/${workOrderXId}`)
        .set('Authorization', `Bearer ${dispatcherToken}`);
      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.id, workOrderXId);
    });

    it('dispeçer İş Emri X\'in durumunu güncelleyebilmeli (200)', async () => {
      // 'sahada' DEĞİL 'yolda' gönderilir: TEST-08'de eklenen durum geçiş
      // kuralı (acik -> yolda -> sahada -> cozuldu) nedeniyle, İş Emri X'in
      // başlangıç durumu 'acik'ten doğrudan 'sahada'ya atlamak artık (doğru
      // şekilde) reddedilir — bu test yalnızca "dispeçer bu endpoint'e
      // erişebiliyor mu" sahiplik/rol sorusunu sınadığı için geçerli bir
      // geçiş kullanmak yeterli.
      const response = await request(app)
        .patch(`/api/workorders/${workOrderXId}/status`)
        .set('Authorization', `Bearer ${dispatcherToken}`)
        .send({ status: 'yolda' });
      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.status, 'yolda');
    });

    it('yönetici İş Emri X\'in detayına erişebilmeli (200)', async () => {
      const response = await request(app)
        .get(`/api/workorders/${workOrderXId}`)
        .set('Authorization', `Bearer ${managerToken}`);
      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.id, workOrderXId);
    });

    it("Kullanıcı A kendi işinin (İş Emri X) DETAYINA erişebilmeli (200)", async () => {
      const response = await request(app)
        .get(`/api/workorders/${workOrderXId}`)
        .set('Authorization', `Bearer ${userAToken}`);
      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.id, workOrderXId);
    });

    it("Kullanıcı A kendi işinin (İş Emri X) DURUMUNU güncelleyebilmeli (200)", async () => {
      const response = await request(app)
        .patch(`/api/workorders/${workOrderXId}/status`)
        .set('Authorization', `Bearer ${userAToken}`)
        .send({ status: 'yolda' });
      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.status, 'yolda');

      const row = db.prepare('SELECT status FROM work_orders WHERE id = ?').get(workOrderXId);
      assert.strictEqual(row.status, 'yolda');
    });
  });

  describe('token olmadan erişim: 401', () => {
    it('GET /:id token olmadan 401 dönmeli', async () => {
      const response = await request(app).get(`/api/workorders/${workOrderXId}`);
      assert.strictEqual(response.status, 401);
    });

    it('PATCH /:id/status token olmadan 401 dönmeli', async () => {
      const response = await request(app).patch(`/api/workorders/${workOrderXId}/status`).send({ status: 'yolda' });
      assert.strictEqual(response.status, 401);
    });
  });

  describe('ID enumeration tutarlılığı (var olan vs olmayan ID AYNI yanıtı vermeli)', () => {
    it('GET /:id — Kullanıcı B için gerçek İş Emri X ID\'si ile olmayan bir ID (99999) AYNI (404) yanıtı vermeli', async () => {
      const realResponse = await request(app)
        .get(`/api/workorders/${workOrderXId}`)
        .set('Authorization', `Bearer ${userBToken}`);
      const fakeResponse = await request(app)
        .get(`/api/workorders/${NON_EXISTENT_ID}`)
        .set('Authorization', `Bearer ${userBToken}`);

      assert.strictEqual(realResponse.status, 404);
      assert.strictEqual(fakeResponse.status, 404);
      assert.strictEqual(
        realResponse.body.error,
        fakeResponse.body.error,
        'var olan (ama sahip olunmayan) ve var olmayan kayıt AYNI mesajı dönmeli — kayıt varlığı sızdırılmamalı'
      );
    });

    it('PATCH /:id/status — Kullanıcı B için gerçek İş Emri X ID\'si ile olmayan bir ID (99999) AYNI (404) yanıtı vermeli', async () => {
      const realResponse = await request(app)
        .patch(`/api/workorders/${workOrderXId}/status`)
        .set('Authorization', `Bearer ${userBToken}`)
        .send({ status: 'yolda' });
      const fakeResponse = await request(app)
        .patch(`/api/workorders/${NON_EXISTENT_ID}/status`)
        .set('Authorization', `Bearer ${userBToken}`)
        .send({ status: 'yolda' });

      assert.strictEqual(realResponse.status, 404);
      assert.strictEqual(fakeResponse.status, 404);
      assert.strictEqual(realResponse.body.error, fakeResponse.body.error);
    });
  });
});

describe('POST /api/workorders/:id/photos — IDOR / sahiplik kontrolü (SEC-03)', () => {
  let seeded;
  let workOrderXId;
  let userAToken;
  let userBToken;
  let dispatcherToken;
  let managerToken;

  function countPhotos(workOrderId) {
    return db.prepare('SELECT COUNT(*) AS c FROM work_order_photos WHERE work_order_id = ?').get(workOrderId).c;
  }

  function countUploadedFiles() {
    const uploadsDir = path.join(__dirname, '..', '..', 'uploads');
    if (!fs.existsSync(uploadsDir)) return 0;
    return fs.readdirSync(uploadsDir).length;
  }

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();

    workOrderXId = seeded.workOrders.ownWorkOrderId;
    userAToken = getTestToken('teknisyen');
    userBToken = generateValidToken({ id: seeded.users.otherTeknisyenId, role: 'teknisyen' });
    dispatcherToken = getTestToken('dispecer');
    managerToken = getTestToken('yonetici');
  });

  describe('[GÜVENLİK AÇIĞI KANITI] cross-user erişim engellenmeli', () => {
    it("Kullanıcı B, Kullanıcı A'ya atanmış iş emrine fotoğraf EKLEYEMEMELİ (404), diskte de kalıcı dosya kalmamalı", async () => {
      const beforeFileCount = countUploadedFiles();

      const response = await request(app)
        .post(`/api/workorders/${workOrderXId}/photos`)
        .set('Authorization', `Bearer ${userBToken}`)
        .attach('photo', VALID_JPEG_BUFFER, { filename: 'x.jpg', contentType: 'image/jpeg' });

      assert.strictEqual(response.status, 404, JSON.stringify(response.body));
      assert.strictEqual(countPhotos(workOrderXId), 0, 'reddedilen istek bir fotoğraf kaydı OLUŞTURMAMALI');
      assert.strictEqual(
        countUploadedFiles(),
        beforeFileCount,
        'reddedilen isteğin dosyası diskte YETİM olarak kalmamalı (silinmeli)'
      );
    });
  });

  describe('pozitif kontroller (fix meşru erişimi kısıtlamamalı — regresyon olmamalı)', () => {
    it('Kullanıcı A kendi işine (İş Emri X) fotoğraf ekleyebilmeli (201)', async () => {
      const response = await request(app)
        .post(`/api/workorders/${workOrderXId}/photos`)
        .set('Authorization', `Bearer ${userAToken}`)
        .attach('photo', VALID_JPEG_BUFFER, { filename: 'x.jpg', contentType: 'image/jpeg' });

      assert.strictEqual(response.status, 201, JSON.stringify(response.body));
      assert.strictEqual(countPhotos(workOrderXId), 1);
    });

    it('dispeçer İş Emri X\'e fotoğraf ekleyebilmeli (201)', async () => {
      const response = await request(app)
        .post(`/api/workorders/${workOrderXId}/photos`)
        .set('Authorization', `Bearer ${dispatcherToken}`)
        .attach('photo', VALID_JPEG_BUFFER, { filename: 'x.jpg', contentType: 'image/jpeg' });

      assert.strictEqual(response.status, 201, JSON.stringify(response.body));
    });

    it('yönetici İş Emri X\'e fotoğraf ekleyebilmeli (201)', async () => {
      const response = await request(app)
        .post(`/api/workorders/${workOrderXId}/photos`)
        .set('Authorization', `Bearer ${managerToken}`)
        .attach('photo', VALID_JPEG_BUFFER, { filename: 'x.jpg', contentType: 'image/jpeg' });

      assert.strictEqual(response.status, 201, JSON.stringify(response.body));
    });
  });

  describe('ID enumeration tutarlılığı', () => {
    it('Kullanıcı B için gerçek İş Emri X ID\'si ile olmayan bir ID (99999) AYNI (404) yanıtı vermeli', async () => {
      const realResponse = await request(app)
        .post(`/api/workorders/${workOrderXId}/photos`)
        .set('Authorization', `Bearer ${userBToken}`)
        .attach('photo', VALID_JPEG_BUFFER, { filename: 'x.jpg', contentType: 'image/jpeg' });
      const fakeResponse = await request(app)
        .post(`/api/workorders/${NON_EXISTENT_ID}/photos`)
        .set('Authorization', `Bearer ${userBToken}`)
        .attach('photo', VALID_JPEG_BUFFER, { filename: 'x.jpg', contentType: 'image/jpeg' });

      assert.strictEqual(realResponse.status, 404);
      assert.strictEqual(fakeResponse.status, 404);
      assert.strictEqual(realResponse.body.error, fakeResponse.body.error);
    });
  });
});

describe('GET /api/workorders (liste) — Adım 5: regresyon kontrolü', () => {
  let seeded;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
  });

  it('teknisyen hâlâ YALNIZCA kendisine atanan iş emirlerini görmeli (IDOR fix\'i listeyi etkilememeli)', async () => {
    const token = getTestToken('teknisyen');
    const response = await request(app).get('/api/workorders').set('Authorization', `Bearer ${token}`);

    assert.strictEqual(response.status, 200);
    const returnedIds = response.body.map((wo) => wo.id);
    assert.deepStrictEqual(returnedIds, [seeded.workOrders.ownWorkOrderId]);
    assert.ok(!returnedIds.includes(seeded.workOrders.otherWorkOrderId));
  });

  it('dispeçer hâlâ KENDİ EKİBİNDEKİ tüm teknisyenlerin iş emirlerini görmeli', async () => {
    const token = getTestToken('dispecer');
    const response = await request(app).get('/api/workorders').set('Authorization', `Bearer ${token}`);

    assert.strictEqual(response.status, 200);
    const returnedIds = response.body.map((wo) => wo.id).sort();
    assert.deepStrictEqual(returnedIds, [seeded.workOrders.ownWorkOrderId, seeded.workOrders.otherWorkOrderId].sort());
  });

  it('yönetici hâlâ filtresiz tüm iş emirlerini görmeli', async () => {
    const token = getTestToken('yonetici');
    const response = await request(app).get('/api/workorders').set('Authorization', `Bearer ${token}`);

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.length, 2);
  });
});
