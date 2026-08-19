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

// SEC-05: NODE_ENV bazı platformlarda varsayılan olarak ATANMAZ — "production
// gibi davranır" varsaymak yerine, tanımsızsa AÇIKÇA bir konsol uyarısı
// bırakılır. Bu ÖNEMLİ çünkü NODE_ENV production DEĞİLKEN Express'in
// varsayılan hata işleyicisi tam stack trace'i client'a döndürür (bkz.
// middleware/errorHandler.js) — merkezi hata işleyicimiz bunu zaten
// engelliyor, ama bu uyarı bir deploy'un NODE_ENV'i unutması durumunda
// SESSİZCE değil, AÇIKÇA fark edilir olsun diye ek bir güvenlik ağı.
if (!process.env.NODE_ENV) {
  console.warn('[UYARI] NODE_ENV tanımlı değil, varsayılan davranış öngörülemez olabilir');
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
const assistantRouter = require('./routes/assistant');
const kvkkRouter = require('./routes/kvkk');
const adminRouter = require('./routes/admin');
const auditLogRouter = require('./routes/auditLog');
const authRouter = require('./routes/auth');
const uploadsRouter = require('./routes/uploads');
const { verifyToken } = require('./middleware/auth');
const errorHandler = require('./middleware/errorHandler');
const { startScheduledPurgeJobs } = require('./jobs/scheduler');

const app = express();
const PORT = process.env.PORT || 3000;

// Railway (ve genel olarak her ters proxy arkasındaki deploy) bir tek hop
// (reverse proxy) üzerinden istekleri iletir. Bu ayar olmadan Express,
// `req.ip`'yi HER ZAMAN proxy'nin kendi IP'si olarak görür — gerçek istemci
// IP'si `X-Forwarded-For` header'ında gelir ama Express bunu OKUMAZ. Sonuç:
// tüm istekler aynı (proxy) IP'den geliyormuş gibi görünür ve IP bazlı her
// türlü kontrol (bkz. middleware/loginRateLimit.js, routes/auth.js
// loginIpLimiter) anlamsızlaşır — farklı kullanıcılar birbirini kilitler.
// `1` = yalnızca EN YAKIN (bir) hop'a güven; bu, Railway gibi tek katmanlı
// bir proxy önünde çalışırken doğru ve güvenli varsayılan davranıştır.
app.set('trust proxy', 1);

// SEC-05: Express'in varsayılan olarak eklediği `X-Powered-By: Express`
// header'ını kaldırır — kullanılan framework'ü dışarıya açık etmeyi azaltan,
// standart bir sertleştirme adımı (bkz. curl -I ile doğrulama).
app.disable('x-powered-by');

const UPLOADS_DIR = path.join(__dirname, 'uploads');
fs.mkdirSync(UPLOADS_DIR, { recursive: true });
// İSG Bildirimi (Modül 5) fotoğrafları için ayrı bir alt klasör.
fs.mkdirSync(path.join(UPLOADS_DIR, 'isg'), { recursive: true });
// Profil fotoğrafları (Modül 8 — Profil ve Kullanıcı Yönetimi) için ayrı bir alt klasör.
fs.mkdirSync(path.join(UPLOADS_DIR, 'profiles'), { recursive: true });
// İş emri fotoğrafları (Modül 1) için ayrı bir alt klasör — SEC-04 ÖNCESİ bu
// dosyalar `uploads/` KÖKÜNE yazılıyordu (isg/profiles ile TUTARSIZ); yeni
// güvenli statik route'un (routes/uploads.js) klasör whitelist'i ('isg',
// 'workorders', 'profiles') üçünün de KENDİ alt klasörüne sahip olmasını
// varsaydığı için bu tutarsızlık burada giderildi (bkz. routes/workOrders.js).
fs.mkdirSync(path.join(UPLOADS_DIR, 'workorders'), { recursive: true });

app.use(cors());
app.use(express.json());

// SEC-04: eski `express.static` yerine, güvenlik başlıkları ekleyen ve
// path traversal'a karşı ayrıca (whitelist + path.basename + startsWith
// kontrolü ile) savunma yapan özel bir router (bkz. routes/uploads.js).
// Fotoğraflar hâlâ AYNI bu klasörde gerçekten saklanır (bkz. ARCHITECTURE.md
// Bölüm 10 ve 11.2) — sunucu yeniden başlasa da kaybolmaz, yalnızca SERVİS
// EDİLME şekli değişti.
app.use('/uploads', uploadsRouter);

// SEC-05 Adım 0 — GEÇİCİ, yalnızca test amaçlı endpoint. Bilerek yakalanmamış
// bir hata fırlatır; amaç, Express'in varsayılan hata işleyicisinin (NODE_ENV
// production DEĞİLKEN) tam stack trace'i/dosya yollarını client'a HTML olarak
// sızdırdığını kanıtlamak (bkz. test/integration/errorHandling.test.js).
// Yalnızca NODE_ENV === 'test' iken mount edilir — gerçek production/deploy'a
// ASLA gitmez. Aşağıdaki `/api/...` router'larından (hepsi kendi başına
// verifyToken uyguluyor) ÖNCE tanımlanmalı, aksi halde `app.use('/api', ...)`
// ile mount edilen router'lardan biri (örn. riskRouter) bu path'i hiç
// görmeden önce verifyToken 401 ile isteği keser.
if (process.env.NODE_ENV === 'test') {
  app.get('/api/__test-error', () => {
    throw new Error('SEC-05 kasıtlı test hatası — bu asla production\'da tetiklenmemeli');
  });
}

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
// AI Asistan / Sohbet Arayüzü (Modül 16) — tüm roller erişebilir (kendi
// RBAC kapsamındaki veriyi sorgular, bkz. services/assistantQueries.js).
app.use('/api/assistant', verifyToken, assistantRouter);
// KVKK Uyum Modülü — aydınlatma metni + veri özeti + silme talebi akışı
// (bkz. routes/kvkk.js). Diğer tüm modüller gibi verifyToken arkasında;
// yalnızca giriş yapmış kullanıcılar kendi verilerini görebilir/talep açabilir.
app.use('/api/kvkk', verifyToken, kvkkRouter);
// Yönetici Bakım Araçları — bkz. routes/admin.js (kendi içinde
// requireRole('yonetici') uygular, burada yalnızca verifyToken).
app.use('/api/admin', verifyToken, adminRouter);
// Denetim Logu — bkz. routes/auditLog.js (kendi içinde requireRole('yonetici')
// uygular, burada yalnızca verifyToken).
app.use('/api/audit-log', verifyToken, auditLogRouter);

app.get('/', (req, res) => {
  res.json({ message: 'ArasSaha backend çalışıyor.' });
});

// SEC-05: var olmayan bir route'a istek atıldığında Express'in varsayılan
// "Cannot GET /..." HTML sayfası yerine tutarlı, genel bir JSON yanıtı.
// TÜM route'lardan SONRA, hata işleyiciden ÖNCE tanımlanmalı (bkz. Express'in
// middleware eşleştirme sırası — buraya kadar hiçbir route eşleşmediyse
// buraya düşer).
app.use((req, res) => {
  res.status(404).json({ error: 'Endpoint bulunamadı' });
});

// SEC-05: Merkezi hata işleyici — 4 parametreli (err, req, res, next)
// middleware'ler Express tarafından hata işleyici olarak tanınır ve
// ZİNCİRİN EN SONUNDA olmalıdır (bkz. middleware/errorHandler.js).
app.use(errorHandler);

// Test ortamında (NODE_ENV=test) sunucu GERÇEKTEN dinlemeye başlamaz —
// supertest, app nesnesini doğrudan (bir port açmadan) kullanır. Bu, test
// altyapısının çalışabilmesi için gereken tek refactor: app.listen() öncesi
// hiçbir davranış değişmedi, npm start (NODE_ENV=test olmadan çalıştığında)
// eskisiyle birebir aynı şekilde dinlemeye başlar.
if (process.env.NODE_ENV !== 'test') {
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

    // Dosya Temizleme (Orphan + Saklama Süresi) — bkz. jobs/scheduler.js.
    // Yalnızca sunucu GERÇEKTEN dinlemeye başladığında kurulur (testte
    // asla) — her `node --test` çalıştırmasında arka planda asılı kalan bir
    // cron zamanlayıcısı istenmez.
    startScheduledPurgeJobs();
  });
}

// supertest'in `request(app)` ile doğrudan kullanabilmesi için Express app
// nesnesi export edilir (bkz. test/integration/*.test.js).
module.exports = app;
