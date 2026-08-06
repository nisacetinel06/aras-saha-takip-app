// AI Asistan / Sohbet Arayüzü (Modül 16) — Google Gemini API entegrasyonu.
//
// Bu dosya YALNIZCA iki şey için Gemini'ye başvurur:
//   1) parseUserIntent — kullanıcının doğal dil sorusunu, assistantIntents.js
//      şemasına uyan bir { intent, filters } JSON'una çevirmek (SQL DEĞİL).
//   2) formatAnswer — assistantQueries.js'ten dönen GERÇEK veritabanı
//      sonucunu doğal bir Türkçe cümleye çevirmek (sayı UYDURMAZ, yalnızca
//      kendisine verilen sayıları yorumlar).
// İkisi de gemini-3.5-flash-lite kullanır: her kullanıcı mesajı için 2 çağrı
// yapıldığından (niyet çıkarımı + yanıt formatlama), ücretsiz kotayı aşmamak
// ve maliyeti düşük tutmak amacıyla daha büyük bir modele BİLİNÇLİ olarak
// geçilmedi — bu basit bir sınıflandırma/cümle kurma görevi, Flash fazlasıyla
// yeterli.
const { GoogleGenerativeAI } = require('@google/generative-ai');
const { INTENT_SCHEMA, ALLOWED_INTENTS } = require('./assistantIntents');

const MODEL = 'gemini-3.5-flash-lite';

let _client = null;
function getClient() {
  // Lazy init: GEMINI_API_KEY server.js'in process.loadEnvFile'ından SONRA
  // okunmalı — modül yüklenirken değil, ilk gerçek çağrıda okunur.
  if (!_client) {
    if (!process.env.GEMINI_API_KEY) {
      throw new AssistantUnavailableError('GEMINI_API_KEY tanımlı değil.');
    }
    _client = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
  }
  return _client;
}

// Gemini API'ye ulaşılamadığında (ağ hatası, geçersiz anahtar, kota aşımı,
// timeout vb.) fırlatılır — routes/assistant.js bunu yakalayıp kullanıcıya
// sabit, zarif bir "şu an yanıt veremiyorum" mesajı döner; uygulama ASLA çökmez.
class AssistantUnavailableError extends Error {}

function buildIntentSystemPrompt() {
  const intentLines = ALLOWED_INTENTS.filter((name) => name !== 'unknown').map((name) => {
    const schema = INTENT_SCHEMA[name];
    const filterLines = Object.entries(schema.filters)
      .map(([field, def]) => {
        if (def.type === 'enum') return `    - ${field}: şu değerlerden biri: ${def.values.join(', ')}`;
        if (def.type === 'number') return `    - ${field}: sayı (${def.min}-${def.max} arası, belirtilmezse varsayılan ${def.default})`;
        if (def.type === 'date') return `    - ${field}: YYYY-MM-DD formatında tarih`;
        return `    - ${field}: metin${def.required ? ' (ZORUNLU)' : ''}`;
      })
      .join('\n');
    return `- "${name}": ${schema.description}\n${filterLines || '    (filtre yok)'}`;
  });

  return `Sen ArasSaha saha yönetim uygulamasının bir parçasısın. Görevin, kullanıcının Türkçe sorusunu SADECE aşağıdaki JSON şemasına uyan bir niyet (intent) nesnesine çevirmek.

İzin verilen intent'ler ve filtreleri:
${intentLines.join('\n')}
- "unknown": Soru yukarıdaki kategorilerden hiçbirine uymuyorsa, filtreler: (filtre yok)

KURALLAR:
- SADECE geçerli bir JSON nesnesi döndür: {"intent": "...", "filters": {...}}
- Başka HİÇBİR metin, açıklama, markdown kod bloğu (\`\`\`) EKLEME.
- Yalnızca kullanıcının sorusunda AÇIKÇA belirttiği filtreleri doldur, geri kalanını filters nesnesine hiç ekleme.
- Soru yukarıdaki kategorilerin hiçbirine uymuyorsa veya belirsizse "unknown" döndür.
- Sen bir veritabanı sorgusu YAZMIYORSUN, yalnızca niyeti sınıflandırıyorsun — asıl veri sorgusunu sunucu çalıştıracak.`;
}

