// jobs/orphanFilePurge.js ve jobs/retentionPurge.js testleri için ortak
// yardımcılar. GÜVENLİK NOTU (bkz. jobs/orphanFilePurge.js "uploadsRoot"
// parametresi): bu yardımcılar HER ZAMAN izole, geçici bir dizin (os.tmpdir()
// altında) oluşturur — GERÇEK/paylaşılan uploads/ klasörüne asla dokunmaz.
// Bu, findOrphanFiles({ dryRun: false })'ın test sırasında, test DB'sinin
// (izole :memory:) bilmediği ama gerçekte kullanılan (başka test
// dosyalarının veya gerçek uygulamanın) dosyaları yanlışlıkla "orphan"
// sanıp GERÇEKTEN silmesini imkansız kılar.
const fs = require('fs');
const path = require('path');
const os = require('os');

const PURGE_TEST_FOLDERS = ['isg', 'workorders', 'profiles'];

/** İzole bir geçici uploads kök dizini oluşturur (isg/workorders/profiles alt klasörleriyle). */
function makeScratchUploadsRoot() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'arassaha-purge-test-'));
  for (const folder of PURGE_TEST_FOLDERS) {
    fs.mkdirSync(path.join(root, folder), { recursive: true });
  }
  return root;
}

function cleanupScratchUploadsRoot(root) {
  fs.rmSync(root, { recursive: true, force: true });
}

/**
 * Verilen klasörde gerçek bir dosya oluşturur ve mtime'ını (dosya YAŞINI)
 * elle ayarlar — grace period / saklama süresi senaryolarını (dosyanın
 * "eski" ya da "yeni" olması) deterministik şekilde test edebilmek için.
 * @returns {string} oluşturulan dosyanın tam yolu
 */
function writeFileWithAge(uploadsRoot, folder, filename, ageHours) {
  const fullPath = path.join(uploadsRoot, folder, filename);
  fs.writeFileSync(fullPath, 'purge-test-dosya-icerigi');
  const targetTime = new Date(Date.now() - ageHours * 60 * 60 * 1000);
  fs.utimesSync(fullPath, targetTime, targetTime);
  return fullPath;
}

/** created_at için, verilen gün sayısı kadar geçmişte bir ISO zaman damgası. */
function daysAgoIso(days) {
  return new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString();
}

module.exports = {
  PURGE_TEST_FOLDERS,
  makeScratchUploadsRoot,
  cleanupScratchUploadsRoot,
  writeFileWithAge,
  daysAgoIso,
};
