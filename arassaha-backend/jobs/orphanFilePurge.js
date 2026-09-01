// Orphan Dosya Temizleme — diskte fiziksel olarak var olan ama hiçbir DB
// kaydının photo_path alanında referans edilmeyen dosyaları tespit
// eder/(gerçek modda) siler. bkz. jobs/retentionPurge.js (kavramsal olarak
// FARKLI bir temizlik: bu dosya "hiç referansı yok", diğeri "referansı var
// ama saklama süresi doldu").
//
// GÜVENLİK NOTU (bkz. görev raporu): `getReferencedPathsForFolder`'da bir
// hata (yanlış tablo/sütun) GERÇEKTEN kullanılan dosyaların "orphan"
// görünüp silinmesine yol açar — bu, geri alınamaz bir veri kaybıdır. Bu
// yüzden aşağıdaki FOLDER_QUERIES eşlemesi yazıldıktan sonra AYRICA kod
// incelemesiyle iki kez doğrulandı (bkz. görev raporu) ve
// test/integration/orphanFilePurge.test.js'te HER klasör için "referanslı
// dosya asla silinmez" senaryosu somut olarak kanıtlanmıştır.
const fs = require('fs');
const path = require('path');
const db = require('../database');
const { logPurgeAction } = require('./purgeLog');

const UPLOADS_ROOT = path.resolve(__dirname, '..', 'uploads');

// routes/uploads.js'teki KLASÖR WHITELIST'İYLE birebir aynı dört klasör.
const UPLOAD_FOLDERS = ['isg', 'workorders', 'profiles', 'feedback'];

// Bu süreden daha YENİ dosyalar asla silinmez. Sebep: bir dosya yüklemesi
// iki adımdan oluşur — (1) dosya diske yazılır (multer), (2) DB satırı
// INSERT edilir (route handler). Bu iki adım arasında (ağ gecikmesi, sunucu
// yeniden başlaması, vb.) çok kısa bir pencere vardır; tarama TAM O ANDA
// yapılırsa, GERÇEKTEN kullanılacak ama henüz DB'ye yazılmamış bir dosya
// "orphan" görünüp yanlışlıkla silinebilir. 24 saat bu riski pratikte sıfıra
// indiren büyük bir güvenlik payıdır.
const GRACE_PERIOD_HOURS = 24;

// Her klasörün HANGİ tabloya/sütuna karşılık geldiği — bkz. dosya başı
// GÜVENLİK NOTU. Dört klasör de routes/uploads.js'teki whitelist'le,
// routes/kvkk.js'teki anonimleştirme akışıyla (feedback HARİÇ — bkz.
// routes/feedback.js dosya başı notu, bu modül KVKK akışına henüz dahil
// edilmedi) ve routes/users.js / routes/isg.js / routes/workOrders.js /
// routes/feedback.js'teki gerçek yükleme endpoint'leriyle TUTARLIDIR:
//   - isg        -> isg_reports.photo_path       (bkz. routes/isg.js POST /)
//   - workorders -> work_order_photos.photo_path (bkz. routes/workOrders.js POST /:id/photos)
//   - profiles   -> users.photo_path              (bkz. routes/users.js POST /:id/photo)
//   - feedback   -> feedback_items.photo_path     (bkz. routes/feedback.js POST /)
const FOLDER_QUERIES = {
  isg: 'SELECT photo_path FROM isg_reports WHERE photo_path IS NOT NULL',
  workorders: 'SELECT photo_path FROM work_order_photos WHERE photo_path IS NOT NULL',
  profiles: 'SELECT photo_path FROM users WHERE photo_path IS NOT NULL',
  feedback: 'SELECT photo_path FROM feedback_items WHERE photo_path IS NOT NULL',
};

/**
 * Verilen klasördeki dosyalara referans veren TÜM DB kayıtlarının dosya
 * adlarını (yalnızca basename, "/uploads/<klasör>/" öneki olmadan) döner.
 * @param {'isg'|'workorders'|'profiles'|'feedback'} folder
 * @returns {Set<string>}
 */
function getReferencedPathsForFolder(folder) {
  const query = FOLDER_QUERIES[folder];
  if (!query) {
    throw new Error(`Bilinmeyen upload klasörü: ${folder}`);
  }
  const rows = db.prepare(query).all();
  return new Set(rows.map((row) => path.basename(row.photo_path)));
}

/**
 * @param {object} [options]
 * @param {boolean} [options.dryRun=true] - true ise hiçbir dosya SİLİNMEZ,
 *   yalnızca "silinirdi" listesi döner.
 * @param {string} [options.uploadsRoot] - Uploads kök klasörü. TEST İZOLASYONU
 *   İÇİN vardır: test/integration/orphanFilePurge.test.js, GERÇEK
 *   `uploads/` klasörüne (paylaşılan, başka testlerin/gerçek kullanımın
 *   dosyalarını da içerebilen bir dizin) ASLA dokunmadan, kendi izole geçici
 *   bir klasörle çalışır — aksi halde `dryRun: false` testi, test DB'sinin
 *   (izole `:memory:`) BİLMEDİĞİ ama gerçekte kullanılan dosyaları "orphan"
 *   sanıp GERÇEKTEN silebilirdi. Production'da HER ZAMAN varsayılan (gerçek)
 *   kök kullanılır — bu parametre API üzerinden asla dışarıya açılmaz (bkz.
 *   routes/admin.js).
 * @returns {Array<{ folder: string, filename: string, fullPath: string, ageHours: number }>}
 */
function findOrphanFiles({ dryRun = true, uploadsRoot = UPLOADS_ROOT } = {}) {
  const results = [];

  for (const folder of UPLOAD_FOLDERS) {
    const folderPath = path.join(uploadsRoot, folder);
    if (!fs.existsSync(folderPath)) continue; // o klasöre henüz hiç dosya yüklenmemiş olabilir

    const referencedFilenames = getReferencedPathsForFolder(folder);
    const filesOnDisk = fs.readdirSync(folderPath);

    for (const filename of filesOnDisk) {
      const fullPath = path.join(folderPath, filename);
      const stats = fs.statSync(fullPath);
      if (!stats.isFile()) continue; // beklenmeyen bir alt klasör varsa atla

      const ageHours = (Date.now() - stats.mtimeMs) / (1000 * 60 * 60);
      if (ageHours < GRACE_PERIOD_HOURS) continue;

      if (referencedFilenames.has(filename)) continue; // GERÇEKTEN kullanılıyor — dokunma

      results.push({ folder, filename, fullPath, ageHours });

      if (!dryRun) {
        fs.unlinkSync(fullPath);
        logPurgeAction({
          filePath: `/uploads/${folder}/${filename}`,
          relatedTable: null,
          relatedRecordId: null,
          reason: 'orphan',
        });
      }
    }
  }

  return results;
}

module.exports = {
  findOrphanFiles,
  getReferencedPathsForFolder,
  GRACE_PERIOD_HOURS,
  UPLOAD_FOLDERS,
  UPLOADS_ROOT,
};
