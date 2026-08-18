// SEC-05: Merkezi hata işleyici — Express'te 4 parametre alan (err, req, res,
// next) bir middleware, Express tarafından ÖZEL olarak "hata işleyici" kabul
// edilir ve YALNIZCA server.js'teki tüm route/middleware zincirinin EN
// SONUNDA (app.listen()'dan hemen önce) bağlanmalıdır — aksi halde hiç
// çalışmaz (bkz. server.js).
//
// Buraya üç yoldan hata gelebilir: (1) senkron bir handler'da fırlatılan
// hata (Express 4 bunu zaten otomatik yakalar), (2) asyncHandler() ile
// sarılmış bir async handler'daki reddedilen Promise (bkz.
// utils/asyncHandler.js), (3) route'ların KENDİ try/catch'lerinin kaçırdığı
// herhangi bir beklenmedik durum. Üçünde de amaç AYNI: client'a ASLA
// err.stack/err.message'ın ham hâlini/dosya yolunu göstermemek, ama sunucu
// tarafında TAM hatayı loglamaya devam etmek (debug yeteneği kaybolmasın).
function errorHandler(err, req, res, next) {
  // Sunucu tarafında TAM hatayı loglasın (stack trace dahil) — bu, debug için
  // hâlâ gerekli, sadece client'a gitmiyor.
  console.error(`[HATA] ${req.method} ${req.originalUrl}:`, err);

  // Eğer hata zaten bilinen, kasıtlı bir uygulama hatasıysa (örn. statusCode
  // taşıyan bir hata nesnesi), onu koru — bu codebase'de route'ların BÜYÜK
  // çoğunluğu kendi try/catch'inde zaten doğru 4xx'i dönüyor (bkz.
  // middleware/auth.js, routes/*.js), bu handler yalnızca GERÇEKTEN
  // beklenmeyen/yakalanmamış durumlar için bir güvenlik ağıdır.
  const statusCode = err.statusCode || 500;

  // Client'a SADECE genel, güvenli bir mesaj dönsün — asla err.stack, err.message'ın
  // ham SQL/dosya yolu içerebilecek hâli gönderilmez.
  const safeMessage =
    statusCode === 500 ? 'Beklenmeyen bir sunucu hatası oluştu' : err.clientMessage || 'İstek işlenemedi';

  res.status(statusCode).json({ error: safeMessage });
}

module.exports = errorHandler;
