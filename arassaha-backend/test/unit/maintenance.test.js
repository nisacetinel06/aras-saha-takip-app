// Saf fonksiyon testi: Modül 12 (Kestirimci Bakım Planlama) risk_score ->
// urgency_level kural tablosu (bkz. routes/maintenance.js deriveUrgencyRule).
// HTTP/DB gerektirmez, yalnızca kural tabanlı iş mantığını test eder — bu
// route'taki tek "ML" olan Modül 9 (routes/risk.js) buraya karışmaz.
const { describe, it } = require('node:test');
const assert = require('node:assert');
const { deriveUrgencyRule } = require('../../routes/maintenance');

describe('deriveUrgencyRule (risk_score -> urgency_level)', () => {
  it('67 ve üzeri skorlar için "yuksek" aciliyet, 7 gün sonrasını önermeli', () => {
    assert.deepStrictEqual(deriveUrgencyRule(67), { minScore: 67, level: 'yuksek', daysAhead: 7 });
    assert.strictEqual(deriveUrgencyRule(100).level, 'yuksek');
  });

  it('34-66 arası skorlar için "orta" aciliyet, 30 gün sonrasını önermeli', () => {
    assert.deepStrictEqual(deriveUrgencyRule(34), { minScore: 34, level: 'orta', daysAhead: 30 });
    assert.strictEqual(deriveUrgencyRule(66).level, 'orta');
  });

  it("33 ve altı skorlar (düşük risk) için hiçbir öneri kuralı eşleşmemeli (null)", () => {
    assert.strictEqual(deriveUrgencyRule(33), null);
    assert.strictEqual(deriveUrgencyRule(0), null);
  });

  it('sınır değerlerde (66/67 ve 33/34) doğru tarafa düşmeli', () => {
    assert.strictEqual(deriveUrgencyRule(66).level, 'orta');
    assert.strictEqual(deriveUrgencyRule(67).level, 'yuksek');
    assert.strictEqual(deriveUrgencyRule(33), null);
    assert.strictEqual(deriveUrgencyRule(34).level, 'orta');
  });
});
