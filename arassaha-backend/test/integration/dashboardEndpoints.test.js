// TEST-10: Dashboard (Modül 2/9/13) salt-okunur endpoint'leri.
//
// ADIM 0 BULGUSU (kod incelemesi, routes/dashboard.js GET /summary):
// Kritik kontrol noktası ZATEN DOĞRU uygulanmış durumda — `visibilityClause()`
// fonksiyonu routes/workOrders.js'teki `applyVisibilityFilter` ile BİREBİR
// AYNI üç katmanlı kuralı (teknisyen: yalnızca kendi işleri, dispeçer: yalnızca
// kendi ekibi, yönetici: filtresiz) TÜM özet sorgularına (open_count,
// resolved_today_count, avg_resolution_hours, status_breakdown,
// priority_breakdown, recent_activity) uyguluyor. Yani bir teknisyen giriş
// yaptığında "açık arıza: 3" derken bu GERÇEKTEN onun kendi işleri — tüm
// şirketin sayısı DEĞİL. Bu dosyada bu davranış GERÇEK veriyle (teknisyene
// atanmamış ekstra iş emirleri seed edilerek) kanıtlanıyor; kod değişikliği
// GEREKMEDİ.
//
// AYRICA BULUNAN: GET /api/dashboard/risky-equipment (routes/risk.js)
// requireRole('yonetici') ile ZATEN yalnızca yöneticiye açıktı (envanterdeki
// "giriş yapmış herkes mi yoksa yönetici mi?" sorusunun cevabı: YÖNETİCİ).
// Ancak `il` filtre parametresini HİÇ desteklemiyordu (yalnızca `limit`) —
// bu görevin filtreleme testi gereksinimini karşılamak için routes/risk.js'e
// opsiyonel `il` filtresi eklendi (verilmezse eski davranış birebir korunur).
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const request = require('supertest');
const app = require('../../server');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');
const { getTestToken } = require('../helpers/authHelper');
const { assertSchema, assertArraySchema } = require('../helpers/assertSchema');

function insertEquipmentWithRisk({ qr_code, il, riskScore, riskLevel = 'orta' }) {
  const now = new Date().toISOString();
  const info = db
    .prepare(
      `INSERT INTO equipment
         (qr_code, equipment_type, il, ilce, mahalle, location_name, lat, lng, install_date, last_maintenance_date, manufacturer, capacity_info, status, created_at)
       VALUES (?, 'trafo', ?, 'Merkez', 'Merkez Mah.', ?, 39.9, 41.2, '2020-01-01', '2023-01-01', 'ABB', '400 kVA', 'aktif', ?)`
    )
    .run(qr_code, il, `${il} / Merkez / Merkez Mah.`, now);
  const equipmentId = info.lastInsertRowid;

  db.prepare(
    `INSERT INTO equipment_risk_scores (equipment_id, risk_score, risk_level, computed_at) VALUES (?, ?, ?, ?)`
  ).run(equipmentId, riskScore, riskLevel, now);

  return equipmentId;
}

