// SQLite veritabanı bağlantısı ve şema kurulumu.
// Node.js'in yerleşik node:sqlite modülü (DatabaseSync) kullanılıyor; better-sqlite3 ile
// aynı senkron API'ye (prepare/run/get/all) sahip olduğu için ek native derleme gerektirmez.
const path = require('path');
const { DatabaseSync } = require('node:sqlite');

// Test izolasyonu: NODE_ENV=test iken gerçek aras_saha.db dosyası HİÇ
// açılmaz — bellek içi (:memory:) ayrı bir veritabanı kullanılır. Böylece
// test suite'i (bkz. test/) production verisine asla dokunamaz; her test
// süreci kendi boş, sıfırdan şemasıyla başlar. DB_PATH varsa (yalnızca elle,
// debug amaçlı set edilir — bkz. README "Testler" bölümü) her şeyin önüne
// geçer; bu, bir test hatasını incelerken veritabanının son halini gözle
// görülebilir bir dosyada tutabilmek için bilinçli bir kaçış kapısıdır.
function resolveDbPath() {
  if (process.env.DB_PATH) {
    return process.env.DB_PATH; // elle override edilmişse öncelik bunda
  }
  if (process.env.NODE_ENV === 'test') {
    return ':memory:';
  }
  return path.join(__dirname, 'aras_saha.db'); // production varsayılanı, DEĞİŞMİYOR
}

const db = new DatabaseSync(resolveDbPath());

