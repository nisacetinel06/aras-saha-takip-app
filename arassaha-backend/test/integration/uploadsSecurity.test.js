// SEC-04 Kısım B: routes/uploads.js — eski `express.static('uploads')`
// yerine geçen, güvenlik başlıkları ekleyen ve path traversal'a karşı
// EXPLICIT savunma yapan özel route handler'ının testleri.
//
// Bu route `/uploads` altında, `verifyToken` MOUNT EDİLMEDEN ÖNCE bağlanır
// (bkz. server.js) — yani bu testlerde Authorization header'ı GEREKMEZ,
// gerçek davranışla tutarlı (Flutter'ın Image.network çağrısı token
// göndermeden çalışır).
const { describe, it, before, beforeEach } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const request = require('supertest');
const app = require('../../server');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');
const { getTestToken } = require('../helpers/authHelper');

const UPLOADS_ROOT = path.join(__dirname, '..', '..', 'uploads');
const ISG_UPLOADS_DIR = path.join(UPLOADS_ROOT, 'isg');

const VALID_JPEG_BUFFER = fs.readFileSync(path.join(__dirname, '..', 'fixtures', 'valid-test-image.jpg'));

describe('routes/uploads.js — güvenlik başlıkları ve path traversal savunması', () => {
  let uploadedPhotoPath; // gerçek, var olan bir dosyanın URL yolu (örn. /uploads/isg/....jpeg)

  before(async () => {
    resetTestDatabase();
    seedMinimalTestData();
    const technicianToken = getTestToken('teknisyen');

    const response = await request(app)
      .post('/api/isg-reports')
      .set('Authorization', `Bearer ${technicianToken}`)
      .field('description', 'uploads route testi için gerçek fotoğraf')
      .field('category', 'ekipman_arizasi')
      .field('lat', '39.9')
      .field('lng', '41.27')
      .attach('photo', VALID_JPEG_BUFFER, { filename: 'gercek.jpg', contentType: 'image/jpeg' });

    assert.strictEqual(response.status, 201, JSON.stringify(response.body));
    uploadedPhotoPath = response.body.photo_path; // örn. '/uploads/isg/173...-abcd.jpeg'
  });

  describe('Adım 4 — normal erişim: güvenlik başlıkları gerçekten mevcut olmalı', () => {
    it('yüklenmiş gerçek bir dosyaya erişilince X-Content-Type-Options, Content-Type, X-Frame-Options, Content-Disposition, Cache-Control başlıkları dönmeli', async () => {
      const response = await request(app).get(uploadedPhotoPath);

      assert.strictEqual(response.status, 200, JSON.stringify(response.body));
      assert.strictEqual(response.headers['x-content-type-options'], 'nosniff');
      assert.strictEqual(response.headers['x-frame-options'], 'DENY');
      assert.strictEqual(response.headers['content-disposition'], 'inline');
      assert.match(response.headers['cache-control'], /private/);
      // Content-Type SUNUCUNUN belirlediği (uzantı whitelist'inden), dosya
      // adından TAHMİN edilen bir değer değil — bkz. routes/uploads.js.
      assert.strictEqual(response.headers['content-type'], 'image/jpeg');
    });
  });

  describe('Adım 5 — whitelist dışı klasör: 404', () => {
    it('/uploads/gizli-klasor/dosya.jpg → 404 (klasör whitelist\'te değil)', async () => {
      const response = await request(app).get('/uploads/gizli-klasor/dosya.jpg');
      assert.strictEqual(response.status, 404);
    });
  });

  describe('Adım 6 — izin verilmeyen uzantı: 404 (savunmacı test)', () => {
    it('diskte GERÇEKTEN var olan ama izin verilmeyen (.exe) uzantılı bir dosyaya erişim 404 dönmeli', async () => {
      // Normal yükleme akışı ASLA .exe uzantılı bir dosya üretmez (bkz.
      // Kısım A — uzantı her zaman doğrulanmış içerikten türetilir); bu
      // senaryo yalnızca "diskte YANLIŞLIKLA/başka bir yolla böyle bir dosya
      // olsaydı bile servis edilmemeli" savunmasını test eder.
      fs.mkdirSync(ISG_UPLOADS_DIR, { recursive: true });
      const strayFilePath = path.join(ISG_UPLOADS_DIR, 'stray-test-file.exe');
      fs.writeFileSync(strayFilePath, 'MZ sahte exe icerigi');

      try {
        const response = await request(app).get('/uploads/isg/stray-test-file.exe');
        assert.strictEqual(response.status, 404);
      } finally {
        fs.unlinkSync(strayFilePath);
      }
    });
  });

  describe('Adım 3 — path traversal denemeleri reddedilmeli', () => {
    it('düz (encode edilmemiş) "../../../etc/passwd" isteği 400/404 ile reddedilmeli, dosya İÇERİĞİ SIZDIRILMAMALI', async () => {
      const response = await request(app).get('/uploads/isg/../../../etc/passwd');

      assert.ok(
        response.status === 400 || response.status === 404,
        `beklenmedik status: ${response.status} — path traversal 400/404 DIŞINDA bir yanıt vermemeli`
      );
      // Ne olursa olsun, gerçek bir sistem dosyasının içeriği (örn. "root:")
      // yanıtta ASLA görünmemeli.
      assert.ok(
        !String(response.text || '').includes('root:'),
        'yanıt bir sistem dosyasının içeriğini SIZDIRMIŞ olabilir'
      );
    });

    it('URL-encode edilmiş "%2e%2e%2f" (gizlenmiş "../") denemesi — path.basename() tarafından ZARARSIZ hale getirilmeli', async () => {
      // Bu, düz "../" denemesinden DAHA TEHLİKELİ bir varyanttır: Express,
      // route parametrelerini LİTERAL "/" karakterlerine göre segmentlere
      // ayırdıktan SONRA decode eder — yani "%2f" (encode edilmiş "/"),
      // yeni bir segment sınırı OLUŞTURMADAN tek bir ":filename" parametresi
      // İÇİNE "../../../etc/passwd" gibi çözülebilecek bir değer
      // sızdırabilir. routes/uploads.js'teki path.basename(filename)
      // TAM OLARAK bu senaryoya karşı savunma katmanıdır.
      const response = await request(app).get(
        '/uploads/isg/%2e%2e%2f%2e%2e%2f%2e%2e%2fetc%2fpasswd'
      );

      assert.ok(
        response.status === 400 || response.status === 404,
        `beklenmedik status: ${response.status}`
      );
      assert.ok(!String(response.text || '').includes('root:'));
    });
  });
});
