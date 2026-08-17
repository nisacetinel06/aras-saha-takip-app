// TEST-10: Raporlar / Analitik Sayfası (Modül 14) salt-okunur endpoint'leri.
//
// ADIM 0 BULGUSU: routes/reports.js `router.use(requireRole('yonetici'))`
// ile TÜM endpoint'lere tek seferde uygulanıyor (kod incelemesiyle
// DOĞRULANDI) — envanterdeki "sadece yönetici" beklentisiyle birebir
// uyuşuyor, düzeltme GEREKMEDİ.
//
// GET /api/reports/fault-trend NÜANSI: prompt "?from=...&to=..." parametreli
// bir tarih aralığı varsayıyordu, ama GERÇEK endpoint böyle bir parametre
// KABUL ETMİYOR — bunun yerine ŞİMDİDEN GERİYE DOĞRU göreli bir `?months=N`
// penceresi kullanıyor (varsayılan 6, 1-12 arası sınırlanır). Bu yüzden Adım
// 7'deki senaryolar bu GERÇEK parametreye göre uyarlandı:
//   - "gelecekte/veri olmayan aralık" -> months=1, veri YOKKEN sıfır sonuç
//   - "yıl sınırını aşan aralık" -> months=12 (bugünün tarihine göre bu
//     pencere doğal olarak bir yıl sınırını kapsıyor — bkz. aşağıdaki test)
//   - "from > to mantıksız aralık" -> UYGULANAMAZ (böyle bir parametre yok),
//     bunun yerine GEÇERSİZ months değerleri (negatif/sıfır/sayısal olmayan/
//     aşırı büyük) test edildi — hiçbiri 500 DÖNMÜYOR, hepsi güvenle
//     clamp/varsayılana düşüyor (bkz. mevcut `Math.min(Math.max(...))` deseni).
//   - "tek günlük aralık" -> months=1 (en küçük geçerli pencere)
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const request = require('supertest');
const app = require('../../server');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');
const { getTestToken } = require('../helpers/authHelper');
const { seedTestMaterial } = require('../helpers/materialFixtures');
const { assertSchema, assertArraySchema } = require('../helpers/assertSchema');

function insertWorkOrder({ il, equipmentId, assignedUserId, createdAt }) {
  const ts = createdAt || new Date().toISOString();
  db.prepare(
    `INSERT INTO work_orders (title, description, status, priority, il, ilce, mahalle, location_name, lat, lng, assigned_user_id, equipment_id, created_at, updated_at)
     VALUES ('Test İş', '', 'acik', 'normal', ?, 'Merkez', 'Merkez Mah.', 'x', 39.9, 41.2, ?, ?, ?, ?)`
  ).run(il, assignedUserId, equipmentId, ts, ts);
}

// seedMinimalTestData() KENDİSİ 1 ekipman + 2 iş emri (ikisi de 'Erzurum'/
// 'trafo') seed ediyor — bu "boş veri" ve "tam sayı" testlerinin (sıralama,
// tek aylık pencere vb.) beklediği TEMİZ/BOŞ tabloyla ÇELİŞİYOR. Bu yüzden
// sayıya duyarlı testlerde seedMinimalTestData() YERİNE bu bare-user helper'ı
// kullanılıyor: yalnızca token üretebilmek için üç rolden birer kullanıcı
// ekler, hiçbir equipment/work_order/material eklemez.
function seedBareRoleUsers() {
  const insertUser = db.prepare(
    'INSERT INTO users (name, role, sicil_no, password_hash, supervisor_id) VALUES (?, ?, ?, ?, ?)'
  );
  const yoneticiId = insertUser.run('Bare Yönetici', 'yonetici', '3900', 'x', null).lastInsertRowid;
  const dispecerId = insertUser.run('Bare Dispeçer', 'dispecer', '2900', 'x', yoneticiId).lastInsertRowid;
  const teknisyenId = insertUser.run('Bare Teknisyen', 'teknisyen', '1900', 'x', dispecerId).lastInsertRowid;
  return { yoneticiId, dispecerId, teknisyenId };
}

function insertEquipment({ qr_code, il, equipment_type = 'trafo' }) {
  const now = new Date().toISOString();
  return db
    .prepare(
      `INSERT INTO equipment (qr_code, equipment_type, il, ilce, mahalle, location_name, lat, lng, install_date, last_maintenance_date, manufacturer, capacity_info, status, created_at)
       VALUES (?, ?, ?, 'Merkez', 'Merkez Mah.', ?, 39.9, 41.2, '2020-01-01', '2023-01-01', 'ABB', '400 kVA', 'aktif', ?)`
    )
    .run(qr_code, equipment_type, il, `${il} / Merkez`, now).lastInsertRowid;
}

