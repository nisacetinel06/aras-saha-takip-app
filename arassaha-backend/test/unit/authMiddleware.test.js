// Saf unit testler: middleware/auth.js (verifyToken, requireRole). Ne
// veritabanına ne gerçek bir HTTP sunucusuna bağımlı — middleware
// fonksiyonları, test/helpers/mockExpress.js'teki sahte req/res/next
// nesneleriyle DOĞRUDAN çağrılır (server.js, database.js veya supertest
// import EDİLMEZ). test/integration/auth.test.js'teki uçtan uca (gerçek
// HTTP isteği atan) testlerden ayrı, daha hızlı/izole bir katman — bkz.
// TEST-02.
//
// Kod incelemesi notu (middleware/auth.js): verifyToken yalnızca jwt.verify
// ile token'ı çözüp req.user = { id, role } atıyor, HERHANGİ bir veritabanı
// sorgusu ATMIYOR (Modül 7 tasarımı: payload zaten id/role taşıyor). Bu
// yüzden mock'lanması gereken bir DB çağrısı yok. requireRole tamamen
// senkron, yalnızca req.user.role'ü allowedRoles listesiyle karşılaştırıyor.
const { describe, it } = require('node:test');
const assert = require('node:assert');
const { createMockReq, createMockRes, createMockNext } = require('../helpers/mockExpress');
const { generateValidToken, generateExpiredToken, generateInvalidSignatureToken } = require('../helpers/tokenHelper');
const { verifyToken, requireRole } = require('../../middleware/auth');

function withAuthHeader(token) {
  return createMockReq({ authorization: `Bearer ${token}` });
}

describe('verifyToken', () => {
  it('geçerli bir token ile next() tam olarak bir kez, hatasız çağrılmalı', () => {
    const req = withAuthHeader(generateValidToken());
    const res = createMockRes();
    const next = createMockNext();

    verifyToken(req, res, next);

    assert.strictEqual(next.mock.calls.length, 1);
    assert.strictEqual(next.mock.calls[0].arguments.length, 0);
    assert.strictEqual(res.status.mock.calls.length, 0, 'başarılı durumda res.status hiç çağrılmamalı');
  });

  it('token payload\'ındaki id/role req.user\'a birebir yansımalı', () => {
    const req = withAuthHeader(generateValidToken({ id: 42, role: 'yonetici' }));
    const res = createMockRes();
    const next = createMockNext();

    verifyToken(req, res, next);

    assert.strictEqual(req.user.id, 42);
    assert.strictEqual(req.user.role, 'yonetici');
  });

  it('Authorization header hiç yoksa 401 dönmeli, next() çağrılmamalı', () => {
    const req = createMockReq({});
    const res = createMockRes();
    const next = createMockNext();

    verifyToken(req, res, next);

    assert.strictEqual(res.status.mock.calls[0].arguments[0], 401);
    assert.strictEqual(next.mock.calls.length, 0);
  });

  it('yanlış secret ile imzalanmış (geçersiz) token için 401 dönmeli, next() çağrılmamalı', () => {
    const req = withAuthHeader(generateInvalidSignatureToken());
    const res = createMockRes();
    const next = createMockNext();

    verifyToken(req, res, next);

    assert.strictEqual(res.status.mock.calls[0].arguments[0], 401);
    assert.strictEqual(next.mock.calls.length, 0);
  });

  it('süresi dolmuş (expired) token için 401 dönmeli, next() çağrılmamalı', () => {
    const req = withAuthHeader(generateExpiredToken());
    const res = createMockRes();
    const next = createMockNext();

    verifyToken(req, res, next);

    assert.strictEqual(res.status.mock.calls[0].arguments[0], 401);
    assert.strictEqual(next.mock.calls.length, 0);
  });

  it('expired ve invalid-signature durumları AYNI genel mesajı dönmeli (kod bu ikisini ayırt etmiyor)', () => {
    // middleware/auth.js tek bir `catch {}` bloğu kullanıyor — jwt.verify'ın
    // fırlattığı TokenExpiredError ile JsonWebTokenError arasında ayrım
    // yapmıyor, ikisi için de aynı genel mesajı dönüyor. Bu testin amacı bu
    // tasarım kararını sabitlemek (regression guard): biri değişip diğeri
    // değişmezse bu test kırılır.
    const expiredRes = createMockRes();
    verifyToken(withAuthHeader(generateExpiredToken()), expiredRes, createMockNext());

    const invalidRes = createMockRes();
    verifyToken(withAuthHeader(generateInvalidSignatureToken()), invalidRes, createMockNext());

    assert.strictEqual(expiredRes.jsonBody.error, invalidRes.jsonBody.error);
    assert.strictEqual(expiredRes.jsonBody.error, 'Oturum süresi doldu veya geçersiz. Lütfen tekrar giriş yapın.');
  });

  it('"Bearer " öneki olmadan sadece token gönderilirse çökmeden 401 dönmeli', () => {
    const req = createMockReq({ authorization: generateValidToken() });
    const res = createMockRes();
    const next = createMockNext();

    assert.doesNotThrow(() => verifyToken(req, res, next));
    assert.strictEqual(res.status.mock.calls[0].arguments[0], 401);
    assert.strictEqual(next.mock.calls.length, 0);
  });

  it('tamamen anlamsız bir Authorization header\'ı ("Bearer" + rastgele string) çökmeden 401 dönmeli', () => {
    const req = createMockReq({ authorization: 'Bearer bu-bir-token-degil' });
    const res = createMockRes();
    const next = createMockNext();

    assert.doesNotThrow(() => verifyToken(req, res, next));
    assert.strictEqual(res.status.mock.calls[0].arguments[0], 401);
    assert.strictEqual(next.mock.calls.length, 0);
  });

  it('"Bearer" şeması var ama token boşsa (örn. "Bearer " veya sadece "Bearer") 401 dönmeli', () => {
    for (const authorization of ['Bearer', 'Bearer ']) {
      const req = createMockReq({ authorization });
      const res = createMockRes();
      const next = createMockNext();

      verifyToken(req, res, next);

      assert.strictEqual(res.status.mock.calls[0].arguments[0], 401, `header: "${authorization}"`);
      assert.strictEqual(next.mock.calls.length, 0, `header: "${authorization}"`);
    }
  });
});

