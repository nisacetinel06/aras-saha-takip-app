// Yöneticiden Çalışana Duyuru/Mesaj Sistemi — TEK YÖNLÜ yayın endpoint'leri.
//
// Kritik iki güvenlik iddiası burada kanıtlanıyor:
// 1) Yazma yetkisi SADECE yönetici — teknisyen/dispeçer POST /api/manager-messages
//    çağırdığında 403 almalı (RBAC).
// 2) Bir kullanıcı kendisine gönderilmemiş bir mesajın id'sini tahmin ederek
//    PATCH /:id/read çağırırsa 404 almalı (SEC-02 tarzı IDOR kontrolü).
//
// TEST-14 doğrulama notu: routes/managerMessages.js kod incelemesinde bu
// modülün RBAC/sahiplik yüzeyinin TAMAMI (yazma: requireRole('yonetici');
// okuma: recipient_user_id sahipliği; /sent ve /:id/read-status: yalnızca
// GÖNDEREN yönetici) zaten uygulanmış bulundu — bu dosya o davranışı
// doğrulayan regresyon suite'idir. Coverage: routes/managerMessages.js
// %90+ satır, RBAC/sahiplik dallarının tamamı kapsanmış (kapsanmayan
// satırlar yalnızca 500 catch blokları). Ayrı bir managerMessagesRbac.test.js
// dosyası AÇILMADI — aynı senaryoları burada tekrar etmek gereksiz
// duplikasyon olurdu; bunun yerine tespit edilen tek boşluk (dispeçerin
// /sent'e erişememesi) aşağıya eklendi.
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const request = require('supertest');
const app = require('../../server');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');
const { getTestToken } = require('../helpers/authHelper');
const { generateValidToken } = require('../helpers/tokenHelper');
const { assertSchema, assertArraySchema } = require('../helpers/assertSchema');

describe('POST /api/manager-messages', () => {
  let seeded;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
  });

  it('token olmadan 401 döner', async () => {
    const response = await request(app).post('/api/manager-messages').send({
      content: 'Test',
      recipient_user_ids: [1],
    });
    assert.strictEqual(response.status, 401);
  });

  it('KRİTİK RBAC: teknisyen POST çağırdığında 403 döner — mesaj oluşturma yetkisi hiç yok', async () => {
    const token = generateValidToken({ id: seeded.users.teknisyenId, role: 'teknisyen' });
    const response = await request(app)
      .post('/api/manager-messages')
      .set('Authorization', `Bearer ${token}`)
      .send({ content: 'Teknisyenden duyuru', recipient_user_ids: [seeded.users.otherTeknisyenId] });

    assert.strictEqual(response.status, 403);
    // DB'de HİÇBİR mesaj oluşmamış olmalı — yetki reddi gerçekten yazmayı engellemiş.
    const count = db.prepare('SELECT COUNT(*) AS c FROM manager_messages').get().c;
    assert.strictEqual(count, 0, 'Yetkisiz bir istek DB\'ye bir mesaj yazmamalı');
  });

  it('KRİTİK RBAC: dispeçer POST çağırdığında 403 döner', async () => {
    const token = getTestToken('dispecer');
    const response = await request(app)
      .post('/api/manager-messages')
      .set('Authorization', `Bearer ${token}`)
      .send({ content: 'Dispeçerden duyuru', recipient_user_ids: [seeded.users.teknisyenId] });

    assert.strictEqual(response.status, 403);
  });

  it('yönetici 3 teknisyene bir duyuru gönderir: 201 döner, her alıcı için recipient satırı VE bildirim oluşur', async () => {
    // Üçüncü bir teknisyen daha ekle (seedMinimalTestData yalnızca 2 verir).
    const thirdTeknisyenId = db
      .prepare(
        'INSERT INTO users (name, role, sicil_no, password_hash, supervisor_id) VALUES (?, ?, ?, ?, ?)'
      )
      .run('Üçüncü Teknisyen', 'teknisyen', '1003', 'x', seeded.users.dispecerId).lastInsertRowid;

    const token = getTestToken('yonetici');
    const recipientIds = [seeded.users.teknisyenId, seeded.users.otherTeknisyenId, thirdTeknisyenId];

    const response = await request(app)
      .post('/api/manager-messages')
      .set('Authorization', `Bearer ${token}`)
      .send({ title: 'Bakım Duyurusu', content: 'Yarın bakım var.', recipient_user_ids: recipientIds });

    assert.strictEqual(response.status, 201);
    assertSchema(response.body, { id: 'number', recipient_count: 'number' });
    assert.strictEqual(response.body.recipient_count, 3);

    const recipientRows = db
      .prepare('SELECT * FROM manager_message_recipients WHERE message_id = ?')
      .all(response.body.id);
    assert.strictEqual(recipientRows.length, 3, 'Her alıcı için tam olarak bir recipient satırı olmalı');
    assert.ok(
      recipientRows.every((r) => r.read_at === null),
      'Yeni gönderilen mesaj HİÇBİR alıcı için okunmuş olmamalı'
    );

    const notificationRows = db
      .prepare("SELECT * FROM notifications WHERE related_type = 'manager_message' AND related_id = ?")
      .all(response.body.id);
    assert.strictEqual(notificationRows.length, 3, 'Her alıcı GERÇEKTEN bir bildirim almış olmalı');
    for (const recipientId of recipientIds) {
      assert.ok(
        notificationRows.some((n) => n.user_id === recipientId),
        `Alıcı ${recipientId} için bir bildirim satırı eksik`
      );
    }
  });

  it('validasyon: content boşsa 400 döner', async () => {
    const token = getTestToken('yonetici');
    const response = await request(app)
      .post('/api/manager-messages')
      .set('Authorization', `Bearer ${token}`)
      .send({ recipient_user_ids: [seeded.users.teknisyenId] });
    assert.strictEqual(response.status, 400);
  });

  it('validasyon: recipient_user_ids boş dizi/eksikse 400 döner', async () => {
    const token = getTestToken('yonetici');
    const response = await request(app)
      .post('/api/manager-messages')
      .set('Authorization', `Bearer ${token}`)
      .send({ content: 'Alıcısız mesaj', recipient_user_ids: [] });
    assert.strictEqual(response.status, 400);
  });

  it('validasyon: var olmayan bir alıcı id\'si gönderilirse 400 döner, mesaj OLUŞMAZ', async () => {
    const token = getTestToken('yonetici');
    const response = await request(app)
      .post('/api/manager-messages')
      .set('Authorization', `Bearer ${token}`)
      .send({ content: 'Test', recipient_user_ids: [999999] });

    assert.strictEqual(response.status, 400);
    const count = db.prepare('SELECT COUNT(*) AS c FROM manager_messages').get().c;
    assert.strictEqual(count, 0);
  });
});

