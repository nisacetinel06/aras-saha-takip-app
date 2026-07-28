// ArasSaha backend giriş noktası.
const fs = require('fs');
const path = require('path');
const express = require('express');
const cors = require('cors');
const workOrdersRouter = require('./routes/workOrders');
const usersRouter = require('./routes/users');
const dashboardRouter = require('./routes/dashboard');

const app = express();
const PORT = 3000;

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

app.get('/', (req, res) => {
  res.json({ message: 'ArasSaha backend çalışıyor.' });
});

app.listen(PORT, () => {
  console.log(`ArasSaha backend http://localhost:${PORT} üzerinde çalışıyor`);
});
