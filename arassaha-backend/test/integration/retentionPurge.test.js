// jobs/retentionPurge.js — KVKK Aydınlatma Metni'ndeki (TASLAK) saklama
// sürelerini aşan, hâlâ bir DB kaydına BAĞLI dosyaların otomatik temizliği.
// jobs/orphanFilePurge.js'ten (hiç referansı OLMAYAN dosyalar) FARKLI bir
// senaryo: burada dosya referanslı ama artık tutulması gerekmiyor.
//
// KRİTİK İLKE: dosya silinir + photo_path NULL yapılır, ama KAYIT
// (isg_reports/work_order_photos satırı) ASLA silinmez — KVKK Uyum
// Modülü'ndeki "operasyonel kayıt korunur" prensibiyle tutarlılığı bu
// dosyada özellikle doğrulanır.
const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');
const { purgeExpiredFiles, RETENTION_DAYS } = require('../../jobs/retentionPurge');
const {
  makeScratchUploadsRoot,
  cleanupScratchUploadsRoot,
  daysAgoIso,
} = require('../helpers/purgeTestUtils');

function countPurgeLogRows(reason) {
  return db.prepare('SELECT COUNT(*) AS c FROM file_purge_log WHERE reason = ?').get(reason).c;
}

function writeFixtureFile(uploadsRoot, folder, filename) {
  const fullPath = path.join(uploadsRoot, folder, filename);
  fs.writeFileSync(fullPath, 'retention-test-icerigi');
  return fullPath;
}