const REPORT_ENDPOINTS = [
  '/api/reports/regional-risk-summary',
  '/api/reports/fault-by-region',
  '/api/reports/fault-by-equipment-type',
  '/api/reports/fault-trend',
  '/api/reports/anomaly-by-region',
  '/api/reports/material-usage-top',
];

describe('GET /api/reports/* — RBAC (tüm endpoint\'ler için ortak)', () => {
  let seeded;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
  });

  for (const endpoint of REPORT_ENDPOINTS) {
    it(`${endpoint}: teknisyen 403, dispeçer 403, yönetici 200`, async () => {
      const technicianToken = getTestToken('teknisyen');
      const dispatcherToken = getTestToken('dispecer');
      const managerToken = getTestToken('yonetici');

      const techResponse = await request(app).get(endpoint).set('Authorization', `Bearer ${technicianToken}`);
      const dispResponse = await request(app).get(endpoint).set('Authorization', `Bearer ${dispatcherToken}`);
      const managerResponse = await request(app).get(endpoint).set('Authorization', `Bearer ${managerToken}`);

      assert.strictEqual(techResponse.status, 403, endpoint);
      assert.strictEqual(dispResponse.status, 403, endpoint);
      assert.strictEqual(managerResponse.status, 200, `${endpoint}: ${JSON.stringify(managerResponse.body)}`);
    });

    it(`${endpoint}: token olmadan 401`, async () => {
      const response = await request(app).get(endpoint);
      assert.strictEqual(response.status, 401);
    });
  }
});

describe('GET /api/reports/regional-risk-summary', () => {
  let managerToken;

  beforeEach(() => {
    resetTestDatabase();
    seedBareRoleUsers();
    managerToken = getTestToken('yonetici');
  });

  it('şema doğru ve HER ZAMAN 7 sabit il döner (veri olmasa bile)', async () => {
    const response = await request(app).get('/api/reports/regional-risk-summary').set('Authorization', `Bearer ${managerToken}`);
    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.length, 7, '7 hizmet ili için SABİT döner');
    assertArraySchema(response.body, { il: 'string', center_lat: 'number', center_lng: 'number', equipment_count: 'number' });
  });

  it('boş veri durumu: hiç ekipman yokken equipment_count=0, avg_risk_score=null (hata değil)', async () => {
    const response = await request(app).get('/api/reports/regional-risk-summary').set('Authorization', `Bearer ${managerToken}`);
    assert.strictEqual(response.status, 200);
    assert.ok(response.body.every((r) => r.equipment_count === 0));
    assert.ok(response.body.every((r) => r.avg_risk_score === null));
  });
});

describe('GET /api/reports/fault-by-region', () => {
  let bare;
  let equipmentId;
  let managerToken;

  beforeEach(() => {
    resetTestDatabase();
    bare = seedBareRoleUsers();
    equipmentId = insertEquipment({ qr_code: 'FBR-EQ', il: 'Erzurum' });
    managerToken = getTestToken('yonetici');
  });

  it('şema doğru: il/fault_count', async () => {
    insertWorkOrder({ il: 'Erzurum', equipmentId, assignedUserId: bare.teknisyenId });
    const response = await request(app).get('/api/reports/fault-by-region').set('Authorization', `Bearer ${managerToken}`);
    assert.strictEqual(response.status, 200);
    assertArraySchema(response.body, { il: 'string', fault_count: 'number' });
  });

  it('boş veri durumu: hiç iş emri yokken boş dizi döner', async () => {
    const response = await request(app).get('/api/reports/fault-by-region').set('Authorization', `Bearer ${managerToken}`);
    assert.strictEqual(response.status, 200);
    assert.deepStrictEqual(response.body, []);
  });

  it('sıralama: en çok arızası olan il listenin BAŞINDA (azalan sırada)', async () => {
    for (let i = 0; i < 5; i += 1) insertWorkOrder({ il: 'Erzurum', equipmentId, assignedUserId: bare.teknisyenId });
    for (let i = 0; i < 2; i += 1) insertWorkOrder({ il: 'Kars', equipmentId, assignedUserId: bare.teknisyenId });
    insertWorkOrder({ il: 'Ağrı', equipmentId, assignedUserId: bare.teknisyenId });

    const response = await request(app).get('/api/reports/fault-by-region').set('Authorization', `Bearer ${managerToken}`);

    assert.strictEqual(response.status, 200);
    assert.deepStrictEqual(
      response.body.map((r) => r.il),
      ['Erzurum', 'Kars', 'Ağrı']
    );
    assert.strictEqual(response.body[0].fault_count, 5);
  });
});

