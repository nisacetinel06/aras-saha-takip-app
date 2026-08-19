// TEST-06: POST /api/auth/login — uçtan uca (gerçek Express app + gerçek
// :memory: SQLite test DB + gerçek bcrypt + gerçek jsonwebtoken). Mock YOK —
// bu, middleware'i izole test eden test/unit/auth*.test.js'ten (TEST-03)
// farklı olarak, gerçek HTTP isteği -> gerçek route -> gerçek DB sorgusu ->
// gerçek bcrypt karşılaştırması -> gerçek JWT üretimi zincirini doğrular.
//
// Brute-force / rate limiting senaryoları (sicil_no + IP bazlı kilit) BURADA
// DEĞİL, ayrı test/integration/loginRateLimit.test.js dosyasındadır — bkz.
// middleware/loginRateLimit.js ve SECURITY_NOTES.md.
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const request = require('supertest');
const jwt = require('jsonwebtoken');
const app = require('../../server');
const db = require('../../database');
const { JWT_SECRET } = require('../../middleware/auth');
const { resetTestDatabase } = require('../helpers/testDb');
const { AUTH_TEST_USERS, seedAuthTestUsers } = require('../helpers/authFixtures');

const PROD_DB_PATH = path.join(__dirname, '..', '..', 'aras_saha.db');
const SEVEN_DAYS_IN_SECONDS = 7 * 24 * 60 * 60;
const EXPIRY_TOLERANCE_SECONDS = 5;

// Bu dosyanın testleri BAŞLAMADAN ÖNCE (modül yüklenirken) alınan anlık
// görüntü — dosyanın en altındaki testte "sonra" ile karşılaştırılıp bu
// dosyaya özel gerçek bir önce/sonra kanıtı üretmek için. TEST-02'deki
// test/unit/databaseIsolation.test.js AYNI yöntemi module-require anında
// genel olarak doğruluyor; burada bu görevin kabul kriterinde istendiği gibi
// AYRICA bu dosyanın kendi çalışması için tekrarlanıyor.
const prodDbExistedBefore = fs.existsSync(PROD_DB_PATH);
const prodDbMtimeBefore = prodDbExistedBefore ? fs.statSync(PROD_DB_PATH).mtimeMs : null;

