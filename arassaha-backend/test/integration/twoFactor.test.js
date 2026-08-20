// İki Faktörlü Doğrulama (2FA) — TOTP tabanlı, yalnızca yönetici rolü.
// Mock YOK — gerçek Express app + gerçek :memory: SQLite + gerçek otplib
// (kod üretimi/doğrulaması dahil) + gerçek bcrypt.
//
// otplib'in gerçek zaman tabanlı algoritmasını (RFC 6238) test etmek için
// "QR kod okutma simülasyonu" burada, kurulumda üretilen GERÇEK secret'ı
// DB'den okuyup otplib'in KENDİ `generateSync` fonksiyonuyla o anki geçerli
// kodu üreterek yapılıyor — görev talimatındaki "otplib'in kendi
// authenticator.generate(secret) fonksiyonuyla test için kod üretme"
// önerisinin otplib v13'teki gerçek karşılığı.
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const request = require('supertest');
const { generateSync } = require('otplib');
const app = require('../../server');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData, DEMO_PASSWORD } = require('../helpers/testDb');
const { getTestToken } = require('../helpers/authHelper');

function getUser(id) {
  return db.prepare('SELECT * FROM users WHERE id = ?').get(id);
}

function currentTotpCode(secret) {
  return generateSync({ secret });
}

/** Yönetici için 2FA'yı baştan sona (setup + confirm) etkinleştirir, kullanılan yedek kodları döner. */
async function enableTwoFactorFor(managerToken) {
  const setupResponse = await request(app)
    .post('/api/auth/2fa/setup')
    .set('Authorization', `Bearer ${managerToken}`);
  assert.strictEqual(setupResponse.status, 200, JSON.stringify(setupResponse.body));

  const secret = getUser(getUserIdFromToken(managerToken)).totp_secret;
  const confirmResponse = await request(app)
    .post('/api/auth/2fa/confirm')
    .set('Authorization', `Bearer ${managerToken}`)
    .send({ code: currentTotpCode(secret) });
  assert.strictEqual(confirmResponse.status, 200, JSON.stringify(confirmResponse.body));

  return { secret, backupCodes: setupResponse.body.backup_codes };
}

// Testte token'ın kime ait olduğunu bilmek için basit bir yardımcı — JWT'yi
// çözmek yerine (gereksiz bağımlılık), getTestToken zaten DB'deki gerçek
// kullanıcıdan üretildiği için doğrudan seedMinimalTestData sonucundaki id
// kullanılabilir; bu fonksiyon yalnızca yukarıdaki yardımcının kendi
// içinde "hangi kullanıcı" sorusuna ihtiyaç duyması için mevcut kapsamdaki
// seeded değişkenini okur.
let seeded;
function getUserIdFromToken() {
  return seeded.users.yoneticiId;
}

