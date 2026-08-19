// Saklama Süresi Bazlı Temizleme — hâlâ bir DB kaydına BAĞLI (bkz.
// jobs/orphanFilePurge.js — o dosya hiç referansı OLMAYANLarla ilgilenir,
// bu dosya ise referansı OLAN ama artık tutulması gerekmeyen dosyalarla)
// ama KVKK Aydınlatma Metni'nde belirtilen saklama süresini aşan
// fotoğrafları temizler — kullanıcının elle bir silme talebi açmasını
// beklemeden, politikanın otomatik uygulanması.
//
// KRİTİK İLKE (KVKK Uyum Modülü ile TUTARLI — bkz. routes/kvkk.js dosya
// başı notu): yalnızca dosya diskten silinir ve photo_path NULL yapılır;
// KAYDIN KENDİSİ (isg_reports/work_order_photos satırı) ASLA silinmez —
// operasyonel kayıt (ne olmuş, ne zaman olmuş) denetim amaçlı korunur,
// yalnızca kişisel/görsel veri temizlenir.
const fs = require('fs');
const path = require('path');
const db = require('../database');
const { logPurgeAction } = require('./purgeLog');

const UPLOADS_ROOT = path.resolve(__dirname, '..', 'uploads');

// [TASLAK — HUKUK/İSG BİRİMİ ONAYI GEREKİR] Bu süreler, KVKK Aydınlatma
// Metni'nin (bkz. routes/kvkk.js AYDINLATMA_METNI, Bölüm 3 "Veri Saklama
// Süreleri") kendisinin de açıkça belirttiği gibi HENÜZ hukuk/İSG birimi
// tarafından onaylanmamış taslak değerlerdir. Kod olarak burada
// uygulandılar ki mekanizma gösterilebilsin/test edilebilsin — ama gerçek
// süreler netleşmeden production'da GERÇEK silme modunda (dryRun: false)
// çalıştırılmamalıdır (bkz. jobs/scheduler.js devreye alma notu ve görev
// raporu).
//
// profile_photos BİLEREK bu listeye eklenmez: profil fotoğrafının ayrı bir
// saklama süresi yoktur, hesap aktif olduğu sürece tutulur — yalnızca
// kullanıcının kendi talebiyle (KVKK Uyum Modülü) ya da yönetici tarafından
// değiştirilerek silinir.
const RETENTION_DAYS = {
  isg_photos: 365, // İSG bildirimi fotoğrafları — TASLAK
  work_order_photos: 730, // İş emri fotoğrafları — TASLAK
};

/**
 * photo_path ("/uploads/<klasör>/<dosya>") değerini gerçek bir dosya
 * sistemi yoluna çözer. routes/kvkk.js safeUnlinkPhoto ile AYNI path
 * traversal savunması (path.basename + kök dizin içinde kalma kontrolü) —
 * photo_path DB kökenli olsa da saldırgan-bitişik bir değer olarak ele alınır.
 * @param {string} photoPath
 * @param {string} uploadsRoot
 * @returns {string|null}
 */
function resolveDiskPath(photoPath, uploadsRoot) {
  const relative = String(photoPath).replace(/^\/?uploads\//, '');
  const [folder, ...rest] = relative.split('/');
  const filename = path.basename(rest.join('/'));
  if (!folder || !filename) return null;

  const resolvedPath = path.resolve(uploadsRoot, folder, filename);
  if (!resolvedPath.startsWith(path.resolve(uploadsRoot))) return null;
  return resolvedPath;
}

function purgeExpiredRows({ table, retentionDays, uploadsRoot, dryRun }) {
  const results = [];

  const expired = db
    .prepare(
      `SELECT id, photo_path FROM ${table}
       WHERE photo_path IS NOT NULL
         AND created_at < datetime('now', '-' || ? || ' days')`
    )
    .all(retentionDays);

  for (const row of expired) {
    results.push({ table, id: row.id, photo_path: row.photo_path });

    if (!dryRun) {
      const fullPath = resolveDiskPath(row.photo_path, uploadsRoot);
      if (fullPath && fs.existsSync(fullPath)) {
        fs.unlinkSync(fullPath);
      }
      // Kayıt SİLİNMEZ, yalnızca photo_path NULL yapılır — bkz. dosya başı
      // "KRİTİK İLKE" notu.
      db.prepare(`UPDATE ${table} SET photo_path = NULL WHERE id = ?`).run(row.id);
      logPurgeAction({
        filePath: row.photo_path,
        relatedTable: table,
        relatedRecordId: row.id,
        reason: 'retention_expired',
      });
    }
  }

  return results;
}

/**
 * @param {object} [options]
 * @param {boolean} [options.dryRun=true]
 * @param {string} [options.uploadsRoot] - bkz. jobs/orphanFilePurge.js'teki
 *   AYNI test-izolasyonu gerekçesi. Saklama süresi taraması yalnızca DB
 *   sorgusunun döndürdüğü (dolayısıyla test ortamında tamamen test verisiyle
 *   sınırlı) satırlara dokunduğu için orphan taraması kadar riskli değildir,
 *   ama simetri ve tutarlılık için AYNI enjekte edilebilir parametre burada
 *   da sunulur.
 * @returns {Array<{ table: string, id: number, photo_path: string }>}
 */
function purgeExpiredFiles({ dryRun = true, uploadsRoot = UPLOADS_ROOT } = {}) {
  return [
    ...purgeExpiredRows({
      table: 'isg_reports',
      retentionDays: RETENTION_DAYS.isg_photos,
      uploadsRoot,
      dryRun,
    }),
    ...purgeExpiredRows({
      table: 'work_order_photos',
      retentionDays: RETENTION_DAYS.work_order_photos,
      uploadsRoot,
      dryRun,
    }),
  ];
}

module.exports = { purgeExpiredFiles, RETENTION_DAYS, UPLOADS_ROOT };
