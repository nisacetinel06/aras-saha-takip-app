// Dosya Temizleme görevleri (orphanFilePurge.js, retentionPurge.js) için
// ortak denetim kaydı — utils/notify.js createNotification ile AYNI desen
// (tek bir INSERT'i sarmalayan küçük, paylaşılan bir yardımcı).
const db = require('../database');

const insertPurgeLog = db.prepare(`
  INSERT INTO file_purge_log (file_path, related_table, related_record_id, reason, deleted_at)
  VALUES (@file_path, @related_table, @related_record_id, @reason, @deleted_at)
`);

/**
 * @param {object} params
 * @param {string|null} [params.filePath] - Silinen dosyanın /uploads/... yolu.
 * @param {string|null} [params.relatedTable] - Saklama süresi silmelerinde
 *   dosyanın bağlı olduğu tablo (örn. 'isg_reports'); orphan silmelerinde null.
 * @param {number|null} [params.relatedRecordId] - İlgili satırın id'si; orphan
 *   silmelerinde null (tanım gereği hiçbir kayda bağlı değil).
 * @param {'orphan'|'retention_expired'} params.reason
 */
function logPurgeAction({ filePath = null, relatedTable = null, relatedRecordId = null, reason }) {
  insertPurgeLog.run({
    file_path: filePath,
    related_table: relatedTable,
    related_record_id: relatedRecordId,
    reason,
    deleted_at: new Date().toISOString(),
  });
}

module.exports = { logPurgeAction };
