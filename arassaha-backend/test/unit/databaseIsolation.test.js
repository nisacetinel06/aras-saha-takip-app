// En kritik teknik gereksinim: testler ÇALIŞTIĞI SÜRECE gerçek aras_saha.db
// dosyasının değişme zamanı (mtime) DEĞİŞMEMELİ — bu, database.js'teki
// NODE_ENV=test -> ':memory:' koşulunun (bkz. database.js) gerçekten
// çalıştığının somut, dosya sistemi seviyesinde kanıtıdır.
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');

const PROD_DB_PATH = path.join(__dirname, '..', '..', 'aras_saha.db');

describe('Production veritabanı izolasyonu', () => {
  it('NODE_ENV=test ile çalıştırılmalı', () => {
    assert.strictEqual(process.env.NODE_ENV, 'test');
  });

  it("database.js require edildiğinde gerçek aras_saha.db dosyasına dokunulmamalı", () => {
    const existedBefore = fs.existsSync(PROD_DB_PATH);
    const mtimeBefore = existedBefore ? fs.statSync(PROD_DB_PATH).mtimeMs : null;

    // require cache'de zaten olsa da (diğer test dosyaları önce yüklemiş
    // olabilir) bu çağrı bir yan etki YARATMAMALI; asıl kanıt aşağıdaki
    // mtime karşılaştırması.
    const db = require('../../database');
    assert.ok(db, 'database modülü bir bağlantı nesnesi export etmeli');

    const existedAfter = fs.existsSync(PROD_DB_PATH);
    const mtimeAfter = existedAfter ? fs.statSync(PROD_DB_PATH).mtimeMs : null;

    assert.strictEqual(existedAfter, existedBefore, 'aras_saha.db dosyasının var olma durumu değişmemeli');
    assert.strictEqual(mtimeAfter, mtimeBefore, 'aras_saha.db dosyasının değişme zamanı (mtime) değişmemeli');
  });
});
