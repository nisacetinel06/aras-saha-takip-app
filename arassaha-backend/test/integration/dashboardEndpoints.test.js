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
const { generateValidToken } = require('../helpers/tokenHelper');
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

  it('response schema doğru: open_count/resolved_today_count/avg_resolution_hours/status_breakdown/priority_breakdown/recent_activity/suspicious_meters_count', async () => {
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
      suspicious_meters_count: 'number',
    });
  });

  it('suspicious_meters_count: yalnızca is_suspicious=1 olan sayaçları sayar, teknisyen/yönetici AYNI sayıyı görür', async () => {
    // Ana Sayfa'daki uyarı kartı ekipman-bazlı bir sayı taşır (iş emri DEĞİL),
    // bu yüzden BİLİNÇLİ olarak visibilityClause'a tabi değildir — görünürlük
    // kısıtı yalnızca Flutter tarafında (rol == yönetici) uygulanır. Burada iki
    // sayaç (biri şüpheli, biri değil) seedleyip hem teknisyen hem yöneticinin
    // AYNI toplamı gördüğünü kanıtlıyoruz.
    const now = new Date().toISOString();
    const suspiciousId = db
      .prepare(
        `INSERT INTO equipment (qr_code, equipment_type, il, location_name, status, created_at)
         VALUES ('METER-SUS-1', 'sayac', 'Erzurum', 'x', 'aktif', ?)`
      )
      .run(now).lastInsertRowid;
    const normalId = db
      .prepare(
        `INSERT INTO equipment (qr_code, equipment_type, il, location_name, status, created_at)
         VALUES ('METER-OK-1', 'sayac', 'Erzurum', 'x', 'aktif', ?)`
      )
      .run(now).lastInsertRowid;
    db.prepare(
      `INSERT INTO meter_anomaly_scores (equipment_id, anomaly_score, is_suspicious, detected_reason, computed_at)
       VALUES (?, 90, 1, 'test', ?)`
    ).run(suspiciousId, now);
    db.prepare(
      `INSERT INTO meter_anomaly_scores (equipment_id, anomaly_score, is_suspicious, detected_reason, computed_at)
       VALUES (?, 5, 0, NULL, ?)`
    ).run(normalId, now);

    const technicianToken = getTestToken('teknisyen');
    const managerToken = getTestToken('yonetici');
    const techResponse = await request(app).get('/api/dashboard/summary').set('Authorization', `Bearer ${technicianToken}`);
    const managerResponse = await request(app).get('/api/dashboard/summary').set('Authorization', `Bearer ${managerToken}`);

    assert.strictEqual(techResponse.body.suspicious_meters_count, 1, 'yalnızca is_suspicious=1 olan sayaç sayılmalı');
    assert.strictEqual(managerResponse.body.suspicious_meters_count, 1);
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

// Modül 16 — "Performansım": GET /summary'nin AKSİNE rol bazlı görünürlük
// (visibilityClause) DEĞİL, her zaman `req.user.id` ile sabitlenmiş bir
// filtre kullanır — bu yüzden buradaki IDOR testi statü/öncelik değil,
// İKİ FARKLI teknisyenin sayılarının birbirinden tamamen BAĞIMSIZ olduğunu
// kanıtlar.
describe('GET /api/dashboard/my-performance', () => {
  let seeded;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
  });

  function markCompleted(workOrderId, { priority, updatedAt } = {}) {
    const params = [];
    let sql = `UPDATE work_orders SET status = 'cozuldu'`;
    if (priority) {
      sql += ', priority = ?';
      params.push(priority);
    }
    if (updatedAt) {
      sql += ', updated_at = ?';
      params.push(updatedAt);
    }
    sql += ' WHERE id = ?';
    params.push(workOrderId);
    db.prepare(sql).run(...params);
  }

  it('token olmadan 401 döner', async () => {
    const response = await request(app).get('/api/dashboard/my-performance');
    assert.strictEqual(response.status, 401);
  });

  it('response schema doğru: completed_this_month/total_completed_all_time/avg_resolution_hours/priority_breakdown/isg_reports_count/monthly_trend', async () => {
    const token = getTestToken('teknisyen');
    const response = await request(app).get('/api/dashboard/my-performance').set('Authorization', `Bearer ${token}`);

    assert.strictEqual(response.status, 200);
    assertSchema(response.body, {
      completed_this_month: 'number',
      total_completed_all_time: 'number',
      priority_breakdown: 'object',
      isg_reports_count: 'number',
      monthly_trend: 'array',
    });
    assert.strictEqual(response.body.monthly_trend.length, 6, 'son 6 ayın hepsi, veri olmayanlar 0 ile doldurularak dönmeli');
  });

  it('boş durum: hiç tamamlanmış iş yokken hata değil, sıfır/null değerli geçerli bir yapı döner', async () => {
    const token = getTestToken('teknisyen');
    const response = await request(app).get('/api/dashboard/my-performance').set('Authorization', `Bearer ${token}`);

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.total_completed_all_time, 0);
    assert.strictEqual(response.body.completed_this_month, 0);
    assert.strictEqual(response.body.avg_resolution_hours, null, 'AVG(NULL) durumunda sahte bir 0 DEĞİL, null dönmeli');
    assert.deepStrictEqual(response.body.priority_breakdown, { acil: 0, normal: 0, dusuk: 0 });
    assert.ok(
      response.body.monthly_trend.every((m) => m.completed_count === 0),
      'hiç tamamlanmış iş yokken her ay 0 olmalı'
    );
  });

  it('IDOR yok: iki farklı teknisyenin performans sayıları birbirinden tamamen bağımsız', async () => {
    // seedMinimalTestData: teknisyene 1 (acik), otherTeknisyen'e 1 (acik) iş
    // emri veriyor. Teknisyenin işini 'acil' önceliğiyle tamamlanmış işaretle,
    // otherTeknisyen'inkini AÇIK bırak — eğer endpoint req.user.id'ye göre
    // filtrelemeseydi, iki kullanıcı da AYNI (yanlış) sayıları görürdü.
    markCompleted(seeded.workOrders.ownWorkOrderId, { priority: 'acil' });

    const technicianToken = getTestToken('teknisyen');
    const otherToken = generateValidToken({ id: seeded.users.otherTeknisyenId, role: 'teknisyen' });

    const techResponse = await request(app).get('/api/dashboard/my-performance').set('Authorization', `Bearer ${technicianToken}`);
    const otherResponse = await request(app).get('/api/dashboard/my-performance').set('Authorization', `Bearer ${otherToken}`);

    assert.strictEqual(techResponse.status, 200);
    assert.strictEqual(otherResponse.status, 200);

    assert.strictEqual(techResponse.body.total_completed_all_time, 1, 'teknisyen kendi tamamladığı 1 işi görmeli');
    assert.strictEqual(techResponse.body.priority_breakdown.acil, 1);
    assert.strictEqual(
      otherResponse.body.total_completed_all_time,
      0,
      'diğer teknisyenin işi hâlâ açık — teknisyenin tamamlama sayısı ONA sızmamalı'
    );
    assert.notStrictEqual(
      techResponse.body.total_completed_all_time,
      otherResponse.body.total_completed_all_time,
      'iki teknisyen FARKLI kapsamlı sayılar görmeli — aynı olması IDOR/filtre boşluğuna işaret eder'
    );
  });

  it('isg_reports_count yalnızca bildiren kullanıcının kendi İSG bildirimlerini sayar', async () => {
    const now = new Date().toISOString();
    const insertIsg = db.prepare(
      `INSERT INTO isg_reports (reported_by_user_id, description, category, lat, lng, status, created_at)
       VALUES (?, 'test', 'diger', 39.9, 41.2, 'bekliyor', ?)`
    );
    insertIsg.run(seeded.users.teknisyenId, now);
    insertIsg.run(seeded.users.teknisyenId, now);
    insertIsg.run(seeded.users.otherTeknisyenId, now);

    const token = getTestToken('teknisyen');
    const response = await request(app).get('/api/dashboard/my-performance').set('Authorization', `Bearer ${token}`);

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.isg_reports_count, 2, 'yalnızca KENDİ bildirdiği 2 İSG bildirimi sayılmalı, diğer teknisyeninki değil');
  });
});
