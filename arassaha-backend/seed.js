// Veritabanına gerçek personel kayıtları, 15 adet sahte iş emri yükler.
// Bu script tekrar çalıştırılabilir olsun diye önce mevcut kayıtları temizler.
const bcrypt = require('bcrypt');
const db = require('./database');
const { formatLocationName } = require('./utils/location');

// Tüm demo kullanıcılar aynı basit şifreyi kullanır — staj sunumu için
// kolay hatırlanır olması önemli, gerçek üretimde bu asla yapılmaz
// (bkz. ARCHITECTURE.md Bölüm 10 "Kimlik doğrulama basittir").
const DEMO_PASSWORD = 'sifre123';
const DEMO_PASSWORD_HASH = bcrypt.hashSync(DEMO_PASSWORD, 10);

const locations = [
  { il: 'Erzurum', ilce: 'Yakutiye', mah: 'Merkez Mah.', lat: 39.9086, lng: 41.2769 },
  { il: 'Erzurum', ilce: 'Palandöken', mah: 'Kültür Mah.', lat: 39.8600, lng: 41.2600 },
  { il: 'Erzurum', ilce: 'Aziziye', mah: 'Ilıca Mah.', lat: 39.9700, lng: 41.1900 },
  { il: 'Erzincan', ilce: 'Merkez', mah: 'Fatih Mah.', lat: 39.7500, lng: 39.4900 },
  { il: 'Erzincan', ilce: 'Üzümlü', mah: 'Bahçeler Mah.', lat: 39.6800, lng: 39.5300 },
  { il: 'Ağrı', ilce: 'Merkez', mah: 'Cumhuriyet Mah.', lat: 39.7191, lng: 43.0503 },
  { il: 'Ağrı', ilce: 'Doğubayazıt', mah: 'İshakpaşa Mah.', lat: 39.5500, lng: 44.0900 },
  { il: 'Kars', ilce: 'Merkez', mah: 'Ortakapı Mah.', lat: 40.6013, lng: 43.0975 },
  { il: 'Kars', ilce: 'Sarıkamış', mah: 'Fevzipaşa Mah.', lat: 40.3300, lng: 42.5900 },
  { il: 'Iğdır', ilce: 'Merkez', mah: 'Aras Mah.', lat: 39.9167, lng: 44.0448 },
  { il: 'Iğdır', ilce: 'Tuzluca', mah: 'Cumhuriyet Mah.', lat: 40.0200, lng: 43.6700 },
  { il: 'Ardahan', ilce: 'Merkez', mah: 'Yenidoğan Mah.', lat: 41.1105, lng: 42.7022 },
  { il: 'Ardahan', ilce: 'Göle', mah: 'Merkez Mah.', lat: 40.7900, lng: 42.6100 },
  { il: 'Bayburt', ilce: 'Merkez', mah: 'Dede Korkut Mah.', lat: 40.2552, lng: 40.2249 },
  { il: 'Bayburt', ilce: 'Demirözü', mah: 'Merkez Mah.', lat: 40.1900, lng: 39.9600 },
];

const titles = [
  'Trafo Arızası',
  'Direk Devrilmesi',
  'Kablo Kopması',
  'Sayaç Arızası',
  'Aşırı Yüklenme',
  'Fırtına Hasarı',
];

// "Kişiler" artık sabit bir isimden değil, gerçek bir `users` tablosu kaydından gelir.
// Bu dizi yalnızca seed (sahte veri üretimi) amacıyla kullanılır; uygulama çalışırken
// hiçbir ekran bu listeyi değil, GET /api/users endpoint'ini kullanır (bkz. ARCHITECTURE.md 11.1).
// sicil_no değerleri kasıtlı olarak sade sayısal (1001, 2001, 3001...) — demo
// sunumunda kolay hatırlanması için (bkz. script sonundaki "DEMO GİRİŞ BİLGİLERİ").
//
// `supervisor`: hiyerarşik yetkilendirme (Modül 7 devamı) — her teknisyenin
// bağlı olduğu dispeçeri, her dispeçerin bağlı olduğu yöneticiyi isimle
// işaret eder. Aşağıda 3 teknisyen Zeynep Arslan'a, 3 teknisyen Elif
// Korkmaz'a bağlı; böylece her dispeçer GERÇEKTEN sadece kendi ekibinin
// verisini görür (tek bir "her şeyi gören dispeçer" yoktur).
const personnelSeed = [
  { name: 'Ahmet Yılmaz', role: 'teknisyen', sicil_no: '1001', supervisor: 'Zeynep Arslan' },
  { name: 'Mehmet Demir', role: 'teknisyen', sicil_no: '1002', supervisor: 'Zeynep Arslan' },
  { name: 'Ayşe Kaya', role: 'teknisyen', sicil_no: '1003', supervisor: 'Zeynep Arslan' },
  { name: 'Fatih Şahin', role: 'teknisyen', sicil_no: '1004', supervisor: 'Elif Korkmaz' },
  { name: 'Emre Çelik', role: 'teknisyen', sicil_no: '1005', supervisor: 'Elif Korkmaz' },
  { name: 'Hakan Yıldız', role: 'teknisyen', sicil_no: '1006', supervisor: 'Elif Korkmaz' },
  { name: 'Zeynep Arslan', role: 'dispecer', sicil_no: '2001', supervisor: 'Murat Öztürk' },
  { name: 'Elif Korkmaz', role: 'dispecer', sicil_no: '2002', supervisor: 'Murat Öztürk' },
  { name: 'Murat Öztürk', role: 'yonetici', sicil_no: '3001', supervisor: null },
];

const priorities = ['acil', 'normal', 'normal', 'dusuk'];

// Her teknisyene TÜM statüleri (özellikle 'cozuldu'yu bol miktarda) içeren
// bir iş emri seti garanti eder — dizideki sıra `personnelSeed`'teki
// teknisyen sırasıyla (yani aşağıdaki `technicianIds` ile) BİREBİR eşleşir.
// Ahmet Yılmaz (index 0, sicil_no 1001 — DEMO GİRİŞ BİLGİLERİ'nde belgelenen
// birincil demo hesabı) fazladan 'cozuldu' alır: "Tamamlanan İş Emirlerim"
// bölümünün sayfalama/sonsuz kaydırmasını (bkz. arassaha_flutter
// completed_work_orders_provider.dart, pageSize=15) GERÇEKTEN test edebilmek
// için en az bir teknisyende bir sayfadan (15) fazla tamamlanmış kayıt
// olması gerekir. Diğer 5 teknisyen de her statüden en az birkaç kayıt alır
// ki hiçbirinin İş Emirleri/Tamamlanan İş Emirlerim listesi boş kalmasın.
const workOrderPlanByTechnicianIndex = [
  { acik: 3, yolda: 2, sahada: 2, cozuldu: 20 }, // Ahmet Yılmaz (1001)
  { acik: 2, yolda: 2, sahada: 1, cozuldu: 3 }, // Mehmet Demir (1002)
  { acik: 2, yolda: 1, sahada: 2, cozuldu: 4 }, // Ayşe Kaya (1003)
  { acik: 1, yolda: 2, sahada: 1, cozuldu: 5 }, // Fatih Şahin (1004)
  { acik: 2, yolda: 1, sahada: 1, cozuldu: 3 }, // Emre Çelik (1005)
  { acik: 1, yolda: 1, sahada: 2, cozuldu: 4 }, // Hakan Yıldız (1006)
];

