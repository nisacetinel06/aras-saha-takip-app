// QR Kod Üretimi modülü — routes/equipment.js'e eklenen `qr_printed` filtresi
// (GET /api/equipment) ve PATCH /api/equipment/mark-qr-printed için testler.
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const request = require('supertest');
const app = require('../../server');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');
const { getTestToken } = require('../helpers/authHelper');

// seedMinimalTestData yalnızca TEK (basılmamış) ekipman oluşturur — filtrenin
// GERÇEKTEN ayırt ettiğini (yalnızca "boş liste her zaman geçer" gibi bir
// yanlış-pozitifi değil) kanıtlamak için, testDb.js'teki insertEquipment ile
// AYNI sütun şeklinde ikinci bir ekipman ekliyoruz.
function insertSecondEquipment(qrCode) {
  const now = new Date().toISOString();
  return db
    .prepare(
      `INSERT INTO equipment
        (qr_code, equipment_type, il, ilce, mahalle, location_name, lat, lng, install_date, last_maintenance_date, manufacturer, capacity_info, status, created_at)
       VALUES
        (@qr_code, @equipment_type, @il, @ilce, @mahalle, @location_name, @lat, @lng, @install_date, @last_maintenance_date, @manufacturer, @capacity_info, @status, @created_at)`
    )
    .run({
      qr_code: qrCode,
      equipment_type: 'direk',
      il: 'Erzurum',
      ilce: 'Yakutiye',
      mahalle: 'Merkez Mah.',
      location_name: 'Erzurum / Yakutiye / Merkez Mah.',
      lat: 39.91,
      lng: 41.28,
      install_date: '2021-01-01',
      last_maintenance_date: '2023-01-01',
      manufacturer: 'ABB',
      capacity_info: null,
      status: 'aktif',
      created_at: now,
    }).lastInsertRowid;
}

function getEquipment(id) {
  return db.prepare('SELECT * FROM equipment WHERE id = ?').get(id);
}

