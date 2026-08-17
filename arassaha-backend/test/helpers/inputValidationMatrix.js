// TEST-09: dört yazma route'u (workOrders/isg/materials/users) arasında
// tekrar eden "kötü girdi" testlerini azaltan ortak yardımcı. Her alan için
// sistematik olarak geçersiz varyasyonlar üretir, hepsinin bir 4xx (400-499)
// ile reddedildiğini (ASLA 500 ile değil) doğrular.
//
// İKİ MOD:
//  - JSON (varsayılan): `.send(payload)` ile application/json gövde gönderir.
//    Bu modda "yanlış tip" testi bir string alana SAYI (12345), bir sayı
//    alana STRING ('bu-bir-string') gönderir.
//  - multipart (`multipart: true`): İSG bildirimi gibi multipart/form-data
//    endpoint'ler için `.field()` kullanır. ÖNEMLİ FARK: multipart form
//    alanları HER ZAMAN string olarak gelir (busboy/multer) — bu yüzden bir
//    string alana "sayı" göndermenin gerçekçi bir karşılığı YOKTUR. Bunun
//    yerine gerçekçi risk AYNI ALAN ADI İKİ KEZ gönderilmesidir (busboy bunu
//    bir DİZİYE çevirir, `req.body.alan` bir string değil bir array olur) —
//    bu, "wrongType" testinin multipart karşılığı olarak kullanılır. "null"
//    senaryosu multipart'ta anlamsız olduğu için (form alanları hiçbir zaman
//    gerçek `null` taşıyamaz) ATLANIR.
const assert = require('node:assert');
const request = require('supertest');

function buildRequest(app, method, path, authToken) {
  const req = request(app)[method](path);
  return authToken ? req.set('Authorization', `Bearer ${authToken}`) : req;
}

async function sendJson(app, method, path, authToken, payload) {
  return buildRequest(app, method, path, authToken).send(payload);
}

async function sendMultipart(app, method, path, authToken, payload, fileAttachment, duplicateFieldName) {
  let req = buildRequest(app, method, path, authToken);
  for (const [key, value] of Object.entries(payload)) {
    if (value === undefined) continue; // alan hiç gönderilmemiş (eksik senaryosu)
    const stringValue = value === null ? '' : String(value);
    if (key === duplicateFieldName) {
      // Aynı alanı iki kez göndermek busboy'da bir DİZİ üretir — multipart'ta
      // "yanlış tip" riskinin gerçekçi karşılığı.
      req = req.field(key, stringValue).field(key, stringValue);
    } else {
      req = req.field(key, stringValue);
    }
  }
  if (fileAttachment) {
    req = req.attach(fileAttachment.field, fileAttachment.buffer, {
      filename: fileAttachment.filename,
      contentType: fileAttachment.contentType,
    });
  }
  return req;
}

async function runScenario({ app, method, path, authToken, payload, multipart, fileAttachment, duplicateFieldName, scenarioLabel }) {
  const response = multipart
    ? await sendMultipart(app, method, path, authToken, payload, fileAttachment, duplicateFieldName)
    : await sendJson(app, method, path, authToken, payload);

  return {
    scenarioLabel,
    status: response.status,
    body: response.body,
    pass: response.status >= 400 && response.status < 500,
  };
}

/**
 * @param {object} config
 * @param {object} config.app - supertest ile kullanılacak Express app.
 * @param {string} config.method - 'post' | 'patch'
 * @param {string} config.path
 * @param {string} config.authToken
 * @param {object} config.validPayload - geçerli, tam bir istek gövdesi (baz alınacak).
 * @param {object[]} config.fields - [{ name, type: 'string'|'number'|'enum', required, enumValues, maxLength, rejectsZero }]
 * @param {boolean} [config.multipart] - true ise multipart/form-data olarak gönderir.
 * @param {object} [config.fileAttachment] - multipart ise { field, buffer, filename, contentType }.
 */
