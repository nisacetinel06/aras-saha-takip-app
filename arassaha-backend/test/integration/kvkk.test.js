// KVKK Uyum Modülü — bkz. routes/kvkk.js. Bu dosya üç şeyi kanıtlar:
//   1) GET /my-data-summary'nin sayısal özeti gerçek DB durumunu yansıtıyor.
//   2) 'profil_fotografi_sil' ve 'tum_kisisel_verilerimi_sil' onay akışları
//      DOĞRU işlemi (silme vs anonimleştirme) DOĞRU kayıtlara uyguluyor —
//      operasyonel kayıtlar (isg_reports/work_orders) HİÇBİR ZAMAN silinmiyor,
//      yalnızca kişisel/görsel veri temizleniyor.
//   3) Anonimleştirme transaction'ı GERÇEKTEN atomik: routes/materials.js
//      TEST-07'deki AYNI teknikle (geçerli imzalı ama DB'de var olmayan bir
//      "hayalet" kullanıcı id'sine sahip token → gerçek bir FK ihlali),
//      transaction ortasında başarısız kılınıp, hiçbir yarım kalmış
//      değişikliğin kalıcı olmadığı kanıtlanır.
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const request = require('supertest');
const app = require('../../server');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');
const { getTestToken } = require('../helpers/authHelper');
const { generateValidToken } = require('../helpers/tokenHelper');

const PROFILE_UPLOADS_DIR = path.join(__dirname, '..', '..', 'uploads', 'profiles');
const ISG_UPLOADS_DIR = path.join(__dirname, '..', '..', 'uploads', 'isg');
const WORKORDER_UPLOADS_DIR = path.join(__dirname, '..', '..', 'uploads', 'workorders');

function writeDummyFile(dir, filename) {
  fs.mkdirSync(dir, { recursive: true });
  const fullPath = path.join(dir, filename);
  fs.writeFileSync(fullPath, 'kvkk-test-dosyasi');
  return fullPath;
}

function getUser(id) {
  return db.prepare('SELECT * FROM users WHERE id = ?').get(id);
}

function insertIsgReport({ reportedByUserId, photoPath }) {
  const now = new Date().toISOString();
  const info = db
    .prepare(
      `INSERT INTO isg_reports
         (reported_by_user_id, description, category, photo_path, location_name, lat, lng, status, created_at)
       VALUES (?, 'KVKK testi icin bildirim', 'diger', ?, 'Test Konum', 39.9, 41.2, 'bekliyor', ?)`
    )
    .run(reportedByUserId, photoPath, now);
  return info.lastInsertRowid;
}

function insertWorkOrderPhoto({ workOrderId, photoPath }) {
  const now = new Date().toISOString();
  const info = db
    .prepare('INSERT INTO work_order_photos (work_order_id, photo_path, created_at) VALUES (?, ?, ?)')
    .run(workOrderId, photoPath, now);
  return info.lastInsertRowid;
}

function createDeletionRequest(token, requestType, reason) {
  return request(app)
    .post('/api/kvkk/deletion-requests')
    .set('Authorization', `Bearer ${token}`)
    .send({ request_type: requestType, reason });
}

describe('GET /api/kvkk/aydinlatma-metni', () => {
  beforeEach(() => {
    resetTestDatabase();
    seedMinimalTestData();
  });

  it('taslak metni ve TASLAK uyarısını döner (hukuk birimi onayı notu korunmalı)', async () => {
    const token = getTestToken('teknisyen');
    const response = await request(app).get('/api/kvkk/aydinlatma-metni').set('Authorization', `Bearer ${token}`);

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.is_draft, true);
    assert.match(response.body.draft_warning, /TASLAK/);
    assert.match(response.body.content, /TASLAK/);
    assert.match(response.body.content, /HUKUK BİRİMİ ONAYI/);
  });
});

