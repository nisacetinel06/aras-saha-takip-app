// Görüntü Tabanlı Hasar Tespiti (Modül 15) — ortak CV analiz fonksiyonu.
//
// risk.js/anomaly.js'teki ML servisi çağrılarıyla AYNI mimari: Node bu
// modeli import ETMEZ, ayrı bir Python (FastAPI, arassaha-ml/) servisine HTTP
// ile bağlanır. Buradaki fark, gönderilenin sayısal/metin veri değil BİR
// FOTOĞRAF DOSYASI (multipart/form-data) olması.
//
// KRİTİK KURAL: Bu fonksiyon ASLA fırlatmaz (throw etmez). CV analizi,
// İSG bildirimi/iş emri fotoğrafı akışının üstüne binen EK bir bilgi
// katmanıdır — kritik yol değildir. Python servisi kapalıysa, zaman aşımına
// uğrarsa ya da beklenmedik bir yanıt dönerse bu fonksiyon sessizce
// { cv_is_damaged: null, cv_damage_probability: null } döner; çağıran taraf
// (routes/isg.js, routes/workOrders.js) bunu normal bir INSERT değeri olarak kullanır.
const ML_SERVICE_URL = process.env.ML_SERVICE_URL || 'http://localhost:8000';

const NULL_RESULT = { cv_is_damaged: null, cv_damage_probability: null };

// Sağlık/İSG akışını CV analizi asla bloklamamalı — analiz uzarsa (soğuk
// başlangıç, yoğun CPU) makul bir sürede vazgeçilir.
const TIMEOUT_MS = 15000;

/**
 * @param {Buffer} fileBuffer - Diske zaten yazılmış fotoğrafın buffer'ı (fs.readFileSync ile okunur).
 * @param {string} filename - Orijinal dosya adı (yalnızca Content-Type/uzantı ipucu için).
 * @param {string} mimetype - multer'ın algıladığı MIME tipi (image/jpeg | image/png).
 * @returns {Promise<{cv_is_damaged: (1|0|null), cv_damage_probability: (number|null)}>}
 */
async function classifyImageForDamage(fileBuffer, filename, mimetype) {
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), TIMEOUT_MS);

    const formData = new FormData();
    formData.append('file', new Blob([fileBuffer], { type: mimetype }), filename);

    const response = await fetch(`${ML_SERVICE_URL}/classify-image`, {
      method: 'POST',
      body: formData,
      signal: controller.signal,
    });
    clearTimeout(timeout);

    if (!response.ok) {
      console.warn(`CV hasar analizi başarısız (HTTP ${response.status}) — cv_* alanları null bırakılıyor.`);
      return NULL_RESULT;
    }

    const result = await response.json();
    // TEST-20: result.is_damaged artık ÜÇ durumlu (true/false/null) — ML
    // servisi belirsiz bir olasılık aralığında (bkz. arassaha-ml/app.py
    // DAMAGE_UNCERTAIN_LOW/HIGH) null döner. `result.is_damaged ? 1 : 0`
    // burada YANLIŞ olurdu: JavaScript'te null FALSY olduğu için "belirsiz"
    // sessizce "hasarsız" (0) olarak kaydedilir, tam da önlemeye çalıştığımız
    // sahte kesinlik hatasına düşerdi. NULL zaten bu sütunun (bkz.
    // NULL_RESULT yukarısı) "CV bilgisi yok/güvenilir değil" anlamına gelen
    // kabul edilmiş değeri olduğu için ayrıca bir şema değişikliği gerekmedi.
    return {
      cv_is_damaged: result.is_damaged === null ? null : (result.is_damaged ? 1 : 0),
      cv_damage_probability: result.damage_probability,
    };
  } catch (err) {
    // ML servisi kapalı, zaman aşımı, ağ hatası vb. — hepsi aynı şekilde
    // yutulur (bkz. dosya başındaki KRİTİK KURAL).
    console.warn('CV hasar analizine ulaşılamadı, cv_* alanları null bırakılıyor:', err.message);
    return NULL_RESULT;
  }
}

module.exports = { classifyImageForDamage };