describe('GET /api/dashboard/summary', () => {
  let seeded;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
  });

  it('token olmadan 401 döner', async () => {
    const response = await request(app).get('/api/dashboard/summary');
    assert.strictEqual(response.status, 401);
  });

  it('response schema doğru: open_count/resolved_today_count/avg_resolution_hours/status_breakdown/priority_breakdown/recent_activity', async () => {
    const token = getTestToken('yonetici');
    const response = await request(app).get('/api/dashboard/summary').set('Authorization', `Bearer ${token}`);

    assert.strictEqual(response.status, 200);
    assertSchema(response.body, {
      open_count: 'number',
      resolved_today_count: 'number',
      avg_resolution_hours: 'number',
      status_breakdown: 'object',
      priority_breakdown: 'object',
      recent_activity: 'array',
    });
  });

  it('RBAC × Dashboard: teknisyen SADECE kendi işlerinin sayısını görür, tüm şirketinkini DEĞİL', async () => {
    // seedMinimalTestData zaten teknisyene 1, diğer teknisyene 1 iş emri
    // veriyor (toplam 2, ikisi de 'acik'). Şirket genelinde daha FAZLA iş
    // emri olduğunu kanıtlamak için 3 tane daha (başka kullanıcılara atanmış)
    // ekliyoruz — eğer dashboard filtre UYGULAMASAYDI, teknisyenin
    // open_count'u da yanlışlıkla 5 olurdu.
    const now = new Date().toISOString();
    const insertWo = db.prepare(
      `INSERT INTO work_orders (title, description, status, priority, il, ilce, mahalle, location_name, lat, lng, assigned_user_id, equipment_id, created_at, updated_at)
       VALUES (?, '', 'acik', 'normal', 'Erzurum', 'Yakutiye', 'Merkez', 'x', 39.9, 41.2, ?, ?, ?, ?)`
    );
    insertWo.run('Şirket geneli iş 1', seeded.users.otherTeknisyenId, seeded.equipmentId, now, now);
    insertWo.run('Şirket geneli iş 2', seeded.users.otherTeknisyenId, seeded.equipmentId, now, now);
    insertWo.run('Şirket geneli iş 3', seeded.users.otherTeknisyenId, seeded.equipmentId, now, now);

    const technicianToken = getTestToken('teknisyen');
    const managerToken = getTestToken('yonetici');

    const techResponse = await request(app).get('/api/dashboard/summary').set('Authorization', `Bearer ${technicianToken}`);
    const managerResponse = await request(app).get('/api/dashboard/summary').set('Authorization', `Bearer ${managerToken}`);

    assert.strictEqual(techResponse.status, 200);
    assert.strictEqual(managerResponse.status, 200);

    // Teknisyenin kendi tek işi 'acik' durumda — open_count TAM OLARAK 1 olmalı.
    assert.strictEqual(techResponse.body.open_count, 1, 'teknisyen yalnızca KENDİ açık işini görmeli');
    // Yönetici TÜMÜNÜ görür: 2 (seedMinimalTestData) + 3 (yeni eklenen) = 5.
    assert.strictEqual(managerResponse.body.open_count, 5, 'yönetici ŞİRKET GENELİNİ görmeli');
    assert.notStrictEqual(
      techResponse.body.open_count,
      managerResponse.body.open_count,
      'teknisyen ve yönetici FARKLI kapsamlı sayılar görmeli — aynı olması RBAC boşluğuna işaret eder'
    );

    // recent_activity de aynı şekilde kapsanmalı: teknisyenin listesinde
    // kendisine atanmamış hiçbir iş emri BAŞLIĞI görünmemeli.
    const techTitles = techResponse.body.recent_activity.map((w) => w.title);
    assert.ok(!techTitles.includes('Şirket geneli iş 1'));
    assert.ok(!techTitles.includes('Şirket geneli iş 2'));
    assert.ok(!techTitles.includes('Şirket geneli iş 3'));
  });

  it('RBAC × Dashboard: dispeçer yalnızca KENDİ EKİBİNİN sayılarını görür', async () => {
    // seedMinimalTestData: dispecer -> teknisyen + otherTeknisyen (ikisi de
    // onun ekibinde), her birine 1'er 'acik' iş emri. Ekibi DIŞINDA bir
    // dispeçer/teknisyen daha ekleyip ona da iş emri veriyoruz — dispeçerin
    // sayısına sızmamalı.
    const now = new Date().toISOString();
    const outsideDispecerId = db
      .prepare('INSERT INTO users (name, role, sicil_no, password_hash, supervisor_id) VALUES (?, ?, ?, ?, ?)')
      .run('Başka Dispeçer', 'dispecer', '2099', 'x', null).lastInsertRowid;
    const outsideTeknisyenId = db
      .prepare('INSERT INTO users (name, role, sicil_no, password_hash, supervisor_id) VALUES (?, ?, ?, ?, ?)')
      .run('Başka Teknisyen', 'teknisyen', '1099', 'x', outsideDispecerId).lastInsertRowid;
    db.prepare(
      `INSERT INTO work_orders (title, description, status, priority, il, ilce, mahalle, location_name, lat, lng, assigned_user_id, equipment_id, created_at, updated_at)
       VALUES ('Başka ekip işi', '', 'acik', 'normal', 'Erzurum', 'Yakutiye', 'Merkez', 'x', 39.9, 41.2, ?, ?, ?, ?)`
    ).run(outsideTeknisyenId, seeded.equipmentId, now, now);

    const dispatcherToken = getTestToken('dispecer');
    const response = await request(app).get('/api/dashboard/summary').set('Authorization', `Bearer ${dispatcherToken}`);

    assert.strictEqual(response.status, 200);
    // Dispeçerin ekibi: teknisyen + otherTeknisyen, ikisinin de 1'er 'acik' işi var -> 2.
    assert.strictEqual(response.body.open_count, 2, 'dispeçer yalnızca KENDİ ekibinin işlerini görmeli, başka ekibinkini değil');
  });

  it('boş veri durumu: hiç iş emri yokken hata değil, sıfır değerli geçerli bir yapı döner', async () => {
    resetTestDatabase();
    // Yalnızca kullanıcı seed et (token üretebilmek için), iş emri EKLEME.
    const now = new Date().toISOString();
    db.prepare('INSERT INTO users (name, role, sicil_no, password_hash, supervisor_id) VALUES (?, ?, ?, ?, ?)').run(
      'Boş Test Yönetici', 'yonetici', '3999', 'x', null
    );
    const managerToken = getTestToken('yonetici');

    const response = await request(app).get('/api/dashboard/summary').set('Authorization', `Bearer ${managerToken}`);

    assert.strictEqual(response.status, 200);
    assertSchema(response.body, {
      open_count: 'number',
      resolved_today_count: 'number',
      avg_resolution_hours: 'number',
      status_breakdown: 'object',
      priority_breakdown: 'object',
      recent_activity: 'array',
    });
    assert.strictEqual(response.body.open_count, 0);
    assert.strictEqual(response.body.resolved_today_count, 0);
    assert.strictEqual(response.body.avg_resolution_hours, 0, 'AVG(NULL) durumunda NaN/null DEĞİL, 0 dönmeli');
    assert.deepStrictEqual(response.body.recent_activity, []);
  });
});

