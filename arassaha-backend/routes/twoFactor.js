// İki Faktörlü Doğrulama (2FA) — TOTP tabanlı (RFC 6238), yalnızca yönetici
// rolü için. `otplib` TAMAMEN yerel çalışır — SMS/e-posta gibi ücretli/dış
// bir servise HİÇ bağımlı değildir (bkz. görev talimatı).
//
// GERÇEKLİK NOTU (otplib API sürümü): Bu projede kurulu otplib v13, eski
// `authenticator` tekil (singleton) API'sini (`authenticator.generateSecret()`
// vb.) KALDIRDI — v13 tamamen fonksiyonel bir API sunar (`generateSecret`,
// `generateURI`, `verifySync`). Kod incelemesiyle gerçek API doğrulanıp buna
// göre yazıldı (bkz. node_modules/otplib/dist/functional.d.ts).
//
// GÜVENLİK NOTU — totp_secret DÜZ METİN saklanıyor (bkz. database.js
// userColumnAdditions notu): password_hash'ten FARKLI olarak totp_secret
// TEK YÖNLÜ hash'lenemez — TOTP algoritması her doğrulamada bu secret'ı
// kullanarak KENDİSİ bir kod üretip karşılaştırma yapar; bcrypt gibi bir
// hash'ten orijinal secret geri elde edilemeyeceği için bu iş hash ile
// YAPILAMAZ. Bu PROTOTİPTE bilinçli olarak düz metin saklanıyor — gerçek bir
// üretim sisteminde uygulama seviyesinde (örn. AES-256-GCM + veritabanından
// AYRI bir encryption key) şifrelenmesi gerekir, bkz. README.md.
const crypto = require('crypto');
const express = require('express');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const { generateSecret, generateURI, verifySync } = require('otplib');
const db = require('../database');
const { verifyToken, requireRole, JWT_SECRET } = require('../middleware/auth');
const { createAttemptRateLimiter } = require('../middleware/rateLimiting');
const { issueTokenPair } = require('../utils/authToken');

const router = express.Router();

const TOTP_ISSUER = 'ArasSaha';
const BACKUP_CODE_COUNT = 8;
// 0/O, 1/I/L gibi karışabilecek karakterler BİLİNÇLİ olarak çıkarıldı —
// kullanıcı bir yedek kodu elle okuyup girerken (authenticator'a erişimi
// yoksa) yanlış okuma riskini azaltır.
const BACKUP_CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
// authenticator uygulaması ile sunucu saati arasındaki makul sürüklenme
// payı — otplib'in kendi dokümantasyonundaki "Standard (most 2FA
// implementations)" önerisi (bkz. @otplib/totp/dist/index.d.ts).
const TOTP_EPOCH_TOLERANCE_SECONDS = 30;

function generateRandomBackupCode() {
  const randomChar = () => BACKUP_CODE_CHARS[crypto.randomInt(BACKUP_CODE_CHARS.length)];
  const part = (n) => Array.from({ length: n }, randomChar).join('');
  return `${part(4)}-${part(4)}`;
}

// otplib'in verifySync'i, token TAM OLARAK 6 haneli sayısal DEĞİLSE
// (örn. bir yedek kod gibi "A3F9-K2M1" formatında 9 karakterli bir metin
// gönderilirse) `{ valid: false }` DÖNMEZ, bir TokenLengthError FIRLATIR —
// bu BULUNDU (bkz. görev raporu): /2fa/verify'a bir yedek kod gönderildiğinde
// TOTP kontrolü önce denendiği için bu, düzeltilmeden sunucunun 500 ile
// çökmesine yol açıyordu. Bu yüzden format kontrolü ÖNCEDEN yapılır — 6
// haneli sayısal değilse otplib'e HİÇ gönderilmez, doğrudan geçersiz sayılır
// (akış sorunsuzca yedek kod kontrolüne geçer).
function verifyTotpCode(secret, code) {
  const normalized = String(code).trim();
  if (!/^\d{6}$/.test(normalized)) {
    return { valid: false };
  }
  return verifySync({ secret, token: normalized, epochTolerance: TOTP_EPOCH_TOLERANCE_SECONDS });
}

