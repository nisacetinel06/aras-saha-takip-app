// Access + Refresh Token Sistemi — bkz. utils/authToken.js, utils/refreshToken.js,
// routes/auth.js (POST /refresh, POST /logout). Mock YOK — gerçek Express app +
// gerçek :memory: SQLite + gerçek JWT üretimi/doğrulaması.
//
// Bu dosya görev talimatındaki 7 test senaryosunun BACKEND tarafını kanıtlar:
//   1) login hem access_token hem refresh_token döner (auth.test.js/authLogin.test.js'te de var, burada refresh sistemine özel tekrar doğrulanır)
//   2) access token gerçekten kısa ömründen sonra süresi dolar
//   3) süresi dolmuş access token + /refresh -> yeni GEÇERLİ bir access token
//   4) ROTASYON + YENİDEN KULLANIM TESPİTİ (en kritik senaryo)
//   5) logout sonrası o refresh_token /refresh'te artık KABUL EDİLMEZ
//   7) süresi dolmuş/iptal edilmiş bir refresh_token ile Login sayfasına
//      yönlendirmeyi tetikleyecek 401 (Flutter tarafı bunu SessionExpiredException'a çevirir)
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const request = require('supertest');
const app = require('../../server');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData, DEMO_PASSWORD } = require('../helpers/testDb');
const { generateAccessToken, issueTokenPair } = require('../../utils/authToken');
const { hashToken } = require('../../utils/refreshToken');

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

