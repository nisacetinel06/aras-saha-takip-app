const db = require("./database");
const scores = db.prepare("SELECT a.equipment_id, e.qr_code, a.anomaly_score, a.is_suspicious, a.detected_reason FROM meter_anomaly_scores a JOIN equipment e ON e.id = a.equipment_id ORDER BY a.anomaly_score DESC LIMIT 10").all();
console.table(scores);