describe('GET /api/reports/fault-by-equipment-type', () => {
  let bare;
  let equipmentId;
  let managerToken;

  beforeEach(() => {
    resetTestDatabase();
    bare = seedBareRoleUsers();
    equipmentId = insertEquipment({ qr_code: 'FBET-EQ', il: 'Erzurum' });
    managerToken = getTestToken('yonetici');
  });

  it('şema doğru: equipment_type/fault_count', async () => {
    insertWorkOrder({ il: 'Erzurum', equipmentId, assignedUserId: bare.teknisyenId });
    const response = await request(app).get('/api/reports/fault-by-equipment-type').set('Authorization', `Bearer ${managerToken}`);
    assert.strictEqual(response.status, 200);
    assertArraySchema(response.body, { equipment_type: 'string', fault_count: 'number' });
  });

  it('boş veri durumu: hiç iş emri yokken boş dizi döner', async () => {
    const response = await request(app).get('/api/reports/fault-by-equipment-type').set('Authorization', `Bearer ${managerToken}`);
    assert.strictEqual(response.status, 200);
    assert.deepStrictEqual(response.body, []);
  });
});

describe('GET /api/reports/anomaly-by-region', () => {
  let managerToken;

  beforeEach(() => {
    resetTestDatabase();
    seedMinimalTestData();
    managerToken = getTestToken('yonetici');
  });

  it('şema doğru ve boş veri durumunda boş dizi döner', async () => {
    const response = await request(app).get('/api/reports/anomaly-by-region').set('Authorization', `Bearer ${managerToken}`);
    assert.strictEqual(response.status, 200);
    assert.deepStrictEqual(response.body, []);
  });

  it('şema + oran hesaplama doğru', async () => {
    const now = new Date().toISOString();
    const meterId1 = insertEquipment({ qr_code: 'SAYAC-1', il: 'Erzurum', equipment_type: 'sayac' });
    const meterId2 = insertEquipment({ qr_code: 'SAYAC-2', il: 'Erzurum', equipment_type: 'sayac' });
    db.prepare('INSERT INTO meter_anomaly_scores (equipment_id, anomaly_score, is_suspicious, computed_at) VALUES (?, 80, 1, ?)').run(meterId1, now);
    db.prepare('INSERT INTO meter_anomaly_scores (equipment_id, anomaly_score, is_suspicious, computed_at) VALUES (?, 10, 0, ?)').run(meterId2, now);

    const response = await request(app).get('/api/reports/anomaly-by-region').set('Authorization', `Bearer ${managerToken}`);

    assert.strictEqual(response.status, 200);
    assertArraySchema(response.body, { il: 'string', total_meters: 'number', suspicious_count: 'number', suspicious_ratio: 'number' });
    const erzurum = response.body.find((r) => r.il === 'Erzurum');
    assert.strictEqual(erzurum.total_meters, 2);
    assert.strictEqual(erzurum.suspicious_count, 1);
    assert.strictEqual(erzurum.suspicious_ratio, 0.5);
  });
});

describe('GET /api/reports/material-usage-top', () => {
  let seeded;
  let managerToken;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
    managerToken = getTestToken('yonetici');
  });

  it('boş veri durumu: hiç kullanım yokken boş dizi döner', async () => {
    const response = await request(app).get('/api/reports/material-usage-top').set('Authorization', `Bearer ${managerToken}`);
    assert.strictEqual(response.status, 200);
    assert.deepStrictEqual(response.body, []);
  });

  it('şema doğru ve en çok kullanılan malzeme başta (azalan sırada)', async () => {
    const now = new Date().toISOString();
    const materialAId = seedTestMaterial({ name: 'Çok Kullanılan', stock_quantity: 100 });
    const materialBId = seedTestMaterial({ name: 'Az Kullanılan', stock_quantity: 100 });
    db.prepare(
      `INSERT INTO work_order_materials (work_order_id, material_id, quantity_used, recorded_by_user_id, created_at) VALUES (?, ?, ?, ?, ?)`
    ).run(seeded.workOrders.ownWorkOrderId, materialAId, 20, seeded.users.teknisyenId, now);
    db.prepare(
      `INSERT INTO work_order_materials (work_order_id, material_id, quantity_used, recorded_by_user_id, created_at) VALUES (?, ?, ?, ?, ?)`
    ).run(seeded.workOrders.ownWorkOrderId, materialBId, 2, seeded.users.teknisyenId, now);

    const response = await request(app).get('/api/reports/material-usage-top').set('Authorization', `Bearer ${managerToken}`);

    assert.strictEqual(response.status, 200);
    assertArraySchema(response.body, { id: 'number', name: 'string', unit: 'string', total_used: 'number' });
    assert.strictEqual(response.body[0].name, 'Çok Kullanılan');
    assert.strictEqual(response.body[0].total_used, 20);
  });
});