describe('Access + Refresh Token Sistemi', () => {
  let seeded;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
  });

  it('[TEST 1] login hem access_token hem refresh_token döner, ikisi de FARKLI ve dolu string\'lerdir', async () => {
    const response = await request(app).post('/api/auth/login').send({ sicil_no: '1001', password: DEMO_PASSWORD });

    assert.strictEqual(response.status, 200);
    assert.strictEqual(typeof response.body.access_token, 'string');
    assert.ok(response.body.access_token.length > 0);
    assert.strictEqual(typeof response.body.refresh_token, 'string');
    assert.ok(response.body.refresh_token.length > 0);
    assert.notStrictEqual(response.body.access_token, response.body.refresh_token);
  });

  it('[TEST 2] access token gerçekten çok kısa ömründen (test-only expiresIn) sonra süresi dolar, korumalı endpoint 401 döner', async () => {
    const user = db.prepare('SELECT * FROM users WHERE sicil_no = ?').get('1001');
    // generateAccessToken'ın expiresIn parametresi HİÇBİR API isteğinden
    // erişilemez (bkz. utils/authToken.js) — burada, gerçek 15 dakika
    // beklemeden süre dolumu davranışını test etmek için doğrudan sunucu
    // tarafı kod olarak çağrılıyor.
    const shortLivedToken = generateAccessToken(user, { expiresIn: '1s' });

    const immediateResponse = await request(app)
      .get('/api/auth/me')
      .set('Authorization', `Bearer ${shortLivedToken}`);
    assert.strictEqual(immediateResponse.status, 200, 'token henüz süresi dolmadan geçerli olmalı');

    await sleep(1200);

    const expiredResponse = await request(app)
      .get('/api/auth/me')
      .set('Authorization', `Bearer ${shortLivedToken}`);
    assert.strictEqual(expiredResponse.status, 401, 'süresi dolmuş access token 401 dönmeli');
  });

  it('[TEST 3] süresi dolmuş access token + /refresh -> YENİ geçerli bir access token alınabilir, eski işe yaramaz', async () => {
    const user = db.prepare('SELECT * FROM users WHERE sicil_no = ?').get('1001');
    const { accessToken: expiredAccessToken, refreshToken } = issueTokenPair(user, { accessTokenExpiresIn: '1s' });

    await sleep(1200);

    const expiredResponse = await request(app)
      .get('/api/auth/me')
      .set('Authorization', `Bearer ${expiredAccessToken}`);
    assert.strictEqual(expiredResponse.status, 401, 'süresi dolmuş access token reddedilmeli');

    const refreshResponse = await request(app).post('/api/auth/refresh').send({ refresh_token: refreshToken });
    assert.strictEqual(refreshResponse.status, 200, JSON.stringify(refreshResponse.body));
    assert.strictEqual(typeof refreshResponse.body.access_token, 'string');
    assert.notStrictEqual(refreshResponse.body.access_token, expiredAccessToken);

    const meResponse = await request(app)
      .get('/api/auth/me')
      .set('Authorization', `Bearer ${refreshResponse.body.access_token}`);
    assert.strictEqual(meResponse.status, 200, 'refresh ile alınan YENİ access token gerçekten geçerli olmalı');
    assert.strictEqual(meResponse.body.id, user.id);
  });

  it('[TEST 4 — EN KRİTİK] rotasyon: bir refresh_token TEK KULLANIMLIKTIR; iptal edilmiş bir token TEKRAR kullanılırsa TÜM oturumlar (yeni alınan DAHİL) iptal edilir', async () => {
    const login = await request(app).post('/api/auth/login').send({ sicil_no: '1001', password: DEMO_PASSWORD });
    assert.strictEqual(login.status, 200);
    const originalRefreshToken = login.body.refresh_token;
    const userId = login.body.user.id;

    // 1. meşru kullanım: rotasyon ile YENİ bir çift alınır.
    const firstRefresh = await request(app).post('/api/auth/refresh').send({ refresh_token: originalRefreshToken });
    assert.strictEqual(firstRefresh.status, 200, JSON.stringify(firstRefresh.body));
    const rotatedAccessToken = firstRefresh.body.access_token;
    const rotatedRefreshToken = firstRefresh.body.refresh_token;
    assert.notStrictEqual(rotatedRefreshToken, originalRefreshToken);

    // Rotasyondan sonra eski token DB'de gerçekten revoked=1 mi?
    const originalHash = hashToken(originalRefreshToken);
    const originalRecordAfterRotation = db.prepare('SELECT * FROM refresh_tokens WHERE token_hash = ?').get(originalHash);
    assert.strictEqual(originalRecordAfterRotation.revoked, 1, 'rotasyon sonrası eski token DB\'de revoked=1 olmalı');
    assert.strictEqual(
      originalRecordAfterRotation.replaced_by_token_hash,
      hashToken(rotatedRefreshToken),
      'replaced_by_token_hash yeni token\'ın hash\'ini işaret etmeli (rotasyon zinciri kaydı)'
    );

    // 2. SALDIRI SENARYOSU: aynı (artık iptal edilmiş) eski token TEKRAR kullanılmaya çalışılıyor.
    const reuseAttempt = await request(app).post('/api/auth/refresh').send({ refresh_token: originalRefreshToken });
    assert.strictEqual(reuseAttempt.status, 401, 'iptal edilmiş bir refresh_token\'ın yeniden kullanımı 401 dönmeli');
    assert.match(reuseAttempt.body.error, /güvenlik ihlali/i);

    // KANIT: bu kullanıcının TÜM refresh token'ları — rotasyonla YENİ alınan
    // (rotatedRefreshToken) DAHİL — artık iptal edilmiş olmalı. Bu, "her
    // yerden zorla çıkış" savunmasının GERÇEKTEN çalıştığının somut kanıtıdır.
    const allTokensForUser = db.prepare('SELECT * FROM refresh_tokens WHERE user_id = ?').all(userId);
    assert.ok(allTokensForUser.length >= 2, 'en az orijinal + rotasyonla üretilen token DB\'de bulunmalı');
    for (const record of allTokensForUser) {
      assert.strictEqual(record.revoked, 1, `refresh_tokens id=${record.id} de iptal edilmiş olmalı (revoked=1)`);
    }

    // Rotasyonla meşru şekilde alınan (ama artık "her yerden çıkış" ile iptal
    // edilmiş) token da artık KULLANILAMAZ — meşru kullanıcı bile tekrar
    // giriş yapmak ZORUNDADIR.
    const attemptWithRotatedToken = await request(app)
      .post('/api/auth/refresh')
      .send({ refresh_token: rotatedRefreshToken });
    assert.strictEqual(
      attemptWithRotatedToken.status,
      401,
      'rotasyonla alınan yeni token da artık iptal edilmiş olduğu için 401 dönmeli'
    );

    // rotatedAccessToken (kısa ömürlü JWT, stateless) süresi dolana kadar
    // hâlâ teknik olarak geçerlidir — refresh sisteminin sunucu tarafı
    // iptali yalnızca refresh_token'ı hedefler, bu tasarım gereği beklenir
    // (access token zaten en fazla 15 dk sonra kendiliğinden geçersizleşir).
    assert.strictEqual(typeof rotatedAccessToken, 'string');
  });

  it('[TEST 5] logout sonrası o refresh_token /refresh\'te artık KABUL EDİLMEZ (gerçek sunucu taraflı oturum sonlandırma)', async () => {
    const login = await request(app).post('/api/auth/login').send({ sicil_no: '1001', password: DEMO_PASSWORD });
    assert.strictEqual(login.status, 200);
    const refreshToken = login.body.refresh_token;

    const logoutResponse = await request(app).post('/api/auth/logout').send({ refresh_token: refreshToken });
    assert.strictEqual(logoutResponse.status, 200);
    assert.strictEqual(logoutResponse.body.success, true);

    const tokenHash = hashToken(refreshToken);
    const record = db.prepare('SELECT * FROM refresh_tokens WHERE token_hash = ?').get(tokenHash);
    assert.strictEqual(record.revoked, 1, 'logout sonrası DB\'de revoked=1 olmalı');

    const refreshAfterLogout = await request(app).post('/api/auth/refresh').send({ refresh_token: refreshToken });
    assert.strictEqual(refreshAfterLogout.status, 401, 'logout edilmiş bir refresh_token artık /refresh\'te kabul edilmemeli');
  });

  it('logout: bilinmeyen/uydurma bir refresh_token ile bile İSTEMCİ AÇISINDAN başarı (200) döner (idempotent)', async () => {
    const response = await request(app).post('/api/auth/logout').send({ refresh_token: 'uydurma-bir-token-degeri' });
    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.success, true);
  });

  it('logout: refresh_token eksikse 400 döner', async () => {
    const response = await request(app).post('/api/auth/logout').send({});
    assert.strictEqual(response.status, 400);
  });

  it('[TEST 7] süresi dolmuş bir refresh_token ile /refresh -> 401 (Flutter tarafında bu, Login ekranına zorla yönlendirmeyi tetikler)', async () => {
    const user = db.prepare('SELECT * FROM users WHERE sicil_no = ?').get('1001');
    const expiredRawToken = 'test-suresi-dolmus-refresh-token-degeri';
    const expiredHash = hashToken(expiredRawToken);
    const past = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

    db.prepare(
      `INSERT INTO refresh_tokens (user_id, token_hash, created_at, expires_at, revoked)
       VALUES (?, ?, ?, ?, 0)`
    ).run(user.id, expiredHash, past, past);

    const response = await request(app).post('/api/auth/refresh').send({ refresh_token: expiredRawToken });
    assert.strictEqual(response.status, 401);
    assert.match(response.body.error, /süresi dolmuş/i);
  });

  it('/refresh: hiç var olmayan bir refresh_token ile 401 döner (bilgi sızdırmadan genel hata)', async () => {
    const response = await request(app).post('/api/auth/refresh').send({ refresh_token: 'hic-boyle-bir-token-yok' });
    assert.strictEqual(response.status, 401);
  });

  it('/refresh: refresh_token eksikse 400 döner, sunucu çökmez', async () => {
    const response = await request(app).post('/api/auth/refresh').send({});
    assert.strictEqual(response.status, 400);
  });

  it('/refresh: pasifleştirilmiş (is_active=0) bir kullanıcının GEÇERLİ refresh_token\'ı bile artık KABUL EDİLMEZ', async () => {
    const login = await request(app).post('/api/auth/login').send({ sicil_no: '1001', password: DEMO_PASSWORD });
    assert.strictEqual(login.status, 200);
    const refreshToken = login.body.refresh_token;

    db.prepare('UPDATE users SET is_active = 0 WHERE id = ?').run(seeded.users.teknisyenId);

    const response = await request(app).post('/api/auth/refresh').send({ refresh_token: refreshToken });
    assert.strictEqual(response.status, 401);
  });
});
