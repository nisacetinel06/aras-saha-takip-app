// SQLite veritabanı bağlantısı ve şema kurulumu.
// Node.js'in yerleşik node:sqlite modülü (DatabaseSync) kullanılıyor; better-sqlite3 ile
// aynı senkron API'ye (prepare/run/get/all) sahip olduğu için ek native derleme gerektirmez.
const path = require('path');
const { DatabaseSync } = require('node:sqlite');

const dbPath = path.join(__dirname, 'aras_saha.db');
const db = new DatabaseSync(dbPath);

db.exec('PRAGMA foreign_keys = ON');

db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'teknisyen',
    sicil_no TEXT UNIQUE
  );

  CREATE TABLE IF NOT EXISTS work_orders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    description TEXT,
    status TEXT NOT NULL DEFAULT 'acik',
    priority TEXT NOT NULL DEFAULT 'normal',
    location_name TEXT,
    lat REAL,
    lng REAL,
    assigned_user_id INTEGER,
    equipment_ref TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (assigned_user_id) REFERENCES users (id)
  );

  CREATE TABLE IF NOT EXISTS work_order_photos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    work_order_id INTEGER NOT NULL,
    photo_path TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (work_order_id) REFERENCES work_orders (id)
  );

  -- Cihaz Yönetimi (MDM) modülü — bkz. ARCHITECTURE.md ve DESIGN_SYSTEM.md.
  -- Bu tablo ve ilgili endpoint'ler gerçek bir cihaza komut GÖNDERMEZ; yalnızca
  -- burada tutulan durumu değiştiren bir simülasyondur.
  CREATE TABLE IF NOT EXISTS managed_devices (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    device_name TEXT NOT NULL,
    assigned_user_id INTEGER,
    device_model TEXT,
    os_version TEXT,
    app_version TEXT,
    enrollment_status TEXT NOT NULL DEFAULT 'kayitli',
    compliance_status TEXT NOT NULL DEFAULT 'uyumlu',
    last_sync_at TEXT,
    battery_level INTEGER,
    is_locked INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    FOREIGN KEY (assigned_user_id) REFERENCES users (id)
  );

  CREATE TABLE IF NOT EXISTS device_action_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id INTEGER NOT NULL,
    action_type TEXT NOT NULL,
    performed_by TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (device_id) REFERENCES managed_devices (id)
  );
`);

module.exports = db;
