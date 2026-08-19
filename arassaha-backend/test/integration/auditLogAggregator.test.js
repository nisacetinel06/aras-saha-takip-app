// services/auditLogAggregator.js — 6 kaynak tablonun (7 kaynak sorgusunun,
// KVKK'nın "oluşturma"/"inceleme" olarak ikiye ayrılması nedeniyle) doğru
// birleştirildiğinin, filtrelerin ve sayfalamanın gerçek veriyle kanıtı.
// Mock YOK — gerçek :memory: SQLite, gerçek UNION ALL sorgusu.
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');
const { seedTestMaterial } = require('../helpers/materialFixtures');
const { fetchAuditLog } = require('../../services/auditLogAggregator');

const BASE_TIME = new Date('2026-01-01T00:00:00.000Z').getTime();
// Her kaynağa BİRBİRİNDEN FARKLI, artan bir zaman damgası verir — DESC
// sıralamanın GERÇEKTEN doğru çalıştığını (yalnızca "hepsi orada" değil,
// "doğru sırada") kanıtlayabilmek için.
function isoAt(minutesOffset) {
  return new Date(BASE_TIME + minutesOffset * 60 * 1000).toISOString();
}

function seedOneOfEachCategory(seeded) {
  const { teknisyenId, yoneticiId } = seeded.users;
  const workOrderId = seeded.workOrders.ownWorkOrderId;

  // 1) cihaz_yonetimi (dakika 10)
  const deviceInfo = db
    .prepare(
      `INSERT INTO managed_devices (device_name, assigned_user_id, created_at) VALUES (?, ?, ?)`
    )
    .run('Test Cihaz', teknisyenId, isoAt(0));
  db.prepare(
    'INSERT INTO device_action_logs (device_id, action_type, performed_by, created_at) VALUES (?, ?, ?, ?)'
  ).run(deviceInfo.lastInsertRowid, 'kilitle', 'Murat Öztürk', isoAt(10));

  // 2) kullanici_yonetimi (dakika 20)
  db.prepare(
    'INSERT INTO user_action_logs (target_user_id, action_type, performed_by, created_at) VALUES (?, ?, ?, ?)'
  ).run(teknisyenId, 'pasiflestirildi', 'Murat Öztürk', isoAt(20));

  // 3) giris — başarılı (dakika 30) + başarısız (dakika 31)
  db.prepare(
    'INSERT INTO login_attempts (sicil_no, ip_address, success, created_at) VALUES (?, ?, ?, ?)'
  ).run('1001', '10.0.0.5', 1, isoAt(30));
  db.prepare(
    'INSERT INTO login_attempts (sicil_no, ip_address, success, created_at) VALUES (?, ?, ?, ?)'
  ).run('1001', '10.0.0.5', 0, isoAt(31));

  // 4) kvkk — oluşturma (dakika 40) + inceleme (dakika 45): AYNI satırdan İKİ olay.
  const kvkkInfo = db
    .prepare(
      `INSERT INTO data_deletion_requests (user_id, request_type, status, reviewed_by_user_id, created_at, reviewed_at)
       VALUES (?, 'profil_fotografi_sil', 'tamamlandi', ?, ?, ?)`
    )
    .run(teknisyenId, yoneticiId, isoAt(40), isoAt(45));

  // 5) dosya_temizleme (dakika 50)
  db.prepare(
    "INSERT INTO file_purge_log (file_path, reason, deleted_at) VALUES ('/uploads/isg/x.jpg', 'orphan', ?)"
  ).run(isoAt(50));

  // 6) stok (dakika 60)
  const materialId = seedTestMaterial({ stock_quantity: 20 });
  db.prepare(
    `INSERT INTO material_stock_movements (material_id, movement_type, quantity, related_work_order_id, performed_by_user_id, created_at)
     VALUES (?, 'kullanim', -5, ?, ?, ?)`
  ).run(materialId, workOrderId, teknisyenId, isoAt(60));

  return { kvkkRequestId: kvkkInfo.lastInsertRowid, materialId, deviceId: deviceInfo.lastInsertRowid };
}