function expandStatusPlan(plan) {
  const list = [];
  for (const status of ['acik', 'yolda', 'sahada', 'cozuldu']) {
    for (let i = 0; i < plan[status]; i++) list.push(status);
  }
  return list;
}

function randomJitter() {
  // Koordinatı gerçek mahalle sınırları içinde kalacak kadar küçük oynat (~1-2 km).
  return (Math.random() - 0.5) * 0.03;
}

function randomPastDate(maxDaysAgo) {
  const now = Date.now();
  const daysAgo = Math.random() * maxDaysAgo;
  return new Date(now - daysAgo * 24 * 60 * 60 * 1000);
}

function pick(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

function yearsAgoIsoDate(years) {
  // `years` çeyrek yıl (1.5, 2.5 vb.) olabilir; setFullYear tam sayı olmayan
  // değerlerde yanlış sonuç ürettiği için gün bazlı milisaniye hesabı kullanılır.
  return new Date(Date.now() - years * 365.25 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

function monthsAgoIsoDate(months) {
  const d = new Date();
  d.setMonth(d.getMonth() - months);
  return d.toISOString().slice(0, 10);
}

// user_action_logs, users tablosuna FK ile bağlı (Modül 8 devamı — bkz.
// database.js) — users'ı silmeden ÖNCE bu tablo temizlenmeli, aksi halde
// FOREIGN KEY constraint failed hatası alınır.
// notifications, work_orders/isg_reports/users'a FK ile bağlı (Modül 6 — bkz.
// database.js) — bu kayıtlar silinip yeniden oluşturulunca (yeni id'lerle)
// eski bildirim satırları YANLIŞ/var olmayan kayıtlara işaret eder hale
// gelir; bu yüzden diğerleriyle birlikte temizlenir.
db.exec('DELETE FROM notifications');
db.exec('DELETE FROM user_action_logs');
db.exec('DELETE FROM device_action_logs');
db.exec('DELETE FROM managed_devices');
db.exec('DELETE FROM work_order_photos');
// work_order_materials, HEM work_orders HEM materials'a FK'lidir — ikisi de
// aşağıda silinip yeni id'lerle yeniden oluşturulacağı için (bkz. aşağıdaki
// yorumlarla aynı gerekçe), bu tablo o ikisinden ÖNCE temizlenmeli.
db.exec('DELETE FROM work_order_materials');
db.exec('DELETE FROM work_orders');
db.exec('DELETE FROM equipment_risk_scores');
// meter_consumption/meter_anomaly_scores (Modül 11) equipment_id'ye FK'lidir —
// equipment yeniden oluşturulunca (yeni id'lerle) eski satırlar yanlış/var
// olmayan kayıtlara işaret eder hale gelir; equipment_risk_scores ile AYNI
// sebepten burada da temizleniyor. Gerçek tüketim verisi, seed'den SONRA
// arassaha-ml/generate_consumption_data.py ile ayrıca üretilir.
db.exec('DELETE FROM meter_anomaly_scores');
db.exec('DELETE FROM meter_consumption');
db.exec('DELETE FROM equipment');
db.exec('DELETE FROM isg_reports');
// materials, work_order_materials dışında hiçbir tabloya FK bağımlı değil —
// yine de tekrar çalıştırılabilirlik için (script başındaki genel ilke)
// diğerleriyle birlikte temizlenir.
db.exec('DELETE FROM materials');
db.exec('DELETE FROM users');
db.exec(
  "DELETE FROM sqlite_sequence WHERE name IN ('work_orders', 'work_order_photos', 'work_order_materials', 'users', 'managed_devices', 'device_action_logs', 'equipment', 'isg_reports', 'equipment_risk_scores', 'user_action_logs', 'notifications', 'meter_consumption', 'meter_anomaly_scores', 'materials')"
);

const insertUser = db.prepare(`
  INSERT INTO users (name, role, sicil_no, password_hash) VALUES (@name, @role, @sicil_no, @password_hash)
`);

const insertedUserIds = personnelSeed.map(
  (person) =>
    insertUser.run({
      name: person.name,
      role: person.role,
      sicil_no: person.sicil_no,
      password_hash: DEMO_PASSWORD_HASH,
    }).lastInsertRowid
);
const technicianIds = insertedUserIds.filter((_, i) => personnelSeed[i].role === 'teknisyen');

// İkinci geçiş: supervisor_id set edilir. İlk geçişte teknisyenler kendi
// dispeçerinden ÖNCE eklendiği için (dizideki sıra), dispeçerin id'si o an
// henüz yoktu — bu yüzden isimden id'ye eşleme burada, TÜM kullanıcılar
// eklendikten sonra yapılır.
const userIdByPersonName = Object.fromEntries(personnelSeed.map((p, i) => [p.name, insertedUserIds[i]]));
const updateSupervisor = db.prepare('UPDATE users SET supervisor_id = ? WHERE id = ?');
personnelSeed.forEach((person, i) => {
  if (person.supervisor) {
    updateSupervisor.run(userIdByPersonName[person.supervisor], insertedUserIds[i]);
  }
});

// SEC-03 devamı — "atayan" (assigned_by_user_id) demo verisinde boş
// görünmesin diye: her teknisyenin iş emirleri, GERÇEKÇİ bir şekilde KENDİ
// dispeçerinin ("bu işi bana veren kişi") atadığı varsayılır — üretimde de
// bir dispeçer tipik olarak kendi ekibine iş dağıtır.
const technicianIdToSupervisorId = {};
personnelSeed.forEach((person, i) => {
  if (person.role === 'teknisyen' && person.supervisor) {
    technicianIdToSupervisorId[insertedUserIds[i]] = userIdByPersonName[person.supervisor];
  }
});

// --- Ekipman / Envanter (Modül 4) — bkz. ARCHITECTURE.md, DESIGN_SYSTEM.md ---
// install_date/last_maintenance_date değerleri BİLİNÇLİ olarak çeşitlendirildi
// (1-2 yıllık yeni ekipman ile 10+ yıllık eski ekipman karışık; bazılarında
// bakım çok yakın zamanlı, bazılarında uzun süredir yapılmamış) — bu
// çeşitlilik ileride Arıza Risk Tahmini (ML) modülünün eğitim verisinde
// anlamlı bir dağılım olması için önemlidir. `hasHistory: true` olan
// kayıtlar aşağıda work_orders'a kasıtlı olarak bağlanacak; `false` olanlar
// hiç arıza kaydı olmayan ekipmanı temsil eder (risk modeli için çeşitlilik).
const equipmentSeed = [
  { qr_code: 'TR-2024-0451', equipment_type: 'trafo', location: locations[0], installYears: 1.5, maintenanceMonths: 2, manufacturer: 'ABB', capacity_info: '400 kVA', status: 'aktif', hasHistory: true },
  { qr_code: 'TR-2015-0212', equipment_type: 'trafo', location: locations[1], installYears: 11, maintenanceMonths: 14, manufacturer: 'Siemens', capacity_info: '630 kVA', status: 'aktif', hasHistory: true },
  { qr_code: 'TR-2013-0087', equipment_type: 'trafo', location: locations[3], installYears: 13, maintenanceMonths: 30, manufacturer: 'Schneider Electric', capacity_info: '250 kVA', status: 'bakimda', hasHistory: false },
  { qr_code: 'TR-2023-0733', equipment_type: 'trafo', location: locations[7], installYears: 2, maintenanceMonths: 1, manufacturer: 'ABB', capacity_info: '1000 kVA', status: 'aktif', hasHistory: true },
  { qr_code: 'TR-2012-0159', equipment_type: 'trafo', location: locations[6], installYears: 14, maintenanceMonths: 40, manufacturer: 'Siemens', capacity_info: '250 kVA', status: 'devre_disi', hasHistory: false },

  { qr_code: 'DR-2022-1044', equipment_type: 'direk', location: locations[2], installYears: 2.5, maintenanceMonths: 6, manufacturer: 'Beksan Beton', capacity_info: '12 m beton direk', status: 'aktif', hasHistory: true },
  { qr_code: 'DR-2011-0398', equipment_type: 'direk', location: locations[13], installYears: 14, maintenanceMonths: 36, manufacturer: 'Yılmaz Beton Direk', capacity_info: '9 m beton direk', status: 'aktif', hasHistory: true },
  { qr_code: 'DR-2024-0876', equipment_type: 'direk', location: locations[9], installYears: 1, maintenanceMonths: 3, manufacturer: 'Beksan Beton', capacity_info: '12 m beton direk', status: 'aktif', hasHistory: false },
  { qr_code: 'DR-2014-0261', equipment_type: 'direk', location: locations[11], installYears: 11.5, maintenanceMonths: null, manufacturer: 'Yılmaz Beton Direk', capacity_info: '9 m beton direk', status: 'bakimda', hasHistory: true },
  { qr_code: 'DR-2020-0509', equipment_type: 'direk', location: locations[8], installYears: 5, maintenanceMonths: 10, manufacturer: 'Beksan Beton', capacity_info: '12 m beton direk', status: 'aktif', hasHistory: false },

  { qr_code: 'KS-2023-0334', equipment_type: 'kesici', location: locations[4], installYears: 2, maintenanceMonths: 4, manufacturer: 'Eaton', capacity_info: '630 A', status: 'aktif', hasHistory: true },
  { qr_code: 'KS-2010-0071', equipment_type: 'kesici', location: locations[12], installYears: 15, maintenanceMonths: 20, manufacturer: 'ETİ Elektrik', capacity_info: '400 A', status: 'aktif', hasHistory: true },
  { qr_code: 'KS-2016-0620', equipment_type: 'kesici', location: locations[5], installYears: 9, maintenanceMonths: 30, manufacturer: 'Schneider Electric', capacity_info: '630 A', status: 'bakimda', hasHistory: false },
  { qr_code: 'KS-2024-0198', equipment_type: 'kesici', location: locations[10], installYears: 1, maintenanceMonths: 2, manufacturer: 'Eaton', capacity_info: '400 A', status: 'aktif', hasHistory: false },

  { qr_code: 'SY-2022-0455', equipment_type: 'sayac', location: locations[0], installYears: 3, maintenanceMonths: 5, manufacturer: 'Siemens', capacity_info: null, status: 'aktif', hasHistory: true },
  { qr_code: 'SY-2013-0902', equipment_type: 'sayac', location: locations[14], installYears: 12, maintenanceMonths: 24, manufacturer: 'ABB', capacity_info: null, status: 'aktif', hasHistory: false },
  { qr_code: 'SY-2025-0044', equipment_type: 'sayac', location: locations[6], installYears: 0.5, maintenanceMonths: 1, manufacturer: 'ABB', capacity_info: null, status: 'aktif', hasHistory: false },
  { qr_code: 'SY-2011-0367', equipment_type: 'sayac', location: locations[7], installYears: 14.5, maintenanceMonths: 48, manufacturer: 'Siemens', capacity_info: null, status: 'devre_disi', hasHistory: true },
  // Aşağıdaki 15 kayıt, Modül 11 (Kayıp-Kaçak / Anormal Tüketim Tespiti) için
  // eklendi: arassaha-ml/generate_consumption_data.py, IsolationForest modelini
  // anlamlı bir eğitim seti üretebilmek için en az 15-20 sayaç ekipmanı okumayı
  // bekler (bkz. arassaha-ml/README.md Modül 11 bölümü). Diğer alanlar (yaş,
  // bakım, üretici) yukarıdaki 4 kayıtla aynı çeşitlilik mantığıyla dağıtıldı.
  { qr_code: 'SY-2021-0118', equipment_type: 'sayac', location: locations[1], installYears: 4, maintenanceMonths: 8, manufacturer: 'ABB', capacity_info: null, status: 'aktif', hasHistory: false },
  { qr_code: 'SY-2019-0273', equipment_type: 'sayac', location: locations[2], installYears: 6, maintenanceMonths: 12, manufacturer: 'Siemens', capacity_info: null, status: 'aktif', hasHistory: true },
  { qr_code: 'SY-2023-0561', equipment_type: 'sayac', location: locations[3], installYears: 2, maintenanceMonths: 3, manufacturer: 'ABB', capacity_info: null, status: 'aktif', hasHistory: false },
  { qr_code: 'SY-2016-0730', equipment_type: 'sayac', location: locations[4], installYears: 9, maintenanceMonths: 18, manufacturer: 'Schneider Electric', capacity_info: null, status: 'aktif', hasHistory: false },
  { qr_code: 'SY-2024-0089', equipment_type: 'sayac', location: locations[5], installYears: 1, maintenanceMonths: 2, manufacturer: 'ABB', capacity_info: null, status: 'aktif', hasHistory: false },
  { qr_code: 'SY-2014-0405', equipment_type: 'sayac', location: locations[8], installYears: 11, maintenanceMonths: 30, manufacturer: 'Siemens', capacity_info: null, status: 'aktif', hasHistory: true },
  { qr_code: 'SY-2020-0192', equipment_type: 'sayac', location: locations[9], installYears: 5, maintenanceMonths: 10, manufacturer: 'ABB', capacity_info: null, status: 'aktif', hasHistory: false },
  { qr_code: 'SY-2012-0847', equipment_type: 'sayac', location: locations[10], installYears: 13, maintenanceMonths: 40, manufacturer: 'Schneider Electric', capacity_info: null, status: 'aktif', hasHistory: false },
  { qr_code: 'SY-2022-0316', equipment_type: 'sayac', location: locations[11], installYears: 3.5, maintenanceMonths: 6, manufacturer: 'Siemens', capacity_info: null, status: 'aktif', hasHistory: false },
  { qr_code: 'SY-2018-0654', equipment_type: 'sayac', location: locations[12], installYears: 7, maintenanceMonths: 15, manufacturer: 'ABB', capacity_info: null, status: 'aktif', hasHistory: true },
  { qr_code: 'SY-2010-0021', equipment_type: 'sayac', location: locations[13], installYears: 15.5, maintenanceMonths: 44, manufacturer: 'Siemens', capacity_info: null, status: 'aktif', hasHistory: false },
  { qr_code: 'SY-2023-0740', equipment_type: 'sayac', location: locations[0], installYears: 2.5, maintenanceMonths: 4, manufacturer: 'ABB', capacity_info: null, status: 'aktif', hasHistory: false },
  { qr_code: 'SY-2017-0508', equipment_type: 'sayac', location: locations[2], installYears: 8, maintenanceMonths: 20, manufacturer: 'Schneider Electric', capacity_info: null, status: 'aktif', hasHistory: false },
  { qr_code: 'SY-2015-0362', equipment_type: 'sayac', location: locations[5], installYears: 10, maintenanceMonths: 26, manufacturer: 'Siemens', capacity_info: null, status: 'bakimda', hasHistory: false },
  { qr_code: 'SY-2021-0904', equipment_type: 'sayac', location: locations[9], installYears: 4.5, maintenanceMonths: 9, manufacturer: 'ABB', capacity_info: null, status: 'aktif', hasHistory: false },
];

const insertEquipment = db.prepare(`
  INSERT INTO equipment
    (qr_code, equipment_type, il, ilce, mahalle, location_name, lat, lng, install_date, last_maintenance_date, manufacturer, capacity_info, status, created_at)
  VALUES
    (@qr_code, @equipment_type, @il, @ilce, @mahalle, @location_name, @lat, @lng, @install_date, @last_maintenance_date, @manufacturer, @capacity_info, @status, @created_at)
`);

const equipmentIds = [];
const equipmentIdsWithHistory = [];

// equipmentIdToLocation: her eklenen ekipmanın GERÇEKTEN veritabanına
// yazılan (jitter uygulanmış) konum alanlarının bir kopyası. Aşağıda iş
// emirleri üretilirken bir iş emrinin KONUMU artık rastgele değil,
// BAĞLANDIĞI ekipmanın konumuyla BİREBİR aynıdır (aynı formatLocationName()
// çıktısı, aynı lat/lng) — gerçek hayatta bir arıza her zaman kendi
// ekipmanının bulunduğu yerde olur. Önceden konum ve equipment_id
// birbirinden bağımsız rastgele seçiliyordu, bu da örn. Erzurum'daki bir
// trafonun geçmişinde Bayburt'ta bildirilmiş bir arıza görünmesi gibi
// tutarsız bir sonuca yol açıyordu. Bu, POST /api/workorders'ın (canlı akış)
// equipment kaydından konum türetmesiyle AYNI ilkedir (bkz. routes/workOrders.js).
const equipmentIdToLocation = {};

db.exec('BEGIN');
try {
  for (const eq of equipmentSeed) {
    const il = eq.location.il;
    const ilce = eq.location.ilce;
    const mahalle = eq.location.mah;
    const location_name = formatLocationName({ il, ilce, mahalle });
    const lat = eq.location.lat + randomJitter();
    const lng = eq.location.lng + randomJitter();

    const info = insertEquipment.run({
      qr_code: eq.qr_code,
      equipment_type: eq.equipment_type,
      il,
      ilce,
      mahalle,
      location_name,
      lat,
      lng,
      install_date: yearsAgoIsoDate(eq.installYears),
      last_maintenance_date: eq.maintenanceMonths == null ? null : monthsAgoIsoDate(eq.maintenanceMonths),
      manufacturer: eq.manufacturer,
      capacity_info: eq.capacity_info,
      status: eq.status,
      created_at: yearsAgoIsoDate(eq.installYears),
    });
    equipmentIds.push(info.lastInsertRowid);
    if (eq.hasHistory) equipmentIdsWithHistory.push(info.lastInsertRowid);
    equipmentIdToLocation[info.lastInsertRowid] = { il, ilce, mahalle, location_name, lat, lng };
  }
  db.exec('COMMIT');
} catch (err) {
  db.exec('ROLLBACK');
  throw err;
}

const insertWorkOrder = db.prepare(`
  INSERT INTO work_orders
    (title, description, status, priority, il, ilce, mahalle, location_name, lat, lng, assigned_user_id, assigned_by_user_id, equipment_id, created_at, updated_at)
  VALUES
    (@title, @description, @status, @priority, @il, @ilce, @mahalle, @location_name, @lat, @lng, @assigned_user_id, @assigned_by_user_id, @equipment_id, @created_at, @updated_at)
`);

// node:sqlite'ın better-sqlite3'teki gibi bir db.transaction() sarmalayıcısı yok;
// BEGIN/COMMIT ile manuel olarak sarmalıyoruz.
function insertMany(rows) {
  const insertedIds = [];
  db.exec('BEGIN');
  try {
    for (const row of rows) {
      const info = insertWorkOrder.run(row);
      insertedIds.push(info.lastInsertRowid);
    }
    db.exec('COMMIT');
  } catch (err) {
    db.exec('ROLLBACK');
    throw err;
  }
  return insertedIds;
}

// technicianIds ile workOrderPlanByTechnicianIndex AYNI sırada (personnelSeed
// sırası) — her teknisyenin id'sini kendi planındaki statülerle eşleştirip
// TEK, düz bir atama listesi oluşturur.
const workOrderAssignments = technicianIds.flatMap((technicianId, i) => {
  const plan = workOrderPlanByTechnicianIndex[i] ?? { acik: 1, yolda: 1, sahada: 1, cozuldu: 2 };
  return expandStatusPlan(plan).map((status) => ({ technicianId, status }));
});

const firstCozulduIndex = workOrderAssignments.findIndex((a) => a.status === 'cozuldu');

const rows = workOrderAssignments.map(({ technicianId, status }, index) => {
  // Konum artık iş emrinin bağlandığı ekipmandan türetilir (bkz. yukarıdaki
  // equipmentIdToLocation notu) — rastgele bir konum ile rastgele bir
  // ekipman ayrı ayrı seçilmiyor.
  const equipmentId = pick(equipmentIdsWithHistory);
  const location = equipmentIdToLocation[equipmentId];
  const title = pick(titles);

  let createdAt;
  let updatedAt;

  if (status === 'cozuldu' && index === firstCozulduIndex) {
    // Dashboard'daki "Bugün Çözülen" ve "Ort. Çözüm Süresi" kartlarının anlamlı
    // (sıfır olmayan, tutarlı) bir değer göstermesi için en az bir iş emrinin
    // bugün, makul bir çözüm süresiyle (4-24 saat) çözüldüğünden emin oluyoruz.
    const resolutionHours = Math.random() * 20 + 4;
    updatedAt = new Date(Date.now() - Math.random() * 6 * 60 * 60 * 1000);
    createdAt = new Date(updatedAt.getTime() - resolutionHours * 60 * 60 * 1000);
  } else if (status === 'cozuldu') {
    // Diğer TÜM 'cozuldu' kayıtları geniş bir tamamlanma tarihi aralığına
    // (son 75 gün) yayılır — "Tamamlanan İş Emirlerim" bölümünün sıralama
    // (Yeniden Eskiye/Eskiden Yeniye) kontrolünün GERÇEKTEN görünür bir etkisi
    // olsun diye; hepsi aynı haftaya sıkışmış olsaydı sıralamanın bir önemi
    // kalmazdı.
    const completedDaysAgo = Math.random() * 75;
    const resolutionHours = Math.random() * 46 + 2; // 2 saat - 2 gün arası çözüm süresi
    updatedAt = new Date(Date.now() - completedDaysAgo * 24 * 60 * 60 * 1000);
    createdAt = new Date(updatedAt.getTime() - resolutionHours * 60 * 60 * 1000);
  } else {
    createdAt = randomPastDate(10);
    // Sahadaki işlerde updated_at, created_at'ten sonraki bir zaman olsun.
    updatedAt = status === 'acik' ? createdAt : new Date(createdAt.getTime() + Math.random() * 2 * 24 * 60 * 60 * 1000);
  }

  return {
    title: `${title} - ${location.mahalle}`,
    description: `${location.il} / ${location.ilce} bölgesinde ${title.toLowerCase()} bildirildi. Sahada inceleme ve müdahale gerekiyor. (Kayıt #${index + 1})`,
    status,
    priority: pick(priorities),
    // il/ilce/mahalle/location_name/lat/lng — BAĞLANDIĞI equipment kaydından
    // BİREBİR kopyalanır (ayrıca jitter uygulanmaz); POST /api/workorders'ın
    // canlı akışta yapacağıyla aynı davranış (bkz. routes/workOrders.js).
    il: location.il,
    ilce: location.ilce,
    mahalle: location.mahalle,
    location_name: location.location_name,
    lat: location.lat,
    lng: location.lng,
    assigned_user_id: technicianId,
    assigned_by_user_id: technicianIdToSupervisorId[technicianId] ?? null,
    // equipment.id'ye giden gerçek bir FK — yalnızca "geçmiş arıza kaydı
    // olsun" diye işaretlenmiş ekipmanlardan seçilir (yukarıda); bu sayede
    // bazı ekipmanların gerçek geçmişi olur, bazılarınınsa hiç olmaz.
    equipment_id: equipmentId,
    created_at: createdAt.toISOString(),
    updated_at: updatedAt.toISOString(),
  };
});

// Bildirim seed'i (aşağıda) her teknisyenin GERÇEKTEN oluşturulmuş iş
// emirlerine (gerçek id + başlık) işaret edebilsin diye dönen id'ler saklanır.
const workOrderIds = insertMany(rows);

// Not: Fotoğraflar burada artık sahte/placeholder path ile seed edilmiyor.
// Gerçek dosya diskte yoksa böyle bir kayıt "kaydettim ama görüntülenemiyor" durumuna
// yol açar; bu Temel Kalite İlkesi'ni ihlal eder. Gerçek fotoğraflar yalnızca
// uygulama üzerinden (POST /api/workorders/:id/photos, multipart upload) eklenir.

// --- İSG (İş Sağlığı ve Güvenliği) Bildirimi (Modül 5) — bkz. ARCHITECTURE.md ---
// `photo_path` burada kasıtlı olarak NULL bırakılıyor (bkz. database.js
// yorumu) — Temel Kalite İlkesi gereği var olmayan bir dosyaya işaret eden
// sahte bir yol seed edilmez. Gerçek fotoğraflar yalnızca uygulama üzerinden
// (POST /api/isg-reports, multipart upload) eklenir; bu kayıtlar "uygulama
// öncesinden var olan, fotoğrafsız bildirim" senaryosunu temsil eder.
const isgReportSeed = [
  { category: 'ekipman_arizasi', description: 'Direk üzerindeki izolatör çatlamış, acil kontrol gerekiyor.', location: locations[1], status: 'bekliyor', daysAgo: 2 },
  { category: 'ekipman_arizasi', description: 'Trafo kapağı tam kapanmıyor, içerideki bağlantılar dışarıdan görünüyor.', location: locations[0], status: 'incelendi', daysAgo: 6, reviewNote: 'Bakım ekibi yönlendirildi, parça temini bekleniyor.', reviewAfterDays: 1 },
  { category: 'ekipman_arizasi', description: 'Sayaç kutusunun kapağı kırık, yağmur suyu içeri giriyor.', location: locations[9], status: 'bekliyor', daysAgo: 1 },
  { category: 'tehlikeli_durum', description: 'Trafo çevresindeki güvenlik çiti hasarlı, çocukların girebileceği bir alan oluşmuş.', location: locations[5], status: 'cozuldu', daysAgo: 12, reviewNote: 'Çit onarıldı, saha tekrar kontrol edildi.', reviewAfterDays: 3 },
  { category: 'tehlikeli_durum', description: 'Kablo kanalı kapağı açık kalmış, yaya geçişinde tökezleme riski var.', location: locations[10], status: 'bekliyor', daysAgo: 3 },
  { category: 'tehlikeli_durum', description: 'Direk dibinde çukur oluşmuş, zeminde çökme riski görülüyor.', location: locations[12], status: 'incelendi', daysAgo: 5, reviewNote: 'Zemin etüdü için ekip planlandı.', reviewAfterDays: 2 },
  { category: 'is_kazasi_riski', description: 'Yüksek gerilim hattına çok yakın bir ağaç dalı büyümüş, budama gerekiyor.', location: locations[13], status: 'bekliyor', daysAgo: 4 },
  { category: 'is_kazasi_riski', description: 'Sahada çalışırken merdiven sabitleme ekipmanı eksikti, iş güvenliği talimatı hatırlatılmalı.', location: locations[3], status: 'cozuldu', daysAgo: 15, reviewNote: 'Ekip iş güvenliği eğitiminden geçirildi.', reviewAfterDays: 4 },
  { category: 'is_kazasi_riski', description: 'Trafo odasına giriş kapısının kilidi bozuk, yetkisiz erişime açık.', location: locations[4], status: 'bekliyor', daysAgo: 1 },
  { category: 'diger', description: 'Sahadaki uyarı levhası solmuş, okunmuyor, yenilenmesi gerekiyor.', location: locations[6], status: 'bekliyor', daysAgo: 7 },
  { category: 'diger', description: 'Bölgede sokak aydınlatması bir haftadır çalışmıyor.', location: locations[14], status: 'incelendi', daysAgo: 9, reviewNote: 'Aydınlatma ekibine bildirildi.', reviewAfterDays: 2 },
];

const insertIsgReport = db.prepare(`
  INSERT INTO isg_reports
    (reported_by_user_id, description, category, photo_path, location_name, lat, lng, status, reviewer_note, created_at, reviewed_at)
  VALUES
    (@reported_by_user_id, @description, @category, @photo_path, @location_name, @lat, @lng, @status, @reviewer_note, @created_at, @reviewed_at)
`);

// Bildirim seed'i (aşağıda), incelenmiş/çözülmüş bildirimler için gerçek
// (id, bildiren kullanıcı) çiftlerine ihtiyaç duyduğundan burada saklanır —
// bkz. notificationSeed'in isgReportInserts kullanımı.
const isgReportInserts = [];

db.exec('BEGIN');
try {
  for (const r of isgReportSeed) {
    const createdAt = new Date(Date.now() - r.daysAgo * 24 * 60 * 60 * 1000);
    const reviewedAt =
      r.reviewAfterDays != null ? new Date(createdAt.getTime() + r.reviewAfterDays * 24 * 60 * 60 * 1000) : null;
    const reportedByUserId = pick(technicianIds);

    const info = insertIsgReport.run({
      reported_by_user_id: reportedByUserId,
      description: r.description,
      category: r.category,
      photo_path: null,
      location_name: `${r.location.il} / ${r.location.ilce} / ${r.location.mah}`,
      lat: r.location.lat + randomJitter(),
      lng: r.location.lng + randomJitter(),
      status: r.status,
      reviewer_note: r.reviewNote || null,
      created_at: createdAt.toISOString(),
      reviewed_at: reviewedAt ? reviewedAt.toISOString() : null,
    });
    isgReportInserts.push({ id: info.lastInsertRowid, reportedByUserId, status: r.status });
  }
  db.exec('COMMIT');
} catch (err) {
  db.exec('ROLLBACK');
  throw err;
}

// --- Cihaz Yönetimi (MDM simülasyonu) — bkz. DESIGN_SYSTEM.md ---
// personnelSeed ile aynı isimler kullanılır ki veri seti tutarlı görünsün
// (bir kişinin hem iş emri hem cihaz kaydı olması gerçekçi bir senaryo).
const userIdByName = Object.fromEntries(personnelSeed.map((p, i) => [p.name, insertedUserIds[i]]));

function hoursAgoIso(hours) {
  return new Date(Date.now() - hours * 60 * 60 * 1000).toISOString();
}

// Çoğunluk 'kayitli' + 'uyumlu'; birkaçı eski OS versiyonu yüzünden 'uyumsuz',
// birkaçı henüz ilk senkronunu yapmadığı için 'beklemede' (last_sync_at = null).
const deviceSeed = [
  { person: 'Ahmet Yılmaz', model: 'Samsung Galaxy A54', os: 'Android 14', app: '1.3.0', enrollment: 'kayitli', compliance: 'uyumlu', battery: 82, locked: 0, syncHoursAgo: 2 },
  { person: 'Mehmet Demir', model: 'Samsung Galaxy Tab A9', os: 'Android 13', app: '1.3.0', enrollment: 'kayitli', compliance: 'uyumlu', battery: 65, locked: 0, syncHoursAgo: 5 },
  { person: 'Ayşe Kaya', model: 'Xiaomi Redmi Note 12', os: 'Android 9', app: '1.1.0', enrollment: 'kayitli', compliance: 'uyumsuz', battery: 21, locked: 0, syncHoursAgo: 30 },
  { person: 'Fatih Şahin', model: 'Samsung Galaxy A34', os: 'Android 13', app: '1.3.0', enrollment: 'kayitli', compliance: 'uyumlu', battery: 91, locked: 0, syncHoursAgo: 1 },
  { person: 'Emre Çelik', model: 'Huawei MatePad T10', os: 'Android 10', app: '1.0.0', enrollment: 'kayitli', compliance: 'uyumsuz', battery: 8, locked: 1, syncHoursAgo: 72 },
  { person: 'Hakan Yıldız', model: 'Samsung Galaxy A14', os: 'Android 13', app: '1.3.0', enrollment: 'kayitli', compliance: 'uyumlu', battery: 74, locked: 0, syncHoursAgo: 4 },
  { person: 'Zeynep Arslan', model: 'Xiaomi Redmi 10C', os: 'Android 12', app: '1.2.0', enrollment: 'kayitli', compliance: 'uyumlu', battery: 55, locked: 0, syncHoursAgo: 6 },
  { person: 'Murat Öztürk', model: 'Samsung Galaxy Tab S6 Lite', os: 'Android 14', app: '1.3.0', enrollment: 'kayitli', compliance: 'uyumlu', battery: 98, locked: 0, syncHoursAgo: 0.5 },
  { person: 'Ahmet Yılmaz', model: 'Samsung Galaxy A25', os: 'Android 14', app: '1.3.0', enrollment: 'beklemede', compliance: 'uyumlu', battery: 100, locked: 0, syncHoursAgo: null },
  { person: 'Mehmet Demir', model: 'Oppo A78', os: 'Android 13', app: '1.2.0', enrollment: 'beklemede', compliance: 'uyumlu', battery: 100, locked: 0, syncHoursAgo: null },
  { person: 'Ayşe Kaya', model: 'Xiaomi Redmi Note 11', os: 'Android 11', app: '1.1.0', enrollment: 'kayitli', compliance: 'uyumsuz', battery: 34, locked: 0, syncHoursAgo: 48 },
  { person: 'Fatih Şahin', model: 'Samsung Galaxy A15', os: 'Android 14', app: '1.3.0', enrollment: 'kayitli', compliance: 'uyumlu', battery: 60, locked: 0, syncHoursAgo: 3 },
];

const insertDevice = db.prepare(`
  INSERT INTO managed_devices
    (device_name, assigned_user_id, device_model, os_version, app_version, enrollment_status,
     compliance_status, last_sync_at, battery_level, is_locked, created_at)
  VALUES
    (@device_name, @assigned_user_id, @device_model, @os_version, @app_version, @enrollment_status,
     @compliance_status, @last_sync_at, @battery_level, @is_locked, @created_at)
`);

db.exec('BEGIN');
try {
  for (const d of deviceSeed) {
    insertDevice.run({
      device_name: `${d.person} - ${d.model}`,
      assigned_user_id: userIdByName[d.person],
      device_model: d.model,
      os_version: d.os,
      app_version: d.app,
      enrollment_status: d.enrollment,
      compliance_status: d.compliance,
      last_sync_at: d.syncHoursAgo == null ? null : hoursAgoIso(d.syncHoursAgo),
      battery_level: d.battery,
      is_locked: d.locked,
      created_at: hoursAgoIso(24 * 30),
    });
  }
  db.exec('COMMIT');
} catch (err) {
  db.exec('ROLLBACK');
  throw err;
}

// --- Malzeme / Yedek Parça Stok Takibi (Modül 13) — bkz. routes/materials.js ---
// Önceden bu tabloya HİÇ seed verisi yazılmıyordu — Stok/Malzeme ekranı her
// zaman "veri yok" olarak açılıyordu ve Dashboard'daki "Kritik stokta
// malzeme yok" kartı da (gerçekten kritik malzeme olmadığından değil, hiç
// malzeme kaydı olmadığından) her zaman boş görünüyordu. Aşağıdaki set
// bilerek stock_quantity'si min_stock_threshold'un ALTINDA kalan birkaç
// kayıt İÇERİR (yorumlarda "kritik" işaretli) — Dashboard'daki kritik stok
// kartının da test edilebilmesi için.
const materialSeed = [
  { name: 'NYY 4x16 mm² Yeraltı Kablosu', category: 'kablo', unit: 'metre', stock: 850, minThreshold: 200, compatible: ['trafo', 'direk'], unitCost: 42.5 },
  { name: 'AsXSn 3x70+54.6 mm² OG Kablo', category: 'kablo', unit: 'metre', stock: 120, minThreshold: 150, compatible: ['trafo'], unitCost: 165 }, // kritik
  { name: 'Topraklama Bakır Şeridi 25x4mm', category: 'kablo', unit: 'metre', stock: 180, minThreshold: 60, compatible: ['trafo', 'direk', 'kesici'], unitCost: 55 },
  { name: 'NF Tipi 100A Sigorta', category: 'sigorta', unit: 'adet', stock: 34, minThreshold: 20, compatible: ['trafo', 'kesici'], unitCost: 210 },
  { name: 'HRC 400A Sigorta', category: 'sigorta', unit: 'adet', stock: 8, minThreshold: 15, compatible: ['kesici'], unitCost: 480 }, // kritik
  { name: 'Kompozit Post İzolatör 24kV', category: 'izolator', unit: 'adet', stock: 60, minThreshold: 25, compatible: ['direk', 'trafo'], unitCost: 320 },
  { name: 'Silikon Kapak İzolatörü', category: 'izolator', unit: 'adet', stock: 15, minThreshold: 20, compatible: ['direk'], unitCost: 95 }, // kritik
  { name: 'Bimetal Pabuç Konnektör 16-95mm²', category: 'konnektor', unit: 'adet', stock: 210, minThreshold: 50, compatible: ['trafo', 'direk', 'kesici', 'sayac'], unitCost: 18 },
  { name: 'C Tipi Ek Kelepçe', category: 'konnektor', unit: 'adet', stock: 5, minThreshold: 30, compatible: ['direk'], unitCost: 12 }, // kritik
  { name: 'Ayırıcı Bıçak Seti', category: 'konnektor', unit: 'adet', stock: 22, minThreshold: 10, compatible: ['kesici'], unitCost: 275 },
  { name: 'Vidalı Sayaç Klemensi', category: 'konnektor', unit: 'adet', stock: 260, minThreshold: 80, compatible: ['sayac'], unitCost: 6 },
  { name: 'Elektronik Sayaç Mührü', category: 'diger', unit: 'adet', stock: 500, minThreshold: 100, compatible: ['sayac'], unitCost: 3.5 },
  { name: 'Trafo Yalıtım Yağı', category: 'diger', unit: 'kg', stock: 340, minThreshold: 100, compatible: ['trafo'], unitCost: 28 },
  { name: 'Beton Direk Ek Bandı', category: 'diger', unit: 'adet', stock: 12, minThreshold: 20, compatible: ['direk'], unitCost: 40 }, // kritik
];

const insertMaterial = db.prepare(`
  INSERT INTO materials
    (name, category, unit, stock_quantity, min_stock_threshold, compatible_equipment_types, unit_cost, created_at)
  VALUES
    (@name, @category, @unit, @stock_quantity, @min_stock_threshold, @compatible_equipment_types, @unit_cost, @created_at)
`);

db.exec('BEGIN');
try {
  for (const m of materialSeed) {
    insertMaterial.run({
      name: m.name,
      category: m.category,
      unit: m.unit,
      stock_quantity: m.stock,
      min_stock_threshold: m.minThreshold,
      compatible_equipment_types: m.compatible.join(','),
      unit_cost: m.unitCost,
      created_at: monthsAgoIsoDate(Math.round(Math.random() * 10) + 2),
    });
  }
  db.exec('COMMIT');
} catch (err) {
  db.exec('ROLLBACK');
  throw err;
}

// --- Bildirim Sistemi (Modül 6) seed'i — bkz. utils/notify.js ---
// Önceden bu tabloya HİÇ seed verisi yazılmıyordu (seed, iş emri/İSG
// kayıtlarını route handler'ları ATLAYIP doğrudan tabloya yazdığı için
// createNotification hiç çağrılmamış oluyordu) — Bildirimler ekranı her
// zaman boştu. Mesaj metinleri, GERÇEK çağrı noktalarıyla (routes/workOrders.js,
// routes/isg.js) BİREBİR aynı tutuldu ki bu seed verisi uygulamanın kendi
// ürettiği bildirimlerden görsel/metinsel olarak ayırt edilemesin.
const notificationSeed = [];

// Her teknisyen, kendisine atanmış en yeni 2 iş emri için bir "atandı"
// bildirimi alır (gerçek POST /api/workorders akışıyla AYNI mesaj kalıbı).
technicianIds.forEach((technicianId) => {
  const own = rows
    .map((row, i) => ({ row, id: workOrderIds[i] }))
    .filter(({ row }) => row.assigned_user_id === technicianId)
    .sort((a, b) => new Date(b.row.created_at) - new Date(a.row.created_at))
    .slice(0, 2);
  own.forEach(({ row, id }, i) => {
    notificationSeed.push({
      user_id: technicianId,
      message: `Size yeni bir iş emri atandı: "${row.title}"`,
      related_type: 'work_order',
      related_id: id,
      createdAt: new Date(row.created_at),
      // Yalnızca EN yeni atama okunmamış kalır — tüm geçmiş atamaların
      // sonsuza dek "okunmadı" görünmesi gerçekçi olmazdı.
      isRead: i !== 0,
    });
  });
});

// İncelenmiş/çözülmüş İSG bildirimleri için "durumu güncellendi" bildirimi
// (yalnızca reviewer_note'u olan, yani gerçekten bir yöneticinin/dispeçerin
// baktığı kayıtlar — bkz. routes/isg.js PATCH /:id/status).
isgReportInserts
  .filter((r) => r.status !== 'bekliyor')
  .forEach((r, i) => {
    notificationSeed.push({
      user_id: r.reportedByUserId,
      message: `İSG bildiriminiz "${r.status}" olarak güncellendi`,
      related_type: 'isg_report',
      related_id: r.id,
      createdAt: randomPastDate(10),
      isRead: i !== 0,
    });
  });

const insertNotificationSeed = db.prepare(`
  INSERT INTO notifications (user_id, message, related_type, related_id, is_read, created_at)
  VALUES (@user_id, @message, @related_type, @related_id, @is_read, @created_at)
`);

db.exec('BEGIN');
try {
  for (const n of notificationSeed) {
    insertNotificationSeed.run({
      user_id: n.user_id,
      message: n.message,
      related_type: n.related_type,
      related_id: n.related_id,
      is_read: n.isRead ? 1 : 0,
      created_at: n.createdAt.toISOString(),
    });
  }
  db.exec('COMMIT');
} catch (err) {
  db.exec('ROLLBACK');
  throw err;
}

// --- Kayıp-Kaçak / Anormal Tüketim Tespiti (Modül 11) — meter_consumption ---
//
// DÜRÜSTLÜK NOTU: arassaha-ml/generate_consumption_data.py'nin BİREBİR JS
// karşılığı. O script yalnızca lokalde elle çalıştırıldığında işe yarıyordu;
// Railway'e deploy edilen arassaha-backend imajı yalnızca `node seed.js`
// çalıştırıyor (bkz. Dockerfile), bu yüzden CANLI ortamda meter_consumption
// tablosu hep BOŞ kalıyordu ve Tüketim Analizi (routes/anomaly.js
// computeAndSaveAnomaly) "yeterli tüketim geçmişi yok" hatasıyla
// başarısız oluyordu. Bu blok, o veriyi artık seed.js'in (dolayısıyla her
// Docker build'in) bir parçası yapar — arassaha-ml/generate_consumption_data.py
// hâlâ mevcut ve arassaha-ml'nin KENDİ eğitim verisini (consumption_training_data.csv)
// üretmek için kullanılabilir, ama backend artık ona bağımlı değil.
//
// Basit, tohumlu (seeded) bir PRNG — numpy'nin default_rng'si kadar
// sofistike değil ama AYNI amaca hizmet ediyor: her `node seed.js`
// çalıştırmasında AYNI (deterministik), tekrarlanabilir veri seti üretir.
function mulberry32(seed) {
  let a = seed;
  return function () {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const consumptionRng = mulberry32(42);
function rngFloat(min, max) {
  return min + consumptionRng() * (max - min);
}
function rngGaussian(mean, stdDev) {
  // Box-Muller — generate_consumption_data.py'deki rng.normal ile aynı amaç.
  const u1 = Math.max(consumptionRng(), 1e-9);
  const u2 = consumptionRng();
  const z = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
  return mean + z * stdDev;
}

const SEASONAL_FACTOR = {
  1: 1.22, 2: 1.18, 3: 1.05, 4: 0.95, 5: 0.88, 6: 0.95,
  7: 1.05, 8: 1.05, 9: 0.92, 10: 0.95, 11: 1.1, 12: 1.2,
};
const CONSUMPTION_MONTHS = 12;
const ANOMALY_RATE = 0.15;

function last12MonthLabels() {
  const labels = [];
  const now = new Date();
  let year = now.getFullYear();
  let month = now.getMonth() + 1; // 1-12
  for (let i = 0; i < CONSUMPTION_MONTHS; i++) {
    labels.push(`${year}-${String(month).padStart(2, '0')}`);
    month -= 1;
    if (month === 0) {
      month = 12;
      year -= 1;
    }
  }
  return labels.reverse();
}

function generateNormalSeries(monthLabels, baseline) {
  return monthLabels.map((ym) => {
    const month = Number(ym.split('-')[1]);
    const seasonal = baseline * SEASONAL_FACTOR[month];
    const noise = rngGaussian(0, baseline * 0.06);
    return Math.max(0, seasonal + noise);
  });
}

function generateSuddenDropSeries(monthLabels, baseline) {
  const values = generateNormalSeries(monthLabels, baseline);
  const dropFactor = rngFloat(0.2, 0.4); // kalan oran -> %60-80 düşüş
  for (let i = CONSUMPTION_MONTHS - 3; i < CONSUMPTION_MONTHS; i++) {
    values[i] = values[i] * dropFactor;
  }
  return values;
}

function generateNearZeroSeries() {
  return Array.from({ length: CONSUMPTION_MONTHS }, () => Math.max(0, rngFloat(0, 3)));
}

function generateIrregularSeries(baseline) {
  const low = Math.max(10, baseline * 0.15);
  const high = baseline * 2.5;
  return Array.from({ length: CONSUMPTION_MONTHS }, () => rngFloat(low, high));
}

function pick0(arr) {
  return arr[Math.floor(consumptionRng() * arr.length)];
}

const meterEquipment = equipmentSeed
  .map((eq, i) => ({ ...eq, id: equipmentIds[i] }))
  .filter((eq) => eq.equipment_type === 'sayac');

const monthLabels = last12MonthLabels();
const nAnomalies = Math.round(meterEquipment.length * ANOMALY_RATE);
const shuffledMeterIds = [...meterEquipment].sort(() => consumptionRng() - 0.5);
const anomalyMeterIds = new Set(shuffledMeterIds.slice(0, nAnomalies).map((m) => m.id));

const insertConsumption = db.prepare(`
  INSERT INTO meter_consumption (equipment_id, year_month, consumption_kwh)
  VALUES (@equipment_id, @year_month, @consumption_kwh)
`);

db.exec('BEGIN');
try {
  // Tekrar tekrar çalıştırılabilir olsun diye (generate_consumption_data.py
  // ile AYNI ilke) önce bu sayaçlara ait eski kayıtlar temizlenir.
  const meterIds = meterEquipment.map((m) => m.id);
  if (meterIds.length) {
    db.prepare(
      `DELETE FROM meter_consumption WHERE equipment_id IN (${meterIds.map(() => '?').join(',')})`
    ).run(...meterIds);
  }

  let consumptionRowCount = 0;
  for (const meter of meterEquipment) {
    const baseline = rngFloat(120, 400);
    let values;

    if (anomalyMeterIds.has(meter.id)) {
      const candidates = ['ani_dusus', 'duzensiz'];
      if (meter.status === 'aktif') candidates.push('sifira_yakin');
      const anomalyType = pick0(candidates);
      if (anomalyType === 'ani_dusus') values = generateSuddenDropSeries(monthLabels, baseline);
      else if (anomalyType === 'sifira_yakin') values = generateNearZeroSeries();
      else values = generateIrregularSeries(baseline);
    } else {
      values = generateNormalSeries(monthLabels, baseline);
    }

    monthLabels.forEach((year_month, i) => {
      insertConsumption.run({
        equipment_id: meter.id,
        year_month,
        consumption_kwh: Math.round(values[i] * 100) / 100,
      });
      consumptionRowCount += 1;
    });
  }
  db.exec('COMMIT');
  console.log(
    `${meterEquipment.length} adet sayaç için ${consumptionRowCount} aylık tüketim kaydı ('meter_consumption') oluşturuldu ` +
      `(${anomalyMeterIds.size} tanesi bilerek anomali örüntüsüyle işaretlendi).`
  );
} catch (err) {
  db.exec('ROLLBACK');
  throw err;
}

console.log(
  `${insertedUserIds.length} adet kişi, ${equipmentIds.length} adet ekipman, ${rows.length} adet iş emri ` +
    `(${rows.filter((r) => r.status === 'cozuldu').length} tamamlanmış), ${isgReportSeed.length} adet İSG bildirimi, ` +
    `${deviceSeed.length} adet cihaz kaydı, ${materialSeed.length} adet malzeme tipi ve ${notificationSeed.length} adet bildirim oluşturuldu.`
);

console.log(`
DEMO GİRİŞ BİLGİLERİ:
Teknisyen  → sicil_no: 1001, şifre: ${DEMO_PASSWORD}
Dispeçer   → sicil_no: 2001, şifre: ${DEMO_PASSWORD}
Yönetici   → sicil_no: 3001, şifre: ${DEMO_PASSWORD}
`);
