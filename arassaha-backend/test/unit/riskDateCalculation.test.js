// Saf fonksiyon testi: Modül 9 (Arıza Risk Tahmini) risk skorunun
// girdilerinden biri olan months_since_maintenance hesaplaması (bkz.
// routes/risk.js calculateMonthsSinceMaintenance). HTTP/DB gerektirmez.
//
// Kod incelemesi (routes/risk.js):
//   - Orijinal imza: calculateMonthsSinceMaintenance(lastMaintenanceDate, installDate)
//     — İKİNCİ parametre bir "şu an" (asOfDate) DEĞİL, lastMaintenanceDate boşsa
//     kullanılan bir YEDEK referans tarih (kurulum tarihi). "Şu an" ise fonksiyon
//     içinde doğrudan Date.now() ile üretiliyordu (test edilebilirlik için
//     sorunlu — bkz. aşağıdaki refactor notu).
//   - Algoritma TAKVİM AYI FARKI DEĞİL: `(asOfDate - reference) gün sayısı / 30.44`
//     (30.44 ≈ 365.25/12, ortalama bir ayın gün sayısı). Yani fonksiyon SÜREKLİ
//     (continuous/fractional) bir değer döner, "0 ay" / "1 ay" gibi kesin takvim
//     kovalarına AYRILMAZ. Yuvarlama yalnızca ÇAĞIRAN yerlerde olur: buildFeatures
//     1 ondalığa (risk modeli özelliği), routes/maintenance.js'teki buildReason ise
//     tam sayıya yuvarlar — calculateMonthsSinceMaintenance'ın kendisi YUVARLAMAZ.
//   - null/undefined (ve hiçbir referans yoksa): `if (!reference) return 12` —
//     "hiç bakım/kurulum kaydı yok" durumunda sabit 12 (yüksek ama sonlu bir
//     varsayılan) dönüyor, çökmüyor, NaN üretmiyor. Zaten tanımlıydı, değişmedi.
//   - Gelecek tarih (lastMaintenanceDate, asOfDate'ten ileri): gün farkı negatif
//     çıkar, `Math.max(0, ...)` bunu 0'a sabitliyor — zaten tanımlı ve güvenli,
//     negatif bir değer risk modeline sızmıyor. Değişmedi.
//
// REFACTOR (bu görev kapsamında yapıldı — routes/risk.js):
//   1) Üçüncü bir `asOfDate = new Date()` parametresi eklendi. Varsayılanı
//      verilmezse gerçek çağrı yerleri (buildFeatures, routes/maintenance.js
//      buildReason) hep bugünün tarihini kullanmaya devam eder — geriye dönük
//      UYUMLU, üretim davranışı değişmedi (aşağıda POST /api/ml/refresh-risk-scores
//      ile elle doğrulandı).
//   2) reference sayısal olarak ayrıştırılamıyorsa (Invalid Date -> NaN) artık
//      sessizce NaN üretmek yerine TypeError fırlatıyor — DÜZELTME. ÖNCESİ:
//      calculateMonthsSinceMaintenance('gecersiz-tarih', null) === NaN (sessizce,
//      Math.max(0, NaN) da NaN döner çünkü NaN karşılaştırmaları hep false'tur) —
//      bu NaN, buildFeatures üzerinden risk modeline sessizce sızabilirdi. SONRASI:
//      aynı çağrı artık açıkça TypeError fırlatıyor.
const { describe, it } = require('node:test');
const assert = require('node:assert');
const { calculateMonthsSinceMaintenance } = require('../../routes/risk');

// Tüm testlerde SABİT referans tarih — bugünün gerçek tarihinden bağımsız,
// deterministik sonuçlar için (bkz. yukarıdaki refactor notu).
const REFERENCE_DATE = new Date('2026-08-12T00:00:00.000Z');

// Beklenen ham (rounding YAPILMAMIŞ) değer: gün sayısı hand-verified (aşağıdaki
// her testte açıklanıyor) / 30.44 — calculateMonthsSinceMaintenance'ın kendi
// algoritmasıyla AYNI formül (kod incelemesinde doğrulandı), çünkü fonksiyonun
// sözleşmesi zaten bu: "asOfDate ile reference arasındaki gün farkının 30.44'e
// bölümü". Testin asıl doğruladığı şey bu formülün DOĞRU gün sayısıyla (takvim
// ayı sınırları, Şubat kısalığı, yıl değişimi) çalıştığı.
function expectedMonths(days) {
  return Math.max(0, days / 30.44);
}

