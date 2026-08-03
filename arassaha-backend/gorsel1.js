const db = require("./database");
const rows = db.prepare("SELECT e.id, e.qr_code, e.location_name AS ekipman_konumu, wo.title AS is_emri_basligi FROM equipment e JOIN work_orders wo ON wo.equipment_id = e.id ORDER BY e.id LIMIT 10").all();
console.table(rows);
