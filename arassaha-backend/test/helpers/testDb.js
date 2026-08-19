// Test veritabanı yardımcıları — her testten ÖNCE çağrılıp (bkz. beforeEach
// örnekleri) test veritabanını (NODE_ENV=test iken :memory:, bkz. database.js)
// temiz, bilinen bir duruma getirir.
require('../setup');
const bcrypt = require('bcrypt');
const db = require('../../database');

// Silme sırası, database.js'teki FOREIGN KEY tanımlarına göre ÇOCUKTAN
// EBEVEYNE doğru sıralanmıştır (seed.js'teki DELETE sırasıyla AYNI ilke) —
// aksi halde `PRAGMA foreign_keys = ON` nedeniyle FOREIGN KEY constraint
// failed hatası alınır.
const TABLES_CHILD_TO_PARENT = [
  'login_attempts',
  'data_deletion_requests',
  'device_action_logs',
  'work_order_photos',
  'material_stock_movements',
  'work_order_materials',
  'maintenance_recommendations',
  'work_orders',
  'user_action_logs',
  'notifications',
  'chat_messages',
  'usage_logs',
  'isg_reports',
  'equipment_risk_scores',
  'meter_anomaly_scores',
  'meter_consumption',
  'managed_devices',
  'equipment',
  'materials',
  'processed_client_actions',
  'users',
];

// Tüm tabloları boşaltır (şemayı yeniden oluşturmaz — :memory: veritabanı
// zaten her `node --test` sürecinde sıfırdan/boş başlar, bu yalnızca AYNI
// süreç içindeki testler arasında izolasyon sağlar).
function resetTestDatabase() {
  for (const table of TABLES_CHILD_TO_PARENT) {
    db.exec(`DELETE FROM ${table}`);
  }
  db.exec('DELETE FROM sqlite_sequence');
}

const DEMO_PASSWORD = 'sifre123';
let demoPasswordHash = null;

// Modül 7'nin gerçek seed.js'i (bkz. seed.js) tekrar kullanılabilir
// fonksiyonlar olarak yazılmadığı, tersine kendi kendine çalışan bir script
// olduğu için burada BİLEREK küçültülmüş, bağımsız bir minimal set üretilir
// (seed.js'e dokunmak, "gerekli olan server.js export'u dışında kod mantığına
// dokunma" kuralını ihlal ederdi). Personel/roller ve sicil_no/şifre kalıbı
// seed.js ile TUTARLI tutuldu (1001/2001/3001, DEMO_PASSWORD) ki testler
// demo veriyle aynı zihinsel modeli paylaşsın.
function seedMinimalTestData() {
  demoPasswordHash = demoPasswordHash || bcrypt.hashSync(DEMO_PASSWORD, 10);
  const now = new Date().toISOString();

  const insertUser = db.prepare(
    'INSERT INTO users (name, role, sicil_no, password_hash, supervisor_id) VALUES (@name, @role, @sicil_no, @password_hash, @supervisor_id)'
  );

  const yoneticiId = insertUser.run({
    name: 'Test Yönetici',
    role: 'yonetici',
    sicil_no: '3001',
    password_hash: demoPasswordHash,
    supervisor_id: null,
  }).lastInsertRowid;

  const dispecerId = insertUser.run({
    name: 'Test Dispeçer',
    role: 'dispecer',
    sicil_no: '2001',
    password_hash: demoPasswordHash,
    supervisor_id: yoneticiId,
  }).lastInsertRowid;

  const teknisyenId = insertUser.run({
    name: 'Test Teknisyen',
    role: 'teknisyen',
    sicil_no: '1001',
    password_hash: demoPasswordHash,
    supervisor_id: dispecerId,
  }).lastInsertRowid;

  // RBAC testleri (bkz. test/integration/workOrders.test.js) için: aynı
  // dispeçere bağlı, ama teknisyenden FARKLI ikinci bir teknisyen — "her
  // teknisyen yalnızca KENDİ işlerini görür" kuralının gerçekten test
  // edilebilmesi için en az iki teknisyen gerekir.
  const otherTeknisyenId = insertUser.run({
    name: 'Diğer Teknisyen',
    role: 'teknisyen',
    sicil_no: '1002',
    password_hash: demoPasswordHash,
    supervisor_id: dispecerId,
  }).lastInsertRowid;

  const insertEquipment = db.prepare(`
    INSERT INTO equipment
      (qr_code, equipment_type, il, ilce, mahalle, location_name, lat, lng, install_date, last_maintenance_date, manufacturer, capacity_info, status, created_at)
    VALUES
      (@qr_code, @equipment_type, @il, @ilce, @mahalle, @location_name, @lat, @lng, @install_date, @last_maintenance_date, @manufacturer, @capacity_info, @status, @created_at)
  `);
  const equipmentId = insertEquipment.run({
    qr_code: 'TEST-0001',
    equipment_type: 'trafo',
    il: 'Erzurum',
    ilce: 'Yakutiye',
    mahalle: 'Merkez Mah.',
    location_name: 'Erzurum / Yakutiye / Merkez Mah.',
    lat: 39.9086,
    lng: 41.2769,
    install_date: '2020-01-01',
    last_maintenance_date: '2023-01-01',
    manufacturer: 'ABB',
    capacity_info: '400 kVA',
    status: 'aktif',
    created_at: now,
  }).lastInsertRowid;

  const insertWorkOrder = db.prepare(`
    INSERT INTO work_orders
      (title, description, status, priority, il, ilce, mahalle, location_name, lat, lng, assigned_user_id, equipment_id, created_at, updated_at)
    VALUES
      (@title, @description, @status, @priority, @il, @ilce, @mahalle, @location_name, @lat, @lng, @assigned_user_id, @equipment_id, @created_at, @updated_at)
  `);

  const ownWorkOrderId = insertWorkOrder.run({
    title: 'Test Teknisyene Ait İş Emri',
    description: 'seedMinimalTestData tarafından oluşturuldu.',
    status: 'acik',
    priority: 'normal',
    il: 'Erzurum',
    ilce: 'Yakutiye',
    mahalle: 'Merkez Mah.',
    location_name: 'Erzurum / Yakutiye / Merkez Mah.',
    lat: 39.9086,
    lng: 41.2769,
    assigned_user_id: teknisyenId,
    equipment_id: equipmentId,
    created_at: now,
    updated_at: now,
  }).lastInsertRowid;

  // Görünürlük filtresinin GERÇEKTEN filtrelediğini (yalnızca "boş liste her
  // zaman geçer" gibi yanlış-pozitif bir testi değil) kanıtlamak için, teknisyene
  // atanmamış bu ikinci iş emri kasıtlı olarak eklendi.
  const otherWorkOrderId = insertWorkOrder.run({
    title: 'Diğer Teknisyene Ait İş Emri',
    description: 'seedMinimalTestData tarafından oluşturuldu.',
    status: 'acik',
    priority: 'normal',
    il: 'Erzurum',
    ilce: 'Yakutiye',
    mahalle: 'Merkez Mah.',
    location_name: 'Erzurum / Yakutiye / Merkez Mah.',
    lat: 39.9086,
    lng: 41.2769,
    assigned_user_id: otherTeknisyenId,
    equipment_id: equipmentId,
    created_at: now,
    updated_at: now,
  }).lastInsertRowid;

  return {
    demoPassword: DEMO_PASSWORD,
    users: { yoneticiId, dispecerId, teknisyenId, otherTeknisyenId },
    equipmentId,
    workOrders: { ownWorkOrderId, otherWorkOrderId },
  };
}

module.exports = { resetTestDatabase, seedMinimalTestData, DEMO_PASSWORD };