describe('GET /api/manager-messages (çalışan görünümü)', () => {
  let seeded;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
  });

  function sendMessage(recipientIds, content = 'Test mesajı') {
    const managerToken = getTestToken('yonetici');
    return request(app)
      .post('/api/manager-messages')
      .set('Authorization', `Bearer ${managerToken}`)
      .send({ content, recipient_user_ids: recipientIds });
  }

  it('token olmadan 401 döner', async () => {
    const response = await request(app).get('/api/manager-messages');
    assert.strictEqual(response.status, 401);
  });

  it('response schema doğru: id/title/content/created_at/is_read/sender_name/sender_role içerir', async () => {
    await sendMessage([seeded.users.teknisyenId]);
    const token = getTestToken('teknisyen');

    const response = await request(app).get('/api/manager-messages').set('Authorization', `Bearer ${token}`);

    assert.strictEqual(response.status, 200);
    assertArraySchema(response.body, {
      id: 'number',
      content: 'string',
      created_at: 'string',
      is_read: 'boolean',
      sender_name: 'string',
      sender_role: 'string',
    });
    assert.strictEqual(response.body[0].is_read, false);
  });

  it('CROSS-USER SIZINTI KONTROLÜ: Kullanıcı A, kendisine gönderilmemiş bir mesajı ASLA görmemeli', async () => {
    // A'ya (teknisyenId) 2 mesaj, B'ye (otherTeknisyenId) 1 GİZLİ mesaj.
    await sendMessage([seeded.users.teknisyenId], 'A için mesaj 1');
    await sendMessage([seeded.users.teknisyenId], 'A için mesaj 2');
    const secretResponse = await sendMessage([seeded.users.otherTeknisyenId], 'B için GİZLİ mesaj');
    const secretMessageId = secretResponse.body.id;

    const tokenA = getTestToken('teknisyen');
    const responseA = await request(app).get('/api/manager-messages').set('Authorization', `Bearer ${tokenA}`);

    assert.strictEqual(responseA.status, 200);
    assert.strictEqual(responseA.body.length, 2, 'A yalnızca KENDİ 2 mesajını görmeli');
    const returnedIds = responseA.body.map((m) => m.id);
    assert.ok(!returnedIds.includes(secretMessageId), 'B\'nin gizli mesajının id\'si A\'nın yanıtında SIZMIŞ');
  });

  it('boş veri durumu: hiç mesaj yokken hata değil, boş dizi döner', async () => {
    const token = getTestToken('teknisyen');
    const response = await request(app).get('/api/manager-messages').set('Authorization', `Bearer ${token}`);
    assert.strictEqual(response.status, 200);
    assert.deepStrictEqual(response.body, []);
  });
});

