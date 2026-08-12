// Bu testler GERÇEK SQLite kısıtlama motorunu doğrular, mock kullanılmamıştır.
// database.js, NODE_ENV=test iken node:sqlite'ın DatabaseSync(':memory:')
// bağlantısını kullanır (bkz. database.js resolveDbPath) — burada FOREIGN KEY
// ve UNIQUE ihlallerinin gerçekten SQLite motoru tarafından reddedildiği,
// uygulama kodunun (route handler'ların) hiç araya girmediği doğrudan
// db.prepare(...).run(...) çağrılarıyla kanıtlanır. Bir mock/sahte veritabanı
// bu tür motor-seviyesi davranışları asla gerçekçi biçimde taklit edemez.
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');

describe('SQLite kısıtlama motoru (mock DEĞİL, gerçek node:sqlite)', () => {
  beforeEach(() => {
    resetTestDatabase();
  });

  it('var olmayan bir equipment_id ile work_orders kaydı eklemek FOREIGN KEY hatası fırlatmalı', () => {
    seedMinimalTestData();
    const now = new Date().toISOString();
    const NONEXISTENT_EQUIPMENT_ID = 987654321;

    assert.throws(
      () => {
        db.prepare(
          `INSERT INTO work_orders
             (title, description, status, priority, il, ilce, mahalle, location_name, lat, lng, assigned_user_id, equipment_id, created_at, updated_at)
           VALUES
             ('FK ihlali testi', '', 'acik', 'normal', 'Erzurum', 'Yakutiye', 'Merkez Mah.', 'Erzurum / Yakutiye / Merkez Mah.', 39.9, 41.2, NULL, ?, ?, ?)`
        ).run(NONEXISTENT_EQUIPMENT_ID, now, now);
      },
      (err) => {
        assert.match(err.message, /FOREIGN KEY constraint failed/);
        return true;
      }
    );
  });

  it("bir UNIQUE kısıtlamayı (users.sicil_no) ihlal eden ekleme hata vermeli", () => {
    const insertUser = db.prepare(
      "INSERT INTO users (name, role, sicil_no, password_hash) VALUES (?, 'teknisyen', ?, NULL)"
    );
    insertUser.run('Birinci Kullanıcı', 'DUP-0001');

    assert.throws(
      () => {
        insertUser.run('İkinci Kullanıcı (aynı sicil_no)', 'DUP-0001');
      },
      (err) => {
        assert.match(err.message, /UNIQUE constraint failed/);
        return true;
      }
    );
  });
});