async function runInputValidationMatrix({ app, method, path, authToken, validPayload, fields, multipart = false, fileAttachment }) {
  const results = [];

  for (const field of fields) {
    const base = { ...validPayload };

    // 1. Eksik zorunlu alan.
    if (field.required) {
      const payload = { ...base };
      delete payload[field.name];
      results.push(
        await runScenario({ app, method, path, authToken, payload, multipart, fileAttachment, scenarioLabel: `${field.name} eksik` })
      );
    }

    // 2. Null (yalnızca JSON modunda anlamlı — bkz. dosya başı not).
    // field.skipNull: bazı opsiyonel alanlar `?? varsayılan` deseniyle null'ı
    // GÜVENLİ bir varsayılana düşürür (örn. `Number(min_stock_threshold ?? 0)`)
    // — bu durumda null GERÇEKTEN kabul edilir (reddedilmez), matrisin "her
    // zaman reddedilir" varsayımı bu alan için geçerli değildir.
    if (!multipart && !field.skipNull) {
      results.push(
        await runScenario({
          app, method, path, authToken,
          payload: { ...base, [field.name]: null },
          multipart, fileAttachment,
          scenarioLabel: `${field.name} null`,
        })
      );
    }

    // 3. Empty string (yalnızca string/enum alanlar için).
    if (field.type === 'string' || field.type === 'enum') {
      results.push(
        await runScenario({
          app, method, path, authToken,
          payload: { ...base, [field.name]: '' },
          multipart, fileAttachment,
          scenarioLabel: `${field.name} boş string`,
        })
      );
    }

    // 4. Yanlış veri tipi.
    // field.skipWrongType: bazı "string" alanlar bilinçli olarak String()
    // ile sarmalanır (örn. sicil_no) — sayısal bir değer göndermek GEÇERLİ
    // bir senaryodur (coerce edilir, reddedilmez), bu yüzden bu testin
    // "reddedilmeli" varsayımı bu alanlar için geçerli değildir.
    if (field.skipWrongType) {
      // atla
    } else if (multipart && (field.type === 'string' || field.type === 'enum')) {
      // Multipart'ta "sayı gönder" gerçekçi değil — bunun yerine aynı alanı
      // iki kez göndererek bir DİZİ üretiyoruz (bkz. dosya başı not).
      results.push(
        await runScenario({
          app, method, path, authToken,
          payload: base,
          multipart, fileAttachment,
          duplicateFieldName: field.name,
          scenarioLabel: `${field.name} yanlış tip (dizi — alan iki kez gönderildi)`,
        })
      );
    } else {
      const wrongTypeValue = field.type === 'number' ? 'bu-bir-string' : 12345;
      results.push(
        await runScenario({
          app, method, path, authToken,
          payload: { ...base, [field.name]: wrongTypeValue },
          multipart, fileAttachment,
          scenarioLabel: `${field.name} yanlış tip`,
        })
      );
    }

    // 5. Sayısal alanlar için negatif/sıfır.
    // field.skipNegative: lat/lng gibi coğrafi koordinatlarda negatif değer
    // GEÇERLİDİR (güney yarımküre/batı meridyeni) — bu alanlar için negatif
    // testi ATLANIR, "her zaman reddedilir" varsayımı burada geçerli değil.
    if (field.type === 'number' && !field.skipNegative) {
      results.push(
        await runScenario({
          app, method, path, authToken,
          payload: { ...base, [field.name]: -1 },
          multipart, fileAttachment,
          scenarioLabel: `${field.name} negatif`,
        })
      );
      if (field.rejectsZero) {
        results.push(
          await runScenario({
            app, method, path, authToken,
            payload: { ...base, [field.name]: 0 },
            multipart, fileAttachment,
            scenarioLabel: `${field.name} sıfır`,
          })
        );
      }
    }

    // 6. Geçersiz enum.
    if (field.type === 'enum') {
      results.push(
        await runScenario({
          app, method, path, authToken,
          payload: { ...base, [field.name]: 'GECERSIZ_DEGER_XYZ' },
          multipart, fileAttachment,
          scenarioLabel: `${field.name} geçersiz enum`,
        })
      );
    }

    // 7. Aşırı uzun string.
    if ((field.type === 'string' || field.type === 'enum') && field.maxLength) {
      const tooLong = 'a'.repeat(field.maxLength + 1000);
      results.push(
        await runScenario({
          app, method, path, authToken,
          payload: { ...base, [field.name]: tooLong },
          multipart, fileAttachment,
          scenarioLabel: `${field.name} çok uzun`,
        })
      );
    }
  }

  return results;
}

// Çağıran testte tek satırda tüm sonuçların 4xx (500 DEĞİL) olduğunu doğrular.
// Başarısız senaryoları (varsa) okunabilir biçimde listeler.
function assertAllRejected(results, contextLabel) {
  const failures = results.filter((r) => !r.pass);
  assert.strictEqual(
    failures.length,
    0,
    `${contextLabel}: ${failures.length} senaryo beklenen 4xx yerine farklı bir status döndü:\n` +
      failures.map((f) => `  - ${f.scenarioLabel}: status=${f.status} body=${JSON.stringify(f.body)}`).join('\n')
  );
}

module.exports = { runInputValidationMatrix, assertAllRejected };
