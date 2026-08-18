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
//
// SEC-04 GENİŞLETMESİ: geçerli bir dosyanın UZANTISI da burada, TEK bir
// yerde, gerçek doğrulanmış tipe göre normalize edilir — istemcinin
// gönderdiği dosya adından/uzantısından ASLA değil. Örn. gerçekte bir PNG
// olan ama ".jpg" uzantısıyla gönderilen bir dosya, içerik doğrulamasından
// geçer (gerçekten geçerli bir resim) ama diskte YANLIŞ uzantıyla saklanmış
// olurdu — bu, ileride uzantıdan format tahmin eden araçları (örn. bazı
// resim işleme kütüphaneleri) şaşırtabilir. Bu mantık üç route'un HER
// BİRİNDE ayrı ayrı tekrarlanmak yerine burada, tek bir yerde yapılır —
// `req.file.filename`/`req.file.path` güncellenir, route'lar (isg.js,
// workOrders.js, users.js) bu middleware'den SONRA hâlâ sadece
// `req.file.filename`'i okur, kendileri hiçbir şey değiştirmez.
const fs = require('fs');
const path = require('path');
const { detectImageType } = require('../utils/fileTypeValidator');

const EXTENSION_BY_TYPE = { jpeg: '.jpeg', png: '.png' };

function validateImageContent(req, res, next) {
  if (!req.file) {
    return next();
  }

  // diskStorage kullanıldığı için buffer bellekte değil, dosya zaten diske
  // yazılmış durumda (`req.file.path`) — CV hasar tespiti (Modül 15) için
  // yapılan AYNI okuma deseni burada da kullanılır.
  const buffer = req.file.buffer || fs.readFileSync(req.file.path);
  const detectedType = detectImageType(buffer);

  if (!detectedType) {
    if (req.file.path) {
      try {
        fs.unlinkSync(req.file.path);
      } catch (unlinkErr) {
        console.error('Geçersiz dosya silinirken hata:', unlinkErr);
      }
    }
    return res.status(400).json({ error: 'Yüklenen dosya geçerli bir resim değil.' });
  }

  // Uzantı normalizasyonu: dosya adının BENZERSİZLİĞİ (uuid/timestamp kısmı)
  // korunur, yalnızca UZANTI tespit edilen gerçek tipe göre değiştirilir —
  // istemcinin orijinal dosya adı/uzantısı hiçbir şekilde kullanılmaz.
  const correctExtension = EXTENSION_BY_TYPE[detectedType];
  const currentExtension = path.extname(req.file.path).toLowerCase();
  if (currentExtension !== correctExtension) {
    const dir = path.dirname(req.file.path);
    const baseName = path.basename(req.file.path, path.extname(req.file.path));
    const newFilename = `${baseName}${correctExtension}`;
    const newPath = path.join(dir, newFilename);

    fs.renameSync(req.file.path, newPath);

    req.file.path = newPath;
    req.file.filename = newFilename;
  }

  next();
}

module.exports = validateImageContent;