describe('GET /api/kvkk/my-data-summary', () => {
  let seeded;
  let teknisyenToken;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
    teknisyenToken = getTestToken('teknisyen');
  });

  it('sayısal özet gerçek DB durumunu yansıtır (İSG bildirimi + iş emri + fotoğraf sayıları)', async () => {
    const teknisyenId = seeded.users.teknisyenId;

    // Profil fotoğrafı ata.
    db.prepare('UPDATE users SET photo_path = ? WHERE id = ?').run('/uploads/profiles/dummy.jpg', teknisyenId);
    // 2 İSG bildirimi, biri fotoğraflı biri fotoğrafsız.
    insertIsgReport({ reportedByUserId: teknisyenId, photoPath: '/uploads/isg/a.jpg' });
    insertIsgReport({ reportedByUserId: teknisyenId, photoPath: null });
    // Zaten seedMinimalTestData ile 1 iş emri (ownWorkOrderId) atanmış; ona 1 fotoğraf ekle.
    insertWorkOrderPhoto({ workOrderId: seeded.workOrders.ownWorkOrderId, photoPath: '/uploads/workorders/a.jpg' });

    const response = await request(app)
      .get('/api/kvkk/my-data-summary')
      .set('Authorization', `Bearer ${teknisyenToken}`);

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.profile.sicil_no, '1001');
    assert.strictEqual(response.body.profile.has_photo, true);
    assert.strictEqual(response.body.submitted_isg_reports_count, 2);
    assert.strictEqual(response.body.assigned_work_orders_count, 1);
    // 1 profil fotoğrafı + 1 İSG fotoğrafı + 1 iş emri fotoğrafı = 3
    assert.strictEqual(response.body.uploaded_photos_count, 3);
  });
});

describe('POST /api/kvkk/deletion-requests', () => {
  beforeEach(() => {
    resetTestDatabase();
    seedMinimalTestData();
  });

  it('geçerli request_type: 201, beklemede durumunda oluşturulur, user_id istemciden DEĞİL token\'dan gelir', async () => {
    const token = getTestToken('teknisyen');
    const response = await createDeletionRequest(token, 'profil_fotografi_sil', 'test gerekçesi');

    assert.strictEqual(response.status, 201);
    assert.strictEqual(response.body.status, 'beklemede');
    assert.strictEqual(response.body.request_type, 'profil_fotografi_sil');
    assert.strictEqual(response.body.reason, 'test gerekçesi');
  });

  it('geçersiz request_type: 400', async () => {
    const token = getTestToken('teknisyen');
    const response = await createDeletionRequest(token, 'gecersiz_tip');
    assert.strictEqual(response.status, 400);
  });
});

describe('GET /api/kvkk/deletion-requests — RBAC', () => {
  beforeEach(() => {
    resetTestDatabase();
    seedMinimalTestData();
  });

  it('teknisyen erişemez (403)', async () => {
    const token = getTestToken('teknisyen');
    const response = await request(app).get('/api/kvkk/deletion-requests').set('Authorization', `Bearer ${token}`);
    assert.strictEqual(response.status, 403);
  });

  it('yönetici tüm talepleri, talep eden kullanıcı bilgisiyle birlikte görür', async () => {
    const teknisyenToken = getTestToken('teknisyen');
    await createDeletionRequest(teknisyenToken, 'profil_fotografi_sil');

    const managerToken = getTestToken('yonetici');
    const response = await request(app).get('/api/kvkk/deletion-requests').set('Authorization', `Bearer ${managerToken}`);

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.length, 1);
    assert.strictEqual(response.body[0].user.sicil_no, '1001');
  });
});