describe('QR Kod Üretimi — GET /api/equipment?qr_printed & PATCH /api/equipment/mark-qr-printed', () => {
  let seeded;
  let managerToken;
  let technicianToken;
  let dispatcherToken;
  let equipmentId; // seedMinimalTestData'dan — hep basılmamış başlar
  let secondEquipmentId;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
    managerToken = getTestToken('yonetici');
    technicianToken = getTestToken('teknisyen');
    dispatcherToken = getTestToken('dispecer');
    equipmentId = seeded.equipmentId;
    secondEquipmentId = insertSecondEquipment('TEST-0002');
  });

  describe('GET /api/equipment?qr_printed=false|true', () => {
    it('qr_printed=false: hiçbiri basılmamışken İKİ ekipmanı da döner', async () => {
      const response = await request(app)
        .get('/api/equipment?qr_printed=false')
        .set('Authorization', `Bearer ${managerToken}`);
      assert.strictEqual(response.status, 200);
      const ids = response.body.map((e) => e.id);
      assert.ok(ids.includes(equipmentId));
      assert.ok(ids.includes(secondEquipmentId));
    });

    it('bir ekipman basıldı olarak işaretlendikten sonra qr_printed=false listesinden DÜŞER', async () => {
      await request(app)
        .patch('/api/equipment/mark-qr-printed')
        .set('Authorization', `Bearer ${managerToken}`)
        .send({ equipment_ids: [equipmentId] });

      const response = await request(app)
        .get('/api/equipment?qr_printed=false')
        .set('Authorization', `Bearer ${managerToken}`);
      assert.strictEqual(response.status, 200);
      const ids = response.body.map((e) => e.id);
      assert.ok(!ids.includes(equipmentId), 'basılmış ekipman qr_printed=false listesinde OLMAMALI');
      assert.ok(ids.includes(secondEquipmentId), 'basılmamış ekipman listede kalmalı');
    });

    it('qr_printed=true: yalnızca basılmış ekipmanı döner', async () => {
      await request(app)
        .patch('/api/equipment/mark-qr-printed')
        .set('Authorization', `Bearer ${managerToken}`)
        .send({ equipment_ids: [equipmentId] });

      const response = await request(app)
        .get('/api/equipment?qr_printed=true')
        .set('Authorization', `Bearer ${managerToken}`);
      assert.strictEqual(response.status, 200);
      const ids = response.body.map((e) => e.id);
      assert.deepStrictEqual(ids, [equipmentId]);
    });

    it('type/il gibi diğer filtrelerle BİRLİKTE (AND) çalışır', async () => {
      const response = await request(app)
        .get('/api/equipment?qr_printed=false&type=direk')
        .set('Authorization', `Bearer ${managerToken}`);
      assert.strictEqual(response.status, 200);
      const ids = response.body.map((e) => e.id);
      assert.deepStrictEqual(ids, [secondEquipmentId]);
    });

    it('teknisyen qr_printed filtresiyle çağıramaz (403) — diğer filtreler etkilenmez', async () => {
      const response = await request(app)
        .get('/api/equipment?qr_printed=false')
        .set('Authorization', `Bearer ${technicianToken}`);
      assert.strictEqual(response.status, 403);
    });

    it('dispeçer qr_printed filtresiyle çağıramaz (403)', async () => {
      const response = await request(app)
        .get('/api/equipment?qr_printed=true')
        .set('Authorization', `Bearer ${dispatcherToken}`);
      assert.strictEqual(response.status, 403);
    });

    it('qr_printed filtresi OLMADAN normal ekipman listelemesi TÜM rollere açık kalır (regresyon)', async () => {
      const response = await request(app)
        .get('/api/equipment')
        .set('Authorization', `Bearer ${technicianToken}`);
      assert.strictEqual(response.status, 200);
    });
  });

  describe('PATCH /api/equipment/mark-qr-printed', () => {
    it('yönetici, seçilen ekipmanların qr_printed_at alanını ŞU ANKİ zamana günceller', async () => {
      const before = new Date().toISOString();
      const response = await request(app)
        .patch('/api/equipment/mark-qr-printed')
        .set('Authorization', `Bearer ${managerToken}`)
        .send({ equipment_ids: [equipmentId, secondEquipmentId] });

      assert.strictEqual(response.status, 200, JSON.stringify(response.body));
      assert.strictEqual(response.body.length, 2);
      for (const id of [equipmentId, secondEquipmentId]) {
        const row = getEquipment(id);
        assert.ok(row.qr_printed_at, `${id} için qr_printed_at NULL kalmamalı`);
        assert.ok(row.qr_printed_at >= before, 'qr_printed_at şimdiki zamana yakın olmalı');
      }
    });

    it('yalnızca gönderilen id\'ler güncellenir, diğer ekipmanlar ETKİLENMEZ', async () => {
      await request(app)
        .patch('/api/equipment/mark-qr-printed')
        .set('Authorization', `Bearer ${managerToken}`)
        .send({ equipment_ids: [equipmentId] });

      assert.ok(getEquipment(equipmentId).qr_printed_at);
      assert.strictEqual(getEquipment(secondEquipmentId).qr_printed_at, null);
    });

    it('teknisyen çağıramaz (403)', async () => {
      const response = await request(app)
        .patch('/api/equipment/mark-qr-printed')
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ equipment_ids: [equipmentId] });
      assert.strictEqual(response.status, 403);
      assert.strictEqual(getEquipment(equipmentId).qr_printed_at, null, '403 sonrası DB DEĞİŞMEMİŞ olmalı');
    });

    it('dispeçer çağıramaz (403)', async () => {
      const response = await request(app)
        .patch('/api/equipment/mark-qr-printed')
        .set('Authorization', `Bearer ${dispatcherToken}`)
        .send({ equipment_ids: [equipmentId] });
      assert.strictEqual(response.status, 403);
    });

    it('equipment_ids eksikse 400 döner', async () => {
      const response = await request(app)
        .patch('/api/equipment/mark-qr-printed')
        .set('Authorization', `Bearer ${managerToken}`)
        .send({});
      assert.strictEqual(response.status, 400);
    });

    it('equipment_ids boş dizi ise 400 döner', async () => {
      const response = await request(app)
        .patch('/api/equipment/mark-qr-printed')
        .set('Authorization', `Bearer ${managerToken}`)
        .send({ equipment_ids: [] });
      assert.strictEqual(response.status, 400);
    });

    it('equipment_ids dizi değilse (string) 400 döner, ASLA 500', async () => {
      const response = await request(app)
        .patch('/api/equipment/mark-qr-printed')
        .set('Authorization', `Bearer ${managerToken}`)
        .send({ equipment_ids: 'not-an-array' });
      assert.strictEqual(response.status, 400);
    });

    it('equipment_ids tam sayı olmayan bir değer içeriyorsa 400 döner', async () => {
      const response = await request(app)
        .patch('/api/equipment/mark-qr-printed')
        .set('Authorization', `Bearer ${managerToken}`)
        .send({ equipment_ids: [equipmentId, 'abc'] });
      assert.strictEqual(response.status, 400);
      assert.strictEqual(getEquipment(equipmentId).qr_printed_at, null, 'kısmi geçersiz istekte HİÇBİR şey güncellenmemeli');
    });

    it('equipment_ids var olmayan bir id içeriyorsa 404 döner ve HİÇBİRİ güncellenmez', async () => {
      const response = await request(app)
        .patch('/api/equipment/mark-qr-printed')
        .set('Authorization', `Bearer ${managerToken}`)
        .send({ equipment_ids: [equipmentId, 999999] });
      assert.strictEqual(response.status, 404);
      assert.strictEqual(getEquipment(equipmentId).qr_printed_at, null, 'var olan id de dahil olmak üzere HİÇBİRİ güncellenmemeli (atomiklik)');
    });
  });
});