describe('requireRole', () => {
  it('req.user.role izin verilen listede ise next() çağrılmalı, res.status hiç çağrılmamalı', () => {
    const req = createMockReq();
    req.user = { id: 1, role: 'yonetici' };
    const res = createMockRes();
    const next = createMockNext();

    requireRole('yonetici')(req, res, next);

    assert.strictEqual(next.mock.calls.length, 1);
    assert.strictEqual(res.status.mock.calls.length, 0);
  });

  it('req.user.role izin verilen listede değilse 403 dönmeli (401 DEĞİL), next() çağrılmamalı', () => {
    const req = createMockReq();
    req.user = { id: 1, role: 'teknisyen' };
    const res = createMockRes();
    const next = createMockNext();

    requireRole('yonetici')(req, res, next);

    assert.strictEqual(res.status.mock.calls[0].arguments[0], 403);
    assert.notStrictEqual(res.status.mock.calls[0].arguments[0], 401);
    assert.strictEqual(next.mock.calls.length, 0);
  });

  it('birden fazla izinli rol tanımlıysa, listedeki her rol için next() çağrılmalı', () => {
    const middleware = requireRole('dispecer', 'yonetici');

    for (const role of ['dispecer', 'yonetici']) {
      const req = createMockReq();
      req.user = { id: 1, role };
      const res = createMockRes();
      const next = createMockNext();

      middleware(req, res, next);

      assert.strictEqual(next.mock.calls.length, 1, `role: ${role}`);
      assert.strictEqual(res.status.mock.calls.length, 0, `role: ${role}`);
    }
  });

  it('listede olmayan bir rol, birden fazla izinli rol tanımlı olsa da 403 dönmeli', () => {
    const req = createMockReq();
    req.user = { id: 1, role: 'teknisyen' };
    const res = createMockRes();
    const next = createMockNext();

    requireRole('dispecer', 'yonetici')(req, res, next);

    assert.strictEqual(res.status.mock.calls[0].arguments[0], 403);
    assert.strictEqual(next.mock.calls.length, 0);
  });

  it('req.user hiç yoksa (verifyToken atlanmış/başarısız olmuşsa) çökmeden güvenli bir hata dönmeli', () => {
    const req = createMockReq(); // req.user === undefined
    const res = createMockRes();
    const next = createMockNext();

    assert.doesNotThrow(() => requireRole('yonetici')(req, res, next));
    assert.strictEqual(next.mock.calls.length, 0);
    assert.ok(
      res.status.mock.calls[0].arguments[0] === 401 || res.status.mock.calls[0].arguments[0] === 403,
      'req.user eksikken 401 veya 403 dönmeli (savunmacı kontrol)'
    );
    // Gerçek davranış (kod incelemesi): requireRole DB/verifyToken'a değil
    // yalnızca `!req.user`'a bakıyor, bu da doğrudan 403'e düşüyor — 401
    // dönmüyor. Bu, gerçek davranışı sabitleyen ek bir doğrulama.
    assert.strictEqual(res.status.mock.calls[0].arguments[0], 403);
  });
});

describe('HTTP status code doğruluğu', () => {
  it('kimlik doğrulama başarısız senaryolarının HEPSİ 401 dönmeli (token yok/geçersiz/expired)', () => {
    const scenarios = [
      ['token yok', createMockReq({})],
      ['geçersiz imza', withAuthHeader(generateInvalidSignatureToken())],
      ['expired', withAuthHeader(generateExpiredToken())],
      ['bozuk format', createMockReq({ authorization: 'Bearer bu-bir-token-degil' })],
    ];

    for (const [label, req] of scenarios) {
      const res = createMockRes();
      const next = createMockNext();
      verifyToken(req, res, next);

      assert.strictEqual(res.status.mock.calls[0].arguments[0], 401, `senaryo: ${label}`);
      assert.strictEqual(next.mock.calls.length, 0, `senaryo: ${label}`);
    }
  });

  it('kimlik doğrulandı ama rol yetersiz senaryosu 403 dönmeli, ASLA 401 değil', () => {
    const req = createMockReq();
    req.user = { id: 1, role: 'teknisyen' };
    const res = createMockRes();
    const next = createMockNext();

    requireRole('yonetici')(req, res, next);

    const status = res.status.mock.calls[0].arguments[0];
    assert.strictEqual(status, 403);
    assert.notStrictEqual(status, 401, '401/403 karışırsa Flutter tarafı "tekrar giriş yap" ile "yetkin yok" ayrımını kaybeder');
  });

  it('401 (kimlik) ve 403 (yetki) durumları birbirine karışmamalı — uçtan uca karşılaştırma', () => {
    const authFailureRes = createMockRes();
    verifyToken(createMockReq({}), authFailureRes, createMockNext());

    const roleFailureReq = createMockReq();
    roleFailureReq.user = { id: 1, role: 'teknisyen' };
    const roleFailureRes = createMockRes();
    requireRole('yonetici')(roleFailureReq, roleFailureRes, createMockNext());

    assert.strictEqual(authFailureRes.statusCode, 401);
    assert.strictEqual(roleFailureRes.statusCode, 403);
    assert.notStrictEqual(authFailureRes.statusCode, roleFailureRes.statusCode);
  });
});