// POST /api/auth/2fa/setup — yönetici. Yeni bir TOTP secret + 8 yedek kod
// üretir; HENÜZ ETKİNLEŞTİRMEZ (totp_enabled hâlâ 0/değişmez) — kullanıcı
// authenticator uygulamasından okuduğu ilk kodu POST /confirm ile
// doğrulamadan 2FA aktif olmaz. Aksi halde QR kodu yanlış okutulmuş/hiç
// okutulmamış bir kullanıcı, bir sonraki girişte kendini hesabından
// kilitleyebilirdi.
router.post('/setup', verifyToken, requireRole('yonetici'), (req, res) => {
  try {
    const user = db.prepare('SELECT * FROM users WHERE id = ?').get(req.user.id);
    if (!user) {
      return res.status(404).json({ error: 'Kullanıcı bulunamadı.' });
    }

    const secret = generateSecret();
    const otpauthUri = generateURI({ issuer: TOTP_ISSUER, label: user.sicil_no, secret });

    db.prepare('UPDATE users SET totp_secret = ? WHERE id = ?').run(secret, user.id);

    // Önceki bir kurulum denemesinden kalan (henüz onaylanmamış/kullanılmamış)
    // yedek kodlar varsa temizlenir — her /setup çağrısı SIFIRDAN bir kod
    // seti üretir; eski setin geçerli kalması, kullanıcının hangi kodların
    // GÜNCEL olduğunu karıştırmasına yol açardı.
    db.prepare('DELETE FROM totp_backup_codes WHERE user_id = ?').run(user.id);

    const backupCodes = Array.from({ length: BACKUP_CODE_COUNT }, generateRandomBackupCode);
    const insertBackupCode = db.prepare(
      'INSERT INTO totp_backup_codes (user_id, code_hash, used, created_at) VALUES (?, ?, 0, ?)'
    );
    const now = new Date().toISOString();
    for (const code of backupCodes) {
      insertBackupCode.run(user.id, bcrypt.hashSync(code, 10), now);
    }

    // backup_codes SADECE bu response'ta, BİR KEZ düz metin olarak döner —
    // yalnızca hash'leri saklanır; hiçbir endpoint (bu dahil) bunları bir
    // daha asla düz metin olarak GERİ DÖNMEZ.
    res.json({ otpauth_uri: otpauthUri, backup_codes: backupCodes });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '2FA kurulumu başlatılırken bir hata oluştu.' });
  }
});

// POST /api/auth/2fa/confirm — yönetici. Body: { code }
// authenticator'dan okunan İLK kodu doğrular; doğruysa totp_enabled=1 yapar.
router.post('/confirm', verifyToken, requireRole('yonetici'), (req, res) => {
  try {
    const { code } = req.body;
    if (!code) {
      return res.status(400).json({ error: 'code alanı zorunludur.' });
    }

    const user = db.prepare('SELECT * FROM users WHERE id = ?').get(req.user.id);
    if (!user || !user.totp_secret) {
      return res.status(400).json({ error: 'Önce POST /2fa/setup ile bir kurulum başlatmalısınız.' });
    }

    const result = verifyTotpCode(user.totp_secret, code);
    if (!result.valid) {
      return res.status(400).json({ error: 'Geçersiz kod, tekrar deneyin.' });
    }

    db.prepare('UPDATE users SET totp_enabled = 1 WHERE id = ?').run(user.id);
    res.json({ message: '2FA başarıyla etkinleştirildi.' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '2FA doğrulanırken bir hata oluştu.' });
  }
});

// POST /api/auth/2fa/disable — yönetici. Body: { password }
// GÜVENLİK: mevcut şifrenin TEKRAR girilmesi zorunlu — bir saldırgan, ele
// geçirdiği açık bir tarayıcı/oturumdan (yalnızca geçerli JWT ile) 2FA'yı
// KAPATAMAZ; şifreyi de bilmesi gerekir.
router.post('/disable', verifyToken, requireRole('yonetici'), (req, res) => {
  try {
    const { password } = req.body;
    if (!password) {
      return res.status(400).json({ error: 'password alanı zorunludur.' });
    }

    const user = db.prepare('SELECT * FROM users WHERE id = ?').get(req.user.id);
    if (!user || !user.password_hash || !bcrypt.compareSync(password, user.password_hash)) {
      return res.status(401).json({ error: 'Şifre hatalı.' });
    }

    db.prepare('UPDATE users SET totp_enabled = 0, totp_secret = NULL WHERE id = ?').run(user.id);
    db.prepare('DELETE FROM totp_backup_codes WHERE user_id = ?').run(user.id);

    res.json({ message: '2FA devre dışı bırakıldı.' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '2FA devre dışı bırakılırken bir hata oluştu.' });
  }
});

