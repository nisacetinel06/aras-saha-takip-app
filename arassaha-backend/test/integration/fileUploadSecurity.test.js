// GÜVENLİK: Fotoğraf yükleme endpoint'lerinde (İSG/Modül 5, iş emri fotoğrafı,
// profil fotoğrafı/Modül 8) MIME type sahteciliği (spoofing) açığı.
//
// KÖK NEDEN (Adım 0, kod incelemesi): Her üç route'taki multer `fileFilter`,
// yalnızca `file.mimetype` (isg.js: allowlist ['image/jpeg','image/png'];
// workOrders.js/users.js: `startsWith('image/')`) ve/veya dosya uzantısını
// kontrol ediyordu. `file.mimetype`, istemcinin multipart isteğinde KENDİ
// BEYAN ETTİĞİ bir Content-Type header'ıdır — sunucu tarafından doğrulanmamış,
// dosyanın gerçek baytlarından tamamen bağımsız bir bilgidir. Bir saldırgan
// içeriği tamamen farklı (script, çalıştırılabilir, vb.) bir dosyayı ".jpg"
// uzantısı ve "Content-Type: image/jpeg" ile paketleyip gönderirse, yalnızca
// mimetype/uzantı kontrolü yapan bir fileFilter bunu gerçek bir JPEG sanıp
// kabul eder ve diske yazar — klasik bir dosya yükleme güvenlik açığı.
//
// Bu dosya BİLEREK fix'ten (utils/fileTypeValidator.js + middleware/
// validateImageContent.js) ÖNCE yazıldı: "[GÜVENLİK AÇIĞI KANITI]" testleri
// ilk çalıştırmada KIRMIZI olmalı (400 bekleniyor, gerçek kod 201 dönüp
// sahte dosyayı diske yazıyor) — bu, açığın gerçekten var olduğunun kanıtı.
// Fix uygulandıktan SONRA aynı testler YEŞİL olmalı.
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const request = require('supertest');
const app = require('../../server');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');
const { getTestToken } = require('../helpers/authHelper');

const ISG_UPLOADS_DIR = path.join(__dirname, '..', '..', 'uploads', 'isg');
// SEC-04: iş emri fotoğrafları artık `uploads/` KÖKÜ değil, isg/profiles ile
// TUTARLI şekilde kendi alt klasöründe saklanıyor (bkz. routes/workOrders.js,
// routes/uploads.js'teki klasör whitelist'i).
const WORKORDER_UPLOADS_DIR = path.join(__dirname, '..', '..', 'uploads', 'workorders');
const PROFILE_UPLOADS_DIR = path.join(__dirname, '..', '..', 'uploads', 'profiles');

const VALID_JPEG_BUFFER = fs.readFileSync(path.join(__dirname, '..', 'fixtures', 'valid-test-image.jpg'));

// SEC-04 Kısım A testleri için: gerçek, geçerli, minimal (1x1 piksel,
// şeffaf) bir PNG — yaygın olarak kullanılan, iyi bilinen bir minimal PNG
// payload'ı (67 byte). Ayrı bir ikili fixture dosyası eklemek yerine (diğer
// FAKE_*_BUFFER sabitleriyle AYNI inline desen) base64'ten çözülür.
const VALID_PNG_BUFFER = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  'base64'
);

// Gerçek bir JPEG DEĞİL, düz metin — ama .jpg uzantısı ve image/jpeg
// mimetype'ıyla "gizlenmiş" (saldırganın yapacağı tam olarak budur).
const FAKE_IMAGE_BUFFER = Buffer.from('Bu aslinda bir metin dosyasi, resim degil');

// Gerçek bir küçük script'in baytları (polyglot testi — Adım 3): .jpg
// uzantısı ve image/jpeg mimetype'ıyla gönderilecek ama içerik JPEG/PNG
// imza baytı taşımıyor.
const FAKE_SCRIPT_BUFFER = Buffer.from('#!/bin/sh\necho "bu bir resim degil, bir kabuk betigi"\n');

function filesInDir(dir) {
  return fs.existsSync(dir) ? fs.readdirSync(dir) : [];
}