// KRİTİK: foreign key kısıtlamaları klasik SQLite C API'sinde (ve
// better-sqlite3 gibi sarmalayıcılarda) varsayılan olarak KAPALI gelir, her
// bağlantıda ayrı ayrı açılması gerekir. (Not: node:sqlite'ın DatabaseSync'i
// Node 24'te bunu zaten ön tanımlı ON getiriyor — bkz. `db.prepare('PRAGMA
// foreign_keys').get()` — ama bu, node:sqlite'ın belgelenmemiş/versiyona
// bağlı bir iç davranışı; ileride değişebilir. Bu satır o varsayıma
// GÜVENMEMEK için bilerek/açıkça tekrar set eder.) Bu satır atlanır/OFF
// yapılırsa aşağıdaki tüm FOREIGN KEY tanımları sessizce hiçbir şey yapmaz —
// bkz. test/integration/dbConstraints.test.js: bu satır bilerek `OFF`
// yapılıp testin gerçekten kırmızıya döndüğü doğrulandı (ardından geri
// alındı), yani mock değil gerçek bir motor davranışını doğruluyor.
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
    assigned_by_user_id INTEGER,
    equipment_id INTEGER,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (assigned_user_id) REFERENCES users (id),
    FOREIGN KEY (assigned_by_user_id) REFERENCES users (id),
    FOREIGN KEY (equipment_id) REFERENCES equipment (id)
  );

  -- photo_path NULLABLE'dır (başlangıçta NOT NULL'du — bkz. aşağıdaki KVKK
  -- migrasyon notu): KVKK 'tum_kisisel_verilerimi_sil' onayında, kaydın
  -- kendisi SİLİNMEDEN yalnızca fotoğrafın diskteki dosyası + bu referansı
  -- temizlenebilsin diye (bkz. routes/kvkk.js).
  CREATE TABLE IF NOT EXISTS work_order_photos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    work_order_id INTEGER NOT NULL,
    photo_path TEXT,
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

  -- Kestirimci Bakım Planlama (Modül 12) — bkz. routes/maintenance.js.
  -- ÖNEMLİ AYRIM: Bu tablo bir ML modelinin çıktısı DEĞİLDİR. Modül 9'un
  -- ürettiği equipment_risk_scores.risk_score'u okuyup SABİT eşiklerle
  -- (kural tabanlı) bir bakım önerisine çeviren bir iş mantığı/otomasyon
  -- katmanıdır — bkz. routes/maintenance.js üstündeki not.
  -- risk_score_at_creation: önerinin üretildiği/son güncellendiği andaki skor
  -- (geçmişe dönük "neden önerildi" sorusuna cevap verebilmek için donmuş bir
  -- kopyadır; equipment_risk_scores güncellenmeye devam etse de bu değişmez).
  -- related_work_order_id: öneri bir iş emrine dönüştürüldüğünde doldurulur,
  -- aksi halde NULL kalır.
  CREATE TABLE IF NOT EXISTS maintenance_recommendations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    equipment_id INTEGER NOT NULL,
    risk_score_at_creation INTEGER NOT NULL,
    urgency_level TEXT NOT NULL,
    recommended_date TEXT NOT NULL,
    reason TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'onerildi',
    related_work_order_id INTEGER,
    created_at TEXT NOT NULL,
    FOREIGN KEY (equipment_id) REFERENCES equipment (id),
    FOREIGN KEY (related_work_order_id) REFERENCES work_orders (id)
  );

  -- Malzeme / Yedek Parça Stok Takibi (Modül 13) — bkz. routes/materials.js.
  -- compatible_equipment_types: virgülle ayrılmış equipment.equipment_type
  -- değerleri (örn. "trafo,kesici") — ayrı bir ilişki tablosu yerine BİLİNÇLİ
  -- olarak düz metin tutuldu; bu, "hangi malzeme türü hangi ekipmanla tipik
  -- olarak kullanılır" bilgisi yalnızca ARAMA SIRALAMASINI iyileştiren bir
  -- ipucu (bkz. MaterialPickerField) — normalize edilmiş bir zorunluluk/kısıt
  -- değil, bu yüzden N:N tablo karmaşıklığına gerek yok.
  -- unit_cost: nullable — raporlama için gerçekçilik katar ama zorunlu değil.
  CREATE TABLE IF NOT EXISTS materials (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    category TEXT NOT NULL,
    unit TEXT NOT NULL,
    stock_quantity REAL NOT NULL DEFAULT 0,
    min_stock_threshold REAL NOT NULL DEFAULT 0,
    compatible_equipment_types TEXT,
    unit_cost REAL,
    created_at TEXT NOT NULL
  );

  -- Bir iş emrinde hangi malzemeden ne kadar kullanıldığının kaydı. Bu tablo
  -- yalnızca "kim ne kaydetti" bilgisini tutar; STOK DÜŞÜRME işleminin kendisi
  -- (materials.stock_quantity güncellemesi) routes/materials.js'te AYNI
  -- transaction içinde yapılır — bkz. o dosyadaki not.
  CREATE TABLE IF NOT EXISTS work_order_materials (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    work_order_id INTEGER NOT NULL,
    material_id INTEGER NOT NULL,
    quantity_used REAL NOT NULL,
    recorded_by_user_id INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (work_order_id) REFERENCES work_orders (id),
    FOREIGN KEY (material_id) REFERENCES materials (id),
    FOREIGN KEY (recorded_by_user_id) REFERENCES users (id)
  );

  -- Stok hareketi izlenebilirliği — device_action_logs/user_action_logs ile
  -- AYNI "işlem geçmişi" deseni. quantity İŞARETLİ tutulur: kullanımda NEGATİF,
  -- ikmalde POZİTİF — böylece tek bir alan hem yönü hem miktarı taşır, ayrı
  -- bir "yön" sütununa gerek kalmaz.
  CREATE TABLE IF NOT EXISTS material_stock_movements (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    material_id INTEGER NOT NULL,
    movement_type TEXT NOT NULL,
    quantity REAL NOT NULL,
    related_work_order_id INTEGER,
    performed_by_user_id INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (material_id) REFERENCES materials (id),
    FOREIGN KEY (related_work_order_id) REFERENCES work_orders (id),
    FOREIGN KEY (performed_by_user_id) REFERENCES users (id)
  );

  -- Bildirim Sistemi (Modül 6) — bkz. utils/notify.js ve routes/notifications.js.
  -- Gerçek bir push (FCM vb.) altyapısı KURULMADI: bu tablo, Flutter tarafının
  -- periyodik olarak (30 sn) yokladığı (polling) GET /api/notifications/unread-count
  -- ile okunur ve artış tespit edilirse cihazda flutter_local_notifications ile
  -- gerçek bir OS bildirimi gösterilir (bkz. lib/services/local_notification_service.dart).
  -- Bir staj projesi için FCM'in gerektirdiği sunucu anahtarı/proje kurulumu
  -- gereksiz karmaşıklık katar; polling + yerel bildirim aynı kullanıcı deneyimini
  -- (cihazın bildirim çubuğunda gerçek bir bildirim) çok daha basit bir altyapıyla verir.
  -- related_type: 'work_order' | 'isg_report' | 'equipment' | 'material' —
  -- related_id bu tabloya göre yorumlanır (uygulama tarafında ilgili detay
  -- ekranına yönlendirme için). 'material': Modül 13 — bir malzemenin stoğu
  -- kritik seviyenin altına düştüğünde (bkz. routes/materials.js).
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

  -- Basit Kullanım Analitiği (UX standardizasyonu turu, bölüm E) — ücretli/
  -- harici bir ısı haritası aracı yerine hafif bir kullanım logu. Gerçek bir
  -- analitik SDK'sı (Firebase Analytics, Mixpanel vb.) DEĞİLDİR — yalnızca
  -- "hangi ekran ne sıklıkla açılıyor, hangi buton ne sıklıkla tıklanıyor"
  -- sorusuna cevap veren, kendi veritabanımızdaki bir sayaç tablosudur.
  -- user_id NULL olabilir: teorik olarak auth olmadan da (örn. login ekranı)
  -- bir gün loglanmak istenebilir diye nullable bırakıldı, ama pratikte bu
  -- router zaten verifyToken arkasında mount edildiği için (bkz. server.js)
  -- şu an her zaman dolu gelir.
  CREATE TABLE IF NOT EXISTS usage_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER,
    event_type TEXT NOT NULL,
    screen_name TEXT NOT NULL,
    element_name TEXT,
    created_at TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users (id)
  );

  -- AI Asistan / Sohbet Arayüzü (Modül 16) — bkz. routes/assistant.js ve
  -- services/assistantService.js. Hem kullanıcı mesajlarını hem asistan
  -- yanıtlarını (role='user'|'assistant') AYNI tabloda, gönderilme sırasına
  -- göre tutar — Flutter tarafı GET /api/assistant/history ile tek bir
  -- sorguda tüm sohbeti kronolojik çekip render eder, ayrı bir "eşleştirme"
  -- mantığına gerek kalmaz.
  CREATE TABLE IF NOT EXISTS chat_messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    role TEXT NOT NULL,
    message TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users (id)
  );

  -- Ayarlar / Çevrimdışı Mod (Modül 17) — bkz. routes/workOrders.js
  -- PATCH /:id/status ve arassaha_flutter/lib/services/offline_queue_service.dart.
  -- Flutter tarafındaki çevrimdışı kuyruk, bağlantı geri geldiğinde bekleyen
  -- bir işlemi (örn. durum güncellemesi) senkronize eder; bu istek ağ
  -- hatası/timeout nedeniyle sunucuda BAŞARIYLA işlenip yanıtı istemciye hiç
  -- ulaşmayabilir — istemci bunu "başarısız" sanıp AYNI client_action_id ile
  -- tekrar dener. response_json, ikinci denemede işlemi TEKRAR UYGULAMADAN
  -- (örn. iki kez bildirim göndermeden) İLK seferki gerçek sonucu aynen geri
  -- dönebilmek için saklanır — bkz. PATCH /:id/status üzerindeki not.
  CREATE TABLE IF NOT EXISTS processed_client_actions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    client_action_id TEXT NOT NULL UNIQUE,
    response_json TEXT NOT NULL,
    created_at TEXT NOT NULL
  );

  -- Login brute-force koruması — bkz. middleware/loginRateLimit.js ve
  -- routes/auth.js. sicil_no bilerek bir FOREIGN KEY DEĞİL (users.sicil_no'ya
  -- işaret etmiyor): var olmayan bir sicil_no ile yapılan denemeler de burada
  -- kaydedilip sayılabilmeli (kilit, kullanıcı numaralandırmayı önlemek için
  -- hesabın gerçekten var olup olmadığından BAĞIMSIZ çalışır). ip_address
  -- her zaman req.ip'dir — Railway gibi bir proxy arkasında doğru çalışması
  -- server.js'teki 'trust proxy' ayarına bağlıdır.
  CREATE TABLE IF NOT EXISTS login_attempts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sicil_no TEXT NOT NULL,
    ip_address TEXT NOT NULL,
    success INTEGER NOT NULL,
    created_at TEXT NOT NULL
  );

  -- KVKK Uyum Modülü — bkz. routes/kvkk.js. request_type:
  -- 'profil_fotografi_sil' | 'tum_kisisel_verilerimi_sil'. status:
  -- 'beklemede' | 'onaylandi' | 'reddedildi' | 'tamamlandi' ('onaylandi' bu
  -- akışta fiilen kullanılmaz çünkü onay VE anonimleştirme routes/kvkk.js'te
  -- TEK bir işlemde/senkron olarak yapılır — onaylanan bir talep doğrudan
  -- 'tamamlandi' olur; alan yine de ileride "onaylandı ama işlenmesi
  -- gecikti" gibi bir ara duruma geçilebilsin diye şemada tutulur).
  CREATE TABLE IF NOT EXISTS data_deletion_requests (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    request_type TEXT NOT NULL,
    reason TEXT,
    status TEXT NOT NULL DEFAULT 'beklemede',
    reviewer_note TEXT,
    reviewed_by_user_id INTEGER,
    created_at TEXT NOT NULL,
    reviewed_at TEXT,
    completed_at TEXT,
    FOREIGN KEY (user_id) REFERENCES users (id),
    FOREIGN KEY (reviewed_by_user_id) REFERENCES users (id)
  );

  -- Dosya Temizleme (Orphan + Saklama Süresi) Görevleri — bkz. jobs/orphanFilePurge.js,
  -- jobs/retentionPurge.js. Yalnızca GERÇEK silme işlemlerinde (dry-run
  -- DEĞİLKEN) bir satır eklenir — "ne zaman, neden, hangi dosya silindi"
  -- sorusunun sonradan cevaplanabilmesi için (hem denetim hem de yanlış bir
  -- silme şüphesi doğarsa geriye dönük inceleme). related_table/related_record_id
  -- yalnızca saklama süresi silmelerinde (silinen dosyanın hangi DB satırına
  -- ait olduğu bilindiği için) dolar; orphan silmelerinde NULL kalır — o
  -- dosyanın TANIM GEREĞİ hiçbir DB kaydına bağlı olmadığı zaten bilinir.
  -- FOREIGN KEY YOK (bilerek): related_record_id'nin işaret ettiği satır
  -- (örn. bir isg_reports satırı) ileride başka bir sebeple silinse bile
  -- (bu tabloda satır silme YOK ama teoride) bu log kaydı KALICI/bağımsız
  -- kalmalı — bir denetim izi hiçbir zaman kaynağına bağımlı olmamalı.
  CREATE TABLE IF NOT EXISTS file_purge_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT,
    related_table TEXT,
    related_record_id INTEGER,
    reason TEXT NOT NULL,
    deleted_at TEXT NOT NULL
  );

  -- İki Faktörlü Doğrulama (2FA) — bkz. routes/twoFactor.js. Her kod TEK
  -- KULLANIMLIKTIR (used=1 olduktan sonra bir daha ASLA kabul edilmez, bkz.
  -- POST /2fa/verify). code_hash password_hash ile AYNI ilke (bcrypt) —
  -- yedek kodlar totp_secret'ten FARKLI olarak yalnızca BİR KEZ, tek yönlü
  -- karşılaştırılır (kullanıcı tekrar giremez), bu yüzden düz metin değil
  -- HASH olarak saklanmaları güvenlik açısından hiçbir sakınca doğurmaz.
  CREATE TABLE IF NOT EXISTS totp_backup_codes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    code_hash TEXT NOT NULL,
    used INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users (id)
  );

  -- 2FA doğrulama (POST /2fa/verify) brute-force koruması — login_attempts
  -- ile AYNI şema/desen (bkz. middleware/rateLimiting.js), ama AYRI bir
  -- tabloda: burada "kimlik" (identifier) sicil_no değil user_id'dir —
  -- pending_token zaten doğrulanmış (imzası geçerli) bir JWT'den geldiği
  -- için kullanıcının GERÇEKTEN var olduğu baştan bilinir; login_attempts'taki
  -- "var olmayan sicil_no" enumeration kaygısı burada uygulanabilir değildir.
  CREATE TABLE IF NOT EXISTS two_factor_verify_attempts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    ip_address TEXT NOT NULL,
    success INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users (id)
  );