describe('PATCH /api/kvkk/deletion-requests/:id/approve — profil_fotografi_sil', () => {
  let seeded;
  let teknisyenId;
  let managerToken;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
    teknisyenId = seeded.users.teknisyenId;
    managerToken = getTestToken('yonetici');
  });

  it('dosya GERÇEKTEN diskten silinir, photo_path NULL olur, durum tamamlandi olur', async () => {
    const photoFile = writeDummyFile(PROFILE_UPLOADS_DIR, `kvkk-test-${Date.now()}.jpg`);
    const photoPath = `/uploads/profiles/${path.basename(photoFile)}`;
    db.prepare('UPDATE users SET photo_path = ? WHERE id = ?').run(photoPath, teknisyenId);
    assert.ok(fs.existsSync(photoFile), 'ön koşul: dosya diskte gerçekten var olmalı');

    const teknisyenToken = getTestToken('teknisyen');
    const createResponse = await createDeletionRequest(teknisyenToken, 'profil_fotografi_sil');
    const requestId = createResponse.body.id;

    const approveResponse = await request(app)
      .patch(`/api/kvkk/deletion-requests/${requestId}/approve`)
      .set('Authorization', `Bearer ${managerToken}`)
      .send({});

    assert.strictEqual(approveResponse.status, 200, JSON.stringify(approveResponse.body));
    assert.strictEqual(approveResponse.body.status, 'tamamlandi');
    assert.ok(approveResponse.body.completed_at, 'completed_at doldurulmalı');

    assert.strictEqual(getUser(teknisyenId).photo_path, null, 'photo_path DB\'de NULL olmalı');
    assert.ok(!fs.existsSync(photoFile), 'dosya diskten GERÇEKTEN silinmiş olmalı');

    // Hesap PASİFLEŞMEMELİ — bu yalnızca profil fotoğrafı silme talebi.
    assert.strictEqual(getUser(teknisyenId).is_active, 1);
  });

  it('zaten işlenmiş bir talep tekrar onaylanamaz (400)', async () => {
    const teknisyenToken = getTestToken('teknisyen');
    const createResponse = await createDeletionRequest(teknisyenToken, 'profil_fotografi_sil');
    const requestId = createResponse.body.id;

    await request(app)
      .patch(`/api/kvkk/deletion-requests/${requestId}/approve`)
      .set('Authorization', `Bearer ${managerToken}`)
      .send({});

    const secondApprove = await request(app)
      .patch(`/api/kvkk/deletion-requests/${requestId}/approve`)
      .set('Authorization', `Bearer ${managerToken}`)
      .send({});

    assert.strictEqual(secondApprove.status, 400);
  });
});

