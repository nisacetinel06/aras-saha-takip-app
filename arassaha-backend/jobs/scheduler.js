// Zamanlanmış (cron) arka plan görevleri — dosya temizliği (orphan +
// saklama süresi). node-cron seçildi çünkü tek sunuculu (Railway) bir
// deployment için yeterlidir; Bull/Redis gibi ağır bir job-queue altyapısı
// bu ölçekte gereksiz karmaşıklık katardı.
//
// [ÖNERİ — bkz. görev raporu] Production'a alındıktan sonra İLK BİRKAÇ GÜN
// yalnızca dry-run modunda çalıştırılıp konsol çıktısı (ve gerekirse
// file_purge_log — dry-run'da hiçbir satır YAZILMAZ, bu yüzden ilk günlerde
// "ne silinirdi" listesini görmek için konsol loguna bakılmalı) elle
// incelenmeli, ancak SONRA aşağıdaki `dryRun: false`'a geçilmelidir. Bu
// disiplin RETENTION_DAYS'in hâlâ TASLAK olmasıyla (bkz. jobs/retentionPurge.js)
// birlikte özellikle önemlidir.
const cron = require('node-cron');
const { findOrphanFiles } = require('./orphanFilePurge');
const { purgeExpiredFiles } = require('./retentionPurge');
const { expireStalePredictions } = require('./riskOutcomeExpiry');

function runPurgeJobs() {
  console.log('[PURGE JOB] Orphan dosya taraması başlıyor...');
  try {
    const orphanResults = findOrphanFiles({ dryRun: false });
    console.log(`[PURGE JOB] ${orphanResults.length} orphan dosya temizlendi.`);
  } catch (err) {
    // Bir taramanın başarısız olması diğerini ENGELLEMEMELİ — orphan
    // taraması çökerse bile saklama süresi taraması yine de denenir.
    console.error('[PURGE JOB] Orphan dosya taraması başarısız oldu:', err);
  }

  console.log('[PURGE JOB] Saklama süresi taraması başlıyor...');
  try {
    const retentionResults = purgeExpiredFiles({ dryRun: false });
    console.log(`[PURGE JOB] ${retentionResults.length} süresi dolmuş dosya temizlendi.`);
  } catch (err) {
    console.error('[PURGE JOB] Saklama süresi taraması başarısız oldu:', err);
  }
}

// TEST-19: Gerçek Geri Bildirim Döngüsü'nün 90 günlük "sonuçlanmamış tahmini
// kapat" ayağı (bkz. jobs/riskOutcomeExpiry.js) — dosya temizliğinden AYRI
// bir kaygı olduğu için runPurgeJobs()'a KARIŞTIRILMADI, ama AYNI sessiz
// saatte, AYNI "her adım kendi try/catch'i" disipliniyle çalışır.
function runRiskOutcomeExpiryJob() {
  console.log('[RISK OUTCOME JOB] 90 günü aşmış, sonuçlanmamış risk tahminleri taranıyor...');
  try {
    const expired = expireStalePredictions({ dryRun: false });
    console.log(`[RISK OUTCOME JOB] ${expired.length} tahmin "arızalanmadı" (0) olarak kapatıldı.`);
  } catch (err) {
    console.error('[RISK OUTCOME JOB] Risk tahmini süresi dolumu taraması başarısız oldu:', err);
  }
}

// Her gün gece 03:00 (sunucu saatiyle) — trafiğin en düşük olduğu saat,
// riskRouter/anomalyRouter'ın başlangıç yenilemeleriyle AYNI "sessiz saatte
// çalış" ilkesi.
function startScheduledPurgeJobs() {
  cron.schedule('0 3 * * *', runPurgeJobs);
  cron.schedule('0 3 * * *', runRiskOutcomeExpiryJob);
  console.log('[PURGE JOB] Zamanlanmış dosya temizliği kuruldu (her gün 03:00).');
  console.log('[RISK OUTCOME JOB] Zamanlanmış risk tahmini süresi dolumu taraması kuruldu (her gün 03:00).');
}

module.exports = { startScheduledPurgeJobs, runPurgeJobs, runRiskOutcomeExpiryJob };