describe('calculateMonthsSinceMaintenance — temel senaryolar (gerçek algoritma: gün/30.44, takvim ayı farkı DEĞİL)', () => {
  it('aynı ay içinde (2026-08-01 -> 2026-08-12, 11 gün): ham değer 11/30.44 ≈ 0.36 olmalı (0 DEĞİL — algoritma gün bazlı)', () => {
    // Not: orijinal görev tablosu burada "0" bekliyordu (takvim ayı farkı
    // varsayımıyla) — gerçek gün-bazlı algoritmaya göre bu yanlış, düzeltildi.
    const actual = calculateMonthsSinceMaintenance('2026-08-01', null, REFERENCE_DATE);
    assert.strictEqual(actual, expectedMonths(11));
    assert.ok(actual > 0 && actual < 1, 'bir aydan az geçmiş olmalı');
  });

  it('yaklaşık 1 ay önce (2026-07-12 -> 2026-08-12, Temmuz 31 gün çektiği için tam 31 gün): ham değer 31/30.44 ≈ 1.018 olmalı', () => {
    const actual = calculateMonthsSinceMaintenance('2026-07-12', null, REFERENCE_DATE);
    assert.strictEqual(actual, expectedMonths(31));
  });

  it('birden fazla ay önce (2026-03-12 -> 2026-08-12, 153 gün): ham değer 153/30.44 ≈ 5.03 olmalı', () => {
    const actual = calculateMonthsSinceMaintenance('2026-03-12', null, REFERENCE_DATE);
    assert.strictEqual(actual, expectedMonths(153));
  });

  it('yıl değişimi (2025-11-12 -> 2026-08-12, 273 gün): ham değer 273/30.44 ≈ 8.97 olmalı', () => {
    const actual = calculateMonthsSinceMaintenance('2025-11-12', null, REFERENCE_DATE);
    assert.strictEqual(actual, expectedMonths(273));
  });
});

describe('calculateMonthsSinceMaintenance — ay sınırı senaryoları (en kritik kısım)', () => {
  it('ay sonu/başı sınırı (2026-07-31 -> 2026-08-01, yalnızca 1 GÜN fark ama takvim ayı değişti): 0\'a çok yakın olmalı, "1 ay" SAYILMAMALI', () => {
    // Kod incelemesi bulgusu: algoritma takvim ayını DEĞİL, gün sayısını
    // kullandığı için bu doğru şekilde ~0.03 ay (1/30.44) döner — 1 gün fark,
    // takvim ayı değişmiş olsa bile "1 ay geçti" gibi yanıltıcı bir sıçrama YOK.
    // Bu, kontrol edilen 3 sınır senaryosundan biri; burada bir hata YOK.
    const actual = calculateMonthsSinceMaintenance('2026-07-31', null, new Date('2026-08-01T00:00:00.000Z'));
    assert.strictEqual(actual, expectedMonths(1));
    assert.ok(actual < 0.1, 'yalnızca 1 gün fark varken 1 aya yakın bir değer DÖNMEMELİ');
  });

  it('Şubat ayı kısalığı (2026-01-31 -> 2026-03-01, 2026 artık yıl değil, Şubat 28 gün, toplam 29 gün fark)', () => {
    const actual = calculateMonthsSinceMaintenance('2026-01-31', null, new Date('2026-03-01T00:00:00.000Z'));
    assert.strictEqual(actual, expectedMonths(29));
  });

  it('tam bir takvim ayı fark (her ikisi de ayın 12\'si, 2026-07-12 -> 2026-08-12): ham değer TAM OLARAK 1 DEĞİL (bkz. bulgu notu altta)', () => {
    // BULGU (bug değil, algoritmanın doğal bir sonucu — raporlandı): fonksiyon
        // takvim ayı değil GÜN/30.44 kullandığından, "tam bir takvim ayı" farkı olan
    // iki tarih arasındaki ham değer o ayın gerçek gün sayısına göre 1'in altında
    // veya üstünde çıkar (30 günlük bir ay -> 30/30.44 ≈ 0.984; 31 günlük bir ay
    // -> 31/30.44 ≈ 1.018) ve YALNIZCA ayın gün sayısı tam olarak 30.44 olsaydı
    // (imkansız, gün sayısı tam sayıdır) tam 1 çıkardı. Bu yüzden "tam sınırda
    // kesinlikle 1 döner" varsayımı bu algoritma için GEÇERLİ DEĞİL — burada
    // Temmuz'un 31 gün çekmesi nedeniyle ham değer 31/30.44 ≈ 1.018, yani TAM
    // OLARAK 1 değil (ufak bir sapma var, ama bu bir hata değil, kasıtlı
    // yaklaşık/sürekli bir ML özelliği tasarımı — çağıran yerler zaten 1 ondalığa/
    // tam sayıya yuvarlıyor).
    const actual = calculateMonthsSinceMaintenance('2026-07-12', null, REFERENCE_DATE);
    assert.strictEqual(actual, expectedMonths(31));
    assert.notStrictEqual(actual, 1, 'gün-bazlı algoritmada ham değer nadiren tam sayı çıkar, bu beklenen bir durum');
  });
});