// Gemini'nin ürettiği JSON'a KÖRÜ KÖRÜNE güvenilmez: intent izin verilen
// listede değilse, filtre alanı şemada tanımlı değilse/tipine uymuyorsa o
// alan sessizce ATLANIR (tüm intent'i düşürmez) — yalnızca ZORUNLU bir alan
// (örn. equipment_lookup.qr_code) eksik kalırsa intent 'unknown'a düşer.
function validateIntent(payload) {
  if (!payload || typeof payload !== 'object' || typeof payload.intent !== 'string') {
    return { intent: 'unknown', filters: {} };
  }
  if (!ALLOWED_INTENTS.includes(payload.intent) || payload.intent === 'unknown') {
    return { intent: 'unknown', filters: {} };
  }

  const schema = INTENT_SCHEMA[payload.intent];
  const rawFilters = payload.filters && typeof payload.filters === 'object' ? payload.filters : {};
  const cleanFilters = {};

  for (const [field, def] of Object.entries(schema.filters)) {
    const value = rawFilters[field];
    if (value === undefined || value === null || value === '') continue;

    if (def.type === 'enum' && typeof value === 'string' && def.values.includes(value)) {
      cleanFilters[field] = value;
    } else if (def.type === 'string' && typeof value === 'string' && value.trim().length > 0 && value.length <= 100) {
      cleanFilters[field] = value.trim();
    } else if (def.type === 'number') {
      const n = Number(value);
      if (Number.isFinite(n)) cleanFilters[field] = Math.min(Math.max(Math.round(n), def.min), def.max);
    } else if (def.type === 'date' && typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)) {
      cleanFilters[field] = value;
    }
    // Tipine uymayan bir değer sessizce atlanır — o filtre hiç uygulanmaz.
  }

  for (const [field, def] of Object.entries(schema.filters)) {
    if (def.required && cleanFilters[field] === undefined) {
      return { intent: 'unknown', filters: {} };
    }
    if (def.type === 'number' && cleanFilters[field] === undefined && def.default !== undefined) {
      cleanFilters[field] = def.default;
    }
  }

  return { intent: payload.intent, filters: cleanFilters };
}

async function parseUserIntent(userMessage) {
  let raw;
  try {
    const client = getClient();
    // responseMimeType 'application/json' Gemini'yi SADECE geçerli JSON
    // döndürmeye zorlar (```json bloğu veya ek metin eklemez) — ek bir
    // regex ayıklamaya gerek bırakmaz, ama yine de aşağıda bir güvenlik payı
    // bırakıldı (bkz. JSON.parse try/catch).
    const model = client.getGenerativeModel({
      model: MODEL,
      systemInstruction: buildIntentSystemPrompt(),
      generationConfig: { temperature: 0, responseMimeType: 'application/json' },
    });
    const result = await model.generateContent(userMessage);
    raw = result.response.text();
  } catch (err) {
    throw new AssistantUnavailableError(err.message);
  }

  let payload;
  try {
    const match = raw.match(/\{[\s\S]*\}/);
    payload = JSON.parse(match ? match[0] : raw);
  } catch {
    // JSON.parse başarısız olursa ÇÖKMEZ, intent 'unknown' olarak ele alınır.
    return { intent: 'unknown', filters: {} };
  }

  return validateIntent(payload);
}

async function formatAnswer(intent, filters, queryResult, userMessage) {
  // `items` dizisi taşıyan sonuçlar (list_work_orders, list_high_risk_equipment
  // vb.) kısa bir özet cümlesine SIKIŞTIRILMAMALI — kullanıcı genelde her
  // kaydın başlığını/durumunu/konumunu görmek ister ("içeriğini listele" gibi
  // sorularda özellikle). Sayım/tekil sonuçlar (count, item) için kısa cümle
  // yeterlidir. İki durum için AYRI bir talimat veriyoruz ki Gemini bir liste
  // sonucunu tek cümlede "3 tanesi şu, 2 tanesi bu" diye özetleyip asıl
  // istenen kayıt detaylarını (başlık, açıklama, konum) atlamasın.
  const isList = Array.isArray(queryResult?.items);
  const formatInstruction = isList
    ? 'Bu bir KAYIT LİSTESİ. Her kaydı ayrı bir satırda, "- " ile başlayarak, o kaydın önemli alanlarını (örn. başlık, durum, öncelik, konum) kısaca belirterek listele. Kayıtları özetleyip birleştirme (örn. "3 tanesi X, 2 tanesi Y" gibi gruplama YAPMA) — her kayıt kendi satırında ayrı ayrı görünmeli. Liste boşsa bunu tek cümleyle belirt.'
    : 'Bu veriyi kullanarak kullanıcıya doğal, kısa (1-2 cümle) bir yanıt yaz.';

  const prompt = `Kullanıcının orijinal sorusu: "${userMessage}"

Bu soruya karşılık veritabanından gelen GERÇEK sonuç (JSON):
${JSON.stringify(queryResult)}

${formatInstruction} SADECE yukarıdaki JSON'daki verileri kullan; ekstra bilgi, tahmin veya yorum EKLEME. Türkçe yaz. Markdown kullanma (yıldız, kalın yazı, başlık YOK), yalnızca düz metin ve "- " satır başları kullanabilirsin.`;

  try {
    const client = getClient();
    const model = client.getGenerativeModel({
      model: MODEL,
      systemInstruction: 'Sen ArasSaha saha yönetim uygulamasının asistanısın. Yalnızca sana verilen gerçek verilerle, kısa ve net Türkçe cümleler kurarsın. Asla veri uydurmazsın.',
      generationConfig: { temperature: 0.3 },
    });
    const result = await model.generateContent(prompt);
    return result.response.text().trim();
  } catch (err) {
    throw new AssistantUnavailableError(err.message);
  }
}

module.exports = { parseUserIntent, formatAnswer, AssistantUnavailableError, validateIntent };
