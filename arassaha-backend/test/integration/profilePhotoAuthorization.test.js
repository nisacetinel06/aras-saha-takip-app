// GÜVENLİK KURALI (Kullanıcı Yönetimi / Modül 8): Profil fotoğrafını SADECE
// yönetici ekleyebilir/değiştirebilir — hem yeni kullanıcı oluşturulurken
// hem de var olan bir kullanıcının fotoğrafı sonradan güncellenirken.
// Teknisyen/dispeçer KENDİ fotoğrafını dahi değiştiremez (bkz.
// routes/users.js POST /:id/photo — requireRole('yonetici')).
//
// ADIM 1 DENETİMİ (bu dosya yazılmadan önce yapıldı) — SAPMA BULUNMADI:
//   - Backend: POST /api/users/:id/photo zaten requireRole('yonetici') ile
//     korunuyordu; profil fotoğrafı yazan BAŞKA bir endpoint (örn. bir
//     "kendi fotoğrafını yükle" yolu) YOKTU.
//   - Flutter: screens/profile/profile_screen.dart tamamen salt görüntüleme
//     — UserAvatar widget'ının onTap'i bile yok, kamera ikonu/"Değiştir"
//     butonu hiçbir role (yönetici DAHİL) gösterilmiyor.
//   - Flutter: screens/admin/user_edit_screen.dart'taki fotoğraf değiştirme
//     akışı GERÇEKTEN çalışıyor ve yalnızca Kullanıcı Yönetimi panelinden
//     (zaten isYonetici ile korunan module_entries.dart/home_screen.dart
//     girişleri üzerinden) erişilebiliyor.
// Bu dosya, "şu an doğru çalışıyor" durumunu regresyona karşı KİLİTLER —
// var olan test/integration/usersValidation.test.js'teki "Geçersiz ID"
// matrisi bu endpoint'i YALNIZCA managerToken ile (id doğrulama açısından)
// test ediyordu; RBAC (rol bazlı erişim) açısından hiç test edilmemişti.
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const request = require('supertest');
const app = require('../../server');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');
const { getTestToken } = require('../helpers/authHelper');

const VALID_JPEG_BUFFER = fs.readFileSync(
  path.join(__dirname, '..', 'fixtures', 'valid-test-image.jpg')
);

function getPhotoPath(id) {
  return db.prepare('SELECT photo_path FROM users WHERE id = ?').get(id).photo_path;
}

