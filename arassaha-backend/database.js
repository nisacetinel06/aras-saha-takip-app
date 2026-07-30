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
    sicil_no TEXT UNIQUE,
    password_hash TEXT
  );

  -- Ekipman / Envanter (Modül 4) — bkz. ARCHITECTURE.md ve DESIGN_SYSTEM.md.
  -- Bu tablodaki install_date / last_maintenance_date alanları ve
  -- equipment_history üzerinden sayılabilecek geçmiş arıza adedi BİLİNÇLİ
  -- olarak buradadır: ileride eklenecek Arıza Risk Tahmini (Makine Öğrenmesi)
  -- modülü, "ekipman yaşı" ve "son bakımdan bu yana geçen süre" gibi
  -- özellikleri (feature) doğrudan bu alanlardan türetecektir — bugün sadece
  -- envanter görüntüleme için kullanılıyor olsalar da şema bu yüzden bu
  -- şekilde tasarlandı.
  CREATE TABLE IF NOT EXISTS equipment (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    qr_code TEXT NOT NULL UNIQUE,
    equipment_type TEXT NOT NULL,
    location_name TEXT,
    lat REAL,
    lng REAL,
    install_date TEXT,
    last_maintenance_date TEXT,
    manufacturer TEXT,
    capacity_info TEXT,
    status TEXT NOT NULL DEFAULT 'aktif',
    created_at TEXT NOT NULL
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
    equipment_id INTEGER,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (assigned_user_id) REFERENCES users (id),
    FOREIGN KEY (equipment_id) REFERENCES equipment (id)
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

  -- İSG (İş Sağlığı ve Güvenliği) Bildirimi (Modül 5) — bkz. routes/isg.js.
  -- reported_by_user_id: prompt'ta serbest metin bir "reported_by" alanı
  -- istenmişti, ancak bu, ARCHITECTURE.md Bölüm 11.1'de "Zorunlu kural"
  -- olarak belirlenmiş ilkeyi (kişi bilgisi hiçbir yerde serbest metin/sabit
  -- isim olamaz, her zaman users tablosuna giden gerçek bir FK olmalı) ihlal
  -- ederdi — work_orders.assigned_user_id ve managed_devices.assigned_user_id
  -- ile aynı tutarlılığı korumak için burada da gerçek bir FK kullanıldı.
  -- photo_path NULL olabilir: seed verisinde gerçek bir fotoğraf dosyası
  -- olmadığı için (Temel Kalite İlkesi — sahte/var olmayan dosya yoluna asla
  -- yer verilmez) seed kayıtlarının fotoğrafı yoktur; gerçek fotoğraflar
  -- yalnızca uygulama üzerinden (POST /api/isg-reports, multipart upload)
  -- eklenir ve o zaman dolar.
  CREATE TABLE IF NOT EXISTS isg_reports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    reported_by_user_id INTEGER NOT NULL,
    description TEXT NOT NULL,
    category TEXT NOT NULL,
    photo_path TEXT,
    location_name TEXT,
    lat REAL NOT NULL,
    lng REAL NOT NULL,
    status TEXT NOT NULL DEFAULT 'bekliyor',
    reviewer_note TEXT,
    created_at TEXT NOT NULL,
    reviewed_at TEXT,
    FOREIGN KEY (reported_by_user_id) REFERENCES users (id)
  );

  -- Arıza Risk Tahmini (Modül 9) — bkz. routes/risk.js ve arassaha-ml/.
  -- Her ekipmanın EN GÜNCEL risk skorunu tutar (equipment_id UNIQUE'tir; yeni
  -- bir hesaplama geçmiş kaydı biriktirmez, var olan satırı günceller). Skoru
  -- üreten model, ayrı bir Python (FastAPI) servisinde çalışır ve SENTETİK
  -- (kural tabanlı üretilmiş) veriyle eğitildi — bkz. arassaha-ml/README.md.
  CREATE TABLE IF NOT EXISTS equipment_risk_scores (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    equipment_id INTEGER NOT NULL UNIQUE,
    risk_score INTEGER NOT NULL,
    risk_level TEXT NOT NULL,
    computed_at TEXT NOT NULL,
    FOREIGN KEY (equipment_id) REFERENCES equipment (id)
  );
`);

// Migrasyon: bu proje ilk kurulduğunda `users` tablosu `password_hash`
// sütunu olmadan oluşturulmuştu (Modül 7 öncesi). `CREATE TABLE IF NOT EXISTS`
// var olan bir tabloya yeni sütun eklemediği için, sütun eksikse burada
// `ALTER TABLE` ile eklenir — mevcut aras_saha.db dosyasını silmeden Modül 7'ye
// geçilebilsin diye.
const userColumns = db.prepare('PRAGMA table_info(users)').all();
const hasPasswordHash = userColumns.some((col) => col.name === 'password_hash');
if (!hasPasswordHash) {
  db.exec('ALTER TABLE users ADD COLUMN password_hash TEXT');
}

module.exports = db;
