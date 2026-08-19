// Yönetici Bakım Araçları — şu an yalnızca dosya temizliği (orphan +
// saklama süresi) görevinin manuel/test amaçlı tetiklenmesi için. Gerçek
// zamanlanmış (otomatik) çalıştırma jobs/scheduler.js'tedir; bu endpoint,
// yöneticinin gece 03:00'ı beklemeden sonucu görebilmesi içindir.
const express = require('express');
const { requireRole } = require('../middleware/auth');
const { findOrphanFiles } = require('../jobs/orphanFilePurge');
const { purgeExpiredFiles } = require('../jobs/retentionPurge');

const router = express.Router();

// POST /api/admin/run-purge-job?dryRun=true|false — yalnızca yönetici.
//
// GÜVENLİ VARSAYILAN: `dryRun` query parametresi HİÇ verilmezse ya da tam
// olarak 'false' DIŞINDA herhangi bir değer taşırsa dry-run kabul edilir —
// gerçek silme yalnızca AÇIKÇA `?dryRun=false` geçilirse tetiklenir. Bu,
// "unutulan/yazım hatalı bir query parametresi yüzünden yanlışlıkla gerçek
// silme" riskini ortadan kaldırır (bkz. görev talimatı "önce dry-run"
// disiplini).
router.post('/run-purge-job', requireRole('yonetici'), (req, res) => {
  try {
    const dryRun = req.query.dryRun !== 'false';

    // TEST İZOLASYONU (bkz. jobs/orphanFilePurge.js "uploadsRoot" notu ve
    // server.js'teki '/api/__test-error' ile AYNI ilke): yalnızca
    // NODE_ENV==='test' İKEN VE test süreci kendi ortam değişkenini açıkça
    // ayarlamışsa, gerçek `uploads/` kökü yerine izole bir test dizini
    // kullanılır. Bu HİÇBİR istemci/API isteğiyle (query/body parametresi
    // DEĞİL, yalnızca sunucu SÜRECİNİN kendi ortam değişkeni) kontrol
    // edilemez — production'a asla sızamaz, testlerin `?dryRun=false`'u
    // GERÇEK ama İZOLE bir dizinde uçtan uca (route üzerinden) doğrulamasını
    // sağlar (bkz. test/integration/purgeAdminEndpoint.test.js).
    const testUploadsRoot =
      process.env.NODE_ENV === 'test' ? process.env.PURGE_TEST_UPLOADS_ROOT : undefined;
    const rootOverride = testUploadsRoot ? { uploadsRoot: testUploadsRoot } : {};

    const orphanResults = findOrphanFiles({ dryRun, ...rootOverride });
    const retentionResults = purgeExpiredFiles({ dryRun, ...rootOverride });
    const totalCount = orphanResults.length + retentionResults.length;

    res.json({
      dry_run: dryRun,
      message: dryRun
        ? `${totalCount} dosya silinirdi (dry-run modu, hiçbir şey GERÇEKTEN silinmedi).`
        : `${totalCount} dosya silindi.`,
      orphan_files: {
        count: orphanResults.length,
        items: orphanResults.map((r) => ({
          folder: r.folder,
          filename: r.filename,
          age_hours: Math.round(r.ageHours),
        })),
      },
      expired_files: {
        count: retentionResults.length,
        items: retentionResults.map((r) => ({
          table: r.table,
          id: r.id,
          photo_path: r.photo_path,
        })),
      },
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Temizlik işlemi çalıştırılırken bir hata oluştu.' });
  }
});

module.exports = router;