// `node --test` çoklu test DOSYASINI varsayılan olarak PARALEL çalıştırır;
// uploads/isg, uploads/, uploads/profiles GERÇEK, PAYLAŞILAN diskteki
// klasörlerdir — bu yüzden salt "önce/sonra dosya listesi farkı" (diff)
// diğer test dosyalarının (örn. isgStatusRbac.test.js, kendi validation
// test dosyalarımız) AYNI ANDA o klasöre yazdığı MEŞRU dosyaları da "sızıntı"
// sanıp yanlış-pozitif üretebilir (gerçek bir yarış durumu, uygulama
// kodunda DEĞİL, bu diff yönteminde). Bunun yerine yeni beliren dosyaların
// İÇERİĞİNİ kontrol ediyoruz — yalnızca BİZİM gönderdiğimiz sahte buffer'la
// birebir eşleşen bir dosya varsa gerçekten SIZDIRILMIŞ sayılır; başka bir
// testin o anda yazdığı alakasız bir dosya artık yanlışlıkla eşleşmez.
function leakedFilesMatchingContent(dir, beforeSet, expectedBuffer) {
  return filesInDir(dir)
    .filter((f) => !beforeSet.has(f))
    .filter((f) => {
      try {
        return fs.readFileSync(path.join(dir, f)).equals(expectedBuffer);
      } catch {
        return false; // dosya bu arada başka bir test tarafından silinmiş olabilir — bizim değildi.
      }
    });
}

