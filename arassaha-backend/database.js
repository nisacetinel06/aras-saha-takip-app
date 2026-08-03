// SQLite veritabanı bağlantısı ve şema kurulumu.
// Node.js'in yerleşik node:sqlite modülü (DatabaseSync) kullanılıyor; better-sqlite3 ile
// aynı senkron API'ye (prepare/run/get/all) sahip olduğu için ek native derleme gerektirmez.
const path = require('path');
const { DatabaseSync } = require('node:sqlite');

const dbPath = path.join(__dirname, 'aras_saha.db');
const db = new DatabaseSync(dbPath);

db.exec('PRAGMA foreign_keys = ON');

db.exec(`
  -- supervisor_id: hiyerarşik yetkilendirme (Modül 7 devamı). Bir teknisyenin
  -- supervisor_id'si kendi dispeçerine işaret eder; dispeçerlerinki de
  -- yöneticiye işaret edebilir. Bu sayede "her dispeçer yalnızca kendi
  -- ekibindeki teknisyenlerin verisini görür" kuralı tek bir alanla kurulur.
  -- photo_path/phone/email: Profil ve Kullanıcı Yönetimi (Modül 8). Kullanıcı
  -- kendi profilini yalnızca GÖRÜNTÜLER; bu alanları yalnızca yönetici,
  -- Kullanıcı Yönetimi panelinden değiştirebilir (bkz. routes/users.js).
  -- is_active: yönetici bir kullanıcıyı GERÇEKTEN silmez (geçmiş iş
  -- emirleri/İSG bildirimleri gibi FK bağları kopmasın diye), yalnızca
  -- pasif hale getirir — DELETE /api/users/:id bu yüzden aslında bir
  -- soft-delete'tir.
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'teknisyen',
    sicil_no TEXT UNIQUE,
    password_hash TEXT,
    supervisor_id INTEGER REFERENCES users (id),
    photo_path TEXT,
    phone TEXT,
    email TEXT,
    is_active INTEGER NOT NULL DEFAULT 1
  );

  -- Ekipman / Envanter (Modül 4) — bkz. ARCHITECTURE.md ve DESIGN_SYSTEM.md.
  -- Bu tablodaki install_date / last_maintenance_date alanları ve
  -- equipment_history üzerinden sayılabilecek geçmiş arıza adedi BİLİNÇLİ
  -- olarak buradadır: ileride eklenecek Arıza Risk Tahmini (Makine Öğrenmesi)
  -- modülü, "ekipman yaşı" ve "son bakımdan bu yana geçen süre" gibi
  -- özellikleri (feature) doğrudan bu alanlardan türetecektir — bugün sadece
  -- envanter görüntüleme için kullanılıyor olsalar da şema bu yüzden bu
  -- şekilde tasarlandı.
  -- il/ilce/mahalle: konumun YAPISAL/gerçek kaynağı (bkz. utils/location.js).
  -- location_name bu üçünün formatLocationName() ile üretilmiş, geriye dönük
  -- uyumluluk için hâlâ tutulan insan-okunabilir birleşimidir — elle ayrıca
  -- girilmez, her zaman il/ilce/mahalle yazılırken aynı fonksiyonla türetilir.
  CREATE TABLE IF NOT EXISTS equipment (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    qr_code TEXT NOT NULL UNIQUE,
    equipment_type TEXT NOT NULL,
    il TEXT,
    ilce TEXT,
    mahalle TEXT,
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

  -- il/ilce/mahalle/location_name: bir iş emri OLUŞTURULDUĞU ANDA bağlı
  -- olduğu equipment kaydından KOPYALANIR (bkz. routes/workOrders.js POST /) —
  -- iş emrinin kendi konumu asla elle girilmez/değiştirilemez. Bu alanların
  -- ekipmandan AYRICA bir kopyası olarak (ekipmana canlı bir JOIN yerine)
  -- saklanması bilinçlidir: ekipmanın konumu ileride değişse bile, bu iş
  -- emrinin AÇILDIĞI ANDAKİ konum sabit kalır — geçmişe dönük raporlama
  -- için doğru olan budur.
  CREATE TABLE IF NOT EXISTS work_orders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    description TEXT,
    status TEXT NOT NULL DEFAULT 'acik',
    priority TEXT NOT NULL DEFAULT 'normal',
    il TEXT,
    ilce TEXT,
    mahalle TEXT,
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

  -- Kullanıcı Yönetimi işlem geçmişi (Modül 8 devamı — hesap verebilirlik).
  -- device_action_logs ile AYNI desen: "kim, ne zaman, hangi kullanıcıya ne
  -- yaptı" kaydı. Yönetimsel her aksiyonda (oluşturma, güncelleme,
  -- pasifleştirme, aktifleştirme, şifre sıfırlama, rol değiştirme) otomatik
  -- bir satır eklenir — bkz. routes/users.js logUserAction().
  CREATE TABLE IF NOT EXISTS user_action_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    target_user_id INTEGER NOT NULL,
    action_type TEXT NOT NULL,
    performed_by TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (target_user_id) REFERENCES users (id)
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

  -- Kayıp-Kaçak / Anormal Tüketim Tespiti (Modül 11) — bkz. routes/anomaly.js
  -- ve arassaha-ml/. Her sayaç (equipment_type='sayac') ekipmanının son 12
  -- aylık HAM aylık tüketim geçmişini tutar; diğer ekipman tipleri için
  -- anlamsızdır. Bu veri, gerçek bir AMI/akıllı sayaç okuma sistemi elimizde
  -- olmadığı için SENTETİK olarak arassaha-ml/generate_consumption_data.py
  -- tarafından üretilip hem bu tabloya hem de model eğitimi için
  -- consumption_training_data.csv'ye yazılır (bkz. arassaha-ml/README.md
  -- Modül 11 "Dürüstlük Notu").
  CREATE TABLE IF NOT EXISTS meter_consumption (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    equipment_id INTEGER NOT NULL,
    year_month TEXT NOT NULL,
    consumption_kwh REAL NOT NULL,
    FOREIGN KEY (equipment_id) REFERENCES equipment (id)
  );

  -- equipment_risk_scores (Modül 9) ile AYNI desen: her sayacın EN GÜNCEL
  -- anomali skorunu tutar (equipment_id UNIQUE'tir, yeni bir hesaplama geçmiş
  -- kaydı biriktirmez). Skoru üreten IsolationForest modeli kara kutu olduğu
  -- için detected_reason, tahmin anında (routes/anomaly.js) hesaplanan kural
  -- tabanlı, insan tarafından okunabilir bir açıklama taşır — "neden şüpheli"
  -- sorusuna somut bir yanıt vermek için.
  CREATE TABLE IF NOT EXISTS meter_anomaly_scores (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    equipment_id INTEGER NOT NULL UNIQUE,
    anomaly_score INTEGER NOT NULL,
    is_suspicious INTEGER NOT NULL,
    detected_reason TEXT,
    computed_at TEXT NOT NULL,
    FOREIGN KEY (equipment_id) REFERENCES equipment (id)
  );

  -- Bildirim Sistemi (Modül 6) — bkz. utils/notify.js ve routes/notifications.js.
  -- Gerçek bir push (FCM vb.) altyapısı KURULMADI: bu tablo, Flutter tarafının
  -- periyodik olarak (30 sn) yokladığı (polling) GET /api/notifications/unread-count
  -- ile okunur ve artış tespit edilirse cihazda flutter_local_notifications ile
  -- gerçek bir OS bildirimi gösterilir (bkz. lib/services/local_notification_service.dart).
  -- Bir staj projesi için FCM'in gerektirdiği sunucu anahtarı/proje kurulumu
  -- gereksiz karmaşıklık katar; polling + yerel bildirim aynı kullanıcı deneyimini
  -- (cihazın bildirim çubuğunda gerçek bir bildirim) çok daha basit bir altyapıyla verir.
  -- related_type: 'work_order' | 'isg_report' | 'equipment' — related_id bu tabloya
  -- göre yorumlanır (uygulama tarafında ilgili detay ekranına yönlendirme için).
  CREATE TABLE IF NOT EXISTS notifications (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    message TEXT NOT NULL,
    related_type TEXT NOT NULL,
    related_id INTEGER NOT NULL,
    is_read INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users (id)
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

// Migrasyon: hiyerarşik yetkilendirme (dispeçer -> yalnızca kendi
// teknisyenlerini görür) için sonradan eklenen supervisor_id sütunu.
const hasSupervisorId = userColumns.some((col) => col.name === 'supervisor_id');
if (!hasSupervisorId) {
  db.exec('ALTER TABLE users ADD COLUMN supervisor_id INTEGER REFERENCES users (id)');
}

// Migrasyon: Profil ve Kullanıcı Yönetimi (Modül 8) için sonradan eklenen
// sütunlar — mevcut aras_saha.db dosyasını silmeden geçilebilsin diye.
const userColumnAdditions = {
  photo_path: 'TEXT',
  phone: 'TEXT',
  email: 'TEXT',
  is_active: 'INTEGER NOT NULL DEFAULT 1',
};
for (const [column, type] of Object.entries(userColumnAdditions)) {
  if (!userColumns.some((col) => col.name === column)) {
    db.exec(`ALTER TABLE users ADD COLUMN ${column} ${type}`);
  }
}

// Migrasyon: Konum Tutarlılığı (il/ilçe/mahalle yapısal alanları) — hem
// equipment hem work_orders için sonradan eklendi (bkz. utils/location.js).
// Eskiden bu tablolarda yalnızca serbest metin location_name vardı.
const equipmentColumns = db.prepare('PRAGMA table_info(equipment)').all();
const equipmentColumnAdditions = { il: 'TEXT', ilce: 'TEXT', mahalle: 'TEXT' };
for (const [column, type] of Object.entries(equipmentColumnAdditions)) {
  if (!equipmentColumns.some((col) => col.name === column)) {
    db.exec(`ALTER TABLE equipment ADD COLUMN ${column} ${type}`);
  }
}

const workOrderColumns = db.prepare('PRAGMA table_info(work_orders)').all();
const workOrderColumnAdditions = { il: 'TEXT', ilce: 'TEXT', mahalle: 'TEXT' };
for (const [column, type] of Object.entries(workOrderColumnAdditions)) {
  if (!workOrderColumns.some((col) => col.name === column)) {
    db.exec(`ALTER TABLE work_orders ADD COLUMN ${column} ${type}`);
  }
}

module.exports = db;
