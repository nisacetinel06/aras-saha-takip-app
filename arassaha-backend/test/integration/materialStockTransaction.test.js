// TEST-07: POST /api/workorders/:workOrderId/materials — Modül 13'ün stok
// düşürme transaction'ı. Amaç: stok miktarının HİÇBİR koşulda (yarım kalan
// işlem, gerçek bir constraint ihlali, sınır değer) tutarsız/negatif bir
// duruma düşmediğini, gerçek SQLite BEGIN/COMMIT/ROLLBACK ile kanıtlamak.
// Mock YOK — :memory: gerçek SQLite + gerçek FK constraint'ler (PRAGMA
// foreign_keys = ON, bkz. database.js ve test/integration/dbConstraints.test.js).
//
// ADIM 0 BULGUSU (kod incelemesi, routes/materials.js POST
// /workorders/:workOrderId/materials): stok düşürme mantığı ZATEN gerçek bir
// transaction içinde — db.exec('BEGIN') / try / db.exec('COMMIT') /
// catch { db.exec('ROLLBACK'); throw } deseni (satır ~410-434) INSERT INTO
// work_order_materials + UPDATE materials.stock_quantity + INSERT INTO
// material_stock_movements üçünü SARIYOR. Ayrıca "yetersiz stok" kontrolü
// `quantityUsed > material.stock_quantity` (satır 399) — DOĞRU operatör,
// tam stok kadar kullanım (`quantityUsed === stock_quantity`) yanlışlıkla
// reddedilmiyor. `quantity_used <= 0` kontrolü (satır 388) de ZATEN mevcut —
// negatif/sıfır miktar transaction'a hiç ulaşmıyor. YANİ: bu görevde
// routes/materials.js'te herhangi bir KOD DEĞİŞİKLİĞİ gerekmedi — Adım 0'da
// aranan açıkların hiçbiri yoktu, bu dosya SADECE bu davranışı gerçek
// SQLite'a karşı kanıtlayan testlerden oluşuyor.
//
// ÖNEMLİ NÜANS (Adım 4 ile ilgili): kod, work_order_id ve material_id
// varlığını transaction BAŞLAMADAN ÖNCE (BEGIN'den önce) ayrı SELECT'lerle
// kontrol edip 404 döndürüyor (satır 378-395). Yani "var olmayan
// work_order_id" isteği asla transaction'a/gerçek bir FK ihlaline ulaşmıyor —
// bu senaryoda test edilen şey "pre-check'in transaction'ı hiç açmadığı"
// (aşağıdaki "pre-check" describe bloğu). Task'ın istediği "GERÇEK bir FK
// ihlaliyle transaction ortasında başarısız olma" senaryosunu HTTP üzerinden
// tetiklemek için recorded_by_user_id (JWT'den gelir, route'ta AYRICA
// doğrulanmıyor) kullanıldı — bkz. "gerçek FK ihlali" describe bloğu. Ek
// olarak, node:sqlite'ın BEGIN/ROLLBACK mekanizmasının PRAGMA
// foreign_keys=ON ile GERÇEKTEN kısmi yazmayı geri aldığını, uygulama
// kodundan bağımsız olarak da (düşük seviyeli, doğrudan db'ye karşı)
// doğrulayan bir test eklendi.
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const request = require('supertest');
const app = require('../../server');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');
const { getTestToken } = require('../helpers/authHelper');
const { generateValidToken } = require('../helpers/tokenHelper');
const { seedTestMaterial } = require('../helpers/materialFixtures');

function getMaterial(id) {
  return db.prepare('SELECT * FROM materials WHERE id = ?').get(id);
}
function countUsageRows(workOrderId, materialId) {
  return db
    .prepare('SELECT COUNT(*) AS c FROM work_order_materials WHERE work_order_id = ? AND material_id = ?')
    .get(workOrderId, materialId).c;
}
function countMovementRows(materialId) {
  return db.prepare('SELECT COUNT(*) AS c FROM material_stock_movements WHERE material_id = ?').get(materialId).c;
}

