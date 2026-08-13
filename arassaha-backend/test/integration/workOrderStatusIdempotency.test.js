// TEST-08: PATCH /api/workorders/:id/status — (1) durum geçiş kuralları,
// (2) client_action_id idempotency mekanizması (Modül 17 — Çevrimdışı Yazma
// Kuyruğu). Gerçek :memory: SQLite + gerçek supertest istekleri, mock yok.
//
// ADIM 0 BULGULARI (kod incelemesi, routes/workOrders.js PATCH /:id/status):
//
// 1) DURUM GEÇİŞ KURALI — EKSİKTİ, BULUNDU VE DÜZELTİLDİ. Endpoint yalnızca
//    `VALID_STATUSES.includes(status)` (gönderilen değer 4 enum'dan biri mi)
//    kontrol ediyordu — mevcut durumdan gönderilen duruma GERÇEKTEN mantıklı
//    bir sonraki adım olup olmadığını hiç doğrulamıyordu. Yani API'ye
//    doğrudan istek atan bir istemci 'acik'ten doğrudan 'cozuldu'ya
//    geçebiliyor ya da 'sahada'dan 'yolda'ya geri dönebiliyordu — Flutter
//    UI'ının dayattığı sıra yalnızca istemci tarafında bir kısıtlamaydı.
//    DÜZELTME: routes/workOrders.js'e VALID_TRANSITIONS haritası eklendi
//    (acik->[yolda], yolda->[sahada], sahada->[cozuldu], cozuldu->[]) ve
//    PATCH /:id/status bu haritayı zorunlu kılıyor artık (bkz. aşağıdaki
//    "durum geçiş kuralları" describe bloğu).
//
// 2) İDEMPOTENCY SIRASI — DOĞRUYDU (client_action_id kontrolü zaten
//    ownership kontrolünden SONRA, herhangi bir yazmadan ÖNCE çalışıyordu).
//    Yeni geçiş kuralı kontrolünü BİLEREK client_action_id kontrolünden
//    SONRAYA eklendim: bir action zaten başarıyla işlenmişse, o geçiş bir kez
//    doğrulanıp uygulanmıştır — replay'de TEKRAR geçiş kuralına karşı
//    sınanmaz (aksi halde, örneğin iş emri replay ANINDA farklı bir duruma
//    ilerlemiş olsaydı, ilk seferinde geçerli olan bir geçiş ikinci
//    denemede yanlışlıkla reddedilebilirdi).
//
// 3) BAŞARISIZ DENEME KAYDI — DOĞRUYDU (ve düzeltme sonrası da doğru
//    kalıyor): `processed_client_actions` INSERT'i yalnızca UPDATE'ten
//    SONRA, başarı yolunda çalışıyor (bkz. route sonu). Yeni geçiş kuralı
//    kontrolü UPDATE'ten ÖNCE 400 ile erken çıktığı için, geçersiz bir geçiş
//    denemesi client_action_id'yi ASLA "işlendi" olarak işaretlemiyor —
//    istemci aynı id ile düzeltip tekrar deneyebiliyor (bkz. Adım 6 testi).
//
// 4) DUPLICATE RESPONSE TUTARLILIĞI — DOĞRUYDU: replay, `response_json`
//    olarak SAKLANAN birebir aynı başarılı yanıtı (200 + iş emri nesnesi)
//    döner — istemcinin özel bir "zaten işlendi" durumu ele alması gerekmez.
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const request = require('supertest');
const app = require('../../server');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');
const { getTestToken } = require('../helpers/authHelper');

function getWorkOrder(id) {
  return db.prepare('SELECT * FROM work_orders WHERE id = ?').get(id);
}
function getEquipment(id) {
  return db.prepare('SELECT * FROM equipment WHERE id = ?').get(id);
}
function getProcessedAction(clientActionId) {
  return db.prepare('SELECT * FROM processed_client_actions WHERE client_action_id = ?').get(clientActionId) || null;
}
function countProcessedActions(clientActionId) {
  return db.prepare('SELECT COUNT(*) AS c FROM processed_client_actions WHERE client_action_id = ?').get(clientActionId).c;
}