describe('GET /api/dashboard/risky-equipment', () => {
  let seeded;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
  });

  it('teknisyen ve dispeçer 403 alır (yalnızca yönetimsel rapor)', async () => {
    const technicianToken = getTestToken('teknisyen');
    const dispatcherToken = getTestToken('dispecer');

    const techResponse = await request(app).get('/api/dashboard/risky-equipment').set('Authorization', `Bearer ${technicianToken}`);
    const dispResponse = await request(app).get('/api/dashboard/risky-equipment').set('Authorization', `Bearer ${dispatcherToken}`);

    assert.strictEqual(techResponse.status, 403);
    assert.strictEqual(dispResponse.status, 403);
  });

  it('yönetici 200 alır, response bir dizi ve şeması doğru', async () => {
    insertEquipmentWithRisk({ qr_code: 'RISK-001', il: 'Erzurum', riskScore: 80, riskLevel: 'yuksek' });
    const managerToken = getTestToken('yonetici');

    const response = await request(app).get('/api/dashboard/risky-equipment').set('Authorization', `Bearer ${managerToken}`);

    assert.strictEqual(response.status, 200);
    assertArraySchema(response.body, {
      id: 'number',
      qr_code: 'string',
      equipment_type: 'string',
      il: 'string',
      status: 'string',
      risk_score: 'number',
      risk_level: 'string',
    });
  });

  it('boş veri durumu: hiç risk skoru yokken hata değil, boş dizi döner', async () => {
    const managerToken = getTestToken('yonetici');
    const response = await request(app).get('/api/dashboard/risky-equipment').set('Authorization', `Bearer ${managerToken}`);

    assert.strictEqual(response.status, 200);
    assert.deepStrictEqual(response.body, []);
  });

  it('sıralama: risk skoruna göre AZALAN sırada döner (ilk eleman en yüksek risk)', async () => {
    insertEquipmentWithRisk({ qr_code: 'RISK-LOW', il: 'Erzurum', riskScore: 20 });
    insertEquipmentWithRisk({ qr_code: 'RISK-HIGH', il: 'Erzurum', riskScore: 95 });
    insertEquipmentWithRisk({ qr_code: 'RISK-MID', il: 'Erzurum', riskScore: 55 });
    // 10-15 arası fazladan kayıt: yalnızca "veri döndü" değil, "doğru
    // sırada döndü" iddiasını GERÇEKTEN sınamak için (küçük bir listede
    // yanlışlıkla doğru sıralanmış gibi görünme riskini azaltır).
    for (let i = 0; i < 8; i += 1) {
      insertEquipmentWithRisk({ qr_code: `RISK-EXTRA-${i}`, il: 'Erzurum', riskScore: 30 + i });
    }

    const managerToken = getTestToken('yonetici');
    const response = await request(app)
      .get('/api/dashboard/risky-equipment?limit=10')
      .set('Authorization', `Bearer ${managerToken}`);

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body[0].qr_code, 'RISK-HIGH', 'ilk eleman EN YÜKSEK risk skoruna sahip olmalı');
    const scores = response.body.map((r) => r.risk_score);
    const sortedDesc = [...scores].sort((a, b) => b - a);
    assert.deepStrictEqual(scores, sortedDesc, 'tüm liste azalan sırada olmalı');
  });

  it('filtreleme: ?il=Erzurum yalnızca Erzurum ekipmanlarını döner, başka ilden hiçbir kayıt sızmaz', async () => {
    insertEquipmentWithRisk({ qr_code: 'ERZ-1', il: 'Erzurum', riskScore: 90 });
    insertEquipmentWithRisk({ qr_code: 'ERZ-2', il: 'Erzurum', riskScore: 60 });
    insertEquipmentWithRisk({ qr_code: 'KARS-1', il: 'Kars', riskScore: 99 }); // en yüksek skor ama BAŞKA il

    const managerToken = getTestToken('yonetici');
    const response = await request(app)
      .get('/api/dashboard/risky-equipment?il=Erzurum')
      .set('Authorization', `Bearer ${managerToken}`);

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.length, 2);
    assert.ok(response.body.every((r) => r.il === 'Erzurum'), 'Erzurum dışında hiçbir kayıt sızmamalı');
    assert.ok(!response.body.some((r) => r.qr_code === 'KARS-1'), 'Kars ekipmanı (daha yüksek skorlu olsa bile) filtre dışı kalmalı');
  });
});

describe('GET /api/dashboard/low-stock-materials', () => {
  beforeEach(() => {
    resetTestDatabase();
    seedMinimalTestData();
  });

  it('tüm roller erişebilir (teknisyen/dispeçer/yönetici)', async () => {
    for (const role of ['teknisyen', 'dispecer', 'yonetici']) {
      const token = getTestToken(role);
      const response = await request(app).get('/api/dashboard/low-stock-materials').set('Authorization', `Bearer ${token}`);
      assert.strictEqual(response.status, 200, `${role}: beklenmedik status ${response.status}`);
      assert.ok(Array.isArray(response.body));
    }
  });

  it('boş veri durumu: hiç malzeme yokken hata değil, boş dizi döner', async () => {
    const token = getTestToken('yonetici');
    const response = await request(app).get('/api/dashboard/low-stock-materials').set('Authorization', `Bearer ${token}`);
    assert.strictEqual(response.status, 200);
    assert.deepStrictEqual(response.body, []);
  });
});
