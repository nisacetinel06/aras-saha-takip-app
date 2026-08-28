// TEST-19: Gerçek Geri Bildirim Döngüsü — bkz. database.js risk_prediction_outcomes,
// routes/risk.js (tahmin kaydı + otomatik "arızalandı" eşleştirmesi),
// jobs/orphanFilePurge.js/retentionPurge.js ile AYNI node-cron deseni (bkz.
// jobs/scheduler.js).
//
// Bir risk tahmininin `actual_fault_occurred` alanı, tahminden sonra 90 gün
// geçmesine RAĞMEN hâlâ NULL ise (yani o ekipman için bu süre içinde HİÇ
// arıza iş emri açılmadı), bu KASITLI olarak "arızalanmadı" (0) olarak
// işaretlenir — yalnızca "modelin doğru bildiği" durumları değil, "modelin
// yanlış alarm verdiği" durumları da yakalamak GET /api/ml/risk-model-performance
// özetinin dürüst olabilmesi için ZORUNLUDUR: yalnızca gerçekleşen arızaları
// sayıp hiç gerçekleşmeyenleri sonsuza dek "beklemede" bırakmak, doğruluk
// oranını yapay olarak şişirirdi (yalnızca "isabetli" tahminler asla
// kapanmayan bir payda ile karşılaştırılırdı).
const db = require('../database');

const OUTCOME_EXPIRY_DAYS = 90;

/**
 * @param {object} [options]
 * @param {boolean} [options.dryRun=true] - orphanFilePurge/retentionPurge ile
 *   AYNI güvenli-varsayılan ilkesi: yalnızca hangi kayıtların
 *   işaretleneceğini DÖNER, gerçekten yazmaz; canlı cron (jobs/scheduler.js)
 *   dryRun:false ile açıkça çağırır.
 * @returns {Array<{ id: number, equipment_id: number, predicted_risk_score: number, predicted_at: string }>}
 */
function expireStalePredictions({ dryRun = true } = {}) {
  const stale = db
    .prepare(
      `SELECT id, equipment_id, predicted_risk_score, predicted_at
       FROM risk_prediction_outcomes
       WHERE actual_fault_occurred IS NULL
         AND predicted_at <= datetime('now', '-' || ? || ' days')`
    )
    .all(OUTCOME_EXPIRY_DAYS);

  if (!dryRun && stale.length > 0) {
    const outcomeRecordedAt = new Date().toISOString();
    const markExpired = db.prepare(
      'UPDATE risk_prediction_outcomes SET actual_fault_occurred = 0, outcome_recorded_at = ? WHERE id = ?'
    );
    for (const row of stale) {
      markExpired.run(outcomeRecordedAt, row.id);
    }
  }

  return stale;
}

module.exports = { expireStalePredictions, OUTCOME_EXPIRY_DAYS };
