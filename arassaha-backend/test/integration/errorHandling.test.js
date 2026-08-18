// SEC-05: Express'in varsayılan hata işleyicisi (NODE_ENV production
// DEĞİLKEN) yakalanmamış bir hatanın TAM stack trace'ini, dosya yollarını
// HTML formatında client'a döndürür — ciddi bir bilgi ifşası riski.
//
// Bu dosya BİLEREK fix'ten (utils/asyncHandler.js + middleware/errorHandler.js
// + server.js'teki 404/error middleware zinciri) ÖNCE yazıldı: "[GÜVENLİK
// AÇIĞI KANITI]" testi ilk çalıştırmada KIRMIZI olmalı (stack trace/dosya
// yolu SIZDIRIYOR) — bu, açığın gerçekten var olduğunun kanıtı. Fix
// uygulandıktan SONRA aynı test YEŞİL olmalı (yalnızca genel bir mesaj döner).
//
// GET /api/__test-error yalnızca NODE_ENV === 'test' iken mount edilen,
// bilerek yakalanmamış bir hata fırlatan GEÇİCİ bir endpoint (bkz. server.js) —
// gerçek production'a hiç gitmez.
const { describe, it } = require('node:test');
const assert = require('node:assert');
const request = require('supertest');
const app = require('../../server');

describe('SEC-05 — merkezi hata yönetimi: stack trace client\'a SIZMAMALI', () => {
  it('[GÜVENLİK AÇIĞI KANITI] yakalanmamış bir hata sonrası response\'ta stack trace/dosya yolu OLMAMALI', async () => {
    const response = await request(app).get('/api/__test-error');

    // Bilinçli bir sunucu hatası olduğu için 500 bekleniyor (davranış
    // KORUNMALI, yalnızca gövdenin İÇERİĞİ değişmeli).
    assert.strictEqual(response.status, 500, JSON.stringify(response.body || response.text));

    const rawBody = response.text || '';

    // Express'in varsayılan hata sayfası bir stack trace satırı içerir
    // (örn. "    at Object.<anonymous> (C:\\...\\server.js:...)") — "at "
    // deseni bunun imzasıdır.
    assert.ok(
      !rawBody.includes(' at '),
      `response bir stack trace satırı içeriyor gibi görünüyor: ${rawBody.slice(0, 300)}`
    );
    // Dosya yolu sızıntısı — proje adı/dizin adı HİÇBİR ŞEKİLDE görünmemeli.
    assert.ok(
      !rawBody.includes('arassaha-backend'),
      `response bir dosya yolu içeriyor gibi görünüyor: ${rawBody.slice(0, 300)}`
    );
    // Express'in varsayılan hata sayfası HTML'dir (<pre>, <title>Error</title> vb.)
    // — client'a HER ZAMAN JSON dönmeli.
    assert.ok(
      !rawBody.trim().startsWith('<'),
      `response HTML formatında görünüyor (JSON bekleniyordu): ${rawBody.slice(0, 300)}`
    );

    // Response GERÇEKTEN JSON olmalı ve yalnızca genel, güvenli bir mesaj taşımalı.
    assert.strictEqual(response.body.error, 'Beklenmeyen bir sunucu hatası oluştu');
    // Hatanın kendi mesajı ("SEC-05 kasıtlı test hatası...") client'a SIZMAMALI.
    assert.ok(!rawBody.includes('SEC-05 kasıtlı test hatası'));
  });
});