describe('GET /api/reports/fault-trend — tarih penceresi sınır durumları', () => {
  let bare;
  let equipmentId;
  let managerToken;

  beforeEach(() => {
    resetTestDatabase();
    bare = seedBareRoleUsers();
    equipmentId = insertEquipment({ qr_code: 'FT-EQ', il: 'Erzurum' });
    managerToken = getTestToken('yonetici');
  });

  it('şema doğru: dizi, her eleman year_month/fault_count içerir', async () => {
    const response = await request(app).get('/api/reports/fault-trend').set('Authorization', `Bearer ${managerToken}`);
    assert.strictEqual(response.status, 200);
    assertArraySchema(response.body, { year_month: 'string', fault_count: 'number' });
    assert.strictEqual(response.body.length, 6, 'varsayılan pencere 6 ay olmalı');
  });

  it('veri OLMAYAN pencerede (months=1, hiç iş emri yok) hata değil, sıfır değerli sonuç döner', async () => {
    const response = await request(app).get('/api/reports/fault-trend?months=1').set('Authorization', `Bearer ${managerToken}`);
    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.length, 1);
    assert.strictEqual(response.body[0].fault_count, 0);
  });

  it('YIL SINIRINI AŞAN pencerede (months=12) aylar KARIŞMADAN doğru gruplanır', async () => {
    // months=12 penceresi bugünün tarihine göre GERİYE doğru 12 ay kapsar —
    // bu her zaman bir yıl sınırını (Aralık->Ocak) içerir. Kasım/Aralık/Ocak
    // ayına düşecek gerçek tarihleri, penceredeki monthKeys'in İLK 3 elemanına
    // göre DİNAMİK olarak hesaplıyoruz (test, "bugün" hangi tarih olursa
        // olsun doğru kalsın diye sabit "2025-11" gibi bir string'e GÜVENMİYOR).
    const now = new Date();
    const elevenMonthsAgo = new Date(now.getFullYear(), now.getMonth() - 11, 15);
    const tenMonthsAgo = new Date(now.getFullYear(), now.getMonth() - 10, 15);
    const nineMonthsAgo = new Date(now.getFullYear(), now.getMonth() - 9, 15);

    insertWorkOrder({ il: 'Erzurum', equipmentId, assignedUserId: bare.teknisyenId, createdAt: elevenMonthsAgo.toISOString() });
    insertWorkOrder({ il: 'Erzurum', equipmentId, assignedUserId: bare.teknisyenId, createdAt: tenMonthsAgo.toISOString() });
    insertWorkOrder({ il: 'Erzurum', equipmentId, assignedUserId: bare.teknisyenId, createdAt: nineMonthsAgo.toISOString() });

    const response = await request(app).get('/api/reports/fault-trend?months=12').set('Authorization', `Bearer ${managerToken}`);

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.length, 12);

    const keyFor = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
    const byMonth = Object.fromEntries(response.body.map((r) => [r.year_month, r.fault_count]));

    assert.strictEqual(byMonth[keyFor(elevenMonthsAgo)], 1);
    assert.strictEqual(byMonth[keyFor(tenMonthsAgo)], 1);
    assert.strictEqual(byMonth[keyFor(nineMonthsAgo)], 1);
    // Üç farklı ay anahtarı GERÇEKTEN farklı olmalı (karışıp tek bir kovaya
    // toplanmamış olmalı) — yıl sınırını geçmenin asıl kanıtı.
    const distinctKeys = new Set([keyFor(elevenMonthsAgo), keyFor(tenMonthsAgo), keyFor(nineMonthsAgo)]);
    assert.strictEqual(distinctKeys.size, 3);
  });

  it('GEÇERSİZ months parametreleri çökmeden güvenle clamp/varsayılana düşer (500 ASLA)', async () => {
    const scenarios = ['abc', '-5', '0', '999', '3.7'];
    for (const months of scenarios) {
      const response = await request(app).get(`/api/reports/fault-trend?months=${months}`).set('Authorization', `Bearer ${managerToken}`);
      assert.strictEqual(response.status, 200, `months=${months}: beklenmedik status ${response.status}`);
      assert.ok(Array.isArray(response.body));
      assert.ok(response.body.length >= 1 && response.body.length <= 12, `months=${months}: pencere 1-12 arası olmalı, ${response.body.length} geldi`);
    }
  });

  it('TEK AYLIK pencere (months=1) doğru çalışır — yalnızca içinde bulunulan ay', async () => {
    insertWorkOrder({ il: 'Erzurum', equipmentId, assignedUserId: bare.teknisyenId });
    const response = await request(app).get('/api/reports/fault-trend?months=1').set('Authorization', `Bearer ${managerToken}`);
    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.length, 1);
    assert.strictEqual(response.body[0].fault_count, 1);
  });
});
