// Auth (Modül 7): sicil no + şifre ile giriş, JWT tabanlı oturum.
const express = require('express');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const db = require('../database');
const { verifyToken, JWT_SECRET } = require('../middleware/auth');

const router = express.Router();

// POST /api/auth/login
// Body: { sicil_no, password }
router.post('/login', (req, res) => {
  try {
    const { sicil_no, password } = req.body;

    if (!sicil_no || !password) {
      return res.status(400).json({ error: 'sicil_no ve password alanları zorunludur.' });
    }

    const user = db.prepare('SELECT * FROM users WHERE sicil_no = ?').get(sicil_no);

    // Kullanıcı bulunamasa bile aynı genel mesajı döneriz — hangi alanın
    // hatalı olduğunu (sicil no mu şifre mi) belli etmemek kasıtlıdır.
    const invalidCredentials = () => res.status(401).json({ error: 'Sicil no veya şifre hatalı.' });

    if (!user || !user.password_hash) {
      return invalidCredentials();
    }

    const passwordMatches = bcrypt.compareSync(password, user.password_hash);
    if (!passwordMatches) {
      return invalidCredentials();
    }

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