describe('PATCH /api/kvkk/deletion-requests/:id/approve — tum_kisisel_verilerimi_sil (kritik akış)', () => {
  let seeded;
  let teknisyenId;
  let managerToken;
  let teknisyenToken;
  let profilePhotoFile;
  let isgPhotoFile;
  let workOrderPhotoFile;
  let isgReportId;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
    teknisyenId = seeded.users.teknisyenId;
    managerToken = getTestToken('yonetici');
    teknisyenToken = getTestToken('teknisyen');

    profilePhotoFile = writeDummyFile(PROFILE_UPLOADS_DIR, `kvkk-profile-${Date.now()}.jpg`);
    isgPhotoFile = writeDummyFile(ISG_UPLOADS_DIR, `kvkk-isg-${Date.now()}.jpg`);
    workOrderPhotoFile = writeDummyFile(WORKORDER_UPLOADS_DIR, `kvkk-wo-${Date.now()}.jpg`);

    db.prepare('UPDATE users SET photo_path = ? WHERE id = ?').run(
      `/uploads/profiles/${path.basename(profilePhotoFile)}`,
      teknisyenId
    );
    isgReportId = insertIsgReport({
      reportedByUserId: teknisyenId,
      photoPath: `/uploads/isg/${path.basename(isgPhotoFile)}`,
    });
    insertWorkOrderPhoto({
      workOrderId: seeded.workOrders.ownWorkOrderId,
      photoPath: `/uploads/workorders/${path.basename(workOrderPhotoFile)}`,
    });
  });

  it('kullanıcı anonimleştirilir, TÜM fotoğraflar diskten silinir, AMA operasyonel kayıtlar (isg_reports/work_orders) KALIR', async () => {
    const beforeUser = getUser(teknisyenId);

    const createResponse = await createDeletionRequest(teknisyenToken, 'tum_kisisel_verilerimi_sil', 'artik calismiyorum');
    const requestId = createResponse.body.id;

    const approveResponse = await request(app)
      .patch(`/api/kvkk/deletion-requests/${requestId}/approve`)
      .set('Authorization', `Bearer ${managerToken}`)
      .send({});

    assert.strictEqual(approveResponse.status, 200, JSON.stringify(approveResponse.body));
    assert.strictEqual(approveResponse.body.status, 'tamamlandi');

    // 1) KİMLİK bilgileri GERÇEKTEN anonimleşti.
    const afterUser = getUser(teknisyenId);
    assert.strictEqual(afterUser.name, `Silinmiş Kullanıcı #${teknisyenId}`);
    assert.strictEqual(afterUser.phone, null);
    assert.strictEqual(afterUser.email, null);
    assert.strictEqual(afterUser.photo_path, null);
    assert.strictEqual(afterUser.is_active, 0, 'hesap artık kullanılamaz olmalı');
    assert.notStrictEqual(afterUser.name, beforeUser.name);
    // sicil_no BİLEREK dokunulmaz (bkz. routes/kvkk.js açıklaması).
    assert.strictEqual(afterUser.sicil_no, beforeUser.sicil_no);

    // 2) Dosyalar GERÇEKTEN diskten silindi.
    assert.ok(!fs.existsSync(profilePhotoFile));
    assert.ok(!fs.existsSync(isgPhotoFile));
    assert.ok(!fs.existsSync(workOrderPhotoFile));

    // 3) OPERASYONEL KAYITLAR SİLİNMEDİ — kayıt sayısı DEĞİŞMEDİ.
    const isgReport = db.prepare('SELECT * FROM isg_reports WHERE id = ?').get(isgReportId);
    assert.ok(isgReport, 'İSG bildirimi KAYDI hâlâ var olmalı (silinmemeli)');
    assert.strictEqual(isgReport.reported_by_user_id, teknisyenId, '"kim yaptı" FK\'si teknik olarak KALIR');
    assert.strictEqual(isgReport.photo_path, null, 'yalnızca fotoğraf temizlenir');
    assert.strictEqual(isgReport.description, 'KVKK testi icin bildirim', 'kaydın kendisi (ne olduğu) DEĞİŞMEZ');

    const workOrder = db.prepare('SELECT * FROM work_orders WHERE id = ?').get(seeded.workOrders.ownWorkOrderId);
    assert.ok(workOrder, 'İş emri KAYDI hâlâ var olmalı');
    assert.strictEqual(workOrder.assigned_user_id, teknisyenId);

    const workOrderPhoto = db
      .prepare('SELECT * FROM work_order_photos WHERE work_order_id = ?')
      .get(seeded.workOrders.ownWorkOrderId);
    assert.strictEqual(workOrderPhoto.photo_path, null);

    // 4) "Kim yaptı" artık ANONİM görünüyor — örnek: İSG bildirimini
    // (dispeçer/yönetici erişimiyle) sorgulayınca gerçek isim değil
    // "Silinmiş Kullanıcı #<id>" dönmeli (bkz. routes/isg.js mapIsgRow).
    const isgDetailResponse = await request(app)
      .get(`/api/isg-reports/${isgReportId}`)
      .set('Authorization', `Bearer ${managerToken}`);
    assert.strictEqual(isgDetailResponse.status, 200);
    assert.strictEqual(isgDetailResponse.body.reported_by.name, `Silinmiş Kullanıcı #${teknisyenId}`);

    const workOrderDetailResponse = await request(app)
      .get(`/api/workorders/${seeded.workOrders.ownWorkOrderId}`)
      .set('Authorization', `Bearer ${managerToken}`);
    assert.strictEqual(workOrderDetailResponse.status, 200);
    assert.strictEqual(workOrderDetailResponse.body.assigned_user.name, `Silinmiş Kullanıcı #${teknisyenId}`);
  });

  it('anonimleştirilen kullanıcı ARTIK GİRİŞ YAPAMAZ (is_active=0, login akışı 403 döner)', async () => {
    const createResponse = await createDeletionRequest(teknisyenToken, 'tum_kisisel_verilerimi_sil');
    await request(app)
      .patch(`/api/kvkk/deletion-requests/${createResponse.body.id}/approve`)
      .set('Authorization', `Bearer ${managerToken}`)
      .send({});

    // seedMinimalTestData'daki teknisyen: sicil_no 1001, şifre DEMO_PASSWORD ('sifre123').
    const loginResponse = await request(app)
      .post('/api/auth/login')
      .send({ sicil_no: '1001', password: 'sifre123' });

    assert.strictEqual(loginResponse.status, 403, 'pasifleştirilmiş (anonimleştirilmiş) hesap girişi reddedilmeli');
    assert.strictEqual(loginResponse.body.token, undefined);
  });

  it('bir yönetici KENDİ tum_kisisel_verilerimi_sil talebini onaylayamaz', async () => {
    const managerRow = db.prepare("SELECT id FROM users WHERE role = 'yonetici' LIMIT 1").get();
    const createResponse = await createDeletionRequest(managerToken, 'tum_kisisel_verilerimi_sil');

    const approveResponse = await request(app)
      .patch(`/api/kvkk/deletion-requests/${createResponse.body.id}/approve`)
      .set('Authorization', `Bearer ${managerToken}`)
      .send({});

    assert.strictEqual(approveResponse.status, 400);
    assert.strictEqual(getUser(managerRow.id).is_active, 1, 'yönetici kendi hesabını pasifleştirememiş olmalı');
  });

  describe('TRANSACTION ATOMİKLİĞİ — gerçek FK ihlali → gerçek ROLLBACK', () => {
    it('onaylayan "hayalet" (DB\'de var olmayan) bir yönetici id\'sine sahipse: transaction ORTASINDA başarısız olur, HİÇBİR değişiklik kalıcı OLMAZ', async () => {
      const createResponse = await createDeletionRequest(teknisyenToken, 'tum_kisisel_verilerimi_sil');
      const requestId = createResponse.body.id;

      const beforeUser = getUser(teknisyenId);
      const beforeIsgReport = db.prepare('SELECT * FROM isg_reports WHERE id = ?').get(isgReportId);
      const beforeRequest = db.prepare('SELECT * FROM data_deletion_requests WHERE id = ?').get(requestId);

      // routes/materials.js TEST-07'deki AYNI teknik: geçerli İMZALI ama
      // DB'de karşılığı OLMAYAN bir kullanıcı id'si. requireRole('yonetici')
      // yalnızca JWT payload'ındaki role alanına bakar (DB'ye gitmez) — bu
      // yüzden bu token approve route'una GERÇEKTEN ulaşır. Route'un SON
      // adımı (UPDATE data_deletion_requests SET reviewed_by_user_id = ...)
      // bu id ile GERÇEK bir FK ihlali (reviewed_by_user_id REFERENCES
      // users(id)) tetikler — ama bu ihlal, users/isg_reports/work_order_photos
      // güncellemeleri AYNI transaction içinde ZATEN yapıldıktan SONRA olur.
      const ghostManagerToken = generateValidToken({ id: 999999, role: 'yonetici' });

      const approveResponse = await request(app)
        .patch(`/api/kvkk/deletion-requests/${requestId}/approve`)
        .set('Authorization', `Bearer ${ghostManagerToken}`)
        .send({});

      // Kritik olan status kodu değil (uygulama seviyesinde bu FK önceden
      // kontrol edilmiyor, bu yüzden genel catch'e düşüp 500 döner) — kritik
      // olan sunucunun ÇÖKMEMESİ ve hiçbir yazının KALICI OLMAMASI.
      assert.strictEqual(approveResponse.status, 500);

      const afterUser = getUser(teknisyenId);
      assert.deepStrictEqual(
        afterUser,
        beforeUser,
        'ROLLBACK sonrası kullanıcı satırı BEGIN ÖNCESİ haliyle BİREBİR aynı olmalı (yarım anonimleştirme YOK)'
      );

      const afterIsgReport = db.prepare('SELECT * FROM isg_reports WHERE id = ?').get(isgReportId);
      assert.deepStrictEqual(
        afterIsgReport,
        beforeIsgReport,
        'İSG bildirimindeki photo_path GERİ ALINMALI (transaction içinde NULL yapılmıştı ama COMMIT olmadı)'
      );

      const afterRequest = db.prepare('SELECT * FROM data_deletion_requests WHERE id = ?').get(requestId);
      assert.deepStrictEqual(afterRequest, beforeRequest, 'talep hâlâ "beklemede" durumunda kalmalı');

      // Dosyalar da SİLİNMEMİŞ olmalı — kod dosya silmeyi ancak COMMIT
      // başarılı olduktan SONRA dener (bkz. routes/kvkk.js), COMMIT hiç
      // gerçekleşmediği için bu adıma ULAŞILMADI.
      assert.ok(fs.existsSync(profilePhotoFile), 'COMMIT başarısız olduğu için dosya silinmemiş olmalı');
      assert.ok(fs.existsSync(isgPhotoFile));
      assert.ok(fs.existsSync(workOrderPhotoFile));
    });
  });
});

