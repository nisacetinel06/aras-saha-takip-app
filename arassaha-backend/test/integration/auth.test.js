// POST /api/auth/login — Modül 7 (Auth). Başarılı ve başarısız giriş
// senaryolarını uçtan uca (gerçek Express app + supertest) doğrular.
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const request = require('supertest');
const bcrypt = require('bcrypt');
const app = require('../../server');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData, DEMO_PASSWORD } = require('../helpers/testDb');

describe('POST /api/auth/login', () => {
  beforeEach(() => {
    resetTestDatabase();
    seedMinimalTestData();
  });

  it('geçerli kimlik bilgileriyle bir token ve kullanıcı bilgisi dönmeli', async () => {
    const response = await request(app).post('/api/auth/login').send({ sicil_no: '1001', password: DEMO_PASSWORD });

    assert.strictEqual(response.status, 200);
    assert.ok(response.body.access_token, 'yanıt bir access_token içermeli');
    assert.ok(response.body.refresh_token, 'yanıt bir refresh_token içermeli');
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
    const token = login.body.access_token;

    const response = await request(app).get('/api/auth/me').set('Authorization', `Bearer ${token}`);

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.role, 'yonetici');
  });

  // TEST-13 (coverage analizi) bulgusu: routes/auth.js satır 57-59
  // (`if (!user) return res.status(401)...`) hiçbir testte kapsanmıyordu —
  // token verildikten SONRA kullanıcı silinirse/pasifleştirilirse (örn.
  // başka bir yöneticinin DELETE /api/users/:id çağrısıyla) ne olacağı hiç
  // doğrulanmamıştı. Bu, Authentication kritik alanının doğrudan bir parçası:
  // eski bir token'ın artık var olmayan bir kullanıcı için asla kabul
  // EDİLMEMESİ gerekir.
  it('token geçerli ama kullanıcı SONRADAN silinmişse 401 dönmeli (var olmayan kullanıcı için oturum geçersiz)', async () => {
    // seedMinimalTestData'daki 4 kullanıcının hepsi başka bir tablodan
    // (work_orders.assigned_user_id veya users.supervisor_id) FOREIGN KEY ile
    // referans alıyor — hard DELETE bu yüzden constraint ihlaline düşer.
    // Bu senaryo (token verildikten SONRA satırın gerçekten silinmesi) hiçbir
    // FK'nin işaret etmediği, bağımsız/yalıtılmış bir kullanıcı gerektiriyor.
    const sicilNo = 'test-9001';
    const insertedId = db
      .prepare(
        'INSERT INTO users (name, role, sicil_no, password_hash, supervisor_id) VALUES (?, ?, ?, ?, NULL)'
      )
      .run('Yalıtılmış Test Kullanıcısı', 'teknisyen', sicilNo, bcrypt.hashSync(DEMO_PASSWORD, 10)).lastInsertRowid;

    const login = await request(app).post('/api/auth/login').send({ sicil_no: sicilNo, password: DEMO_PASSWORD });
    assert.strictEqual(login.status, 200, JSON.stringify(login.body));
    const token = login.body.access_token;

    // Access + Refresh Token Sistemi (bkz. utils/refreshToken.js): login artık
    // BU kullanıcıya FK ile bağlı bir refresh_tokens satırı da yaratıyor — hard
    // DELETE'ten önce bu satır da temizlenmeli, aksi halde FOREIGN KEY
    // constraint ihlaline düşer. Gerçek uygulamada kullanıcılar ASLA hard
    // DELETE edilmez (bkz. routes/users.js DELETE /:id — yalnızca soft delete/
    // is_active=0), bu yüzden bu, yalnızca bu testin yapay senaryosuna özgü.
    db.prepare('DELETE FROM refresh_tokens WHERE user_id = ?').run(insertedId);
    db.prepare('DELETE FROM users WHERE id = ?').run(insertedId);

    const response = await request(app).get('/api/auth/me').set('Authorization', `Bearer ${token}`);

    assert.strictEqual(response.status, 401);
    assert.match(response.body.error, /mevcut değil/i);
  });
});
