// POST /api/auth/login — Modül 7 (Auth). Başarılı ve başarısız giriş
// senaryolarını uçtan uca (gerçek Express app + supertest) doğrular.
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const request = require('supertest');
const app = require('../../server');
const { resetTestDatabase, seedMinimalTestData, DEMO_PASSWORD } = require('../helpers/testDb');

describe('POST /api/auth/login', () => {
  beforeEach(() => {
    resetTestDatabase();
    seedMinimalTestData();
  });

  it('geçerli kimlik bilgileriyle bir token ve kullanıcı bilgisi dönmeli', async () => {
    const response = await request(app).post('/api/auth/login').send({ sicil_no: '1001', password: DEMO_PASSWORD });

    assert.strictEqual(response.status, 200);
    assert.ok(response.body.token, 'yanıt bir token içermeli');
    assert.strictEqual(response.body.user.role, 'teknisyen');
  });

  it('geçersiz şifreyle 401 dönmeli', async () => {
    const response = await request(app)
      .post('/api/auth/login')
      .send({ sicil_no: '1001', password: 'yanlisSifre' });

    assert.strictEqual(response.status, 401);
    assert.ok(response.body.error);
  });

  it('var olmayan sicil_no ile 401 dönmeli (kullanıcı yok/şifre yanlış ayrımı yapılmaz)', async () => {
    const response = await request(app)
      .post('/api/auth/login')
      .send({ sicil_no: '9999', password: DEMO_PASSWORD });

    assert.strictEqual(response.status, 401);
  });

  it('sicil_no veya password eksikse 400 dönmeli', async () => {
    const response = await request(app).post('/api/auth/login').send({ sicil_no: '1001' });

    assert.strictEqual(response.status, 400);
  });
});

describe('GET /api/auth/me', () => {
  beforeEach(() => {
    resetTestDatabase();
    seedMinimalTestData();
  });

  it('token olmadan çağrılırsa 401 dönmeli', async () => {
    const response = await request(app).get('/api/auth/me');
    assert.strictEqual(response.status, 401);
  });

  it("geçerli bir token ile giriş yapan kullanıcının bilgisini dönmeli", async () => {
    const login = await request(app).post('/api/auth/login').send({ sicil_no: '3001', password: DEMO_PASSWORD });
    const token = login.body.token;

    const response = await request(app).get('/api/auth/me').set('Authorization', `Bearer ${token}`);

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.role, 'yonetici');
  });
});
