// Veritabanına gerçek personel kayıtları, 15 adet sahte iş emri yükler.
// Bu script tekrar çalıştırılabilir olsun diye önce mevcut kayıtları temizler.
const db = require('./database');

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
const personnelSeed = [
  { name: 'Ahmet Yılmaz', role: 'teknisyen', sicil_no: 'T-1001' },
  { name: 'Mehmet Demir', role: 'teknisyen', sicil_no: 'T-1002' },
  { name: 'Ayşe Kaya', role: 'teknisyen', sicil_no: 'T-1003' },
  { name: 'Fatih Şahin', role: 'teknisyen', sicil_no: 'T-1004' },
  { name: 'Emre Çelik', role: 'teknisyen', sicil_no: 'T-1005' },
  { name: 'Hakan Yıldız', role: 'teknisyen', sicil_no: 'T-1006' },
  { name: 'Zeynep Arslan', role: 'dispecer', sicil_no: 'D-2001' },
  { name: 'Murat Öztürk', role: 'yonetici', sicil_no: 'Y-3001' },
];

const priorities = ['acil', 'normal', 'normal', 'dusuk'];

// İstenen dağılım: 5 acik, 4 yolda, 3 sahada, 3 cozuldu (toplam 15)
const statusPlan = [
  'acik', 'acik', 'acik', 'acik', 'acik',
  'yolda', 'yolda', 'yolda', 'yolda',
  'sahada', 'sahada', 'sahada',
  'cozuldu', 'cozuldu', 'cozuldu',
];

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

// Fisher-Yates: locations dizisini karıştırır. statusPlan ile aynı uzunlukta
// (15) olduğu için her konum tam olarak bir kez kullanılır — bu sayede harita
// ekranında pinler 7 ile de dağılır, tek bir noktada üst üste binmez.
function shuffle(arr) {
  const copy = [...arr];
  for (let i = copy.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy;
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

db.exec('DELETE FROM device_action_logs');
db.exec('DELETE FROM managed_devices');
db.exec('DELETE FROM work_order_photos');
db.exec('DELETE FROM work_orders');
db.exec('DELETE FROM equipment');
db.exec('DELETE FROM users');
db.exec(
  "DELETE FROM sqlite_sequence WHERE name IN ('work_orders', 'work_order_photos', 'users', 'managed_devices', 'device_action_logs', 'equipment')"
);

const insertUser = db.prepare(`
  INSERT INTO users (name, role, sicil_no) VALUES (@name, @role, @sicil_no)
`);

const insertedUserIds = personnelSeed.map((person) => insertUser.run(person).lastInsertRowid);
const technicianIds = insertedUserIds.filter((_, i) => personnelSeed[i].role === 'teknisyen');

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
];

const insertEquipment = db.prepare(`
  INSERT INTO equipment
    (qr_code, equipment_type, location_name, lat, lng, install_date, last_maintenance_date, manufacturer, capacity_info, status, created_at)
  VALUES
    (@qr_code, @equipment_type, @location_name, @lat, @lng, @install_date, @last_maintenance_date, @manufacturer, @capacity_info, @status, @created_at)
`);

const equipmentIds = [];
const equipmentIdsWithHistory = [];

db.exec('BEGIN');
try {
  for (const eq of equipmentSeed) {
    const info = insertEquipment.run({
      qr_code: eq.qr_code,
      equipment_type: eq.equipment_type,
      location_name: `${eq.location.il} / ${eq.location.ilce} / ${eq.location.mah}`,
      lat: eq.location.lat + randomJitter(),
      lng: eq.location.lng + randomJitter(),
      install_date: yearsAgoIsoDate(eq.installYears),
      last_maintenance_date: eq.maintenanceMonths == null ? null : monthsAgoIsoDate(eq.maintenanceMonths),
      manufacturer: eq.manufacturer,
      capacity_info: eq.capacity_info,
      status: eq.status,
      created_at: yearsAgoIsoDate(eq.installYears),
    });
    equipmentIds.push(info.lastInsertRowid);
    if (eq.hasHistory) equipmentIdsWithHistory.push(info.lastInsertRowid);
  }
  db.exec('COMMIT');
} catch (err) {
  db.exec('ROLLBACK');
  throw err;
}

const insertWorkOrder = db.prepare(`
  INSERT INTO work_orders
    (title, description, status, priority, location_name, lat, lng, assigned_user_id, equipment_id, created_at, updated_at)
  VALUES
    (@title, @description, @status, @priority, @location_name, @lat, @lng, @assigned_user_id, @equipment_id, @created_at, @updated_at)
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

const firstCozulduIndex = statusPlan.indexOf('cozuldu');
const shuffledLocations = shuffle(locations);

const rows = statusPlan.map((status, index) => {
  const location = shuffledLocations[index];
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
  } else {
    createdAt = randomPastDate(10);
    // Çözülmüş/sahadaki işlerde updated_at, created_at'ten sonraki bir zaman olsun.
    updatedAt = status === 'acik' ? createdAt : new Date(createdAt.getTime() + Math.random() * 2 * 24 * 60 * 60 * 1000);
  }

  return {
    title: `${title} - ${location.mah}`,
    description: `${location.il} / ${location.ilce} bölgesinde ${title.toLowerCase()} bildirildi. Sahada inceleme ve müdahale gerekiyor. (Kayıt #${index + 1})`,
    status,
    priority: pick(priorities),
    location_name: `${location.il} / ${location.ilce} / ${location.mah}`,
    lat: location.lat + randomJitter(),
    lng: location.lng + randomJitter(),
    assigned_user_id: pick(technicianIds),
    // equipment.id'ye giden gerçek bir FK — yalnızca "geçmiş arıza kaydı
    // olsun" diye işaretlenmiş ekipmanlardan seçilir; bu sayede bazı
    // ekipmanların gerçek geçmişi olur, bazılarınınsa hiç olmaz (bkz. yukarı).
    equipment_id: pick(equipmentIdsWithHistory),
    created_at: createdAt.toISOString(),
    updated_at: updatedAt.toISOString(),
  };
});

insertMany(rows);

// Not: Fotoğraflar burada artık sahte/placeholder path ile seed edilmiyor.
// Gerçek dosya diskte yoksa böyle bir kayıt "kaydettim ama görüntülenemiyor" durumuna
// yol açar; bu Temel Kalite İlkesi'ni ihlal eder. Gerçek fotoğraflar yalnızca
// uygulama üzerinden (POST /api/workorders/:id/photos, multipart upload) eklenir.

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

console.log(
  `${insertedUserIds.length} adet kişi, ${equipmentIds.length} adet ekipman, ${rows.length} adet iş emri ve ${deviceSeed.length} adet cihaz kaydı oluşturuldu.`
);
