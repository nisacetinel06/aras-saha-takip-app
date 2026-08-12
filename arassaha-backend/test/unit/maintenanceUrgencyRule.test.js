// Saf fonksiyon testi: Modül 12 (Kestirimci Bakım Planlama) risk_score ->
// urgency_level kural tablosu (bkz. routes/maintenance.js deriveUrgencyRule).
// HTTP/DB gerektirmez. Odak: sınır (boundary) değerler — bu kuralın ileride
// yanlışlıkla değiştirilip fark edilmeden bozulmasını (regresyon) engellemek.
//
// Kod incelemesi (routes/maintenance.js):
//   - İmza: deriveUrgencyRule(riskScore: number) -> { minScore, level, daysAhead } | null
//     (yalnızca string bir seviye DEĞİL, tüm kural objesini döner — recommended_date
//     çağıran yerde addDaysIso(rule.daysAhead) ile ayrıca hesaplanıyor, bkz. satır ~163.)
//   - Eşikler URGENCY_RULES = [{minScore:67,level:'yuksek'}, {minScore:34,level:'orta'}]
//     üzerinden .find(rule => riskScore >= rule.minScore) ile aranıyor — yani KESİN
//     olarak >= (dahil/inclusive), > değil. 67 -> yuksek, 34 -> orta, 33 -> null.
//   - Fonksiyonun döndürebileceği yalnızca 2 dolu seviye var: 'yuksek' ve 'orta'.
//     'dusuk' diye bir dönüş DEĞERİ YOK — score < 34 için kural hiç eşleşmiyor ve
//     fonksiyon null dönüyor (VALID_URGENCY_LEVELS listesinde 'dusuk' geçse de bu,
//     yalnızca /recommendations?urgency= sorgu doğrulaması için var, deriveUrgencyRule
//     hiçbir zaman 'dusuk' string'i üretmiyor).
//   - DÜZELTME (bu görev kapsamında yapıldı): riskScore sayısal değilse (null,
//     undefined, string, NaN) önceki kod sessizce `undefined >= 67` gibi hep-false
//     karşılaştırmalara düşüp null dönüyordu — yani geçersiz bir girdi, gerçek
//     "düşük risk" durumuyla AYIRT EDİLEMEZ haldeydi. routes/maintenance.js'e
//     `typeof riskScore !== 'number' || !Number.isFinite(riskScore)` kontrolü
//     eklenip bu durumda TypeError fırlatılacak şekilde güncellendi. Bu, gerçek
//     /refresh-recommendations akışını ETKİLEMEZ çünkü equipment_risk_scores.risk_score
//     DB'de INTEGER NOT NULL (bkz. database.js) — yani bu satır zaten hiçbir zaman
//     geçersiz bir değerle çağrılmıyor, yalnızca fonksiyon doğrudan/gelecekte başka
//     bir yerden çağrılırsa devreye giren bir savunma hattı.
const { describe, it } = require('node:test');
const assert = require('node:assert');
const { deriveUrgencyRule } = require('../../routes/maintenance');

describe('deriveUrgencyRule — sınır (boundary) değerler', () => {
  it('risk_score=100 için yuksek dönmeli (üst sınır, maksimum olası değer)', () => {
    assert.strictEqual(deriveUrgencyRule(100).level, 'yuksek');
  });

  it('risk_score=68 için yuksek dönmeli (67\'nin hemen üzeri)', () => {
    assert.strictEqual(deriveUrgencyRule(68).level, 'yuksek');
  });

  it('risk_score=67 için yuksek dönmeli (alt sınır — tam eşik değeri, >= dahil)', () => {
    assert.deepStrictEqual(deriveUrgencyRule(67), { minScore: 67, level: 'yuksek', daysAhead: 7 });
  });

  it('risk_score=66 için orta dönmeli (67\'nin hemen altı — kritik sınır testi)', () => {
    assert.strictEqual(deriveUrgencyRule(66).level, 'orta');
  });

  it('risk_score=50 için orta dönmeli (orta aralığın ortası)', () => {
    assert.strictEqual(deriveUrgencyRule(50).level, 'orta');
  });

  it('risk_score=34 için orta dönmeli (alt sınır — tam eşik değeri, >= dahil)', () => {
    assert.deepStrictEqual(deriveUrgencyRule(34), { minScore: 34, level: 'orta', daysAhead: 30 });
  });

  it('risk_score=33 için null dönmeli (34\'ün hemen altı — kritik sınır testi, öneri üretilmez)', () => {
    assert.strictEqual(deriveUrgencyRule(33), null);
  });

  it('risk_score=0 için null dönmeli (alt sınır, minimum olası değer, öneri üretilmez)', () => {
    assert.strictEqual(deriveUrgencyRule(0), null);
  });
});