describe('jobs/retentionPurge — purgeExpiredFiles', () => {
  let seeded;
  let uploadsRoot;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
    uploadsRoot = makeScratchUploadsRoot();
  });

  afterEach(() => {
    cleanupScratchUploadsRoot(uploadsRoot);
  });

  describe('isg_reports — saklama süresi dolan kayıt doğru işleniyor mu', () => {
    it('süresi DOLMUŞ bir İSG bildirimi: dosya silinir, photo_path NULL olur, AMA KAYIT hâlâ var', () => {
      const filename = 'expired-isg.jpg';
      const fullPath = writeFixtureFile(uploadsRoot, 'isg', filename);

      const info = db
        .prepare(
          `INSERT INTO isg_reports (reported_by_user_id, description, category, photo_path, location_name, lat, lng, status, created_at)
           VALUES (?, 'suresi dolan bildirim', 'diger', ?, 'test', 39.9, 41.2, 'bekliyor', ?)`
        )
        .run(
          seeded.users.teknisyenId,
          `/uploads/isg/${filename}`,
          daysAgoIso(RETENTION_DAYS.isg_photos + 10) // eşiğin rahatça ötesinde
        );
      const reportId = info.lastInsertRowid;

      const beforeLogCount = countPurgeLogRows('retention_expired');
      const results = purgeExpiredFiles({ dryRun: false, uploadsRoot });

      assert.ok(
        results.some((r) => r.table === 'isg_reports' && r.id === reportId),
        'süresi dolmuş kayıt sonuç listesinde OLMALI'
      );
      assert.ok(!fs.existsSync(fullPath), 'dosya diskten GERÇEKTEN silinmeli');

      const afterRow = db.prepare('SELECT * FROM isg_reports WHERE id = ?').get(reportId);
      assert.ok(afterRow, 'isg_reports KAYDI SİLİNMEMİŞ olmalı — yalnızca fotoğraf temizlenir');
      assert.strictEqual(afterRow.photo_path, null, 'photo_path NULL olmalı');
      assert.strictEqual(afterRow.description, 'suresi dolan bildirim', 'kaydın kendisi (içeriği) DEĞİŞMEMELİ');

      assert.strictEqual(countPurgeLogRows('retention_expired'), beforeLogCount + 1);
      const logRow = db
        .prepare("SELECT * FROM file_purge_log WHERE reason = 'retention_expired' ORDER BY id DESC LIMIT 1")
        .get();
      assert.strictEqual(logRow.related_table, 'isg_reports');
      assert.strictEqual(logRow.related_record_id, reportId);
      assert.strictEqual(logRow.file_path, `/uploads/isg/${filename}`);
    });

    it('saklama süresi İÇİNDEKİ (yeni) bir İSG bildirimi silinmez', () => {
      const filename = 'fresh-isg.jpg';
      const fullPath = writeFixtureFile(uploadsRoot, 'isg', filename);

      const info = db
        .prepare(
          `INSERT INTO isg_reports (reported_by_user_id, description, category, photo_path, location_name, lat, lng, status, created_at)
           VALUES (?, 'yeni bildirim', 'diger', ?, 'test', 39.9, 41.2, 'bekliyor', ?)`
        )
        .run(seeded.users.teknisyenId, `/uploads/isg/${filename}`, daysAgoIso(10)); // eşiğin ÇOK altında
      const reportId = info.lastInsertRowid;

      const results = purgeExpiredFiles({ dryRun: false, uploadsRoot });

      assert.ok(!results.some((r) => r.table === 'isg_reports' && r.id === reportId));
      assert.ok(fs.existsSync(fullPath), 'saklama süresi dolmamış dosya silinmemeli');
      assert.strictEqual(db.prepare('SELECT photo_path FROM isg_reports WHERE id = ?').get(reportId).photo_path, `/uploads/isg/${filename}`);
    });
  });

  describe('work_order_photos — saklama süresi dolan kayıt doğru işleniyor mu', () => {
    it('süresi DOLMUŞ bir iş emri fotoğrafı: dosya silinir, photo_path NULL olur, AMA satır hâlâ var', () => {
      const filename = 'expired-wo.jpg';
      const fullPath = writeFixtureFile(uploadsRoot, 'workorders', filename);

      const info = db
        .prepare('INSERT INTO work_order_photos (work_order_id, photo_path, created_at) VALUES (?, ?, ?)')
        .run(
          seeded.workOrders.ownWorkOrderId,
          `/uploads/workorders/${filename}`,
          daysAgoIso(RETENTION_DAYS.work_order_photos + 10)
        );
      const photoId = info.lastInsertRowid;

      const results = purgeExpiredFiles({ dryRun: false, uploadsRoot });

      assert.ok(results.some((r) => r.table === 'work_order_photos' && r.id === photoId));
      assert.ok(!fs.existsSync(fullPath));

      const afterRow = db.prepare('SELECT * FROM work_order_photos WHERE id = ?').get(photoId);
      assert.ok(afterRow, 'work_order_photos KAYDI SİLİNMEMİŞ olmalı');
      assert.strictEqual(afterRow.photo_path, null);
      assert.strictEqual(afterRow.work_order_id, seeded.workOrders.ownWorkOrderId, 'iş emri bağlantısı DEĞİŞMEMELİ');
    });

    it('saklama süresi İÇİNDEKİ bir iş emri fotoğrafı silinmez', () => {
      const filename = 'fresh-wo.jpg';
      const fullPath = writeFixtureFile(uploadsRoot, 'workorders', filename);

      const info = db
        .prepare('INSERT INTO work_order_photos (work_order_id, photo_path, created_at) VALUES (?, ?, ?)')
        .run(seeded.workOrders.ownWorkOrderId, `/uploads/workorders/${filename}`, daysAgoIso(30));
      const photoId = info.lastInsertRowid;

      purgeExpiredFiles({ dryRun: false, uploadsRoot });

      assert.ok(fs.existsSync(fullPath));
      assert.strictEqual(
        db.prepare('SELECT photo_path FROM work_order_photos WHERE id = ?').get(photoId).photo_path,
        `/uploads/workorders/${filename}`
      );
    });
  });

  describe('dry-run modu gerçekten hiçbir şey silmiyor/değiştirmiyor mu', () => {
    it('dry-run: süresi dolmuş kayıt sonuç listesinde görünür ama dosya/DB/log DEĞİŞMEZ', () => {
      const filename = 'dry-run-expired.jpg';
      const fullPath = writeFixtureFile(uploadsRoot, 'isg', filename);

      const info = db
        .prepare(
          `INSERT INTO isg_reports (reported_by_user_id, description, category, photo_path, location_name, lat, lng, status, created_at)
           VALUES (?, 'x', 'diger', ?, 'x', 39.9, 41.2, 'bekliyor', ?)`
        )
        .run(seeded.users.teknisyenId, `/uploads/isg/${filename}`, daysAgoIso(RETENTION_DAYS.isg_photos + 10));
      const reportId = info.lastInsertRowid;

      const beforeLogCount = countPurgeLogRows('retention_expired');
      const results = purgeExpiredFiles({ dryRun: true, uploadsRoot });

      assert.ok(results.some((r) => r.table === 'isg_reports' && r.id === reportId), 'dry-run modunda da sonuç listesi doğru dönmeli');
      assert.ok(fs.existsSync(fullPath), 'dry-run modunda dosya GERÇEKTE silinmemiş olmalı');
      assert.strictEqual(
        db.prepare('SELECT photo_path FROM isg_reports WHERE id = ?').get(reportId).photo_path,
        `/uploads/isg/${filename}`,
        'dry-run modunda photo_path DEĞİŞMEMELİ'
      );
      assert.strictEqual(countPurgeLogRows('retention_expired'), beforeLogCount, "dry-run modunda file_purge_log'a HİÇBİR satır eklenmemeli");
    });
  });
});