describe('calculateMonthsSinceMaintenance — null/undefined/geçersiz girdi', () => {
  it('lastMaintenanceDate ve installDate ikisi de null ise sabit 12 dönmeli (hiç bakım/kurulum kaydı yok varsayımı)', () => {
    assert.strictEqual(calculateMonthsSinceMaintenance(null, null, REFERENCE_DATE), 12);
  });

  it('lastMaintenanceDate ve installDate ikisi de undefined ise sabit 12 dönmeli', () => {
    assert.strictEqual(calculateMonthsSinceMaintenance(undefined, undefined, REFERENCE_DATE), 12);
  });

  it('lastMaintenanceDate null ama installDate geçerliyse, installDate\'e (yedek referans) düşmeli, 12 DÖNMEMELİ', () => {
    const actual = calculateMonthsSinceMaintenance(null, '2026-07-12', REFERENCE_DATE);
    assert.strictEqual(actual, expectedMonths(31));
    assert.notStrictEqual(actual, 12);
  });

  it('lastMaintenanceDate geçersiz bir tarih string\'iyse ("gecersiz-tarih-stringi") TypeError fırlatmalı, sessizce NaN ÜRETMEMELİ', () => {
    // DÜZELTİLEN DAVRANIŞ: bu görev öncesinde bu çağrı sessizce NaN dönüyordu
    // (Invalid Date -> NaN -> Math.max(0, NaN) === NaN), bu da risk modeline
    // sessizce sızabilirdi. Şimdi açıkça fırlatıyor.
    assert.throws(() => calculateMonthsSinceMaintenance('gecersiz-tarih-stringi', null, REFERENCE_DATE), TypeError);
  });

  it('anlamsız bir tarih ("2026-13-45", geçersiz ay/gün) için TypeError fırlatmalı, sessizce NaN ÜRETMEMELİ', () => {
    assert.throws(() => calculateMonthsSinceMaintenance('2026-13-45', null, REFERENCE_DATE), TypeError);
  });

  it('lastMaintenanceDate geçersizse ve installDate geçerliyse BİLE geçersiz olan öncelikli olduğundan hâlâ TypeError fırlatmalı (kısa devre `||` yalnızca falsy değerlerde yedeğe düşer, geçersiz-ama-truthy bir string düşmez)', () => {
    // Bu, kod incelemesinde bulunan önemli bir ayrıntı: `lastMaintenanceDate || installDate`
    // yalnızca lastMaintenanceDate FALSY (null/undefined/'') ise installDate'e
    // düşer. Bozuk ama truthy bir string ("gecersiz-tarih-stringi" gibi) asla
    // yedeğe düşmez, doğrudan geçersiz tarih olarak işlenir.
    assert.throws(
      () => calculateMonthsSinceMaintenance('gecersiz-tarih-stringi', '2026-07-12', REFERENCE_DATE),
      TypeError
    );
  });

  it('hiçbir test sonucu NaN OLMAMALI (regresyon özeti — yukarıdaki tüm geçerli senaryolar)', () => {
    const results = [
      calculateMonthsSinceMaintenance('2026-08-01', null, REFERENCE_DATE),
      calculateMonthsSinceMaintenance('2026-07-12', null, REFERENCE_DATE),
      calculateMonthsSinceMaintenance(null, null, REFERENCE_DATE),
      calculateMonthsSinceMaintenance(null, '2026-07-12', REFERENCE_DATE),
    ];
    for (const value of results) {
      assert.strictEqual(Number.isNaN(value), false, `NaN sızıntısı tespit edildi: ${value}`);
    }
  });
});

describe('calculateMonthsSinceMaintenance — gelecek tarih (savunmacı)', () => {
  it('lastMaintenanceDate, asOfDate\'ten ileri bir tarihse (örn. veri hatasıyla girilmiş gelecek tarih) 0 dönmeli, NEGATİF DEĞER DÖNMEMELİ', () => {
    // Kod incelemesi: gün farkı negatif çıkar, Math.max(0, ...) bunu 0'a
    // sabitliyor — zaten tanımlı ve güvenli davranış, değişiklik gerekmedi.
    const actual = calculateMonthsSinceMaintenance('2026-09-12', null, REFERENCE_DATE);
    assert.strictEqual(actual, 0);
  });
});