describe('PATCH /api/manager-messages/:id/read', () => {
  let seeded;
  let messageId;

  beforeEach(async () => {
    resetTestDatabase();
    seeded = seedMinimalTestData();

    const managerToken = getTestToken('yonetici');
    const created = await request(app)
      .post('/api/manager-messages')
      .set('Authorization', `Bearer ${managerToken}`)
      .send({ content: 'Okundu testi mesajı', recipient_user_ids: [seeded.users.teknisyenId] });
    messageId = created.body.id;
  });

  it('token olmadan 401 döner', async () => {
    const response = await request(app).patch(`/api/manager-messages/${messageId}/read`);
    assert.strictEqual(response.status, 401);
  });

  it('gerçek alıcı okundu işaretlediğinde: 200 + success:true döner, read_at DB\'de dolar', async () => {
    const token = getTestToken('teknisyen'); // seedMinimalTestData'da teknisyenId
    const response = await request(app)
      .patch(`/api/manager-messages/${messageId}/read`)
      .set('Authorization', `Bearer ${token}`);

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.success, true);

    const row = db
      .prepare('SELECT read_at FROM manager_message_recipients WHERE message_id = ? AND recipient_user_id = ?')
      .get(messageId, seeded.users.teknisyenId);
    assert.ok(row.read_at !== null, 'read_at DB\'de dolmuş olmalı');
  });

  it('KRİTİK SIZINTI TESTİ: alıcı OLMAYAN bir kullanıcı ID\'yi tahmin edip PATCH çağırırsa 404 döner', async () => {
    // otherTeknisyenId bu mesajın alıcısı DEĞİL (yalnızca teknisyenId'ye gönderildi).
    const tokenB = generateValidToken({ id: seeded.users.otherTeknisyenId, role: 'teknisyen' });
    const response = await request(app)
      .patch(`/api/manager-messages/${messageId}/read`)
      .set('Authorization', `Bearer ${tokenB}`);

    assert.strictEqual(response.status, 404);

    // Gerçek alıcının read_at'i bu başarısız denemeden ETKİLENMEMİŞ olmalı.
    const row = db
      .prepare('SELECT read_at FROM manager_message_recipients WHERE message_id = ? AND recipient_user_id = ?')
      .get(messageId, seeded.users.teknisyenId);
    assert.strictEqual(row.read_at, null, 'B\'nin başarısız isteği A\'nın mesajını okunmuş yapmamalı');
  });

  it('var olmayan bir mesaj id\'si için 404 döner', async () => {
    const token = getTestToken('teknisyen');
    const response = await request(app)
      .patch('/api/manager-messages/999999/read')
      .set('Authorization', `Bearer ${token}`);
    assert.strictEqual(response.status, 404);
  });

  it('idempotent: aynı mesaj iki kez okundu işaretlenirse ilk read_at KORUNUR, hata vermez', async () => {
    const token = getTestToken('teknisyen');
    await request(app).patch(`/api/manager-messages/${messageId}/read`).set('Authorization', `Bearer ${token}`);
    const firstReadAt = db
      .prepare('SELECT read_at FROM manager_message_recipients WHERE message_id = ? AND recipient_user_id = ?')
      .get(messageId, seeded.users.teknisyenId).read_at;

    const secondResponse = await request(app)
      .patch(`/api/manager-messages/${messageId}/read`)
      .set('Authorization', `Bearer ${token}`);
    assert.strictEqual(secondResponse.status, 200);

    const secondReadAt = db
      .prepare('SELECT read_at FROM manager_message_recipients WHERE message_id = ? AND recipient_user_id = ?')
      .get(messageId, seeded.users.teknisyenId).read_at;
    assert.strictEqual(secondReadAt, firstReadAt);
  });
});

