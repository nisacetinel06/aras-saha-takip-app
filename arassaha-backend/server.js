// ArasSaha backend giriş noktası.
const fs = require('fs');
const path = require('path');

// JWT_SECRET gibi sırlar koda hardcode edilmez, .env dosyasından okunur
// (bkz. ARCHITECTURE.md Modül 7 — Auth). .env deploy ortamında (Railway vb.)
// zaten ortam değişkeni olarak sağlanıyorsa dosya bulunamaz — bu durumda
// sessizce devam edilir, process.env zaten dolu olur.
try {
  process.loadEnvFile(path.join(__dirname, '.env'));
} catch {
  // .env dosyası yoksa (örn. production'da ortam değişkenleri başka
  // şekilde sağlanmışsa) sorun değil; JWT_SECRET yine de process.env'de
  // yoksa auth middleware'i başlangıçta bunu ayrıca kontrol eder.
}

const express = require('express');
const cors = require('cors');
const workOrdersRouter = require('./routes/workOrders');
const usersRouter = require('./routes/users');
const dashboardRouter = require('./routes/dashboard');
const devicesRouter = require('./routes/devices');
const equipmentRouter = require('./routes/equipment');
const riskRouter = require('./routes/risk');
const anomalyRouter = require('./routes/anomaly');
const isgRouter = require('./routes/isg');
const notificationsRouter = require('./routes/notifications');
const nlpRouter = require('./routes/nlp');
const maintenanceRouter = require('./routes/maintenance');
const materialsRouter = require('./routes/materials');
const analyticsRouter = require('./routes/analytics');
const reportsRouter = require('./routes/reports');
const authRouter = require('./routes/auth');
const { verifyToken } = require('./middleware/auth');

const app = express();
const PORT = process.env.PORT || 3000;

const UPLOADS_DIR = path.join(__dirname, 'uploads');
fs.mkdirSync(UPLOADS_DIR, { recursive: true });
// İSG Bildirimi (Modül 5) fotoğrafları için ayrı bir alt klasör.
fs.mkdirSync(path.join(UPLOADS_DIR, 'isg'), { recursive: true });
// Profil fotoğrafları (Modül 8 — Profil ve Kullanıcı Yönetimi) için ayrı bir alt klasör.
fs.mkdirSync(path.join(UPLOADS_DIR, 'profiles'), { recursive: true });

app.use(cors());
app.use(express.json());

// Fotoğraflar gerçekten bu klasörde saklanır ve buradan servis edilir
// (bkz. ARCHITECTURE.md Bölüm 10 ve 11.2) — sunucu yeniden başlasa da kaybolmaz.
app.use('/uploads', express.static(UPLOADS_DIR));

// /api/auth/login hariç TÜM API istekleri geçerli bir JWT taşımak zorunda
// (bkz. ARCHITECTURE.md Modül 7 — Auth + RBAC). Rol bazlı ek kısıtlamalar
// (requireRole) ilgili router'ların içinde uygulanır.
app.use('/api/auth', authRouter);
app.use('/api/workorders', verifyToken, workOrdersRouter);
app.use('/api/users', verifyToken, usersRouter);
app.use('/api/dashboard', verifyToken, dashboardRouter);
app.use('/api/devices', verifyToken, devicesRouter);
app.use('/api/equipment', verifyToken, equipmentRouter);
// riskRouter kendi içinde 'ml/refresh-risk-scores', 'equipment/:id/risk' ve
// 'dashboard/risky-equipment' gibi farklı öneklere sahip tam yollar
// tanımlar (bkz. routes/risk.js); bu yüzden '/api' kökünde mount edilir.
app.use('/api', verifyToken, riskRouter);
// anomalyRouter da riskRouter gibi 'ml/refresh-anomaly-scores',
// 'meters/suspicious', 'equipment/:id/anomaly' gibi farklı öneklere sahip tam
// yollar tanımlar (bkz. routes/anomaly.js) — bu yüzden '/api' kökünde mount edilir.
app.use('/api', verifyToken, anomalyRouter);
app.use('/api/isg-reports', verifyToken, isgRouter);
app.use('/api/notifications', verifyToken, notificationsRouter);
// nlpRouter da riskRouter gibi '/api/ml/...' altında tam yol tanımlar
// (bkz. routes/nlp.js) — bu yüzden '/api' kökünde mount edilir.
app.use('/api', verifyToken, nlpRouter);
// maintenanceRouter da riskRouter gibi 'refresh-recommendations',
// 'recommendations', 'recommendations/:id/...' gibi öneki paylaşan tam
// yollar tanımlar (bkz. routes/maintenance.js) — bu yüzden '/api/maintenance'
// altında mount edilir.
app.use('/api/maintenance', verifyToken, maintenanceRouter);
// materialsRouter da riskRouter gibi 'materials/...', 'workorders/:id/materials...'
// ve 'dashboard/low-stock-materials' gibi farklı öneklere sahip tam yollar
// tanımlar (bkz. routes/materials.js) — bu yüzden '/api' kökünde mount edilir.
app.use('/api', verifyToken, materialsRouter);
app.use('/api/analytics', verifyToken, analyticsRouter);
// Raporlar / Analitik Sayfası (Modül 14) — reportsRouter kendi içinde
// requireRole('yonetici') uygular (bkz. routes/reports.js), burada yalnızca
// verifyToken ile diğer tüm router'larla AYNI kimlik doğrulama uygulanır.
app.use('/api/reports', verifyToken, reportsRouter);

app.get('/', (req, res) => {
  res.json({ message: 'ArasSaha backend çalışıyor.' });
});

app.listen(PORT, async () => {
  console.log(`ArasSaha backend http://localhost:${PORT} üzerinde çalışıyor`);

  // Uygulama açıldığında risk skorlarının güncel olması için başlangıçta bir
  // kere otomatik çalıştırılır (Modül 9). Python ML servisi o an ayakta
  // değilse (bağlantı hatası) bu, sunucunun başlamasını ENGELLEMEZ — hata
  // yutulmaz ama nazikçe loglanır; skorlar POST /api/ml/refresh-risk-scores
  // ile daha sonra elle de tetiklenebilir.
  try {
    const result = await riskRouter.refreshAllRiskScores();
    console.log(
      `Başlangıç risk skorları güncellendi: ${result.updated} ekipman güncellendi, ${result.failed} hata.`
    );
  } catch (err) {
    console.warn('Başlangıçta risk skorları güncellenemedi (ML servisi kapalı olabilir):', err.message);
  }

  // Modül 11 — riskRouter ile AYNI başlangıç deseni (bkz. yukarısı). Sayaçların
  // meter_consumption verisi hiç üretilmediyse (generate_consumption_data.py
  // çalıştırılmadıysa) her sayaç kendi try/catch'inde tek tek başarısız olur;
  // bu, sunucunun başlamasını ENGELLEMEZ.
  try {
    const result = await anomalyRouter.refreshAllAnomalyScores();
    console.log(
      `Başlangıç anomali skorları güncellendi: ${result.updated} sayaç güncellendi, ${result.failed} hata.`
    );
  } catch (err) {
    console.warn('Başlangıçta anomali skorları güncellenemedi (ML servisi kapalı olabilir):', err.message);
  }
});