describe('services/auditLogAggregator — fetchAuditLog', () => {
  let seeded;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
  });

  it('6 kaynağın HEPSİNİ (2 login denemesi + KVKK\'nın 2 ayrı olayı nedeniyle 8 satır) doğru kategoriyle birleştirir', () => {
    seedOneOfEachCategory(seeded);

    const result = fetchAuditLog({});

    // device(1) + user_mgmt(1) + login(2: başarılı+başarısız) + kvkk(2: oluşturma+inceleme) + purge(1) + stok(1) = 8
    assert.strictEqual(result.totalCount, 8);
    const categories = result.entries.map((e) => e.category).sort();
    assert.deepStrictEqual(categories, [
      'cihaz_yonetimi',
      'dosya_temizleme',
      'giris',
      'giris',
      'kullanici_yonetimi',
      'kvkk',
      'kvkk',
      'stok',
    ].sort());
  });

  it('en yeniden eskiye (timestamp DESC) doğru sırada döner', () => {
    seedOneOfEachCategory(seeded);
    const result = fetchAuditLog({ limit: 100 });

    const timestamps = result.entries.map((e) => e.timestamp);
    const sortedDesc = [...timestamps].sort().reverse();
    assert.deepStrictEqual(timestamps, sortedDesc, 'kayıtlar timestamp\'e göre azalan sırada olmalı');
    // En yeni: stok (dakika 60), en eski: cihaz_yonetimi (dakika 10).
    assert.strictEqual(result.entries[0].category, 'stok');
    assert.strictEqual(result.entries[result.entries.length - 1].category, 'cihaz_yonetimi');
  });

  it('gerçek isimler users tablosuyla JOIN edilerek çözülüyor (FK olan tablolarda)', () => {
    seedOneOfEachCategory(seeded);
    const result = fetchAuditLog({ category: 'stok' });

    assert.strictEqual(result.entries.length, 1);
    assert.strictEqual(result.entries[0].actor_name, 'Test Teknisyen', 'material_stock_movements.performed_by_user_id JOIN ile gerçek isme çözülmeli');
    assert.strictEqual(result.entries[0].actor_id, seeded.users.teknisyenId);
  });

  it('KVKK: oluşturma ve inceleme olayları FARKLI actor/timestamp/action_type ile İKİ AYRI satır olarak görünür', () => {
    seedOneOfEachCategory(seeded);
    const result = fetchAuditLog({ category: 'kvkk' });

    assert.strictEqual(result.entries.length, 2);
    const [reviewEvent, creationEvent] = result.entries; // DESC sırada: inceleme (dk 45) önce, oluşturma (dk 40) sonra

    assert.strictEqual(creationEvent.action_type, 'talep_olusturuldu');
    assert.strictEqual(creationEvent.actor_name, 'Test Teknisyen', 'talebi AÇAN kişi teknisyen olmalı');

    assert.strictEqual(reviewEvent.action_type, 'tamamlandi');
    assert.strictEqual(reviewEvent.actor_name, 'Test Yönetici', 'talebi İNCELEYEN kişi yönetici olmalı');
  });

  it('device_action_logs/user_action_logs: performed_by ZATEN isim olduğu için actor_id NULL kalır (id sütunu yok)', () => {
    seedOneOfEachCategory(seeded);

    const deviceResult = fetchAuditLog({ category: 'cihaz_yonetimi' });
    assert.strictEqual(deviceResult.entries[0].actor_name, 'Murat Öztürk');
    assert.strictEqual(deviceResult.entries[0].actor_id, null);

    const userMgmtResult = fetchAuditLog({ category: 'kullanici_yonetimi' });
    assert.strictEqual(userMgmtResult.entries[0].actor_name, 'Murat Öztürk');
    assert.strictEqual(userMgmtResult.entries[0].actor_id, null);
  });

  it('login_attempts: sicil_no gerçek bir kullanıcıya eşleşiyorsa actor_id LEFT JOIN ile çözülür', () => {
    seedOneOfEachCategory(seeded);
    const result = fetchAuditLog({ category: 'giris' });

    assert.strictEqual(result.entries.length, 2);
    for (const entry of result.entries) {
      assert.strictEqual(entry.actor_id, seeded.users.teknisyenId, "sicil_no '1001' gerçek teknisyene eşleşmeli");
      assert.match(entry.actor_name, /^1001 \((başarılı|başarısız)\)$/);
    }
  });

  it('var olmayan bir sicil_no ile yapılan login denemesi actor_id=NULL kalır (JOIN eşleşmez)', () => {
    db.prepare(
      'INSERT INTO login_attempts (sicil_no, ip_address, success, created_at) VALUES (?, ?, ?, ?)'
    ).run('99999', '10.0.0.9', 0, isoAt(5));

    const result = fetchAuditLog({ category: 'giris' });
    assert.strictEqual(result.entries.length, 1);
    assert.strictEqual(result.entries[0].actor_id, null);
  });

  it('dosya_temizleme: aktör her zaman "Sistem (otomatik)" ve actor_id her zaman NULL', () => {
    seedOneOfEachCategory(seeded);
    const result = fetchAuditLog({ category: 'dosya_temizleme' });

    assert.strictEqual(result.entries.length, 1);
    assert.strictEqual(result.entries[0].actor_name, 'Sistem (otomatik)');
    assert.strictEqual(result.entries[0].actor_id, null);
  });

  describe('filtreler', () => {
    it('category filtresi yalnızca o kategoriye ait kayıtları döner', () => {
      seedOneOfEachCategory(seeded);
      const result = fetchAuditLog({ category: 'giris' });

      assert.strictEqual(result.totalCount, 2);
      assert.ok(result.entries.every((e) => e.category === 'giris'));
    });

    it('actor_id filtresi yalnızca o aktöre ait kayıtları döner', () => {
      seedOneOfEachCategory(seeded);
      const result = fetchAuditLog({ actorId: seeded.users.yoneticiId });

      // yönetici yalnızca KVKK inceleme olayının aktörüdür (dk 45).
      assert.strictEqual(result.totalCount, 1);
      assert.strictEqual(result.entries[0].category, 'kvkk');
      assert.strictEqual(result.entries[0].action_type, 'tamamlandi');
    });

    it('tarih aralığı (from/to) filtresi doğru aralıktaki kayıtları döner', () => {
      seedOneOfEachCategory(seeded);
      // dakika 20 (kullanici_yonetimi) ile dakika 45 (kvkk inceleme) arası: 4 kayıt
      // (kullanici_yonetimi@20, giris@30, giris@31, kvkk-olusturma@40, kvkk-inceleme@45)
      const result = fetchAuditLog({ fromDate: isoAt(20), toDate: isoAt(45), limit: 100 });

      assert.strictEqual(result.totalCount, 5);
      assert.ok(result.entries.every((e) => e.timestamp >= isoAt(20) && e.timestamp <= isoAt(45)));
    });

    it('kategori + tarih aralığı BİRLİKTE uygulanabilir', () => {
      seedOneOfEachCategory(seeded);
      const result = fetchAuditLog({ category: 'giris', fromDate: isoAt(31) });

      assert.strictEqual(result.totalCount, 1);
      assert.strictEqual(result.entries[0].action_type, 'giris_basarisiz');
    });
  });

  describe('sayfalama', () => {
    it('limit doğru uygulanır, has_more doğru hesaplanır', () => {
      seedOneOfEachCategory(seeded); // toplam 8 kayıt (bkz. yukarıdaki test)

      const page1 = fetchAuditLog({ page: 1, limit: 3 });
      assert.strictEqual(page1.entries.length, 3);
      assert.strictEqual(page1.totalCount, 8);
      assert.strictEqual(page1.hasMore, true);

      const page2 = fetchAuditLog({ page: 2, limit: 3 });
      assert.strictEqual(page2.entries.length, 3);
      assert.strictEqual(page2.hasMore, true);

      const page3 = fetchAuditLog({ page: 3, limit: 3 });
      assert.strictEqual(page3.entries.length, 2, 'son sayfada kalan 2 kayıt dönmeli (8 - 3 - 3)');
      assert.strictEqual(page3.hasMore, false);

      // Sayfalar arasında ÇAKIŞMA/TEKRAR olmamalı.
      const allIds = [...page1.entries, ...page2.entries, ...page3.entries].map(
        (e) => `${e.category}|${e.action_type}|${e.timestamp}`
      );
      assert.strictEqual(new Set(allIds).size, 8, 'sayfalar arasında tekrar eden kayıt OLMAMALI');
    });

    it('limit belirtilmezse varsayılan (50) kullanılır', () => {
      seedOneOfEachCategory(seeded);
      const result = fetchAuditLog({});
      assert.strictEqual(result.limit, 50);
    });

    it('MAX_LIMIT üstü bir limit isteği üst sınıra düşürülür (tüm geçmişi tek seferde çekme engeli)', () => {
      seedOneOfEachCategory(seeded);
      const result = fetchAuditLog({ limit: 999999 });
      assert.ok(result.limit <= 200, 'limit MAX_LIMIT (200) ile sınırlanmalı');
    });
  });
});
