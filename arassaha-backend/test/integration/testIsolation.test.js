// beforeEach + resetTestDatabase()'in GERÇEKTEN temizlediğini kanıtlar: aynı
// dosya/aynı process içinde art arda çalışan iki ayrı it() bloğu arasında
// veri sızıntısı olmamalı. Test A bir kullanıcı ekler; Test B (kendi
// beforeEach'i az önce çalışmış, taze bir durumda) o kullanıcının ARTIK
// orada olmadığını doğrular.
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');

describe('Testler arası izolasyon (aynı process, aynı :memory: DB)', () => {
  beforeEach(() => {
    resetTestDatabase();
  });

  it('Test A: bir kullanıcı oluşturur ("Sızıntı Testi Kullanıcısı")', () => {
    db.prepare("INSERT INTO users (name, role, sicil_no, password_hash) VALUES (?, 'teknisyen', ?, NULL)").run(
      'Sızıntı Testi Kullanıcısı',
      'ISO-LEAK-0001'
    );

    const found = db.prepare('SELECT * FROM users WHERE sicil_no = ?').get('ISO-LEAK-0001');
    assert.ok(found, 'Test A kendi eklediği kaydı görebilmeli');
  });

  it("Test B: Test A'nın eklediği kullanıcı burada ARTIK yok (beforeEach temizledi)", () => {
    const found = db.prepare('SELECT * FROM users WHERE sicil_no = ?').get('ISO-LEAK-0001');
    assert.strictEqual(found, undefined, "Test A'daki kayıt Test B'ye sızmamalı — resetTestDatabase() çalıştı");

    const countBefore = db.prepare('SELECT COUNT(*) AS c FROM users').get().c;
    assert.strictEqual(countBefore, 0, 'beforeEach sonrası users tablosu tamamen boş olmalı');
  });

  it('seedMinimalTestData() her beforeEach sonrası taze veri üretir (öncekiyle çakışmaz)', () => {
    const first = seedMinimalTestData();
    resetTestDatabase();
    const second = seedMinimalTestData();

    // sicil_no'lar (1001/2001/3001...) SABİT kalır (seed.js ile tutarlılık
    // kasıtlı) ama id'ler her seferinde SIFIRDAN başlar — reset gerçekten
    // sqlite_sequence'i de temizlediği için.
    assert.strictEqual(first.users.teknisyenId, second.users.teknisyenId);
    const totalUsers = db.prepare('SELECT COUNT(*) AS c FROM users').get().c;
    assert.strictEqual(totalUsers, 4, 'ikinci seed, birinciyle ÇAKIŞMADAN (UNIQUE sicil_no hatası almadan) çalışmalı');
  });
});
