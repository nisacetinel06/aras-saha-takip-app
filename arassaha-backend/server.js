// ArasSaha backend giriş noktası.
const fs = require('fs');
const path = require('path');
const express = require('express');
const cors = require('cors');
const workOrdersRouter = require('./routes/workOrders');
const usersRouter = require('./routes/users');
const dashboardRouter = require('./routes/dashboard');
const devicesRouter = require('./routes/devices');
const equipmentRouter = require('./routes/equipment');
const riskRouter = require('./routes/risk');

const app = express();
const PORT = process.env.PORT || 3000;

const UPLOADS_DIR = path.join(__dirname, 'uploads');
fs.mkdirSync(UPLOADS_DIR, { recursive: true });

app.use(cors());
app.use(express.json());

// Fotoğraflar gerçekten bu klasörde saklanır ve buradan servis edilir
// (bkz. ARCHITECTURE.md Bölüm 10 ve 11.2) — sunucu yeniden başlasa da kaybolmaz.
app.use('/uploads', express.static(UPLOADS_DIR));

app.use('/api/workorders', workOrdersRouter);
app.use('/api/users', usersRouter);
app.use('/api/dashboard', dashboardRouter);
app.use('/api/devices', devicesRouter);
app.use('/api/equipment', equipmentRouter);
// riskRouter kendi içinde 'ml/refresh-risk-scores', 'equipment/:id/risk' ve
// 'dashboard/risky-equipment' gibi farklı öneklere sahip tam yollar
// tanımlar (bkz. routes/risk.js); bu yüzden '/api' kökünde mount edilir.
app.use('/api', riskRouter);

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
});
