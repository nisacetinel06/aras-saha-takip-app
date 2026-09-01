// jobs/orphanFilePurge.js — orphan (hiçbir DB kaydına bağlı olmayan) dosya
// tespiti/temizliği. Bu dosyanın en kritik sorumluluğu: GERÇEKTEN kullanılan
// (bir DB satırının photo_path'i tarafından referans edilen) bir dosyanın
// HİÇBİR KOŞULDA silinmediğini kanıtlamaktır — bir hata burada, geri
// alınamaz gerçek veri kaybına yol açar (bkz. görev talimatı).
//
// GÜVENLİK NOTU: Bu testler GERÇEK/paylaşılan `uploads/` klasörüne ASLA
// dokunmaz — `findOrphanFiles`'a her zaman `uploadsRoot` ile izole bir
// geçici dizin (bkz. test/helpers/purgeTestUtils.js) enjekte edilir. Aksi
// halde `dryRun: false` çağrısı, bu test dosyasının izole `:memory:` DB'sinin
// bilmediği ama GERÇEKTEN kullanılan (başka test dosyalarının veya gerçek
// uygulamanın) dosyaları "orphan" sanıp silebilirdi.
const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');
const {
  findOrphanFiles,
  getReferencedPathsForFolder,
  GRACE_PERIOD_HOURS,
} = require('../../jobs/orphanFilePurge');
const {
  makeScratchUploadsRoot,
  cleanupScratchUploadsRoot,
  writeFileWithAge,
} = require('../helpers/purgeTestUtils');

const OLD_AGE_HOURS = GRACE_PERIOD_HOURS + 100; // grace period'un rahatça ötesinde

function countPurgeLogRows(reason) {
  return db.prepare('SELECT COUNT(*) AS c FROM file_purge_log WHERE reason = ?').get(reason).c;
}

