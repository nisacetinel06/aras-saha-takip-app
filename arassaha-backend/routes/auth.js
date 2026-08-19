// Auth (Modül 7): sicil no + şifre ile giriş, JWT tabanlı oturum.
const express = require('express');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const rateLimit = require('express-rate-limit');
const db = require('../database');
const { verifyToken, JWT_SECRET } = require('../middleware/auth');
const { checkLoginRateLimit } = require('../middleware/loginRateLimit');

const router = express.Router();

// Sicil_no+IP bazlı kilidin ("checkLoginRateLimit") dışında, ek bir genel
// savunma katmanı: aynı IP'den dakikada en fazla 20 istek. Bu, sicil_no
// bazlı kilidin "her sicil_no ayrı sayaç" mantığını atlatmaya çalışıp çok
// sayıda FARKLI sicil_no deneyen bir saldırganı yakalar.
//
// Test ortamında (NODE_ENV=test) devre dışı bırakılır: `node --test` TÜM test
// dosyalarını AYNI süreçte/AYNI Express app örneğinde çalıştırdığı için, bu
// katmanın bellek içi sayacı test dosyaları arasında PAYLAŞILIR — TEST-06 ve
// bu görevin kendi login testleri toplamda dakikada 20'den fazla /login
// isteği gönderiyor, bu da bu katmanla (test edilen asıl mekanizma olan
// sicil_no+IP kilidiyle İLGİSİZ) sahte 429'lara ve testlerin birbirini
// etkilemesine yol açardı.
const loginIpLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  skip: () => process.env.NODE_ENV === 'test',
  message: { error: 'Çok fazla istek, lütfen bir dakika sonra tekrar deneyin.' },
});

function recordLoginAttempt(sicil_no, ip, success) {
  db.prepare('INSERT INTO login_attempts (sicil_no, ip_address, success, created_at) VALUES (?, ?, ?, ?)').run(
    String(sicil_no),
    ip,
    success ? 1 : 0,
    new Date().toISOString()
  );
}

// POST /api/auth/login
// Body: { sicil_no, password }
router.post('/login', loginIpLimiter, checkLoginRateLimit, (req, res) => {
  try {
    const { sicil_no, password } = req.body;

    if (!sicil_no || !password) {
      return res.status(400).json({ error: 'sicil_no ve password alanları zorunludur.' });
    }

    const user = db.prepare('SELECT * FROM users WHERE sicil_no = ?').get(sicil_no);

    // Kullanıcı bulunamasa bile aynı genel mesajı döneriz — hangi alanın
    // hatalı olduğunu (sicil no mu şifre mi) belli etmemek kasıtlıdır.
    const invalidCredentials = () => {
      recordLoginAttempt(sicil_no, req.ip, false);
      return res.status(401).json({ error: 'Sicil no veya şifre hatalı.' });
    };

    if (!user || !user.password_hash) {
      return invalidCredentials();
    }

    const passwordMatches = bcrypt.compareSync(password, user.password_hash);
    if (!passwordMatches) {
      return invalidCredentials();
    }

    if (!user.is_active) {
      recordLoginAttempt(sicil_no, req.ip, false);
      return res.status(403).json({ error: 'Hesabınız pasif durumda, yöneticinizle iletişime geçin.' });
    }

    recordLoginAttempt(sicil_no, req.ip, true);

    const token = jwt.sign({ id: user.id, role: user.role }, JWT_SECRET, { expiresIn: '7d' });

    res.json({
      token,
      user: { id: user.id, name: user.name, role: user.role },
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Giriş yapılırken bir hata oluştu.' });
  }
});

// GET /api/auth/me
// Header'daki token'ı doğrular, o kullanıcının GÜNCEL bilgisini döner (uygulama
// açılışında oturumun hâlâ geçerli olduğunu kontrol etmek için kullanılır).
router.get('/me', verifyToken, (req, res) => {
  try {
    const user = db.prepare('SELECT id, name, role FROM users WHERE id = ?').get(req.user.id);
    if (!user) {
      return res.status(401).json({ error: 'Kullanıcı artık mevcut değil.' });
    }
    res.json(user);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Kullanıcı bilgisi alınırken bir hata oluştu.' });
  }
});

module.exports = router;
