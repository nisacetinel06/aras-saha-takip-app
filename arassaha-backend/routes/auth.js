// Auth (Modül 7): sicil no + şifre ile giriş, JWT tabanlı oturum.
const express = require('express');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const rateLimit = require('express-rate-limit');
const db = require('../database');
const { verifyToken, JWT_SECRET } = require('../middleware/auth');
const { checkLoginRateLimit } = require('../middleware/loginRateLimit');
const { createAttemptRateLimiter } = require('../middleware/rateLimiting');
const { generateAccessToken, issueTokenPair } = require('../utils/authToken');
const {
  hashToken,
  issueRefreshToken,
  findRefreshTokenByHash,
  revokeRefreshToken,
  revokeAllRefreshTokensForUser,
} = require('../utils/refreshToken');

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

    // İki Faktörlü Doğrulama (2FA) — bkz. routes/twoFactor.js. Yalnızca
    // yönetici rolü VE 2FA GERÇEKTEN etkinleştirilmişse (totp_enabled=1)
    // devreye girer; teknisyen/dispeçer VEYA 2FA'sı kapalı bir yönetici için
    // davranış aşağıdaki mevcut tam-token akışıyla TAMAMEN AYNI kalır. Şifre
    // doğru olsa bile TAM yetkili bir JWT HENÜZ verilmez — yalnızca 5 dakika
    // geçerli, SADECE POST /2fa/verify'a gönderilebilecek (pending2fa: true
    // claim'li) kısa ömürlü bir "ara" token döner.
    if (user.role === 'yonetici' && user.totp_enabled) {
      const pendingToken = jwt.sign({ id: user.id, pending2fa: true }, JWT_SECRET, { expiresIn: '5m' });
      return res.json({ requires_2fa: true, pending_token: pendingToken });
    }

    // İki Parçalı Token Sistemi (Access + Refresh) — bkz. utils/authToken.js,
    // utils/refreshToken.js. access_token kısa ömürlü (15 dk, stateless
    // JWT); refresh_token uzun ömürlü (30 gün) AMA sunucu tarafında
    // İZLENEBİLİR/İPTAL EDİLEBİLİR (bkz. POST /refresh, POST /logout).
    const { accessToken, refreshToken } = issueTokenPair(user);

    res.json({
      access_token: accessToken,
      refresh_token: refreshToken,
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

// POST /api/auth/refresh — herkese açık (verifyToken KULLANILMAZ; access
// token zaten geçersiz/süresi dolmuş olabileceği için asıl kimlik kanıtı
// burada refresh_token'ın KENDİSİDİR). Body: { refresh_token }
//
// ROTASYON + YENİDEN KULLANIM TESPİTİ (en kritik kısım — bkz. görev
// talimatı): HER başarılı /refresh çağrısı, KULLANILAN token'ı iptal edip
// YENİ bir çift üretir — bu sayede her refresh token TEK KULLANIMLIKTIR.
// İPTAL EDİLMİŞ bir token TEKRAR kullanılmaya çalışılırsa, bu GÜÇLÜ bir
// çalınma sinyalidir: meşru istemci zaten rotasyonla yeni bir token almıştı,
// aynı eski (artık geçersiz) token'ı BAŞKA biri de kullanmaya çalışıyor
// demektir — bu durumda kullanıcının TÜM refresh token'ları (yeni alınanı
// DAHİL) iptal edilir, savunmacı bir "her yerden zorla çıkış".
router.post('/refresh', (req, res) => {
  try {
    const { refresh_token } = req.body;
    if (!refresh_token || typeof refresh_token !== 'string') {
      return res.status(400).json({ error: 'refresh_token gerekli.' });
    }

    const tokenHash = hashToken(refresh_token);
    const record = findRefreshTokenByHash(tokenHash);

    if (!record) {
      return res.status(401).json({ error: 'Geçersiz refresh token.' });
    }

    if (record.revoked === 1) {
      revokeAllRefreshTokensForUser(record.user_id);
      console.error(
        `[GÜVENLİK UYARISI] Kullanıcı #${record.user_id} için refresh token yeniden kullanım denemesi tespit edildi — tüm oturumlar iptal edildi.`
      );
      return res.status(401).json({ error: 'Güvenlik ihlali tespit edildi, lütfen tekrar giriş yapın.' });
    }

    if (new Date(record.expires_at) < new Date()) {
      return res.status(401).json({ error: 'Refresh token süresi dolmuş, lütfen tekrar giriş yapın.' });
    }

    const user = db.prepare('SELECT * FROM users WHERE id = ?').get(record.user_id);
    if (!user || !user.is_active) {
      return res.status(401).json({ error: 'Hesap bulunamadı veya pasif.' });
    }

    // ROTASYON: eski token'ı iptal et, yeni bir çift üret — TEK bir
    // transaction içinde (bkz. routes/materials.js/routes/kvkk.js'teki AYNI
    // disiplin): eski token iptal edilip yenisi hiç üretilmeden aradaki bir
    // hata kullanıcıyı "elindeki tek token iptal, yenisi yok" durumunda
    // kilitli bırakabilirdi.
    let newAccessToken;
    let newRefreshToken;
    db.exec('BEGIN');
    try {
      newAccessToken = generateAccessToken(user);
      newRefreshToken = issueRefreshToken(user.id);
      revokeRefreshToken(record.id, hashToken(newRefreshToken));
      db.exec('COMMIT');
    } catch (txErr) {
      db.exec('ROLLBACK');
      throw txErr;
    }

    res.json({ access_token: newAccessToken, refresh_token: newRefreshToken });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Token yenilenirken bir hata oluştu.' });
  }
});

// POST /api/auth/logout — herkese açık (access token ZATEN süresi dolmuş
// olabilir, kullanıcı yine de "çıkış yapmak" isteyebilir — bu yüzden
// verifyToken KULLANILMAZ). Body: { refresh_token }
//
// Yalnızca YEREL depolamayı temizlemek YETERLİ DEĞİLDİ (bkz. "Güvenli
// Token Saklama" görevi) — bu artık GERÇEK bir sunucu tarafı iptaldir:
// refresh_token revoked=1 yapılır, bir daha /refresh'te KABUL EDİLMEZ.
// İdempotent: token zaten yoksa/geçersizse/zaten iptal edilmişse bile
// İSTEMCİ AÇISINDAN başarı sayılır (200) — "çıkış" işlemi asla
// başarısız GÖRÜNMEMELİDİR.
router.post('/logout', (req, res) => {
  try {
    const { refresh_token } = req.body;
    if (!refresh_token || typeof refresh_token !== 'string') {
      return res.status(400).json({ error: 'refresh_token gerekli.' });
    }

    const tokenHash = hashToken(refresh_token);
    const record = findRefreshTokenByHash(tokenHash);
    if (record && record.revoked === 0) {
      revokeRefreshToken(record.id);
    }

    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Çıkış yapılırken bir hata oluştu.' });
  }
});

// "Şifremi Değiştir" deneme sınırlaması — routes/twoFactor.js'teki
// checkTwoFactorRateLimit ile BİREBİR AYNI desen, yalnızca farklı bir
// tabloda (password_change_attempts, bkz. database.js). Bu endpoint zaten
// geçerli bir JWT gerektirdiği için login kadar kritik bir brute-force
// riski taşımaz, ama "mevcut şifre" alanına karşı deneme sınırlaması
// savunma derinliği açısından eklendi.
const checkPasswordChangeRateLimit = createAttemptRateLimiter({
  table: 'password_change_attempts',
  identifierColumn: 'user_id',
  getIdentifier: (req) => req.user?.id ?? null,
});

// POST /api/auth/change-password — giriş yapmış HERKES kendi şifresini
// değiştirir. Admin'in PATCH /api/users/:id/reset-password'ünden BİLİNÇLİ
// olarak AYRI bir endpoint, KARIŞTIRILMAMALI: reset-password bir KURTARMA
// akışıdır (kullanıcı şifresini unutmuştur, mevcut şifreyi bilemez, bu
// yüzden istenmez); bu endpoint ise kullanıcının KENDİ isteğiyle, kendi
// bildiği şifreyle yaptığı bir değişikliktir — mevcut şifre doğrulaması
// olmadan, kilidi açık bırakılmış bir cihaza kısa süreliğine erişen biri
// kullanıcıyı sessizce hesaptan atabilirdi (bkz. dosya başı dokümantasyonu).
router.post('/change-password', verifyToken, checkPasswordChangeRateLimit, (req, res) => {
  try {
    const { current_password, new_password } = req.body;

    if (!current_password || !new_password) {
      return res.status(400).json({ error: 'Mevcut ve yeni şifre gerekli.' });
    }
    if (new_password.length < 8) {
      return res.status(400).json({ error: 'Yeni şifre en az 8 karakter olmalı.' });
    }
    if (current_password === new_password) {
      return res.status(400).json({ error: 'Yeni şifre mevcut şifreyle aynı olamaz.' });
    }

    const user = db.prepare('SELECT * FROM users WHERE id = ?').get(req.user.id);
    if (!user) {
      return res.status(404).json({ error: 'Kullanıcı bulunamadı.' });
    }

    const isCurrentPasswordCorrect = bcrypt.compareSync(current_password, user.password_hash);

    // Deneme (başarılı/başarısız) HER ZAMAN kaydedilir — checkPasswordChangeRateLimit
    // bir SONRAKİ istekte bu satırları sayar (bkz. routes/twoFactor.js AYNI ilke).
    db.prepare(
      'INSERT INTO password_change_attempts (user_id, ip_address, success, created_at) VALUES (?, ?, ?, ?)'
    ).run(req.user.id, req.ip, isCurrentPasswordCorrect ? 1 : 0, new Date().toISOString());

    if (!isCurrentPasswordCorrect) {
      return res.status(401).json({ error: 'Mevcut şifre hatalı.' });
    }

    const newHash = bcrypt.hashSync(new_password, 10);
    db.prepare('UPDATE users SET password_hash = ? WHERE id = ?').run(newHash, req.user.id);

    // Kullanıcı Yönetimi işlem geçmişiyle AYNI tablo/desen (bkz.
    // routes/users.js logUserAction) — o anki ADI yazılır (isim sonradan
    // değişse bile geçmiş kaydı doğru kalsın diye).
    db.prepare(
      'INSERT INTO user_action_logs (target_user_id, action_type, performed_by, created_at) VALUES (?, ?, ?, ?)'
    ).run(req.user.id, 'sifre_degistirildi_kendisi', user.name, new Date().toISOString());

    // Şifre değiştiğinde TÜM oturumlar (bu cihaz DAHİL) iptal edilir — bir
    // saldırganın çalınmış bir refresh_token'ı hâlâ elinde tutuyor olması
    // ihtimaline karşı. Flutter tarafı bu davranışa göre kullanıcıyı
    // otomatik olarak Login ekranına düşürür (bkz.
    // screens/settings/change_password_screen.dart).
    revokeAllRefreshTokensForUser(req.user.id);

    res.json({ message: 'Şifreniz başarıyla değiştirildi.' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Şifre değiştirilirken bir hata oluştu.' });
  }
});

// POST /api/auth/register-fcm-token — Push Bildirim (FCM), bkz.
// services/pushNotificationService.js, utils/notify.js. Giriş yapmış HERKES
// kendi cihaz token'ını kaydeder/günceller. Body: { fcm_token: string|null }
// — Flutter tarafı çıkış yaparken (bkz. AuthProvider.logout) `null` göndererek
// çıkış yapılmış bir cihaza artık bildirim gitmemesini sağlar.
router.post('/register-fcm-token', verifyToken, (req, res) => {
  try {
    const { fcm_token } = req.body;
    if (fcm_token !== null && typeof fcm_token !== 'string') {
      return res.status(400).json({ error: 'fcm_token alanı zorunludur.' });
    }

    db.prepare('UPDATE users SET fcm_token = ? WHERE id = ?').run(fcm_token, req.user.id);
    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Bildirim token\'ı kaydedilirken bir hata oluştu.' });
  }
});

module.exports = router;