describe('PATCH /api/kvkk/deletion-requests/:id/reject', () => {
  let managerToken;
  let teknisyenToken;

  beforeEach(() => {
    resetTestDatabase();
    seedMinimalTestData();
    managerToken = getTestToken('yonetici');
    teknisyenToken = getTestToken('teknisyen');
  });

  it('reviewer_note (gerekçe) olmadan reddetmeye izin VERMEZ (400)', async () => {
    const createResponse = await createDeletionRequest(teknisyenToken, 'profil_fotografi_sil');
    const response = await request(app)
      .patch(`/api/kvkk/deletion-requests/${createResponse.body.id}/reject`)
      .set('Authorization', `Bearer ${managerToken}`)
      .send({});

    assert.strictEqual(response.status, 400);

    const stillPending = db
      .prepare('SELECT status FROM data_deletion_requests WHERE id = ?')
      .get(createResponse.body.id);
    assert.strictEqual(stillPending.status, 'beklemede', 'gerekçesiz istek durumu DEĞİŞTİRMEMİŞ olmalı');
  });

  it('boş/yalnızca boşluk içeren reviewer_note de reddedilir (400)', async () => {
    const createResponse = await createDeletionRequest(teknisyenToken, 'profil_fotografi_sil');
    const response = await request(app)
      .patch(`/api/kvkk/deletion-requests/${createResponse.body.id}/reject`)
      .set('Authorization', `Bearer ${managerToken}`)
      .send({ reviewer_note: '   ' });

    assert.strictEqual(response.status, 400);
  });

  it('geçerli reviewer_note ile: 200, durum reddedildi olur, hiçbir kullanıcı verisi DEĞİŞMEZ', async () => {
    const createResponse = await createDeletionRequest(teknisyenToken, 'tum_kisisel_verilerimi_sil');
    const response = await request(app)
      .patch(`/api/kvkk/deletion-requests/${createResponse.body.id}/reject`)
      .set('Authorization', `Bearer ${managerToken}`)
      .send({ reviewer_note: 'Yasal saklama süresi dolmadığı için reddedildi' });

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.status, 'reddedildi');
    assert.strictEqual(response.body.reviewer_note, 'Yasal saklama süresi dolmadığı için reddedildi');

    const teknisyenRow = db.prepare("SELECT * FROM users WHERE sicil_no = '1001'").get();
    assert.strictEqual(teknisyenRow.is_active, 1, 'reddedilen talep kullanıcıya HİÇBİR ŞEY yapmamalı');
  });

  it('teknisyen reddedemez (403 — yalnızca yönetici)', async () => {
    const createResponse = await createDeletionRequest(teknisyenToken, 'profil_fotografi_sil');
    const response = await request(app)
      .patch(`/api/kvkk/deletion-requests/${createResponse.body.id}/reject`)
      .set('Authorization', `Bearer ${teknisyenToken}`)
      .send({ reviewer_note: 'denemek istedim' });

    assert.strictEqual(response.status, 403);
  });
});