// --- POST /api/auth/2fa/verify — login akışının 2. adımı ---
// GÜVENLİK: verifyToken KULLANILMAZ — henüz tam yetkili bir oturum yok
// (bkz. routes/auth.js POST /login). Bunun yerine kısa ömürlü (5 dk),
// yalnızca bu endpoint için geçerli `pending_token` burada AYRICA/manuel
// olarak doğrulanır (pending2fa: true claim'i olmayan/imzası geçersiz/süresi
// dolmuş bir token her koşulda reddedilir).
function attachPendingTwoFactorUser(req, res, next) {
  const { pending_token } = req.body;
  if (!pending_token || typeof pending_token !== 'string') {
    return res.status(400).json({ error: 'pending_token alanı zorunludur.' });
  }

  let decoded;
  try {
    decoded = jwt.verify(pending_token, JWT_SECRET);
  } catch {
    return res.status(401).json({ error: 'Geçersiz veya süresi dolmuş oturum, tekrar giriş yapın.' });
  }
  if (!decoded.pending2fa || !Number.isInteger(decoded.id)) {
    return res.status(400).json({ error: 'Geçersiz istek.' });
  }

  req.twoFactorPendingUserId = decoded.id;
  next();
}

// Login rate limiting görevindeki (middleware/loginRateLimit.js) AYNI
// desen, middleware/rateLimiting.js'teki genel fabrikayla — burada kimlik
// sicil_no değil, ZATEN doğrulanmış (pending_token imzasından gelen)
// user_id'dir. 6 haneli bir TOTP kodu teorik olarak brute-force edilebilir
// (1.000.000 olasılık) — 30 saniyelik geçerlilik penceresinde pratik
// olmasa da bu, ek bir savunma katmanıdır (bkz. görev talimatı madde 5).
const checkTwoFactorRateLimit = createAttemptRateLimiter({
  table: 'two_factor_verify_attempts',
  identifierColumn: 'user_id',
  getIdentifier: (req) => req.twoFactorPendingUserId ?? null,
});

router.post('/verify', attachPendingTwoFactorUser, checkTwoFactorRateLimit, (req, res) => {
  try {
    const { code } = req.body;
    if (!code) {
      return res.status(400).json({ error: 'code alanı zorunludur.' });
    }

    const user = db.prepare('SELECT * FROM users WHERE id = ?').get(req.twoFactorPendingUserId);
    if (!user || !user.totp_enabled || !user.totp_secret) {
      return res.status(400).json({ error: 'Bu hesap için 2FA etkin değil.' });
    }
    if (!user.is_active) {
      return res.status(403).json({ error: 'Hesabınız pasif durumda, yöneticinizle iletişime geçin.' });
    }

    const totpResult = verifyTotpCode(user.totp_secret, code);

    // Önce TOTP kodu olarak dene; değilse yedek kodlardan biri mi kontrol et.
    let matchedBackupId = null;
    if (!totpResult.valid) {
      const unusedBackupCodes = db
        .prepare('SELECT * FROM totp_backup_codes WHERE user_id = ? AND used = 0')
        .all(user.id);
      for (const backup of unusedBackupCodes) {
        if (bcrypt.compareSync(String(code), backup.code_hash)) {
          matchedBackupId = backup.id;
          break;
        }
      }
    }

    const isValid = totpResult.valid || matchedBackupId !== null;

    // Deneme (başarılı/başarısız) HER ZAMAN kaydedilir — checkTwoFactorRateLimit
    // bir SONRAKİ istekte bu satırları sayar (bkz. routes/auth.js
    // recordLoginAttempt ile AYNI ilke).
    db.prepare(
      'INSERT INTO two_factor_verify_attempts (user_id, ip_address, success, created_at) VALUES (?, ?, ?, ?)'
    ).run(user.id, req.ip, isValid ? 1 : 0, new Date().toISOString());

    if (!isValid) {
      return res.status(401).json({ error: 'Geçersiz kod.' });
    }

    // Yedek kod GERÇEKTEN tek kullanımlıktır — eşleşen satır burada used=1
    // yapılır, bir daha ASLA kabul edilmez (bkz. testler).
    if (matchedBackupId !== null) {
      db.prepare('UPDATE totp_backup_codes SET used = 1 WHERE id = ?').run(matchedBackupId);
    }

    // İki Parçalı Token Sistemi — bkz. routes/auth.js POST /login'deki AYNI
    // issueTokenPair çağrısı. 2FA doğrulaması da, normal (2FA'sız) girişle
    // BİREBİR aynı access+refresh token çiftini üretir.
    const { accessToken, refreshToken } = issueTokenPair(user);
    res.json({
      access_token: accessToken,
      refresh_token: refreshToken,
      user: { id: user.id, name: user.name, role: user.role },
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '2FA doğrulanırken bir hata oluştu.' });
  }
});

module.exports = router;