describe('Fotoğraf yükleme güvenliği — MIME type sahteciliği (spoofing)', () => {
  let seeded;
  let technicianToken;
  let managerToken;
  let workOrderId;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
    technicianToken = getTestToken('teknisyen');
    managerToken = getTestToken('yonetici');
    workOrderId = seeded.workOrders.ownWorkOrderId;
  });

  describe('[GÜVENLİK AÇIĞI KANITI] Adım 1 — İSG bildirimi (POST /api/isg-reports)', () => {
    it('.jpg uzantılı ama gerçekte JPEG olmayan bir dosya kabul edilmemeli', async () => {
      const beforeFiles = new Set(filesInDir(ISG_UPLOADS_DIR));

      const response = await request(app)
        .post('/api/isg-reports')
        .set('Authorization', `Bearer ${technicianToken}`)
        .field('description', 'Test bildirimi')
        .field('category', 'ekipman_arizasi')
        .field('lat', '39.9')
        .field('lng', '41.27')
        .attach('photo', FAKE_IMAGE_BUFFER, { filename: 'sahte-resim.jpg', contentType: 'image/jpeg' });

      assert.strictEqual(response.status, 400, `beklenmedik yanıt: ${response.status} ${JSON.stringify(response.body)}`);

      // Reddedilen dosya diskte KALICI olarak bırakılmamalı.
      const leaked = leakedFilesMatchingContent(ISG_UPLOADS_DIR, beforeFiles, FAKE_IMAGE_BUFFER);
      assert.strictEqual(leaked.length, 0, `sahte dosya diskte kalmış: ${JSON.stringify(leaked)}`);

      // Veritabanına da hiçbir kayıt eklenmemeli.
      const count = db.prepare('SELECT COUNT(*) AS c FROM isg_reports').get().c;
      assert.strictEqual(count, 0);
    });
  });

  describe('Adım 3 — pozitif kontrol: gerçek bir JPEG kabul edilmeli', () => {
    it('İSG: gerçek bir küçük JPEG (test/fixtures/valid-test-image.jpg) başarıyla kabul edilmeli', async () => {
      const response = await request(app)
        .post('/api/isg-reports')
        .set('Authorization', `Bearer ${technicianToken}`)
        .field('description', 'Gerçek fotoğraflı bildirim')
        .field('category', 'ekipman_arizasi')
        .field('lat', '39.9')
        .field('lng', '41.27')
        .attach('photo', VALID_JPEG_BUFFER, { filename: 'gercek.jpg', contentType: 'image/jpeg' });

      assert.strictEqual(response.status, 201, `beklenmedik yanıt: ${response.status} ${JSON.stringify(response.body)}`);
      assert.ok(response.body.photo_path.startsWith('/uploads/isg/'));

      // Dosya gerçekten diskte kalıcı olmalı (meşru yükleme silinmemeli).
      const savedFilename = response.body.photo_path.split('/').pop();
      assert.ok(fs.existsSync(path.join(ISG_UPLOADS_DIR, savedFilename)));
    });

    it('İş emri fotoğrafı: gerçek bir küçük JPEG başarıyla kabul edilmeli', async () => {
      const response = await request(app)
        .post(`/api/workorders/${workOrderId}/photos`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .attach('photo', VALID_JPEG_BUFFER, { filename: 'gercek.jpg', contentType: 'image/jpeg' });

      assert.strictEqual(response.status, 201, `beklenmedik yanıt: ${response.status} ${JSON.stringify(response.body)}`);
    });

    it('Profil fotoğrafı: gerçek bir küçük JPEG başarıyla kabul edilmeli', async () => {
      const response = await request(app)
        .post(`/api/users/${seeded.users.teknisyenId}/photo`)
        .set('Authorization', `Bearer ${managerToken}`)
        .attach('photo', VALID_JPEG_BUFFER, { filename: 'gercek.jpg', contentType: 'image/jpeg' });

      assert.strictEqual(response.status, 200, `beklenmedik yanıt: ${response.status} ${JSON.stringify(response.body)}`);
      assert.ok(response.body.photo_path.startsWith('/uploads/profiles/'));
    });
  });

  describe('Adım 3 — izin verilmeyen uzantı (fileFilter katmanı)', () => {
    it('İSG: .exe uzantılı dosya (application/octet-stream) fileFilter seviyesinde reddedilmeli', async () => {
      const response = await request(app)
        .post('/api/isg-reports')
        .set('Authorization', `Bearer ${technicianToken}`)
        .field('description', 'Test')
        .field('category', 'ekipman_arizasi')
        .field('lat', '39.9')
        .field('lng', '41.27')
        .attach('photo', Buffer.from('MZ fake exe content'), {
          filename: 'kotu-amacli.exe',
          contentType: 'application/octet-stream',
        });

      assert.strictEqual(response.status, 400);
    });
  });

  describe('Adım 3 — sahte MIME type (genişletilmiş, .png)', () => {
    it('İSG: .png uzantısı + image/png mimetype ama gerçek PNG imzası yok → 400', async () => {
      const response = await request(app)
        .post('/api/isg-reports')
        .set('Authorization', `Bearer ${technicianToken}`)
        .field('description', 'Test')
        .field('category', 'ekipman_arizasi')
        .field('lat', '39.9')
        .field('lng', '41.27')
        .attach('photo', FAKE_IMAGE_BUFFER, { filename: 'sahte.png', contentType: 'image/png' });

      assert.strictEqual(response.status, 400);
    });
  });

  describe('Adım 3 — polyglot testi (gerçek script baytları, .jpg/.image-jpeg kılığında)', () => {
    it('İSG: script baytları .jpg uzantısı ve image/jpeg mimetype ile gönderilirse 400, diskte kalmamalı', async () => {
      const beforeFiles = new Set(filesInDir(ISG_UPLOADS_DIR));

      const response = await request(app)
        .post('/api/isg-reports')
        .set('Authorization', `Bearer ${technicianToken}`)
        .field('description', 'Test')
        .field('category', 'ekipman_arizasi')
        .field('lat', '39.9')
        .field('lng', '41.27')
        .attach('photo', FAKE_SCRIPT_BUFFER, { filename: 'sahte-resim.jpg', contentType: 'image/jpeg' });

      assert.strictEqual(response.status, 400);
      const leaked = leakedFilesMatchingContent(ISG_UPLOADS_DIR, beforeFiles, FAKE_SCRIPT_BUFFER);
      assert.strictEqual(leaked.length, 0, `script dosyası diskte kalmış: ${JSON.stringify(leaked)}`);
    });

    it('İş emri fotoğrafı: aynı polyglot senaryosu 400 dönmeli, diskte kalmamalı', async () => {
      const beforeFiles = new Set(filesInDir(WORKORDER_UPLOADS_DIR));

      const response = await request(app)
        .post(`/api/workorders/${workOrderId}/photos`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .attach('photo', FAKE_SCRIPT_BUFFER, { filename: 'sahte-resim.jpg', contentType: 'image/jpeg' });

      assert.strictEqual(response.status, 400);
      const leaked = leakedFilesMatchingContent(WORKORDER_UPLOADS_DIR, beforeFiles, FAKE_SCRIPT_BUFFER);
      assert.strictEqual(leaked.length, 0, `script dosyası diskte kalmış: ${JSON.stringify(leaked)}`);

      const photoCount = db.prepare('SELECT COUNT(*) AS c FROM work_order_photos WHERE work_order_id = ?').get(workOrderId).c;
      assert.strictEqual(photoCount, 0);
    });

    it('Profil fotoğrafı: aynı polyglot senaryosu 400 dönmeli, diskte kalmamalı, photo_path güncellenmemeli', async () => {
      const beforeFiles = new Set(filesInDir(PROFILE_UPLOADS_DIR));

      const response = await request(app)
        .post(`/api/users/${seeded.users.teknisyenId}/photo`)
        .set('Authorization', `Bearer ${managerToken}`)
        .attach('photo', FAKE_SCRIPT_BUFFER, { filename: 'sahte-resim.jpg', contentType: 'image/jpeg' });

      assert.strictEqual(response.status, 400);
      const leaked = leakedFilesMatchingContent(PROFILE_UPLOADS_DIR, beforeFiles, FAKE_SCRIPT_BUFFER);
      assert.strictEqual(leaked.length, 0, `script dosyası diskte kalmış: ${JSON.stringify(leaked)}`);

      const user = db.prepare('SELECT photo_path FROM users WHERE id = ?').get(seeded.users.teknisyenId);
      assert.strictEqual(user.photo_path, null);
    });
  });

  describe('Adım 3 — dosya olmadan istek', () => {
    it('İSG: photo alanı hiç gönderilmeden 400 dönmeli (500 DEĞİL)', async () => {
      const response = await request(app)
        .post('/api/isg-reports')
        .set('Authorization', `Bearer ${technicianToken}`)
        .field('description', 'Fotoğrafsız test')
        .field('category', 'ekipman_arizasi')
        .field('lat', '39.9')
        .field('lng', '41.27');

      assert.strictEqual(response.status, 400);
      assert.ok(response.body.error);
    });
  });

  describe('Adım 3 — boyut sınırı (multer limits.fileSize)', () => {
    it('İSG: 5MB limitini aşan bir dosya düzgün bir 400 JSON ile reddedilmeli (500/stack trace DEĞİL)', async () => {
      const oversized = Buffer.alloc(6 * 1024 * 1024, 0); // 6MB, sıfır byte'larla dolu
      const response = await request(app)
        .post('/api/isg-reports')
        .set('Authorization', `Bearer ${technicianToken}`)
        .field('description', 'Boyut testi')
        .field('category', 'ekipman_arizasi')
        .field('lat', '39.9')
        .field('lng', '41.27')
        .attach('photo', oversized, { filename: 'buyuk.jpg', contentType: 'image/jpeg' });

      assert.strictEqual(response.status, 400, `beklenmedik yanıt: ${response.status} ${JSON.stringify(response.body)}`);
      assert.ok(response.body.error, 'yanıt düzgün bir JSON error alanı içermeli, çirkin bir stack trace değil');
    });
  });

  describe('Adım 3 — birden fazla dosya (aynı alan adı altında)', () => {
    it('İSG: aynı "photo" alanı altında iki dosya gönderilirse sunucu çökmemeli, anlamlı 400 dönmeli', async () => {
      const response = await request(app)
        .post('/api/isg-reports')
        .set('Authorization', `Bearer ${technicianToken}`)
        .field('description', 'Çoklu dosya testi')
        .field('category', 'ekipman_arizasi')
        .field('lat', '39.9')
        .field('lng', '41.27')
        .attach('photo', VALID_JPEG_BUFFER, { filename: 'birinci.jpg', contentType: 'image/jpeg' })
        .attach('photo', VALID_JPEG_BUFFER, { filename: 'ikinci.jpg', contentType: 'image/jpeg' });

      assert.strictEqual(response.status, 400, `beklenmedik yanıt: ${response.status} ${JSON.stringify(response.body)}`);
      assert.ok(response.body.error);
    });
  });

  // SEC-04 Kısım A: uzantı artık istemcinin gönderdiği dosya adından DEĞİL,
  // detectImageType() ile doğrulanmış GERÇEK tipten türetiliyor. Bu, "geçerli
  // bir PNG ama .jpg uzantısıyla gönderilmiş" gibi meşru-ama-yanlış-etiketli
  // dosyaların diskte YANLIŞ uzantıyla saklanmasını önler (bkz.
  // middleware/validateImageContent.js).
  describe('Adım 4 (SEC-04) — uzantı, doğrulanmış GERÇEK içerikten türetilir', () => {
    it('.jpg uzantılı ama içeriği GERÇEKTEN PNG olan bir dosya diskte .png uzantısıyla kaydedilmeli (.jpg İLE DEĞİL)', async () => {
      const response = await request(app)
        .post('/api/isg-reports')
        .set('Authorization', `Bearer ${technicianToken}`)
        .field('description', 'Uzantı normalizasyonu testi')
        .field('category', 'ekipman_arizasi')
        .field('lat', '39.9')
        .field('lng', '41.27')
        .attach('photo', VALID_PNG_BUFFER, { filename: 'aslinda-png.jpg', contentType: 'image/jpeg' });

      assert.strictEqual(response.status, 201, `beklenmedik yanıt: ${response.status} ${JSON.stringify(response.body)}`);
      assert.ok(
        response.body.photo_path.endsWith('.png'),
        `photo_path .png ile bitmeli (gerçek içerik PNG), aldığımız: ${response.body.photo_path}`
      );
      assert.ok(
        !response.body.photo_path.endsWith('.jpg'),
        'photo_path istemcinin YANLIŞ beyan ettiği .jpg uzantısını TAŞIMAMALI'
      );

      // Dosya GERÇEKTEN diskte, doğru uzantıyla var olmalı.
      const savedFilename = response.body.photo_path.split('/').pop();
      assert.ok(fs.existsSync(path.join(ISG_UPLOADS_DIR, savedFilename)));
      assert.ok(savedFilename.endsWith('.png'));

      // Yanlış (istemcinin beyan ettiği) uzantıyla bir dosya diskte OLUŞMAMALI.
      const wrongExtensionFilename = savedFilename.replace(/\.png$/, '.jpg');
      assert.ok(!fs.existsSync(path.join(ISG_UPLOADS_DIR, wrongExtensionFilename)));
    });

    it('gerçek bir JPEG, doğru uzantıyla yüklendiğinde HÂLÂ .jpeg/.jpg ile kaydedilmeli (normalizasyon meşru yüklemeyi bozmamalı)', async () => {
      const response = await request(app)
        .post('/api/isg-reports')
        .set('Authorization', `Bearer ${technicianToken}`)
        .field('description', 'Kontrol senaryosu')
        .field('category', 'ekipman_arizasi')
        .field('lat', '39.9')
        .field('lng', '41.27')
        .attach('photo', VALID_JPEG_BUFFER, { filename: 'gercek.jpg', contentType: 'image/jpeg' });

      assert.strictEqual(response.status, 201, `beklenmedik yanıt: ${response.status} ${JSON.stringify(response.body)}`);
      assert.ok(
        response.body.photo_path.endsWith('.jpeg') || response.body.photo_path.endsWith('.jpg'),
        `gerçek bir JPEG hâlâ .jpeg/.jpg ile kaydedilmeli, aldığımız: ${response.body.photo_path}`
      );

      const savedFilename = response.body.photo_path.split('/').pop();
      assert.ok(fs.existsSync(path.join(ISG_UPLOADS_DIR, savedFilename)), 'meşru yükleme diskte kalmalı, silinmemeli');
    });

    it('İş emri fotoğrafı: aynı normalizasyon (yanlış etiketli PNG → .png ile kaydedilir)', async () => {
      const response = await request(app)
        .post(`/api/workorders/${workOrderId}/photos`)
        .set('Authorization', `Bearer ${technicianToken}`)
        .attach('photo', VALID_PNG_BUFFER, { filename: 'aslinda-png.jpg', contentType: 'image/jpeg' });

      assert.strictEqual(response.status, 201, JSON.stringify(response.body));
      assert.ok(response.body.photo_path.startsWith('/uploads/workorders/'));
      assert.ok(response.body.photo_path.endsWith('.png'));
    });

    it('Profil fotoğrafı: aynı normalizasyon (yanlış etiketli PNG → .png ile kaydedilir)', async () => {
      const response = await request(app)
        .post(`/api/users/${seeded.users.teknisyenId}/photo`)
        .set('Authorization', `Bearer ${managerToken}`)
        .attach('photo', VALID_PNG_BUFFER, { filename: 'aslinda-png.jpg', contentType: 'image/jpeg' });

      assert.strictEqual(response.status, 200, JSON.stringify(response.body));
      const user = db.prepare('SELECT photo_path FROM users WHERE id = ?').get(seeded.users.teknisyenId);
      assert.ok(user.photo_path.startsWith('/uploads/profiles/'));
      assert.ok(user.photo_path.endsWith('.png'));
    });
  });
});