`);

// Denetim Logu Toplayıcı (bkz. services/auditLogAggregator.js) — PERFORMANS.
// Toplayıcı, bu 6 tabloyu UNION ALL ile birleştirip HER ZAMAN timestamp'e
// göre (DESC) sıralayıp filtreliyor; veri arttıkça (özellikle login_attempts
// gibi her giriş denemesinde yazılan bir tabloda) bu sütunlarda index
// OLMADAN yapılan bir tam tablo taraması (full table scan) gözle görülür
// biçimde yavaşlar. `IF NOT EXISTS` ile idempotent — var olan bir
// production veritabanında da güvenle tekrar çalıştırılabilir.
db.exec(`
  CREATE INDEX IF NOT EXISTS idx_device_action_logs_created_at ON device_action_logs (created_at);
  CREATE INDEX IF NOT EXISTS idx_user_action_logs_created_at ON user_action_logs (created_at);
  CREATE INDEX IF NOT EXISTS idx_login_attempts_created_at ON login_attempts (created_at);
  CREATE INDEX IF NOT EXISTS idx_data_deletion_requests_created_at ON data_deletion_requests (created_at);
  CREATE INDEX IF NOT EXISTS idx_data_deletion_requests_reviewed_at ON data_deletion_requests (reviewed_at);
  CREATE INDEX IF NOT EXISTS idx_file_purge_log_deleted_at ON file_purge_log (deleted_at);
  CREATE INDEX IF NOT EXISTS idx_material_stock_movements_created_at ON material_stock_movements (created_at);
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
//
// totp_secret/totp_enabled — İki Faktörlü Doğrulama (2FA), bkz. routes/twoFactor.js.
// GÜVENLİK NOTU: totp_secret şifre (password_hash) gibi TEK YÖNLÜ hash'lenemez
// — TOTP algoritması her doğrulamada bu secret'ı kullanarak KENDİSİ tekrar
// bir kod üretip karşılaştırma yapar (bcrypt gibi bir hash'ten orijinal
// secret geri elde edilemeyeceği için bu işlem hash ile YAPILAMAZ). Bu
// PROTOTİPTE totp_secret BİLİNÇLİ olarak düz metin saklanıyor; gerçek bir
// üretim sisteminde bu alanın uygulama seviyesinde (örn. AES-256-GCM ile,
// veritabanı dosyasından AYRI/harici bir encryption key kullanarak)
// şifrelenmesi GEREKİR — bkz. README.md "Bilinen Kısıtlar" bölümü.
const userColumnAdditions = {
  photo_path: 'TEXT',
  phone: 'TEXT',
  email: 'TEXT',
  is_active: 'INTEGER NOT NULL DEFAULT 1',
  totp_secret: 'TEXT',
  totp_enabled: 'INTEGER NOT NULL DEFAULT 0',
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
// assigned_by_user_id (SEC-03 devamı — "bu işi bana kim verdi" şeffaflığı):
// NULLABLE, FOREIGN KEY tanımı olmadan eklenir çünkü SQLite'ta ALTER TABLE
// ADD COLUMN bir REFERENCES kısıtlaması EKLEYEMEZ (yalnızca CREATE TABLE
// anında tanımlanabilir) — bu, mevcut/production aras_saha.db dosyalarında
// bu sütun eksikken de sorunsuz çalışır. Var olan (bu değişiklikten önce
// oluşturulmuş) kayıtlarda bu alan NULL kalır; routes/workOrders.js ve
// Flutter tarafı bunu "eski kayıt, atayan bilgisi mevcut değil" olarak ele
// alır, hata FIRLATMAZ.
const workOrderColumnAdditions = { il: 'TEXT', ilce: 'TEXT', mahalle: 'TEXT', assigned_by_user_id: 'INTEGER' };
for (const [column, type] of Object.entries(workOrderColumnAdditions)) {
  if (!workOrderColumns.some((col) => col.name === column)) {
    db.exec(`ALTER TABLE work_orders ADD COLUMN ${column} ${type}`);
  }
}

// Migrasyon: Kestirimci Bakım Planlama (Modül 12) — arıza iş emirlerini
// önleyici bakım iş emirlerinden ayırt etmek için sonradan eklenen sütunlar.
// source_type'ı olmayan (yani sütun yeni eklenmiş) TÜM mevcut kayıtlar geriye
// dönük uyumluluk için 'ariza' kabul edilir — bu proje Modül 12'den önce
// yalnızca arıza iş emirleri üretiyordu, bu yüzden bu varsayım kesindir.
const hasSourceType = workOrderColumns.some((col) => col.name === 'source_type');
if (!hasSourceType) {
  db.exec("ALTER TABLE work_orders ADD COLUMN source_type TEXT NOT NULL DEFAULT 'ariza'");
  db.exec("ALTER TABLE work_orders ADD COLUMN source_recommendation_id INTEGER REFERENCES maintenance_recommendations (id)");
  db.exec("UPDATE work_orders SET source_type = 'ariza' WHERE source_type IS NULL");
}

// Migrasyon: Görüntü Tabanlı Hasar Tespiti (Modül 15) — İSG bildirimi
// fotoğrafı VE iş emri fotoğrafları için sonradan eklenen CV analiz sonucu
// sütunları. İkisi de nullable: arassaha-ml servisi kapalıysa/hata dönerse
// (bkz. utils/damageDetection.js) bu alanlar null kalır — fotoğraf
// yükleme/bildirim oluşturma işlemi CV analizinin sonucunu ASLA beklemez.
const cvColumnAdditions = { cv_is_damaged: 'INTEGER', cv_damage_probability: 'REAL' };

const isgReportColumns = db.prepare('PRAGMA table_info(isg_reports)').all();
for (const [column, type] of Object.entries(cvColumnAdditions)) {
  if (!isgReportColumns.some((col) => col.name === column)) {
    db.exec(`ALTER TABLE isg_reports ADD COLUMN ${column} ${type}`);
  }
}

const workOrderPhotoColumns = db.prepare('PRAGMA table_info(work_order_photos)').all();
for (const [column, type] of Object.entries(cvColumnAdditions)) {
  if (!workOrderPhotoColumns.some((col) => col.name === column)) {
    db.exec(`ALTER TABLE work_order_photos ADD COLUMN ${column} ${type}`);
  }
}

// Migrasyon: KVKK Uyum Modülü (bkz. routes/kvkk.js) — 'tum_kisisel_verilerimi_sil'
// onayında, bir kullanıcıya atanmış iş emirlerindeki fotoğraflar diskten
// silinip work_order_photos.photo_path NULL yapılmalı (KAYDIN KENDİSİ
// SİLİNMEDEN — bkz. kvkk.js başındaki "silme vs anonimleştirme" ayrımı).
// photo_path ilk kurulumda NOT NULL tanımlanmıştı; SQLite'ta ALTER TABLE ile
// bir NOT NULL kısıtlaması DOĞRUDAN kaldırılamaz, bu yüzden standart SQLite
// "tabloyu yeniden kur" deseni kullanılır (yeni/gevşetilmiş şemayla tablo
// oluşturulur, veriler kopyalanır, eskisi silinip yenisi eski adını alır).
// Idempotent: yalnızca sütun HÂLÂ NOT NULL ise (notnull === 1) çalışır.
const workOrderPhotoColumnsAfterCv = db.prepare('PRAGMA table_info(work_order_photos)').all();
const photoPathColumnInfo = workOrderPhotoColumnsAfterCv.find((col) => col.name === 'photo_path');
if (photoPathColumnInfo && photoPathColumnInfo.notnull === 1) {
  db.exec('PRAGMA foreign_keys = OFF'); // tablo yeniden kurulurken FK kontrolleri geçici kapatılır
  db.exec('BEGIN');
  try {
    db.exec(`
      CREATE TABLE work_order_photos_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        work_order_id INTEGER NOT NULL,
        photo_path TEXT,
        created_at TEXT NOT NULL,
        cv_is_damaged INTEGER,
        cv_damage_probability REAL,
        FOREIGN KEY (work_order_id) REFERENCES work_orders (id)
      );
    `);
    db.exec(`
      INSERT INTO work_order_photos_new (id, work_order_id, photo_path, created_at, cv_is_damaged, cv_damage_probability)
      SELECT id, work_order_id, photo_path, created_at, cv_is_damaged, cv_damage_probability FROM work_order_photos;
    `);
    db.exec('DROP TABLE work_order_photos;');
    db.exec('ALTER TABLE work_order_photos_new RENAME TO work_order_photos;');
    db.exec('COMMIT');
  } catch (err) {
    db.exec('ROLLBACK');
    throw err;
  } finally {
    db.exec('PRAGMA foreign_keys = ON');
  }
}

// Malzeme / Yedek Parça Stok Takibi (Modül 13) — İLK KURULUM tohum verisi.
// seed.js'teki (work_orders/users/equipment) desenden BİLİNÇLİ olarak farklı:
// seed.js her çalıştırıldığında önce SİLİP yeniden ekliyor (tam demo sıfırlama
// içindir); materials burada yalnızca tablo BOŞSA bir kerelik eklenir —
// böylece sunucu her yeniden başladığında, o ana kadar gerçekten kullanılmış/
// ikmal edilmiş stok verisi (work_order_materials, material_stock_movements)
// asla silinmez. `npm run seed` çalıştırılırsa da bu veriler zaten var
// olduğu için (count > 0) tekrar eklenmez.
const materialCount = db.prepare('SELECT COUNT(*) AS c FROM materials').get().c;
if (materialCount === 0) {
  const now = new Date().toISOString();
  const seedMaterials = [
    // kablo
    { name: '16mm² NYY Kablo', category: 'kablo', unit: 'metre', stock_quantity: 450, min_stock_threshold: 100, compatible_equipment_types: 'trafo,direk,kesici', unit_cost: 12.5 },
    { name: '25mm² NYY Kablo', category: 'kablo', unit: 'metre', stock_quantity: 320, min_stock_threshold: 100, compatible_equipment_types: 'trafo,direk', unit_cost: 18.0 },
    { name: '4mm² TTR Kablo', category: 'kablo', unit: 'metre', stock_quantity: 80, min_stock_threshold: 100, compatible_equipment_types: 'sayac,direk', unit_cost: 4.5 },
    { name: '50mm² Alüminyum İletken', category: 'kablo', unit: 'metre', stock_quantity: 600, min_stock_threshold: 150, compatible_equipment_types: 'direk', unit_cost: 9.0 },
    // sigorta
    { name: '100A Trafo Sigortası', category: 'sigorta', unit: 'adet', stock_quantity: 22, min_stock_threshold: 10, compatible_equipment_types: 'trafo', unit_cost: 145.0 },
    { name: '200A Trafo Sigortası', category: 'sigorta', unit: 'adet', stock_quantity: 6, min_stock_threshold: 8, compatible_equipment_types: 'trafo', unit_cost: 210.0 },
    { name: '63A Kesici Sigortası', category: 'sigorta', unit: 'adet', stock_quantity: 40, min_stock_threshold: 15, compatible_equipment_types: 'kesici', unit_cost: 65.0 },
    { name: '32A Hat Sigortası', category: 'sigorta', unit: 'adet', stock_quantity: 5, min_stock_threshold: 12, compatible_equipment_types: 'kesici,sayac', unit_cost: 28.0 },
    // izolator
    { name: 'Silindirik Porselen İzolatör', category: 'izolator', unit: 'adet', stock_quantity: 75, min_stock_threshold: 20, compatible_equipment_types: 'direk', unit_cost: 55.0 },
    { name: 'Kompozit Askı İzolatörü', category: 'izolator', unit: 'adet', stock_quantity: 18, min_stock_threshold: 20, compatible_equipment_types: 'direk', unit_cost: 90.0 },
    { name: 'Post İzolatör', category: 'izolator', unit: 'adet', stock_quantity: 30, min_stock_threshold: 10, compatible_equipment_types: 'trafo,direk', unit_cost: 120.0 },
    // konnektor
    { name: 'Bimetal Konnektör 16-25mm²', category: 'konnektor', unit: 'adet', stock_quantity: 200, min_stock_threshold: 50, compatible_equipment_types: 'trafo,direk,kesici,sayac', unit_cost: 8.0 },
    { name: 'Preslik Konnektör', category: 'konnektor', unit: 'adet', stock_quantity: 12, min_stock_threshold: 30, compatible_equipment_types: 'direk,kesici', unit_cost: 15.0 },
    // diger
    { name: 'Ayırıcı Bıçak Seti', category: 'diger', unit: 'adet', stock_quantity: 14, min_stock_threshold: 5, compatible_equipment_types: 'kesici', unit_cost: 320.0 },
    { name: 'Topraklama Çubuğu', category: 'diger', unit: 'adet', stock_quantity: 40, min_stock_threshold: 10, compatible_equipment_types: 'direk,trafo', unit_cost: 60.0 },
    { name: 'Sayaç Mühürü', category: 'diger', unit: 'adet', stock_quantity: 500, min_stock_threshold: 100, compatible_equipment_types: 'sayac', unit_cost: 0.5 },
    { name: 'Trafo Yağı', category: 'diger', unit: 'kg', stock_quantity: 90, min_stock_threshold: 40, compatible_equipment_types: 'trafo', unit_cost: 22.0 },
    { name: 'Kelepçe (Kablo Bağı)', category: 'diger', unit: 'adet', stock_quantity: 8, min_stock_threshold: 20, compatible_equipment_types: 'trafo,direk,kesici,sayac', unit_cost: 1.2 },
  ];

  const insertMaterial = db.prepare(`
    INSERT INTO materials
      (name, category, unit, stock_quantity, min_stock_threshold, compatible_equipment_types, unit_cost, created_at)
    VALUES
      (@name, @category, @unit, @stock_quantity, @min_stock_threshold, @compatible_equipment_types, @unit_cost, @created_at)
  `);
  for (const material of seedMaterials) {
    insertMaterial.run({ ...material, created_at: now });
  }
}

module.exports = db;
