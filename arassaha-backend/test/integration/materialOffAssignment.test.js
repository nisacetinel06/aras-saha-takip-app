// "Atanmamış iş emrine malzeme kaydı" görünürlüğü (hesap verebilirlik) —
// bkz. routes/materials.js POST/GET /workorders/:workOrderId/materials ve
// GET /materials/off-assignment-usage. Bu bir onay iş akışı DEĞİL, sadece
// loglama/işaretleme + bilgilendirici bir uyarı — POST endpoint'i hâlâ
// herkese (teknisyen dahil) açık kalır, hiçbir istek bu yüzden REDDEDİLMEZ.
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const request = require('supertest');
const app = require('../../server');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');
const { getTestToken } = require('../helpers/authHelper');
const { seedTestMaterial } = require('../helpers/materialFixtures');

function getUsageRow(id) {
  return db.prepare('SELECT * FROM work_order_materials WHERE id = ?').get(id);
}

// seedMinimalTestData() her zaman atanmış iş emirleri üretir — hiç
// atanmamış (assigned_user_id=NULL) bir iş emri senaryosu için burada
// AYRICA, doğrudan DB'ye bir tane eklenir.
function insertUnassignedWorkOrder(equipmentId) {
  const now = new Date().toISOString();
  const info = db
    .prepare(
      `INSERT INTO work_orders
         (title, description, status, priority, il, ilce, mahalle, location_name, lat, lng, assigned_user_id, equipment_id, created_at, updated_at)
       VALUES ('Atanmamış İş Emri', 'test', 'acik', 'normal', 'Erzurum', 'Yakutiye', 'Merkez Mah.', 'Erzurum / Yakutiye / Merkez Mah.', 39.9086, 41.2769, NULL, ?, ?, ?)`
    )
    .run(equipmentId, now, now);
  return info.lastInsertRowid;
}

