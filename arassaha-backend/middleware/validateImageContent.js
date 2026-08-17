// Fotoğraf yükleme güvenliği (ortak katman) — İSG (Modül 5), iş emri
// fotoğrafı ve profil fotoğrafı (Modül 8) endpoint'lerinin ÜÇÜ tarafından da
// kullanılır (kod tekrarını önlemek için tek bir yerde).
//
// multer'ın fileFilter'ı yalnızca `file.mimetype`/uzantıya bakar — bu,
// istemcinin multipart isteğinde KENDİ BEYAN ETTİĞİ, sunucu tarafından
// doğrulanmamış bir değerdir. Bir saldırgan farklı içerikli bir dosyayı
// ".jpg" uzantısı ve "Content-Type: image/jpeg" ile paketleyip fileFilter'ı
// geçebilir. Bu middleware, multer dosyayı diske YAZDIKTAN HEMEN SONRA
// (route içinde `upload.single(...)` callback'i tamamlandıktan ve `req.file`
// varlığı doğrulandıktan sonra çağrılmalı) dosyanın GERÇEK baytlarını
// (magic number) kontrol eder — uzantı/mimetype katmanı bunun YERİNE değil,
// ÖNÜNE eklenen ekstra bir katmandır, ikisi birlikte kalır.
//
// Geçersizse: diske zaten yazılmış dosya HEMEN silinir (kötü niyetli/
// hatalı bir dosyanın sunucuda kalıcı olarak durmasını önlemek için), 400
// döner ve `next()` ÇAĞRILMAZ — çağıran route'un geri kalan mantığı
// (DB INSERT dahil) hiç çalışmaz.
const fs = require('fs');
const { isValidImageBuffer } = require('../utils/fileTypeValidator');

function validateImageContent(req, res, next) {
  if (!req.file) {
    return next();
  }

  // diskStorage kullanıldığı için buffer bellekte değil, dosya zaten diske
  // yazılmış durumda (`req.file.path`) — CV hasar tespiti (Modül 15) için
  // yapılan AYNI okuma deseni burada da kullanılır.
  const buffer = req.file.buffer || fs.readFileSync(req.file.path);

  if (!isValidImageBuffer(buffer)) {
    if (req.file.path) {
      try {
        fs.unlinkSync(req.file.path);
      } catch (unlinkErr) {
        console.error('Geçersiz dosya silinirken hata:', unlinkErr);
      }
    }
    return res.status(400).json({ error: 'Yüklenen dosya geçerli bir resim değil.' });
  }

  next();
}

module.exports = validateImageContent;
