// TEST-10: harici bir JSON schema kütüphanesine ihtiyaç duymadan, bir
// response body'sinin beklenen anahtarlara/tiplere sahip olduğunu doğrulayan
// hafif yardımcı. expectedShape: { alan: 'string'|'number'|'boolean'|'object'|'array' }
const assert = require('node:assert');

function assertSchema(obj, expectedShape, label = '') {
  const prefix = label ? `${label}: ` : '';
  assert.ok(obj && typeof obj === 'object', `${prefix}response bir obje olmalı`);

  for (const [key, expectedType] of Object.entries(expectedShape)) {
    assert.ok(key in obj, `${prefix}${key} alanı response'ta eksik`);
    if (expectedType === 'array') {
      assert.ok(Array.isArray(obj[key]), `${prefix}${key} bir dizi olmalı, ${typeof obj[key]} geldi`);
    } else if (expectedType === 'object') {
      assert.ok(
        obj[key] !== null && typeof obj[key] === 'object' && !Array.isArray(obj[key]),
        `${prefix}${key} bir obje olmalı, ${typeof obj[key]} geldi`
      );
    } else {
      assert.strictEqual(typeof obj[key], expectedType, `${prefix}${key} tipi ${expectedType} olmalı, ${typeof obj[key]} geldi`);
    }
  }
}

// Bir dizideki HER elemanın aynı şekle sahip olduğunu doğrular (rapor
// endpoint'leri gibi dizi döndüren yanıtlar için).
function assertArraySchema(arr, expectedShape, label = '') {
  assert.ok(Array.isArray(arr), `${label}: response bir dizi olmalı`);
  arr.forEach((item, i) => assertSchema(item, expectedShape, `${label}[${i}]`));
}

module.exports = { assertSchema, assertArraySchema };