describe('GET /api/manager-messages/sent (yönetici görünümü)', () => {
  let seeded;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
  });

  it('token olmadan 401 döner', async () => {
    const response = await request(app).get('/api/manager-messages/sent');
    assert.strictEqual(response.status, 401);
  });

  it('KRİTİK RBAC: teknisyen /sent çağırdığında 403 döner', async () => {
    const token = getTestToken('teknisyen');
    const response = await request(app).get('/api/manager-messages/sent').set('Authorization', `Bearer ${token}`);
    assert.strictEqual(response.status, 403);
  });

  // TEST-14 bulgusu: /sent yalnızca teknisyen için test ediliyordu — modül
  // tasarımında dispeçer de (yönetici DIŞINDA herkes gibi) mesaj GÖNDEREMEZ,
  // dolayısıyla kendi gönderdiği mesajları listeleyen bu endpoint'e de erişimi
  // olmamalı. requireRole('yonetici') zaten tek başına bunu garanti ediyor
  // ama ayrı bir rol için ayrı bir regresyon testi olmadan bu örtük kalıyordu.
  it('KRİTİK RBAC: dispeçer /sent çağırdığında 403 döner', async () => {
    const token = getTestToken('dispecer');
    const response = await request(app).get('/api/manager-messages/sent').set('Authorization', `Bearer ${token}`);
    assert.strictEqual(response.status, 403);
  });

  it('bir teknisyen mesajı okuduktan sonra: yöneticinin /sent listesinde read_count doğru şekilde artar', async () => {
    const managerToken = getTestToken('yonetici');
    const created = await request(app)
      .post('/api/manager-messages')
      .set('Authorization', `Bearer ${managerToken}`)
      .send({
        content: 'Güvenlik duyurusu',
        recipient_user_ids: [seeded.users.teknisyenId, seeded.users.otherTeknisyenId],
      });

    let sentResponse = await request(app)
      .get('/api/manager-messages/sent')
      .set('Authorization', `Bearer ${managerToken}`);
    assert.strictEqual(sentResponse.status, 200);
    const beforeRead = sentResponse.body.find((m) => m.id === created.body.id);
    assertSchema(beforeRead, { id: 'number', recipient_count: 'number', read_count: 'number' });
    assert.strictEqual(beforeRead.recipient_count, 2);
    assert.strictEqual(beforeRead.read_count, 0);

    const teknisyenToken = getTestToken('teknisyen');
    await request(app)
      .patch(`/api/manager-messages/${created.body.id}/read`)
      .set('Authorization', `Bearer ${teknisyenToken}`);

    sentResponse = await request(app)
      .get('/api/manager-messages/sent')
      .set('Authorization', `Bearer ${managerToken}`);
    const afterRead = sentResponse.body.find((m) => m.id === created.body.id);
    assert.strictEqual(afterRead.read_count, 1, '2 alıcıdan 1\'i okudu — read_count 1 olmalı');
    assert.strictEqual(afterRead.recipient_count, 2);
  });
});

describe('GET /api/manager-messages/:id/read-status', () => {
  let seeded;
  let messageId;

  beforeEach(async () => {
    resetTestDatabase();
    seeded = seedMinimalTestData();

    const managerToken = getTestToken('yonetici');
    const created = await request(app)
      .post('/api/manager-messages')
      .set('Authorization', `Bearer ${managerToken}`)
      .send({
        content: 'İSG duyurusu',
        recipient_user_ids: [seeded.users.teknisyenId, seeded.users.otherTeknisyenId],
      });
    messageId = created.body.id;

    const teknisyenToken = getTestToken('teknisyen');
    await request(app)
      .patch(`/api/manager-messages/${messageId}/read`)
      .set('Authorization', `Bearer ${teknisyenToken}`);
  });

  it('gönderen yönetici: hangi alıcının okuyup hangisinin okumadığını doğru görür', async () => {
    const managerToken = getTestToken('yonetici');
    const response = await request(app)
      .get(`/api/manager-messages/${messageId}/read-status`)
      .set('Authorization', `Bearer ${managerToken}`);

    assert.strictEqual(response.status, 200);
    assertArraySchema(response.body.recipients, {
      recipient_user_id: 'number',
      name: 'string',
      role: 'string',
    });

    const teknisyenEntry = response.body.recipients.find(
      (r) => r.recipient_user_id === seeded.users.teknisyenId
    );
    const otherEntry = response.body.recipients.find(
      (r) => r.recipient_user_id === seeded.users.otherTeknisyenId
    );
    assert.ok(teknisyenEntry.read_at !== null, 'Okuyan teknisyen "okundu" görünmeli');
    assert.strictEqual(otherEntry.read_at, null, 'Okumayan teknisyen "okunmadı" görünmeli');
  });

  it('KRİTİK: mesajı GÖNDERMEYEN başka bir yönetici bu okundu takibini göremez (404)', async () => {
    const otherManagerId = db
      .prepare('INSERT INTO users (name, role, sicil_no, password_hash) VALUES (?, ?, ?, ?)')
      .run('Diğer Yönetici', 'yonetici', '3002', 'x').lastInsertRowid;
    const otherManagerToken = generateValidToken({ id: otherManagerId, role: 'yonetici' });

    const response = await request(app)
      .get(`/api/manager-messages/${messageId}/read-status`)
      .set('Authorization', `Bearer ${otherManagerToken}`);

    assert.strictEqual(response.status, 404);
  });

  it('KRİTİK RBAC: teknisyen kendi aldığı mesajın read-status\'unu göremez (403)', async () => {
    const token = getTestToken('teknisyen');
    const response = await request(app)
      .get(`/api/manager-messages/${messageId}/read-status`)
      .set('Authorization', `Bearer ${token}`);
    assert.strictEqual(response.status, 403);
  });
});