describe('POST /api/workorders/:workOrderId/materials — stok transaction\'ı', () => {
  let seeded;
  let workOrderId;
  let materialId;
  let technicianToken;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
    workOrderId = seeded.workOrders.ownWorkOrderId;
    materialId = seedTestMaterial({ stock_quantity: 20 });
    technicianToken = getTestToken('teknisyen');
  });

  describe('pozitif senaryolar', () => {
    it('yeterli stok: 5 birim kullanımı 201 döner, stok DB\'de gerçekten 15\'e düşer', async () => {
      const response = await request(app)
        .post(`/api/workorders/${workOrderId}/materials`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ material_id: materialId, quantity_used: 5 });

      assert.strictEqual(response.status, 201);

      const material = getMaterial(materialId);
      assert.strictEqual(material.stock_quantity, 15, 'DB\'deki gerçek stok 20 - 5 = 15 olmalı');
      assert.strictEqual(countUsageRows(workOrderId, materialId), 1);
      assert.strictEqual(countMovementRows(materialId), 1);
    });

    it('SINIR DURUMU: tam stok kadar (20/20) kullanım BAŞARILI olmalı, 400 DÖNMEMELİ (> operatörü doğru)', async () => {
      const response = await request(app)
        .post(`/api/workorders/${workOrderId}/materials`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ material_id: materialId, quantity_used: 20 });

      assert.strictEqual(response.status, 201, `beklenmedik yanıt: ${JSON.stringify(response.body)}`);

      const material = getMaterial(materialId);
      assert.strictEqual(material.stock_quantity, 0, 'stok tam olarak 0\'a düşmeli, negatif OLMAMALI');
    });
  });

  describe('negatif/sınır senaryoları — negatif stok ASLA oluşmamalı', () => {
    it('yetersiz stok (25 > 20): 400 döner, stok DEĞİŞMEZ', async () => {
      const response = await request(app)
        .post(`/api/workorders/${workOrderId}/materials`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ material_id: materialId, quantity_used: 25 });

      assert.strictEqual(response.status, 400);

      const material = getMaterial(materialId);
      assert.strictEqual(material.stock_quantity, 20, 'reddedilen istek stoğu DEĞİŞTİRMEMİŞ olmalı');
      assert.strictEqual(countUsageRows(workOrderId, materialId), 0);
    });

    it('negatif miktar (-5): 400 döner, stok DEĞİŞMEZ/ARTMAZ (quantity_used <= 0 kontrolü)', async () => {
      const response = await request(app)
        .post(`/api/workorders/${workOrderId}/materials`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ material_id: materialId, quantity_used: -5 });

      assert.strictEqual(response.status, 400);
      assert.match(response.body.error, /pozitif/i);

      const material = getMaterial(materialId);
      // BULGU DOĞRULAMASI: kod incelemesinde bulunan risk — yalnızca
      // `quantity_used > stock_quantity` kontrolü olsaydı, -5 > 20 YANLIŞ
      // olduğundan "yeterli stok var" sayılıp UPDATE stock_quantity = 20 - (-5)
      // = 25 ile stoğu YANLIŞLIKLA ARTIRABİLİRDİ. Gerçek kod bunu
      // `quantity_used <= 0` kontrolüyle ayrıca ve AÇIKÇA reddediyor (satır
      // 388) — bu yüzden burada stoğun hem AZALMADIĞINI hem ARTMADIĞINI
      // (tam olarak 20'de sabit kaldığını) doğruluyoruz.
      assert.strictEqual(material.stock_quantity, 20, 'negatif miktar stoğu ARTIRMAMALI/AZALTMAMALI');
      assert.strictEqual(countUsageRows(workOrderId, materialId), 0);
    });

    it('sıfır miktar (0): 400 döner, stok DEĞİŞMEZ', async () => {
      const response = await request(app)
        .post(`/api/workorders/${workOrderId}/materials`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ material_id: materialId, quantity_used: 0 });

      assert.strictEqual(response.status, 400);

      const material = getMaterial(materialId);
      assert.strictEqual(material.stock_quantity, 20);
      assert.strictEqual(countUsageRows(workOrderId, materialId), 0);
    });
  });

  describe('pre-check: var olmayan work_order_id / material_id (transaction hiç AÇILMAZ)', () => {
    it('var olmayan work_order_id (999999): 404 döner, hiçbir yazma olmaz (transaction başlamadan reddedilir)', async () => {
      const response = await request(app)
        .post('/api/workorders/999999/materials')
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ material_id: materialId, quantity_used: 5 });

      assert.strictEqual(response.status, 404);

      const material = getMaterial(materialId);
      assert.strictEqual(material.stock_quantity, 20, 'stok DEĞİŞMEMİŞ olmalı');
      assert.strictEqual(countUsageRows(999999, materialId), 0);
      assert.strictEqual(countMovementRows(materialId), 0);
    });

    it('var olmayan material_id (999999): 404 döner, hiçbir yazma olmaz', async () => {
      const response = await request(app)
        .post(`/api/workorders/${workOrderId}/materials`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ material_id: 999999, quantity_used: 5 });

      assert.strictEqual(response.status, 404);
      assert.strictEqual(countUsageRows(workOrderId, 999999), 0);
    });
  });

  describe('gerçek FK ihlali → gerçek ROLLBACK (recorded_by_user_id, HTTP üzerinden tetiklenebilir)', () => {
    it('var olmayan bir kullanıcı id\'siyle imzalanmış (geçerli imzalı) token: transaction FK ihlaliyle başarısız olur, stok GERÇEKTEN geri döner', async () => {
      // work_order_id ve material_id'nin aksine, recorded_by_user_id
      // route'ta HİÇBİR ÖN KONTROLDEN geçmeden doğrudan req.user.id'den
      // (JWT payload'ından) alınıp INSERT'e yazılır — bu yüzden "kullanıcı
      // token alındıktan SONRA silindi" gibi gerçek bir senaryoyu simüle
      // eden, var olmayan bir id'ye sahip ama GEÇERLİ İMZALI bir token,
      // work_order_materials.recorded_by_user_id FK'sini GERÇEKTEN ihlal
      // ettirip transaction'ı ortasında başarısız kılar.
      const ghostUserToken = generateValidToken({ id: 999999, role: 'teknisyen' });

      const beforeMaterial = getMaterial(materialId);
      const beforeUsageCount = countUsageRows(workOrderId, materialId);
      const beforeMovementCount = countMovementRows(materialId);

      const response = await request(app)
        .post(`/api/workorders/${workOrderId}/materials`)
        .set('Authorization', `Bearer ${ghostUserToken}`)
        .send({ material_id: materialId, quantity_used: 5 });

      // routes/materials.js'te FK ihlali app seviyesinde ÖNGÖRÜLMÜYOR (bu
      // alan hiç kontrol edilmiyor), bu yüzden hata dıştaki genel catch'e
      // düşüp 500 olarak dönüyor — 400/404 değil. Kritik olan status kodu
      // DEĞİL, sunucunun ÇÖKMEMESİ ve stoğun/kayıtların GERÇEKTEN
      // değişmemiş olması.
      assert.ok(
        [400, 404, 500].includes(response.status),
        `sunucu çökmemeli, beklenmedik status: ${response.status}`
      );

      // EN KRİTİK KONTROL: transaction'ın ROLLBACK ile başlangıç durumuna
      // GERÇEKTEN döndüğü — ne stok değişmiş, ne yarım bir kullanım kaydı
      // ne de yarım bir stok hareketi kalmış olmalı.
      const afterMaterial = getMaterial(materialId);
      assert.strictEqual(
        afterMaterial.stock_quantity,
        beforeMaterial.stock_quantity,
        'ROLLBACK sonrası stok BEGIN öncesi haliyle BİREBİR aynı olmalı'
      );
      assert.strictEqual(countUsageRows(workOrderId, materialId), beforeUsageCount, 'yarım kalmış bir kullanım kaydı OLMAMALI');
      assert.strictEqual(countMovementRows(materialId), beforeMovementCount, 'yarım kalmış bir stok hareketi kaydı OLMAMALI');
    });
  });

  describe('birden fazla eşzamanlı constraint ihlali — çökmeden tutarlı bir hata', () => {
    it('hem geçersiz material_id hem negatif quantity_used: sunucu çökmez (500 DEĞİL), tek ve net bir hata döner', async () => {
      const response = await request(app)
        .post(`/api/workorders/${workOrderId}/materials`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .send({ material_id: 999999, quantity_used: -5 });

      // Kod, quantity_used <= 0 kontrolünü material_id'nin VAR OLUP
      // olmadığını sorgulamadan ÖNCE yapıyor (satır 383-390) — yani bu
      // kombinasyonda gerçek hata "quantity_used" hakkında olur, material_id
      // sorgusuna hiç gidilmez. Önemli olan: TEK, TUTARLI bir 400.
      assert.strictEqual(response.status, 400);
      assert.strictEqual(typeof response.body.error, 'string');
    });
  });
});