describe('routes/users.js POST /:id/photo — profil fotoğrafı yetkilendirmesi (SADECE yönetici)', () => {
  let seeded;
  let technicianToken;
  let dispatcherToken;
  let managerToken;
  let technicianUserId;
  let dispatcherUserId;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
    technicianToken = getTestToken('teknisyen');
    dispatcherToken = getTestToken('dispecer');
    managerToken = getTestToken('yonetici');
    technicianUserId = seeded.users.teknisyenId;
    dispatcherUserId = seeded.users.dispecerId;
  });

  it('[GÜVENLİK KONTROLÜ] teknisyen kendi fotoğrafını değiştirememeli (KENDİ id\'siyle bile)', async () => {
    const response = await request(app)
      .post(`/api/users/${technicianUserId}/photo`) // KENDİ id'siyle bile
      .set('Authorization', `Bearer ${technicianToken}`)
      .attach('photo', VALID_JPEG_BUFFER, { filename: 'test.jpg', contentType: 'image/jpeg' });

    assert.strictEqual(response.status, 403);
    // Reddedilen istek DB'de HİÇBİR iz bırakmamalı — "sessizce başarılı"
    // gibi görünüp fotoğrafın aslında değişmediği bir ara durum YOK.
    assert.strictEqual(
      getPhotoPath(technicianUserId),
      null,
      'reddedilen istekten sonra photo_path DEĞİŞMEMİŞ olmalı'
    );
  });

  it('[GÜVENLİK KONTROLÜ] dispeçer de kendi fotoğrafını değiştirememeli', async () => {
    const response = await request(app)
      .post(`/api/users/${dispatcherUserId}/photo`)
      .set('Authorization', `Bearer ${dispatcherToken}`)
      .attach('photo', VALID_JPEG_BUFFER, { filename: 'test.jpg', contentType: 'image/jpeg' });

    assert.strictEqual(response.status, 403); // dispeçer de yönetici değil, aynı kısıtlamaya tabi
    assert.strictEqual(getPhotoPath(dispatcherUserId), null);
  });

  it('[GÜVENLİK KONTROLÜ] dispeçer BAŞKA bir kullanıcının (teknisyenin) fotoğrafını da değiştirememeli', async () => {
    const response = await request(app)
      .post(`/api/users/${technicianUserId}/photo`)
      .set('Authorization', `Bearer ${dispatcherToken}`)
      .attach('photo', VALID_JPEG_BUFFER, { filename: 'test.jpg', contentType: 'image/jpeg' });

    assert.strictEqual(response.status, 403);
    assert.strictEqual(getPhotoPath(technicianUserId), null);
  });

  it('[POZİTİF KONTROL] yönetici bir kullanıcının fotoğrafını değiştirebilmeli — 200 döner, photo_path DB\'de GERÇEKTEN dolar', async () => {
    const response = await request(app)
      .post(`/api/users/${technicianUserId}/photo`)
      .set('Authorization', `Bearer ${managerToken}`)
      .attach('photo', VALID_JPEG_BUFFER, { filename: 'test.jpg', contentType: 'image/jpeg' });

    assert.strictEqual(response.status, 200, JSON.stringify(response.body));
    const savedPath = getPhotoPath(technicianUserId);
    assert.ok(
      savedPath && savedPath.startsWith('/uploads/profiles/'),
      `photo_path DB'de kalıcı bir URL olarak dolmuş olmalı, gelen: ${savedPath}`
    );
  });

  it('[GÜVENLİK KONTROLÜ] yönetici bile KENDİ fotoğrafını bu endpoint dışında bir yoldan değiştiremez — profil fotoğrafı yazan TEK endpoint budur', async () => {
    // "Kendi fotoğrafını kendisi yükleyebilecek" ayrı bir /me/photo benzeri
    // bir yol OLMADIĞINI kanıtlar — yönetici bile KENDİ id'sini vererek
    // AYNI (tek) endpoint'i çağırmak ZORUNDADIR, ve bu da zaten çalışır
    // (kural "istisnasız yönetici-only" demek, "yönetici kendi fotoğrafını
    // asla değiştiremez" demek DEĞİL — bkz. dosya başı dokümantasyonu).
    const response = await request(app)
      .post(`/api/users/${seeded.users.yoneticiId}/photo`)
      .set('Authorization', `Bearer ${managerToken}`)
      .attach('photo', VALID_JPEG_BUFFER, { filename: 'test.jpg', contentType: 'image/jpeg' });

    assert.strictEqual(response.status, 200, JSON.stringify(response.body));
    assert.ok(getPhotoPath(seeded.users.yoneticiId));
  });

  // ADIM 3: Yeni Kullanıcı Oluşturma Akışında Fotoğrafın Doğrulanması.
  // Flutter tarafı (user_edit_screen.dart "ekleme modu") fotoğrafı
  // POST /api/users'ın KENDİSİYLE değil, kullanıcı oluşturulduktan HEMEN
  // SONRA dönen id ile AYRI bir POST /:id/photo çağrısıyla kaydeder (bkz.
  // providers/user_provider.dart createUser + uploadUserPhoto). Bu test o
  // iki adımlı akışın backend tarafını uçtan uca kanıtlar.
  it('[UÇTAN UCA] yeni kullanıcı oluşturma + hemen ardından fotoğraf yükleme akışı çalışmalı', async () => {
    const createResponse = await request(app)
      .post('/api/users')
      .set('Authorization', `Bearer ${managerToken}`)
      .send({ name: 'Fotoğraflı Yeni Kullanıcı', sicil_no: '9999', password: 'gizli123', role: 'teknisyen' });

    assert.strictEqual(createResponse.status, 201, JSON.stringify(createResponse.body));
    const newUserId = createResponse.body.id;
    assert.strictEqual(getPhotoPath(newUserId), null, 'yeni kullanıcı fotoğrafsız oluşturulmuş olmalı');

    const photoResponse = await request(app)
      .post(`/api/users/${newUserId}/photo`)
      .set('Authorization', `Bearer ${managerToken}`)
      .attach('photo', VALID_JPEG_BUFFER, { filename: 'yeni.jpg', contentType: 'image/jpeg' });

    assert.strictEqual(photoResponse.status, 200, JSON.stringify(photoResponse.body));
    assert.ok(
      getPhotoPath(newUserId)?.startsWith('/uploads/profiles/'),
      'yeni kullanıcının photo_path\'i ikinci istekten sonra dolmuş olmalı'
    );
  });
});