describe('POST /api/auth/login (uçtan uca)', () => {
  let userIds;

  beforeEach(() => {
    resetTestDatabase();
    userIds = seedAuthTestUsers();
  });

  it('geçerli sicil no + doğru şifre: 200, token ve user döner, password_hash SIZDIRILMAZ', async () => {
    const response = await request(app)
      .post('/api/auth/login')
      .send({ sicil_no: AUTH_TEST_USERS.activeUser.sicil_no, password: AUTH_TEST_USERS.activeUser.plainPassword });

    assert.strictEqual(response.status, 200);
    assert.strictEqual(typeof response.body.token, 'string');
    assert.ok(response.body.token.length > 0, 'token boş olmamalı');

    assert.strictEqual(response.body.user.id, userIds.activeUser);
    assert.strictEqual(response.body.user.name, AUTH_TEST_USERS.activeUser.name);
    assert.strictEqual(response.body.user.role, AUTH_TEST_USERS.activeUser.role);

    assert.strictEqual(response.body.user.password_hash, undefined, 'user nesnesinde password_hash OLMAMALI');
    assert.strictEqual(response.body.password_hash, undefined, 'response body kökünde password_hash OLMAMALI');
  });

  it('yanlış şifre: 401, genel hata mesajı, token yok', async () => {
    const response = await request(app)
      .post('/api/auth/login')
      .send({ sicil_no: AUTH_TEST_USERS.activeUser.sicil_no, password: 'yanlisSifre123!' });

    assert.strictEqual(response.status, 401);
    assert.strictEqual(typeof response.body.error, 'string');
    assert.ok(response.body.error.length > 0);
    assert.strictEqual(response.body.token, undefined);
  });

  it('olmayan sicil no: 401, "yanlış şifre" ile AYNI genel mesaj (user enumeration önlenmiş)', async () => {
    const wrongPasswordResponse = await request(app)
      .post('/api/auth/login')
      .send({ sicil_no: AUTH_TEST_USERS.activeUser.sicil_no, password: 'yanlisSifre123!' });

    const nonExistentUserResponse = await request(app)
      .post('/api/auth/login')
      .send({ sicil_no: '9999', password: AUTH_TEST_USERS.activeUser.plainPassword });

    assert.strictEqual(nonExistentUserResponse.status, 401);
    assert.strictEqual(nonExistentUserResponse.body.token, undefined);

    // Kod incelemesi bulgusu: routes/auth.js her iki durumda da AYNI
    // invalidCredentials() yardımcısını çağırıyor — bu test bunu somut
    // olarak kanıtlar. Mesajlar farklı olsaydı bu, hangi sicil no'ların
    // sistemde var olduğunu (user enumeration) sızdırırdı.
    assert.strictEqual(
      nonExistentUserResponse.body.error,
      wrongPasswordResponse.body.error,
      '"olmayan kullanıcı" ve "yanlış şifre" senaryoları AYNI genel mesajı dönmeli (user enumeration riski)'
    );
  });

  it('pasif kullanıcı: doğru şifreyle bile 403, token yok (Modül 8 pasifleştirme login\'i engellemeli)', async () => {
    const response = await request(app)
      .post('/api/auth/login')
      .send({ sicil_no: AUTH_TEST_USERS.inactiveUser.sicil_no, password: AUTH_TEST_USERS.inactiveUser.plainPassword });

    assert.strictEqual(response.status, 403);
    assert.strictEqual(typeof response.body.error, 'string');
    assert.ok(response.body.error.length > 0);
    assert.strictEqual(response.body.token, undefined);
  });

  it('eksik sicil_no: 400, sunucu çökmez (500 DEĞİL)', async () => {
    const response = await request(app).post('/api/auth/login').send({ password: 'herhangi-bir-sifre' });

    assert.strictEqual(response.status, 400);
    assert.strictEqual(typeof response.body.error, 'string');
  });

  it('eksik password: 400, sunucu çökmez (500 DEĞİL)', async () => {
    const response = await request(app)
      .post('/api/auth/login')
      .send({ sicil_no: AUTH_TEST_USERS.activeUser.sicil_no });

    assert.strictEqual(response.status, 400);
    assert.strictEqual(typeof response.body.error, 'string');
  });

  it('tamamen boş body ({}) : 400, sunucu çökmez', async () => {
    const response = await request(app).post('/api/auth/login').send({});
    assert.strictEqual(response.status, 400);
    assert.strictEqual(typeof response.body.error, 'string');
  });

  it('null değerler: 400, sunucu çökmez', async () => {
    const response = await request(app).post('/api/auth/login').send({ sicil_no: null, password: null });
    assert.strictEqual(response.status, 400);
    assert.strictEqual(typeof response.body.error, 'string');
  });

  it('beklenmedik tipte veri (sicil_no sayı olarak): sunucu çökmez (500 DEĞİL), düzgün bir hata döner', async () => {
    // BULGU (zorunlu düzeltme değil, TEST-06 kapsamı dışı — bkz. rapor):
    // `if (!sicil_no || !password)` yalnızca "truthy" kontrolü yapar, TİP
    // kontrolü yapmaz — sayısal 9001 bu kontrolü geçer. Ardından
    // `db.prepare('... WHERE sicil_no = ?').get(sicil_no)` çağrılır; ancak
    // node:sqlite bağlı parametrelerde SQLite'ın TEXT sütun affinity
    // dönüşümünü UYGULAMADIĞI doğrulandı (bkz. görev raporu) — yani sayısal
    // 9001, metin '9001' ile EŞLEŞMEZ. Sonuç: kullanıcı "bulunamadı" dallanır
    // ve genel 401 mesajı döner — ideal olan (tip hatası için net bir 400)
    // DEĞİL, ama güvenli (çökmüyor, bilgi sızdırmıyor). bcrypt.compareSync'e
    // sayısal bir password asla ULAŞMIYOR (kullanıcı zaten bulunamadığı için)
    // — aksi halde bcrypt bunu fırlatırdı (bkz. rapor), bu yüzden 500 riski
    // bu spesifik kod yolunda fiilen yok.
    const response = await request(app).post('/api/auth/login').send({ sicil_no: 9001, password: 12345 });
    assert.notStrictEqual(response.status, 500, '500 dönmemeli (sunucu çökmemeli)');
    assert.ok([400, 401].includes(response.status), `400 ya da 401 dönmeli, gerçek: ${response.status}`);
    assert.strictEqual(typeof response.body.error, 'string');
  });

  describe('JWT üretimi ve claim doğrulaması (derinlemesine)', () => {
    it('decoded.id gerçek kullanıcı id\'siyle, decoded.role beklenen rolle eşleşmeli', async () => {
      const response = await request(app)
        .post('/api/auth/login')
        .send({ sicil_no: AUTH_TEST_USERS.activeUser.sicil_no, password: AUTH_TEST_USERS.activeUser.plainPassword });

      const decoded = jwt.verify(response.body.token, JWT_SECRET);

      const dbUser = db.prepare('SELECT id FROM users WHERE sicil_no = ?').get(AUTH_TEST_USERS.activeUser.sicil_no);
      assert.strictEqual(decoded.id, dbUser.id);
      assert.strictEqual(decoded.role, 'teknisyen');
    });

    it('decoded.exp, iat\'tan yaklaşık 7 gün sonrası olmalı (birkaç saniye tolerans)', async () => {
      const response = await request(app)
        .post('/api/auth/login')
        .send({ sicil_no: AUTH_TEST_USERS.activeUser.sicil_no, password: AUTH_TEST_USERS.activeUser.plainPassword });

      const decoded = jwt.verify(response.body.token, JWT_SECRET);

      assert.ok(decoded.exp, 'token bir exp claim\'i içermeli');
      assert.ok(decoded.iat, 'token bir iat claim\'i içermeli');

      const lifetimeSeconds = decoded.exp - decoded.iat;
      assert.ok(
        Math.abs(lifetimeSeconds - SEVEN_DAYS_IN_SECONDS) <= EXPIRY_TOLERANCE_SECONDS,
        `token ömrü ~7 gün (${SEVEN_DAYS_IN_SECONDS}sn) olmalı, gerçek: ${lifetimeSeconds}sn`
      );
    });

    it('yanlış secret ile doğrulama başarısız olmalı (token gerçekten doğru secret\'la imzalanmış)', async () => {
      const response = await request(app)
        .post('/api/auth/login')
        .send({ sicil_no: AUTH_TEST_USERS.activeUser.sicil_no, password: AUTH_TEST_USERS.activeUser.plainPassword });

      assert.throws(() => {
        jwt.verify(response.body.token, 'bu-kesinlikle-yanlis-bir-secret');
      });
    });
  });

  describe('response format tutarlılığı', () => {
    it('tüm başarısız senaryolar (400/401/403) AYNI { error: string } şeklini kullanmalı', async () => {
      const scenarios = [
        { body: { password: 'x' }, expectedStatus: 400 },
        { body: { sicil_no: AUTH_TEST_USERS.activeUser.sicil_no }, expectedStatus: 400 },
        { body: { sicil_no: AUTH_TEST_USERS.activeUser.sicil_no, password: 'yanlis' }, expectedStatus: 401 },
        { body: { sicil_no: '9999', password: 'x' }, expectedStatus: 401 },
        {
          body: { sicil_no: AUTH_TEST_USERS.inactiveUser.sicil_no, password: AUTH_TEST_USERS.inactiveUser.plainPassword },
          expectedStatus: 403,
        },
      ];

      for (const scenario of scenarios) {
        const response = await request(app).post('/api/auth/login').send(scenario.body);
        assert.strictEqual(response.status, scenario.expectedStatus);
        assert.deepStrictEqual(
          Object.keys(response.body),
          ['error'],
          `status ${scenario.expectedStatus} için response body { error } dışında alan İÇERMEMELİ, gerçek: ${JSON.stringify(response.body)}`
        );
        assert.strictEqual(typeof response.body.error, 'string');
      }
    });
  });

  describe('production veritabanı izolasyonu (bu test dosyasına özel doğrulama)', () => {
    it('bu dosyadaki tüm login testleri çalıştıktan sonra aras_saha.db değişmemiş olmalı', () => {
      // node:test dosya içindeki testleri TANIMLANMA sırasıyla çalıştırır, bu
      // yüzden bu son test dosyanın en altında olduğu sürece yukarıdaki TÜM
      // senaryolardan (ve onların beforeEach'lerinden) SONRA çalışır.
      const existedAfter = fs.existsSync(PROD_DB_PATH);
      const mtimeAfter = existedAfter ? fs.statSync(PROD_DB_PATH).mtimeMs : null;

      assert.strictEqual(existedAfter, prodDbExistedBefore, 'aras_saha.db dosyasının var olma durumu değişmemeli');
      assert.strictEqual(mtimeAfter, prodDbMtimeBefore, 'aras_saha.db dosyasının değişme zamanı (mtime) değişmemeli');
    });
  });
});
