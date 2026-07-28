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

function equipmentRef() {
  const year = 2020 + Math.floor(Math.random() * 5);
  const num = String(Math.floor(Math.random() * 9999)).padStart(4, '0');
  return `TR-${year}-${num}`;
}

db.exec('DELETE FROM work_order_photos');
db.exec('DELETE FROM work_orders');
db.exec('DELETE FROM users');
db.exec("DELETE FROM sqlite_sequence WHERE name IN ('work_orders', 'work_order_photos', 'users')");

const insertUser = db.prepare(`
  INSERT INTO users (name, role, sicil_no) VALUES (@name, @role, @sicil_no)
`);

const insertedUserIds = personnelSeed.map((person) => insertUser.run(person).lastInsertRowid);
const technicianIds = insertedUserIds.filter((_, i) => personnelSeed[i].role === 'teknisyen');

const insertWorkOrder = db.prepare(`
  INSERT INTO work_orders
    (title, description, status, priority, location_name, lat, lng, assigned_user_id, equipment_ref, created_at, updated_at)
  VALUES
    (@title, @description, @status, @priority, @location_name, @lat, @lng, @assigned_user_id, @equipment_ref, @created_at, @updated_at)
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
    equipment_ref: equipmentRef(),
    created_at: createdAt.toISOString(),
    updated_at: updatedAt.toISOString(),
  };
});

insertMany(rows);

// Not: Fotoğraflar burada artık sahte/placeholder path ile seed edilmiyor.
// Gerçek dosya diskte yoksa böyle bir kayıt "kaydettim ama görüntülenemiyor" durumuna
// yol açar; bu Temel Kalite İlkesi'ni ihlal eder. Gerçek fotoğraflar yalnızca
// uygulama üzerinden (POST /api/workorders/:id/photos, multipart upload) eklenir.

console.log(`${insertedUserIds.length} adet kişi ve ${rows.length} adet iş emri oluşturuldu.`);