describe('PATCH /api/workorders/:id/status — durum geçişi + idempotency', () => {
  let seeded;
  let workOrderId;
  let equipmentId;
  let technicianToken;
  let dispatcherToken;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
    workOrderId = seeded.workOrders.ownWorkOrderId; // başlangıç durumu: 'acik' (bkz. testDb.js)
    equipmentId = seeded.equipmentId;
    technicianToken = getTestToken('teknisyen'); // İş Emri X'in sahibi
    dispatcherToken = getTestToken('dispecer');
  });

  describe('durum geçiş kuralları (acik -> yolda -> sahada -> cozuldu)', () => {
    it('geçerli geçiş (acik -> yolda): 200, DB\'de durum gerçekten yolda olmalı', async () => {
      const response = await request(app)
        .patch(`/api/workorders/${workOrderId}/status`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ status: 'yolda' });

      assert.strictEqual(response.status, 200);
      assert.strictEqual(getWorkOrder(workOrderId).status, 'yolda');
    });

    it('geçersiz geçiş — ADIM ATLAMA (acik -> cozuldu doğrudan): 400, durum DEĞİŞMEMELİ', async () => {
      const response = await request(app)
        .patch(`/api/workorders/${workOrderId}/status`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ status: 'cozuldu' });

      assert.strictEqual(response.status, 400);
      assert.strictEqual(getWorkOrder(workOrderId).status, 'acik', 'adım atlayan geçiş uygulanmamış olmalı');
    });

    it('geçersiz geçiş — GERİYE GİTME (sahada -> yolda): 400, durum DEĞİŞMEMELİ', async () => {
      db.prepare('UPDATE work_orders SET status = ? WHERE id = ?').run('sahada', workOrderId);

      const response = await request(app)
        .patch(`/api/workorders/${workOrderId}/status`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ status: 'yolda' });

      assert.strictEqual(response.status, 400);
      assert.strictEqual(getWorkOrder(workOrderId).status, 'sahada', 'geriye giden geçiş uygulanmamış olmalı');
    });

    it('SON DURUMDAN çıkış denemesi (cozuldu -> herhangi bir durum): 400', async () => {
      db.prepare('UPDATE work_orders SET status = ? WHERE id = ?').run('cozuldu', workOrderId);

      const response = await request(app)
        .patch(`/api/workorders/${workOrderId}/status`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ status: 'acik' });

      assert.strictEqual(response.status, 400);
      assert.strictEqual(getWorkOrder(workOrderId).status, 'cozuldu', "'cozuldu' son durum, hiçbir yere geçemez");
    });
  });

  describe('idempotency — temel senaryo (Adım 3)', () => {
    it('aynı client_action_id ile ikinci istek, durumu tekrar değiştirmemeli, AYNI yanıtı dönmeli', async () => {
      const clientActionId = 'test-uuid-12345';

      const firstResponse = await request(app)
        .patch(`/api/workorders/${workOrderId}/status`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ status: 'yolda', client_action_id: clientActionId });
      assert.strictEqual(firstResponse.status, 200);

      const secondResponse = await request(app)
        .patch(`/api/workorders/${workOrderId}/status`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ status: 'yolda', client_action_id: clientActionId });
      assert.strictEqual(secondResponse.status, 200); // hata değil, yine başarılı
      assert.deepStrictEqual(secondResponse.body, firstResponse.body); // AYNI response

      // DB'de sadece BİR kez işlenmiş — hâlâ 'yolda', üçüncü bir duruma sıçramamış.
      assert.strictEqual(getWorkOrder(workOrderId).status, 'yolda');
    });
  });

  describe('idempotency — yan etkilerin TEKRARLANMAMASI (Adım 4)', () => {
    // NOT: Bu endpoint (PATCH /:id/status) Modül 6 bildirim sistemini
    // TETİKLEMİYOR (createNotification çağrısı yok — kod incelemesiyle
    // doğrulandı, bkz. routes/workOrders.js; bildirim yalnızca POST / ve
    // PATCH /:id/assign'da var). Bu yüzden prompt'un "notifications
    // tablosunda tekrar bildirim gitmedi" kontrolü bu endpoint için
        // UYGULANAMAZ — atlandı (görevde de "geçerli değilse atla" deniyordu).
    // Onun yerine, bu endpoint'in GERÇEKTEN var olan tek yan etkisi
    // (equipment.last_maintenance_date güncellemesi, status 'cozuldu'
    // olduğunda) kullanıldı: eğer idempotency bozuk olsaydı, replay tekrar
    // UPDATE çalıştırır ve last_maintenance_date'i YENİ bir timestamp'e
    // günceller (kod her çağrıda `new Date().toISOString()` üretiyor) —
    // bu yüzden "değişmedi" kontrolü gerçek bir kanıt değeri taşıyor.
    it('cozuldu geçişinde tetiklenen equipment.last_maintenance_date güncellemesi İKİNCİ istekte TEKRARLANMAMALI', async () => {
      // Önce geçerli sırayla 'sahada'ya kadar ilerlet (idempotency dışı, düz istekler).
      await request(app)
        .patch(`/api/workorders/${workOrderId}/status`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ status: 'yolda' });
      await request(app)
        .patch(`/api/workorders/${workOrderId}/status`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ status: 'sahada' });

      const clientActionId = 'test-uuid-cozuldu-001';

      const firstResponse = await request(app)
        .patch(`/api/workorders/${workOrderId}/status`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ status: 'cozuldu', client_action_id: clientActionId });
      assert.strictEqual(firstResponse.status, 200);

      const equipmentAfterFirst = getEquipment(equipmentId);
      assert.ok(equipmentAfterFirst.last_maintenance_date, 'ilk başarılı geçişte last_maintenance_date damgalanmalı');

      // Küçük bir gecikme, eğer idempotency bozuksa ikinci UPDATE'in KESİNLİKLE
      // farklı (daha geç) bir timestamp üretmesini garanti eder — testin
      // yanlışlıkla "aynı milisaniyeye denk geldiği için geçti" olmasını önler.
      await new Promise((resolve) => setTimeout(resolve, 20));

      const secondResponse = await request(app)
        .patch(`/api/workorders/${workOrderId}/status`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ status: 'cozuldu', client_action_id: clientActionId });

      assert.strictEqual(secondResponse.status, 200);
      assert.deepStrictEqual(secondResponse.body, firstResponse.body, 'replay birebir AYNI yanıtı dönmeli (updated_at dahil)');

      const equipmentAfterSecond = getEquipment(equipmentId);
      assert.strictEqual(
        equipmentAfterSecond.last_maintenance_date,
        equipmentAfterFirst.last_maintenance_date,
        'yan etki (last_maintenance_date güncellemesi) İKİNCİ istekte TEKRARLANMAMALI'
      );
    });
  });

  describe('processed_client_actions kaydının doğruluğu (Adım 5)', () => {
    it('ilk başarılı istekten sonra TAM OLARAK 1 kayıt olmalı, ikinci (duplicate) istekten sonra da hâlâ 1', async () => {
      const clientActionId = 'test-uuid-12345';

      await request(app)
        .patch(`/api/workorders/${workOrderId}/status`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ status: 'yolda', client_action_id: clientActionId });

      const afterFirst = getProcessedAction(clientActionId);
      assert.ok(afterFirst, 'processed_client_actions\'da bir kayıt olmalı');
      assert.strictEqual(countProcessedActions(clientActionId), 1);

      await request(app)
        .patch(`/api/workorders/${workOrderId}/status`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ status: 'yolda', client_action_id: clientActionId });

      assert.strictEqual(
        countProcessedActions(clientActionId),
        1,
        'ikinci (duplicate) istek YENİ bir kayıt eklememeli — hâlâ tam olarak 1'
      );
    });
  });

  describe('başarısız işlem sonrası idempotency davranışı (Adım 6)', () => {
    it('başarısız bir işlem processed_client_actions\'a kaydedilmemeli, istemci AYNI id ile tekrar deneyebilmeli', async () => {
      const clientActionId = 'test-uuid-99999';

      // İlk deneme — GEÇERSİZ bir durum geçişi (acik'ten doğrudan cozuldu'ya).
      const failedResponse = await request(app)
        .patch(`/api/workorders/${workOrderId}/status`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ status: 'cozuldu', client_action_id: clientActionId });
      assert.strictEqual(failedResponse.status, 400);

      // processed_client_actions'da bu id KAYITLI OLMAMALI.
      assert.strictEqual(getProcessedAction(clientActionId), null);
      assert.strictEqual(getWorkOrder(workOrderId).status, 'acik', 'başarısız deneme durumu değiştirmemiş olmalı');

      // Şimdi AYNI client_action_id ile GEÇERLİ bir istek (istemci düzeltip tekrar deniyor).
      const retryResponse = await request(app)
        .patch(`/api/workorders/${workOrderId}/status`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ status: 'yolda', client_action_id: clientActionId });
      assert.strictEqual(retryResponse.status, 200, 'aynı id ile düzeltilmiş istek KİLİTLENMEMİŞ olmalı');
      assert.strictEqual(getWorkOrder(workOrderId).status, 'yolda');
      assert.strictEqual(countProcessedActions(clientActionId), 1, 'yalnızca başarılı deneme kaydedilmeli');
    });
  });

  describe('offline kuyruğundan duplicate istek — uçtan uca simülasyon (Adım 7)', () => {
    it(
      'GERÇEK DÜNYA SENARYOSU: istemci isteği gönderir, sunucu BAŞARIYLA işler, ama yanıt ağ kesintisi ' +
        'yüzünden istemciye ULAŞMAZ — istemci başarılı olduğunu BİLMEDİĞİ için (offline_queue_service.dart, ' +
        'Modül 17) GÜVENLİ OLMAK İÇİN aynı client_action_id ile isteği TEKRAR gönderir. Sunucu bu ikinci ' +
        'isteği güvenle, yan etkisiz, tutarlı bir başarılı yanıtla karşılamalı — istemcinin "zaten işlendi mi?" ' +
        'diye ayrı bir sorgu atmasına gerek kalmamalı.',
      async () => {
        const clientActionId = 'offline-queue-sync-uuid-777';

        // Sunucu tarafında GERÇEKTEN başarıyla işlenen orijinal istek.
        const serverProcessedResponse = await request(app)
          .patch(`/api/workorders/${workOrderId}/status`)
          .set('Authorization', `Bearer ${technicianToken}`)
          .send({ status: 'yolda', client_action_id: clientActionId });
        assert.strictEqual(serverProcessedResponse.status, 200);
        assert.strictEqual(getWorkOrder(workOrderId).status, 'yolda');

        // İstemci yanıtı ALMADI (varsayım) ve güvenlik için AYNI isteği tekrar gönderiyor.
        const clientRetryResponse = await request(app)
          .patch(`/api/workorders/${workOrderId}/status`)
          .set('Authorization', `Bearer ${technicianToken}`)
          .send({ status: 'yolda', client_action_id: clientActionId });

        assert.strictEqual(clientRetryResponse.status, 200, 'istemci normal bir başarılı yanıt almalı, özel bir hata DEĞİL');
        assert.deepStrictEqual(clientRetryResponse.body, serverProcessedResponse.body);
        assert.strictEqual(getWorkOrder(workOrderId).status, 'yolda', 'durum İKİNCİ kez ilerlememiş olmalı');
        assert.strictEqual(countProcessedActions(clientActionId), 1);
      }
    );
  });

  describe('dispeçer de aynı geçiş kuralına ve idempotency\'ye tabi (regresyon)', () => {
    it('dispeçer için de geçersiz geçiş 400 döner', async () => {
      const response = await request(app)
        .patch(`/api/workorders/${workOrderId}/status`)
        .set('Authorization', `Bearer ${dispatcherToken}`)
        .send({ status: 'cozuldu' });
      assert.strictEqual(response.status, 400);
    });
  });
});