describe('BEGIN/ROLLBACK — düşük seviyeli, uygulama kodundan bağımsız kanıt', () => {
  beforeEach(() => {
    resetTestDatabase();
  });

  it("gerçek bir FK ihlali, BEGIN ile başlayan bir transaction'ı GERÇEKTEN geri alır (node:sqlite + PRAGMA foreign_keys=ON)", () => {
    const materialId = seedTestMaterial({ stock_quantity: 20 });

    // work_order_materials.recorded_by_user_id NOT NULL + FK REFERENCES
    // users(id) — 999999 hiçbir zaman var olmayan bir kullanıcı id'si.
    // Bu test, routes/materials.js'i (route seviyesi kontrolleri) ATLAYIP
    // AYNI SQL deseniyle (stok önce güncellenir, SONRA ihlal eden INSERT
    // denenir) doğrudan veritabanına karşı çalışır — amaç, uygulama
    // kodunun doğruluğundan BAĞIMSIZ olarak node:sqlite'ın BEGIN/ROLLBACK
    // mekanizmasının, PRAGMA foreign_keys = ON altında, KISMİ bir yazmayı
    // (stok zaten düşürülmüşken) gerçekten geri aldığını kanıtlamak.
    const beforeStock = db.prepare('SELECT stock_quantity FROM materials WHERE id = ?').get(materialId).stock_quantity;
    assert.strictEqual(beforeStock, 20);

    let threw = false;
    db.exec('BEGIN');
    try {
      // 1) stok ÖNCE düşürülüyor (asıl route'takinden farklı sıra, BİLEREK —
      // "yarım kalmış bir güncelleme" senaryosunu netleştirmek için)
      db.prepare('UPDATE materials SET stock_quantity = stock_quantity - 5 WHERE id = ?').run(materialId);

      const midTransactionStock = db.prepare('SELECT stock_quantity FROM materials WHERE id = ?').get(materialId)
        .stock_quantity;
      assert.strictEqual(midTransactionStock, 15, 'transaction İÇİNDE (henüz COMMIT edilmeden) stok 15 görünmeli');

      // 2) SONRA gerçek bir FK ihlali tetiklenir (var olmayan kullanıcı id'si)
      db.prepare(
        `INSERT INTO work_order_materials (work_order_id, material_id, quantity_used, recorded_by_user_id, created_at)
         VALUES (?, ?, ?, ?, ?)`
      ).run(1, materialId, 5, 999999, new Date().toISOString());

      db.exec('COMMIT');
    } catch (err) {
      threw = true;
      db.exec('ROLLBACK');
    }

    assert.ok(threw, 'FK ihlali GERÇEKTEN bir hata fırlatmalı (PRAGMA foreign_keys=ON çalışıyor olmalı)');

    const afterStock = db.prepare('SELECT stock_quantity FROM materials WHERE id = ?').get(materialId).stock_quantity;
    assert.strictEqual(afterStock, 20, 'ROLLBACK sonrası stok BEGIN ÖNCESİ değerine (20) GERİ DÖNMÜŞ olmalı — 15\'te KALMAMALI');

    const usageCount = db.prepare('SELECT COUNT(*) AS c FROM work_order_materials WHERE material_id = ?').get(materialId).c;
    assert.strictEqual(usageCount, 0, 'başarısız INSERT kalıcı OLMAMALI');
  });
});