describe('deriveUrgencyRule — her aciliyet sonucunun kapsanması', () => {
  // Fonksiyonun üretebileceği tüm sonuçlar: 'yuksek', 'orta', null. ('dusuk' bir
  // dönüş değeri değil — yukarıdaki kod incelemesi notuna bkz.)
  it('yuksek seviyesi en az bir sınır testinde kapsanıyor (bkz. risk_score=67/68/100)', () => {
    assert.strictEqual(deriveUrgencyRule(67).level, 'yuksek');
  });

  it('orta seviyesi en az bir sınır testinde kapsanıyor (bkz. risk_score=34/50/66)', () => {
    assert.strictEqual(deriveUrgencyRule(34).level, 'orta');
  });

  it('null (öneri yok / düşük risk) sonucu en az bir sınır testinde kapsanıyor (bkz. risk_score=0/33)', () => {
    assert.strictEqual(deriveUrgencyRule(33), null);
  });
});

describe('deriveUrgencyRule — ondalıklı girdi (karşılaştırmanın tam sayıya değil, sayısal değere göre yapıldığını doğrular)', () => {
  // Not: equipment_risk_scores.risk_score DB'de INTEGER NOT NULL (bkz. database.js,
  // Modül 9'da 0-100 arası tam sayı üretiliyor) — yani gerçek akışta risk_score HİÇBİR
  // ZAMAN ondalıklı gelmez. Yine de kod incelemesi `riskScore >= rule.minScore` şeklinde
  // düz bir sayısal karşılaştırma (yuvarlama/floor YOK) olduğunu gösterdiği için, bu
  // durumu netleştirmek adına birkaç ondalıklı değer test ediliyor.
  it('risk_score=66.9 için orta dönmeli (67 eşiğinin altında kalıyor)', () => {
    assert.strictEqual(deriveUrgencyRule(66.9).level, 'orta');
  });

  it('risk_score=67.1 için yuksek dönmeli (67 eşiğini geçiyor)', () => {
    assert.strictEqual(deriveUrgencyRule(67.1).level, 'yuksek');
  });

  it('risk_score=33.9 için null dönmeli (34 eşiğinin altında kalıyor)', () => {
    assert.strictEqual(deriveUrgencyRule(33.9), null);
  });
});

describe('deriveUrgencyRule — geçersiz/beklenmeyen girdi', () => {
  it('null için TypeError fırlatmalı (sayısal değil — sessizce "düşük risk" ile karışmamalı)', () => {
    assert.throws(() => deriveUrgencyRule(null), TypeError);
  });

  it('undefined için TypeError fırlatmalı', () => {
    assert.throws(() => deriveUrgencyRule(undefined), TypeError);
  });

  it('string bir değer ("yüksek risk") için TypeError fırlatmalı', () => {
    assert.throws(() => deriveUrgencyRule('yüksek risk'), TypeError);
  });

  it('NaN için TypeError fırlatmalı', () => {
    assert.throws(() => deriveUrgencyRule(NaN), TypeError);
  });

  it('negatif bir sayı (-5) İÇİN HATA FIRLATMAMALI — geçerli bir sayı olduğundan null (düşük risk) dönmeli', () => {
    // -5, tip olarak geçerli bir number; yalnızca sayısal OLMAYAN girdiler (null,
    // undefined, string, NaN) TypeError fırlatıyor. -5, 34 eşiğinin altında kaldığı
    // için diğer düşük risk değerleriyle (0, 33) TUTARLI şekilde null dönüyor.
    assert.strictEqual(deriveUrgencyRule(-5), null);
  });

  it('100\'den büyük bir sayı (150) için hâlâ yuksek dönmeli (üst sınırın üstü, kasıtlı davranış)', () => {
    // Üst eşik ÜST SINIRSIZ: `riskScore >= 67` kontrolü 150 için de doğru, kod
    // ayrıca bir üst limit (<=100) kontrolü yapmıyor. Bu kasıtlı — risk_score'un
    // teorik üst sınırı 100 olsa da (Modül 9), kuralın kendisi "67 ve üzeri" diye
    // tanımlı, 100'ü aşan bir değer gelse bile en acil kategoriye düşmesi doğru.
    assert.strictEqual(deriveUrgencyRule(150).level, 'yuksek');
  });
});