describe('İki Faktörlü Doğrulama (2FA)', () => {
  let managerToken;
  let technicianToken;
  let dispatcherToken;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
    managerToken = getTestToken('yonetici');
    technicianToken = getTestToken('teknisyen');
    dispatcherToken = getTestToken('dispecer');
  });

  describe('RBAC — 2FA yönetimi yalnızca yönetici', () => {
    it('teknisyen /2fa/setup çağıramaz (403)', async () => {
      const response = await request(app)
        .post('/api/auth/2fa/setup')
        .set('Authorization', `Bearer ${technicianToken}`);
      assert.strictEqual(response.status, 403);
    });

    it('dispeçer /2fa/setup çağıramaz (403)', async () => {
      const response = await request(app)
        .post('/api/auth/2fa/setup')
        .set('Authorization', `Bearer ${dispatcherToken}`);
      assert.strictEqual(response.status, 403);
    });
  });

  describe('[MADDE 1] 2FA kurulumu baştan sona', () => {
    it('setup: otpauth_uri + 8 yedek kod döner, totp_enabled HENÜZ 1 OLMAZ', async () => {
      const response = await request(app)
        .post('/api/auth/2fa/setup')
        .set('Authorization', `Bearer ${managerToken}`);

      assert.strictEqual(response.status, 200);
      assert.match(response.body.otpauth_uri, /^otpauth:\/\/totp\//);
      assert.strictEqual(response.body.backup_codes.length, 8);
      for (const code of response.body.backup_codes) {
        assert.match(code, /^[A-Z0-9]{4}-[A-Z0-9]{4}$/);
      }

      const dbUser = getUser(seeded.users.yoneticiId);
      assert.ok(dbUser.totp_secret, 'secret DB\'ye yazılmalı');
      assert.strictEqual(dbUser.totp_enabled, 0, 'confirm edilmeden totp_enabled 1 OLMAMALI');

      // Yedek kodlar DB'de yalnızca HASH olarak durur, düz metin hiçbir yerde YOK.
      const storedCodes = db.prepare('SELECT code_hash FROM totp_backup_codes WHERE user_id = ?').all(seeded.users.yoneticiId);
      assert.strictEqual(storedCodes.length, 8);
      for (const row of storedCodes) {
        assert.ok(!response.body.backup_codes.includes(row.code_hash));
      }
    });

    it('confirm: doğru TOTP kodu ile totp_enabled=1 olur', async () => {
      const { secret } = await enableTwoFactorFor(managerToken);
      assert.ok(secret);
      assert.strictEqual(getUser(seeded.users.yoneticiId).totp_enabled, 1);
    });

    it('confirm: yanlış kod ile 400 döner, totp_enabled 0 kalır', async () => {
      await request(app).post('/api/auth/2fa/setup').set('Authorization', `Bearer ${managerToken}`);

      const response = await request(app)
        .post('/api/auth/2fa/confirm')
        .set('Authorization', `Bearer ${managerToken}`)
        .send({ code: '000000' });

      assert.strictEqual(response.status, 400);
      assert.strictEqual(getUser(seeded.users.yoneticiId).totp_enabled, 0);
    });
  });

  describe('[MADDE 2] 2FA etkin yöneticiyle giriş — tam token HENÜZ verilmez', () => {
    it('şifre doğru olsa bile requires_2fa:true + pending_token döner, token/user ALANI OLMAZ', async () => {
      await enableTwoFactorFor(managerToken);

      const loginResponse = await request(app)
        .post('/api/auth/login')
        .send({ sicil_no: '3001', password: DEMO_PASSWORD });

      assert.strictEqual(loginResponse.status, 200);
      assert.strictEqual(loginResponse.body.requires_2fa, true);
      assert.strictEqual(typeof loginResponse.body.pending_token, 'string');
      assert.strictEqual(loginResponse.body.token, undefined, 'TAM token HENÜZ verilmemeli');
      assert.strictEqual(loginResponse.body.user, undefined);
    });
  });

  describe('[MADDE 3] doğru TOTP kodu ile /2fa/verify', () => {
    it('tam token döner, normal şekilde kimlik doğrulaması yapılabilir', async () => {
      const { secret } = await enableTwoFactorFor(managerToken);

      const loginResponse = await request(app)
        .post('/api/auth/login')
        .send({ sicil_no: '3001', password: DEMO_PASSWORD });
      const pendingToken = loginResponse.body.pending_token;

      const verifyResponse = await request(app)
        .post('/api/auth/2fa/verify')
        .send({ pending_token: pendingToken, code: currentTotpCode(secret) });

      assert.strictEqual(verifyResponse.status, 200, JSON.stringify(verifyResponse.body));
      assert.strictEqual(typeof verifyResponse.body.token, 'string');
      assert.strictEqual(verifyResponse.body.user.role, 'yonetici');

      // Dönen tam token GERÇEKTEN normal yetkili istekler için kullanılabiliyor mu?
      const meResponse = await request(app)
        .get('/api/auth/me')
        .set('Authorization', `Bearer ${verifyResponse.body.token}`);
      assert.strictEqual(meResponse.status, 200);
      assert.strictEqual(meResponse.body.id, seeded.users.yoneticiId);
    });
  });

  describe('[MADDE 4] yanlış kod ile /2fa/verify', () => {
    it('401 döner, tam token VERİLMEZ', async () => {
      await enableTwoFactorFor(managerToken);
      const loginResponse = await request(app)
        .post('/api/auth/login')
        .send({ sicil_no: '3001', password: DEMO_PASSWORD });

      const verifyResponse = await request(app)
        .post('/api/auth/2fa/verify')
        .send({ pending_token: loginResponse.body.pending_token, code: '000000' });

      assert.strictEqual(verifyResponse.status, 401);
      assert.strictEqual(verifyResponse.body.token, undefined);
    });
  });

  describe('[MADDE 5] yedek kod ile giriş — tek kullanımlık', () => {
    it('yedek kodla giriş başarılı olur, AYNI kod ikinci kez REDDEDİLİR', async () => {
      const { backupCodes } = await enableTwoFactorFor(managerToken);
      const oneBackupCode = backupCodes[0];

      const loginResponse = await request(app)
        .post('/api/auth/login')
        .send({ sicil_no: '3001', password: DEMO_PASSWORD });
      const pendingToken = loginResponse.body.pending_token;

      const firstUse = await request(app)
        .post('/api/auth/2fa/verify')
        .send({ pending_token: pendingToken, code: oneBackupCode });
      assert.strictEqual(firstUse.status, 200, JSON.stringify(firstUse.body));
      assert.strictEqual(typeof firstUse.body.token, 'string');

      // used=1 GERÇEKTEN DB'de işaretlendi mi?
      const usedRow = db.prepare('SELECT used FROM totp_backup_codes WHERE user_id = ?').all(seeded.users.yoneticiId).find((r) => r.used === 1);
      assert.ok(usedRow, 'kullanılan yedek kod DB\'de used=1 olarak işaretlenmeli');

      // Yeni bir pending_token ile (5 dk içinde) İKİNCİ kez AYNI kodu dene.
      const secondLoginResponse = await request(app)
        .post('/api/auth/login')
        .send({ sicil_no: '3001', password: DEMO_PASSWORD });
      const secondUse = await request(app)
        .post('/api/auth/2fa/verify')
        .send({ pending_token: secondLoginResponse.body.pending_token, code: oneBackupCode });

      assert.strictEqual(secondUse.status, 401, 'kullanılmış bir yedek kod İKİNCİ kez KABUL EDİLMEMELİ');
    });
  });

  describe('[MADDE 6] teknisyen/dispeçer regresyonu — tek adımda normal giriş', () => {
    it('teknisyen tek adımda tam token alır (2FA hiç devreye girmez)', async () => {
      const response = await request(app)
        .post('/api/auth/login')
        .send({ sicil_no: '1001', password: DEMO_PASSWORD });

      assert.strictEqual(response.status, 200);
      assert.strictEqual(typeof response.body.token, 'string');
      assert.strictEqual(response.body.requires_2fa, undefined);
    });

    it('dispeçer tek adımda tam token alır', async () => {
      const response = await request(app)
        .post('/api/auth/login')
        .send({ sicil_no: '2001', password: DEMO_PASSWORD });

      assert.strictEqual(response.status, 200);
      assert.strictEqual(typeof response.body.token, 'string');
    });

    it('2FA\'sı KAPALI bir yönetici de tek adımda tam token alır (yalnızca 2FA etkin yöneticiler etkilenir)', async () => {
      const response = await request(app)
        .post('/api/auth/login')
        .send({ sicil_no: '3001', password: DEMO_PASSWORD });

      assert.strictEqual(response.status, 200);
      assert.strictEqual(typeof response.body.token, 'string');
      assert.strictEqual(response.body.requires_2fa, undefined);
    });
  });

  describe('[MADDE 7] /2fa/verify brute-force koruması', () => {
    it('art arda 5 yanlış kod sonrası, DOĞRU kod bile 429 ile reddedilir', async () => {
      const { secret } = await enableTwoFactorFor(managerToken);
      const loginResponse = await request(app)
        .post('/api/auth/login')
        .send({ sicil_no: '3001', password: DEMO_PASSWORD });
      const pendingToken = loginResponse.body.pending_token;

      for (let i = 0; i < 5; i++) {
        const r = await request(app)
          .post('/api/auth/2fa/verify')
          .send({ pending_token: pendingToken, code: '000000' });
        assert.strictEqual(r.status, 401, `${i + 1}. deneme henüz kilitlenmemiş olmalı`);
      }

      const lockedResponse = await request(app)
        .post('/api/auth/2fa/verify')
        .send({ pending_token: pendingToken, code: currentTotpCode(secret) });

      assert.strictEqual(lockedResponse.status, 429, 'eşiğe ulaşıldıktan sonra DOĞRU kod bile işe yaramamalı');
      assert.strictEqual(lockedResponse.body.token, undefined);
    });
  });

  describe('ek senaryolar', () => {
    it('geçersiz/uydurma pending_token: 401', async () => {
      const response = await request(app)
        .post('/api/auth/2fa/verify')
        .send({ pending_token: 'bu-gecerli-bir-jwt-degil', code: '123456' });
      assert.strictEqual(response.status, 401);
    });

    it('TAM (pending OLMAYAN) bir token pending_token olarak gönderilirse: 400', async () => {
      // Normal /login'den (2FA'sız bir kullanıcı) alınan GERÇEK tam token —
      // pending2fa claim'i taşımadığı için reddedilmeli.
      const loginResponse = await request(app)
        .post('/api/auth/login')
        .send({ sicil_no: '1001', password: DEMO_PASSWORD });

      const response = await request(app)
        .post('/api/auth/2fa/verify')
        .send({ pending_token: loginResponse.body.token, code: '123456' });
      assert.strictEqual(response.status, 400);
    });

    it('pending_token eksikse: 400', async () => {
      const response = await request(app).post('/api/auth/2fa/verify').send({ code: '123456' });
      assert.strictEqual(response.status, 400);
    });

    it('disable: yanlış şifreyle 401 döner, totp_enabled DEĞİŞMEZ', async () => {
      await enableTwoFactorFor(managerToken);

      const response = await request(app)
        .post('/api/auth/2fa/disable')
        .set('Authorization', `Bearer ${managerToken}`)
        .send({ password: 'yanlis-sifre' });

      assert.strictEqual(response.status, 401);
      assert.strictEqual(getUser(seeded.users.yoneticiId).totp_enabled, 1);
    });

    it('disable: doğru şifreyle 2FA kapanır, sonraki giriş tekrar tek adımlı olur', async () => {
      await enableTwoFactorFor(managerToken);

      const disableResponse = await request(app)
        .post('/api/auth/2fa/disable')
        .set('Authorization', `Bearer ${managerToken}`)
        .send({ password: DEMO_PASSWORD });

      assert.strictEqual(disableResponse.status, 200);
      assert.strictEqual(getUser(seeded.users.yoneticiId).totp_enabled, 0);
      assert.strictEqual(getUser(seeded.users.yoneticiId).totp_secret, null, 'secret de temizlenmeli');

      const loginResponse = await request(app)
        .post('/api/auth/login')
        .send({ sicil_no: '3001', password: DEMO_PASSWORD });
      assert.strictEqual(typeof loginResponse.body.token, 'string');
      assert.strictEqual(loginResponse.body.requires_2fa, undefined);
    });

    it('GET /api/users/me yanıtı totp_enabled İÇERİR ama totp_secret ASLA içermez', async () => {
      await enableTwoFactorFor(managerToken);

      const response = await request(app)
        .get('/api/users/me')
        .set('Authorization', `Bearer ${managerToken}`);

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.totp_enabled, true);
      assert.strictEqual(response.body.totp_secret, undefined, 'totp_secret HİÇBİR yanıtta dönmemeli');
    });
  });
});