describe('Malzeme kullanımında "atanmamış iş emri" işaretlemesi', () => {
  let seeded;
  let materialId;
  let technicianToken;
  let dispatcherToken;
  let managerToken;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
    materialId = seedTestMaterial({ stock_quantity: 100 });
    technicianToken = getTestToken('teknisyen');
    dispatcherToken = getTestToken('dispecer');
    managerToken = getTestToken('yonetici');
  });

  describe('[MADDE 1] teknisyen KENDİ işine malzeme ekliyor', () => {
    it('is_off_assignment=0, response\'ta warning YOK', async () => {
      const response = await request(app)
        .post(`/api/workorders/${seeded.workOrders.ownWorkOrderId}/materials`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ material_id: materialId, quantity_used: 5 });

      assert.strictEqual(response.status, 201, JSON.stringify(response.body));
      assert.strictEqual(response.body.is_off_assignment, false);
      assert.strictEqual(response.body.recorded_by_role, 'teknisyen');
      assert.strictEqual(response.body.warning, undefined);

      const dbRow = getUsageRow(response.body.id);
      assert.strictEqual(dbRow.is_off_assignment, 0);
      assert.strictEqual(dbRow.recorded_by_role, 'teknisyen');
    });
  });

  describe('[MADDE 2] teknisyen BAŞKASINA atanmış bir işe malzeme ekliyor', () => {
    it('is_off_assignment=1 olarak kaydedilir, response\'ta warning VAR', async () => {
      // ownWorkOrderId, teknisyene DEĞİL, otherTeknisyen'e atanmış olan
      // otherWorkOrderId'ye teknisyen olarak ekleme yapıyoruz.
      const response = await request(app)
        .post(`/api/workorders/${seeded.workOrders.otherWorkOrderId}/materials`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ material_id: materialId, quantity_used: 3 });

      assert.strictEqual(response.status, 201, JSON.stringify(response.body));
      assert.strictEqual(response.body.is_off_assignment, true);
      assert.strictEqual(response.body.recorded_by_role, 'teknisyen');
      assert.strictEqual(
        response.body.warning,
        'Bu iş emri size atanmamış, kayıt yine de işlendi ve loglandı.'
      );

      // KRİTİK: kayıt yine de İŞLENDİ — bloklayıcı bir hata DEĞİL.
      const dbRow = getUsageRow(response.body.id);
      assert.strictEqual(dbRow.is_off_assignment, 1);
      assert.strictEqual(dbRow.work_order_id, seeded.workOrders.otherWorkOrderId);
    });
  });

  describe('[MADDE 3] teknisyen HİÇ ATANMAMIŞ bir işe malzeme ekliyor', () => {
    it('is_off_assignment=1 olarak işaretlenir', async () => {
      const unassignedWorkOrderId = insertUnassignedWorkOrder(seeded.equipmentId);

      const response = await request(app)
        .post(`/api/workorders/${unassignedWorkOrderId}/materials`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ material_id: materialId, quantity_used: 2 });

      assert.strictEqual(response.status, 201, JSON.stringify(response.body));
      assert.strictEqual(response.body.is_off_assignment, true);
      assert.ok(response.body.warning);
    });
  });

  describe('[MADDE 4] dispeçer/yönetici için is_off_assignment HER ZAMAN 0', () => {
    it('dispeçer, kendisine atanmamış bir işe ekliyor: is_off_assignment=0, warning YOK', async () => {
      const response = await request(app)
        .post(`/api/workorders/${seeded.workOrders.ownWorkOrderId}/materials`) // teknisyene atanmış, dispeçere değil
        .set('Authorization', `Bearer ${dispatcherToken}`)
        .send({ material_id: materialId, quantity_used: 1 });

      assert.strictEqual(response.status, 201, JSON.stringify(response.body));
      assert.strictEqual(response.body.is_off_assignment, false, 'dispeçer için atanmamışlık anomali sayılmaz');
      assert.strictEqual(response.body.recorded_by_role, 'dispecer');
      assert.strictEqual(response.body.warning, undefined);
    });

    it('yönetici, hiç atanmamış bir işe ekliyor: is_off_assignment=0, warning YOK', async () => {
      const unassignedWorkOrderId = insertUnassignedWorkOrder(seeded.equipmentId);

      const response = await request(app)
        .post(`/api/workorders/${unassignedWorkOrderId}/materials`)
        .set('Authorization', `Bearer ${managerToken}`)
        .send({ material_id: materialId, quantity_used: 1 });

      assert.strictEqual(response.status, 201, JSON.stringify(response.body));
      assert.strictEqual(response.body.is_off_assignment, false);
      assert.strictEqual(response.body.recorded_by_role, 'yonetici');
      assert.strictEqual(response.body.warning, undefined);
    });
  });

  describe('recorded_by_role — o anki role göre doğru doluyor', () => {
    it('üç farklı rol (teknisyen/dispeçer/yönetici) kendi rollerini doğru kaydeder', async () => {
      const tokensAndRoles = [
        { token: technicianToken, role: 'teknisyen' },
        { token: dispatcherToken, role: 'dispecer' },
        { token: managerToken, role: 'yonetici' },
      ];

      for (const { token, role } of tokensAndRoles) {
        const response = await request(app)
          .post(`/api/workorders/${seeded.workOrders.ownWorkOrderId}/materials`)
          .set('Authorization', `Bearer ${token}`)
          .send({ material_id: materialId, quantity_used: 1 });

        assert.strictEqual(response.status, 201, `${role} için: ${JSON.stringify(response.body)}`);
        assert.strictEqual(response.body.recorded_by_role, role);
        assert.strictEqual(getUsageRow(response.body.id).recorded_by_role, role);
      }
    });
  });

  describe('[MADDE 5] GET /workorders/:workOrderId/materials — geçmişte doğru görünüyor', () => {
    it('is_off_assignment ve recorded_by_role her kayıtla birlikte döner', async () => {
      // 1) normal (kendi işi) kayıt
      await request(app)
        .post(`/api/workorders/${seeded.workOrders.ownWorkOrderId}/materials`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ material_id: materialId, quantity_used: 1 });

      // 2) atanmamış (başkasının işi) kayıt
      await request(app)
        .post(`/api/workorders/${seeded.workOrders.otherWorkOrderId}/materials`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ material_id: materialId, quantity_used: 1 });

      const ownHistory = await request(app)
        .get(`/api/workorders/${seeded.workOrders.ownWorkOrderId}/materials`)
        .set('Authorization', `Bearer ${technicianToken}`);
      assert.strictEqual(ownHistory.body.length, 1);
      assert.strictEqual(ownHistory.body[0].is_off_assignment, false);
      assert.strictEqual(ownHistory.body[0].recorded_by_role, 'teknisyen');

      const otherHistory = await request(app)
        .get(`/api/workorders/${seeded.workOrders.otherWorkOrderId}/materials`)
        .set('Authorization', `Bearer ${technicianToken}`);
      assert.strictEqual(otherHistory.body.length, 1);
      assert.strictEqual(otherHistory.body[0].is_off_assignment, true);
      assert.strictEqual(otherHistory.body[0].recorded_by_role, 'teknisyen');
    });

    it('bu değişiklikten ÖNCE oluşturulmuş (recorded_by_role/is_off_assignment NULL) bir kayıt kırılmadan, is_off_assignment=false olarak görünür', async () => {
      // Eski (migrasyon öncesi) bir kaydı simüle eder — doğrudan, yeni
      // sütunlar hiç verilmeden INSERT edilir.
      const now = new Date().toISOString();
      db.prepare(
        `INSERT INTO work_order_materials (work_order_id, material_id, quantity_used, recorded_by_user_id, created_at)
         VALUES (?, ?, ?, ?, ?)`
      ).run(seeded.workOrders.ownWorkOrderId, materialId, 4, seeded.users.teknisyenId, now);

      const response = await request(app)
        .get(`/api/workorders/${seeded.workOrders.ownWorkOrderId}/materials`)
        .set('Authorization', `Bearer ${technicianToken}`);

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.length, 1);
      assert.strictEqual(response.body[0].is_off_assignment, false, 'NULL -> Boolean(null) -> false olmalı, ASLA çökmemeli');
      assert.strictEqual(response.body[0].recorded_by_role, null);
    });
  });

  describe('GET /api/materials/off-assignment-usage — yönetici özeti', () => {
    it('teknisyen erişemez (403)', async () => {
      const response = await request(app)
        .get('/api/materials/off-assignment-usage')
        .set('Authorization', `Bearer ${technicianToken}`);
      assert.strictEqual(response.status, 403);
    });

    it('yalnızca is_off_assignment=1 kayıtları listeler, normal kayıtları DEĞİL', async () => {
      // normal kayıt (listede OLMAMALI)
      await request(app)
        .post(`/api/workorders/${seeded.workOrders.ownWorkOrderId}/materials`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ material_id: materialId, quantity_used: 1 });

      // atanmamış kayıt (listede OLMALI)
      const offAssignmentResponse = await request(app)
        .post(`/api/workorders/${seeded.workOrders.otherWorkOrderId}/materials`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ material_id: materialId, quantity_used: 2 });

      // dispeçer/yönetici kaydı (is_off_assignment her zaman 0 — listede OLMAMALI)
      await request(app)
        .post(`/api/workorders/${seeded.workOrders.ownWorkOrderId}/materials`)
        .set('Authorization', `Bearer ${dispatcherToken}`)
        .send({ material_id: materialId, quantity_used: 1 });

      const summary = await request(app)
        .get('/api/materials/off-assignment-usage')
        .set('Authorization', `Bearer ${managerToken}`);

      assert.strictEqual(summary.status, 200);
      assert.strictEqual(summary.body.length, 1, 'yalnızca 1 off-assignment kaydı olmalı');
      assert.strictEqual(summary.body[0].id, offAssignmentResponse.body.id);
      assert.strictEqual(summary.body[0].recorded_by.role, 'teknisyen');
      assert.strictEqual(summary.body[0].recorded_by.id, seeded.users.teknisyenId);
      assert.strictEqual(summary.body[0].work_order_id, seeded.workOrders.otherWorkOrderId);
      assert.strictEqual(
        summary.body[0].assigned_user.id,
        seeded.users.otherTeknisyenId,
        'atanan kişi (teknisyen DEĞİL, otherWorkOrderId\'nin gerçek sahibi) doğru görünmeli'
      );
    });

    it('30 günden eski bir off-assignment kaydı listede GÖRÜNMEZ', async () => {
      const oldDate = new Date(Date.now() - 40 * 24 * 60 * 60 * 1000).toISOString();
      db.prepare(
        `INSERT INTO work_order_materials
           (work_order_id, material_id, quantity_used, recorded_by_user_id, recorded_by_role, is_off_assignment, created_at)
         VALUES (?, ?, 1, ?, 'teknisyen', 1, ?)`
      ).run(seeded.workOrders.otherWorkOrderId, materialId, seeded.users.teknisyenId, oldDate);

      const summary = await request(app)
        .get('/api/materials/off-assignment-usage')
        .set('Authorization', `Bearer ${managerToken}`);

      assert.strictEqual(summary.status, 200);
      assert.strictEqual(summary.body.length, 0, '30 günden eski kayıt listede olmamalı');
    });
  });
});