describe('jobs/orphanFilePurge — findOrphanFiles', () => {
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

  describe('[EN KRİTİK GÜVENLİK TESTİ] referanslı bir dosya ASLA silinmez', () => {
    it('isg_reports.photo_path\'te referans edilen bir dosya, grace period\'un çok ötesinde bile silinmez', () => {
      const filename = 'referenced-isg.jpg';
      const fullPath = writeFileWithAge(uploadsRoot, 'isg', filename, OLD_AGE_HOURS);

      db.prepare(
        `INSERT INTO isg_reports (reported_by_user_id, description, category, photo_path, location_name, lat, lng, status, created_at)
         VALUES (?, 'test bildirimi', 'diger', ?, 'test konum', 39.9, 41.2, 'bekliyor', ?)`
      ).run(seeded.users.teknisyenId, `/uploads/isg/${filename}`, new Date().toISOString());

      const results = findOrphanFiles({ dryRun: false, uploadsRoot });

      assert.ok(
        !results.some((r) => r.folder === 'isg' && r.filename === filename),
        'referanslı dosya sonuç listesinde GÖRÜNMEMELİ'
      );
      assert.ok(fs.existsSync(fullPath), 'referanslı dosya diskte GERÇEKTEN hâlâ var olmalı');
    });

    it('work_order_photos.photo_path\'te referans edilen bir dosya silinmez', () => {
      const filename = 'referenced-wo.jpg';
      const fullPath = writeFileWithAge(uploadsRoot, 'workorders', filename, OLD_AGE_HOURS);

      db.prepare('INSERT INTO work_order_photos (work_order_id, photo_path, created_at) VALUES (?, ?, ?)').run(
        seeded.workOrders.ownWorkOrderId,
        `/uploads/workorders/${filename}`,
        new Date().toISOString()
      );

      const results = findOrphanFiles({ dryRun: false, uploadsRoot });

      assert.ok(!results.some((r) => r.folder === 'workorders' && r.filename === filename));
      assert.ok(fs.existsSync(fullPath));
    });

    it('users.photo_path\'te referans edilen bir dosya silinmez', () => {
      const filename = 'referenced-profile.jpg';
      const fullPath = writeFileWithAge(uploadsRoot, 'profiles', filename, OLD_AGE_HOURS);

      db.prepare('UPDATE users SET photo_path = ? WHERE id = ?').run(
        `/uploads/profiles/${filename}`,
        seeded.users.teknisyenId
      );

      const results = findOrphanFiles({ dryRun: false, uploadsRoot });

      assert.ok(!results.some((r) => r.folder === 'profiles' && r.filename === filename));
      assert.ok(fs.existsSync(fullPath));
    });

    it('feedback_items.photo_path\'te referans edilen bir dosya silinmez', () => {
      const filename = 'referenced-feedback.jpg';
      const fullPath = writeFileWithAge(uploadsRoot, 'feedback', filename, OLD_AGE_HOURS);

      db.prepare(
        `INSERT INTO feedback_items (submitted_by_user_id, category, description, photo_path, status, created_at)
         VALUES (?, 'sikayet', 'test bildirimi', ?, 'bekliyor', ?)`
      ).run(seeded.users.teknisyenId, `/uploads/feedback/${filename}`, new Date().toISOString());

      const results = findOrphanFiles({ dryRun: false, uploadsRoot });

      assert.ok(
        !results.some((r) => r.folder === 'feedback' && r.filename === filename),
        'referanslı dosya sonuç listesinde GÖRÜNMEMELİ'
      );
      assert.ok(fs.existsSync(fullPath), 'referanslı dosya diskte GERÇEKTEN hâlâ var olmalı');
    });
  });

  describe('orphan dosyalar gerçekten temizleniyor mu (her klasör için)', () => {
    for (const folder of ['isg', 'workorders', 'profiles', 'feedback']) {
      it(`${folder} klasöründeki referanssız/eski bir dosya silinir VE file_purge_log'a kaydedilir`, () => {
        const filename = `orphan-${folder}.jpg`;
        const fullPath = writeFileWithAge(uploadsRoot, folder, filename, OLD_AGE_HOURS);

        const beforeLogCount = countPurgeLogRows('orphan');
        const results = findOrphanFiles({ dryRun: false, uploadsRoot });

        assert.ok(
          results.some((r) => r.folder === folder && r.filename === filename),
          'orphan dosya sonuç listesinde OLMALI'
        );
        assert.ok(!fs.existsSync(fullPath), 'orphan dosya diskten GERÇEKTEN silinmiş olmalı');

        const afterLogCount = countPurgeLogRows('orphan');
        assert.strictEqual(afterLogCount, beforeLogCount + 1, "file_purge_log'a tam olarak 1 satır eklenmeli");

        const logRow = db
          .prepare("SELECT * FROM file_purge_log WHERE reason = 'orphan' ORDER BY id DESC LIMIT 1")
          .get();
        assert.strictEqual(logRow.file_path, `/uploads/${folder}/${filename}`);
        assert.strictEqual(logRow.related_table, null, 'orphan silmelerinde related_table NULL olmalı (tanım gereği hiçbir kayda bağlı değil)');
        assert.strictEqual(logRow.related_record_id, null);
        assert.ok(logRow.deleted_at, 'deleted_at doldurulmalı');
      });
    }
  });

  describe('grace period gerçekten çalışıyor mu', () => {
    it('yeni oluşturulmuş (grace period içindeki) referanssız bir dosya SİLİNMEZ', () => {
      const filename = 'too-new-orphan.jpg';
      const fullPath = writeFileWithAge(uploadsRoot, 'isg', filename, 1); // 1 saat önce — 24 saatlik grace period İÇİNDE

      const results = findOrphanFiles({ dryRun: false, uploadsRoot });

      assert.ok(
        !results.some((r) => r.folder === 'isg' && r.filename === filename),
        'grace period içindeki dosya sonuç listesinde OLMAMALI (henüz taranmaya bile alınmamalı)'
      );
      assert.ok(fs.existsSync(fullPath), 'grace period içindeki dosya diskte HÂLÂ var olmalı');
    });

    it('grace period sınırının hemen altında (23 saat) bir dosya da silinmez', () => {
      const filename = 'just-under-grace.jpg';
      const fullPath = writeFileWithAge(uploadsRoot, 'isg', filename, GRACE_PERIOD_HOURS - 1);

      findOrphanFiles({ dryRun: false, uploadsRoot });

      assert.ok(fs.existsSync(fullPath), '23 saatlik dosya grace period İÇİNDE kalır, silinmemeli');
    });
  });

  describe('dry-run modu gerçekten hiçbir şey silmiyor mu', () => {
    it('dry-run: orphan dosya sonuç listesinde görünür ama diskten SİLİNMEZ, log da yazılmaz', () => {
      const filename = 'dry-run-orphan.jpg';
      const fullPath = writeFileWithAge(uploadsRoot, 'isg', filename, OLD_AGE_HOURS);

      const beforeLogCount = countPurgeLogRows('orphan');
      const results = findOrphanFiles({ dryRun: true, uploadsRoot });

      assert.ok(
        results.some((r) => r.folder === 'isg' && r.filename === filename),
        'dry-run modunda da "silinirdi" listesi doğru dönmeli'
      );
      assert.ok(fs.existsSync(fullPath), 'dry-run modunda dosya GERÇEKTE silinmemiş olmalı');
      assert.strictEqual(countPurgeLogRows('orphan'), beforeLogCount, "dry-run modunda file_purge_log'a HİÇBİR satır eklenmemeli");
    });
  });

  describe('getReferencedPathsForFolder — doğru tabloyu sorguladığının kanıtı (çapraz-tablo izolasyonu)', () => {
    it('bir dosya adı yalnızca isg_reports\'ta referans edilirken workorders/profiles klasörleri için "referanslı" SAYILMAZ', () => {
      const filename = 'same-name.jpg';
      db.prepare(
        `INSERT INTO isg_reports (reported_by_user_id, description, category, photo_path, location_name, lat, lng, status, created_at)
         VALUES (?, 'x', 'diger', ?, 'x', 39.9, 41.2, 'bekliyor', ?)`
      ).run(seeded.users.teknisyenId, `/uploads/isg/${filename}`, new Date().toISOString());

      assert.ok(getReferencedPathsForFolder('isg').has(filename), "isg_reports'taki referans 'isg' klasörü için görülmeli");
      assert.ok(!getReferencedPathsForFolder('workorders').has(filename), "'workorders' sorgusu isg_reports'a BAKMAMALI");
      assert.ok(!getReferencedPathsForFolder('profiles').has(filename), "'profiles' sorgusu isg_reports'a BAKMAMALI");
    });

    it('work_order_photos referansı yalnızca workorders klasörü için görülür', () => {
      const filename = 'wo-only.jpg';
      db.prepare('INSERT INTO work_order_photos (work_order_id, photo_path, created_at) VALUES (?, ?, ?)').run(
        seeded.workOrders.ownWorkOrderId,
        `/uploads/workorders/${filename}`,
        new Date().toISOString()
      );

      assert.ok(getReferencedPathsForFolder('workorders').has(filename));
      assert.ok(!getReferencedPathsForFolder('isg').has(filename));
      assert.ok(!getReferencedPathsForFolder('profiles').has(filename));
    });

    it('users.photo_path referansı yalnızca profiles klasörü için görülür', () => {
      const filename = 'profile-only.jpg';
      db.prepare('UPDATE users SET photo_path = ? WHERE id = ?').run(
        `/uploads/profiles/${filename}`,
        seeded.users.teknisyenId
      );

      assert.ok(getReferencedPathsForFolder('profiles').has(filename));
      assert.ok(!getReferencedPathsForFolder('isg').has(filename));
      assert.ok(!getReferencedPathsForFolder('workorders').has(filename));
    });

    it('feedback_items.photo_path referansı yalnızca feedback klasörü için görülür', () => {
      const filename = 'feedback-only.jpg';
      db.prepare(
        `INSERT INTO feedback_items (submitted_by_user_id, category, description, photo_path, status, created_at)
         VALUES (?, 'oneri', 'x', ?, 'bekliyor', ?)`
      ).run(seeded.users.teknisyenId, `/uploads/feedback/${filename}`, new Date().toISOString());

      assert.ok(getReferencedPathsForFolder('feedback').has(filename));
      assert.ok(!getReferencedPathsForFolder('isg').has(filename));
      assert.ok(!getReferencedPathsForFolder('workorders').has(filename));
      assert.ok(!getReferencedPathsForFolder('profiles').has(filename));
    });

    it('bilinmeyen bir klasör adı için hata fırlatır (savunmacı — sessizce boş dönüp her şeyi "orphan" saymamalı)', () => {
      assert.throws(() => getReferencedPathsForFolder('bilinmeyen-klasor'));
    });
  });
});
