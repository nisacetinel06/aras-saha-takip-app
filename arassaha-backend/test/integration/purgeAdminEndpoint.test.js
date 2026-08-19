// POST /api/admin/run-purge-job — bkz. routes/admin.js. RBAC, "güvenli
// varsayılan" davranışı (dryRun parametresi verilmezse/açıkça 'false'
// değilse dry-run kabul edilir) VE `?dryRun=false`'un route üzerinden
// GERÇEKTEN silme tetiklediği doğrulanır.
//
// GÜVENLİK NOTU: GERÇEK silmeyi UÇTAN UCA (HTTP route üzerinden) test etmek
// için route'un GERÇEK/paylaşılan `uploads/` klasörüne dokunmasına ASLA
// izin verilmez — bkz. routes/admin.js'teki `PURGE_TEST_UPLOADS_ROOT` test
// izolasyon kapısı (yalnızca NODE_ENV==='test' iken VE bu ortam değişkeni
// açıkça ayarlanmışsa devreye girer; hiçbir API isteğiyle kontrol edilemez,
// production'a asla sızamaz — server.js'teki '/api/__test-error' ile AYNI
// ilke). Bu sayede `?dryRun=false` burada TAMAMEN İZOLE bir geçici dizinde
// gerçek bir silme ile kanıtlanabiliyor.
const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const request = require('supertest');
const app = require('../../server');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');
const { getTestToken } = require('../helpers/authHelper');
const { GRACE_PERIOD_HOURS } = require('../../jobs/orphanFilePurge');
const {
  makeScratchUploadsRoot,
  cleanupScratchUploadsRoot,
  writeFileWithAge,
} = require('../helpers/purgeTestUtils');

describe('POST /api/admin/run-purge-job', () => {
  beforeEach(() => {
    resetTestDatabase();
    seedMinimalTestData();
  });

  afterEach(() => {
    delete process.env.PURGE_TEST_UPLOADS_ROOT;
  });

  it('teknisyen erişemez (403 — yalnızca yönetici)', async () => {
    const token = getTestToken('teknisyen');
    const response = await request(app)
      .post('/api/admin/run-purge-job')
      .set('Authorization', `Bearer ${token}`);
    assert.strictEqual(response.status, 403);
  });

  it('dispeçer erişemez (403)', async () => {
    const token = getTestToken('dispecer');
    const response = await request(app)
      .post('/api/admin/run-purge-job')
      .set('Authorization', `Bearer ${token}`);
    assert.strictEqual(response.status, 403);
  });

  it('GÜVENLİ VARSAYILAN: dryRun hiç verilmezse dry_run=true olarak çalışır', async () => {
    const token = getTestToken('yonetici');
    const response = await request(app)
      .post('/api/admin/run-purge-job')
      .set('Authorization', `Bearer ${token}`);

    assert.strictEqual(response.status, 200, JSON.stringify(response.body));
    assert.strictEqual(response.body.dry_run, true);
    assert.strictEqual(typeof response.body.orphan_files.count, 'number');
    assert.ok(Array.isArray(response.body.orphan_files.items));
    assert.strictEqual(typeof response.body.expired_files.count, 'number');
    assert.ok(Array.isArray(response.body.expired_files.items));
  });

  it('?dryRun=true açıkça verilirse de dry-run kalır', async () => {
    const token = getTestToken('yonetici');
    const response = await request(app)
      .post('/api/admin/run-purge-job?dryRun=true')
      .set('Authorization', `Bearer ${token}`);
    assert.strictEqual(response.body.dry_run, true);
  });

  it('GÜVENLİ VARSAYILAN: "false" DIŞINDA herhangi bir/yazım hatalı bir değer (örn. "0", "no") dry-run kabul edilir', async () => {
    const token = getTestToken('yonetici');
    const response = await request(app)
      .post('/api/admin/run-purge-job?dryRun=0')
      .set('Authorization', `Bearer ${token}`);
    assert.strictEqual(response.body.dry_run, true, '"false" dizesi DIŞINDAKİ her değer güvenli tarafta (dry-run) kalmalı');
  });

  it('yalnızca AÇIKÇA ?dryRun=false verilirse dry_run=false döner VE GERÇEKTEN siler (izole test dizininde)', async () => {
    const scratchRoot = makeScratchUploadsRoot();
    try {
      const filename = 'admin-endpoint-orphan.jpg';
      const fullPath = writeFileWithAge(scratchRoot, 'isg', filename, GRACE_PERIOD_HOURS + 10);
      process.env.PURGE_TEST_UPLOADS_ROOT = scratchRoot;

      const token = getTestToken('yonetici');
      const response = await request(app)
        .post('/api/admin/run-purge-job?dryRun=false')
        .set('Authorization', `Bearer ${token}`);

      assert.strictEqual(response.status, 200, JSON.stringify(response.body));
      assert.strictEqual(response.body.dry_run, false);
      assert.strictEqual(response.body.orphan_files.count, 1);
      assert.strictEqual(response.body.orphan_files.items[0].filename, filename);
      assert.ok(!fs.existsSync(fullPath), 'route üzerinden tetiklenen dryRun=false, izole dizindeki orphan dosyayı GERÇEKTEN silmeli');
    } finally {
      cleanupScratchUploadsRoot(scratchRoot);
    }
  });
});
