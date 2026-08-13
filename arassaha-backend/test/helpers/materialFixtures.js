// TEST-07: routes/materials.js'teki stok düşürme transaction'ı için sabit/
// bilinen bir test malzemesi seed eden yardımcı. seedMinimalTestData()
// (bkz. testDb.js) zaten bir iş emri + teknisyen seed ediyor, o yüzden burada
// yalnızca malzeme tarafı eklenir — iş emri/kullanıcı fixture'ı TEKRAR
// icat edilmez.
require('../setup');
const db = require('../../database');

const DEFAULT_MATERIAL = {
  name: 'Test Sigorta',
  category: 'sigorta',
  unit: 'adet',
  stock_quantity: 20,
  min_stock_threshold: 5,
  compatible_equipment_types: 'trafo',
  unit_cost: null,
};

// seedTestMaterial({ stock_quantity: 20, name: '...' , ... }) — verilmeyen
// alanlar DEFAULT_MATERIAL'dan gelir. materials.id döner.
function seedTestMaterial(overrides = {}) {
  const material = { ...DEFAULT_MATERIAL, ...overrides };

  const info = db
    .prepare(
      `INSERT INTO materials
         (name, category, unit, stock_quantity, min_stock_threshold, compatible_equipment_types, unit_cost, created_at)
       VALUES (@name, @category, @unit, @stock_quantity, @min_stock_threshold, @compatible_equipment_types, @unit_cost, @created_at)`
    )
    .run({ ...material, created_at: new Date().toISOString() });

  return info.lastInsertRowid;
}

module.exports = { seedTestMaterial, DEFAULT_MATERIAL };
