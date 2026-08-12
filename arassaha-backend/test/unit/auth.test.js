// Saf fonksiyon testi: şifre hash/doğrulama (bcrypt). HTTP/DB gerektirmez —
// routes/auth.js'in login akışında kullandığı bcrypt.compareSync ile AYNI
// mantığı doğrudan test eder.
const { describe, it } = require('node:test');
const assert = require('node:assert');
const bcrypt = require('bcrypt');

describe('Şifre hash/doğrulama (bcrypt)', () => {
  it('doğru şifreyle karşılaştırıldığında eşleşmeli', () => {
    const hash = bcrypt.hashSync('sifre123', 10);
    assert.strictEqual(bcrypt.compareSync('sifre123', hash), true);
  });

  it('yanlış şifreyle karşılaştırıldığında eşleşmemeli', () => {
    const hash = bcrypt.hashSync('sifre123', 10);
    assert.strictEqual(bcrypt.compareSync('yanlisSifre', hash), false);
  });

  it('aynı şifre için her seferinde farklı bir hash üretmeli (salt)', () => {
    const hash1 = bcrypt.hashSync('sifre123', 10);
    const hash2 = bcrypt.hashSync('sifre123', 10);
    assert.notStrictEqual(hash1, hash2);
    assert.strictEqual(bcrypt.compareSync('sifre123', hash1), true);
    assert.strictEqual(bcrypt.compareSync('sifre123', hash2), true);
  });
});
