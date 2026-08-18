// SEC-04 Kısım B: eski `express.static('uploads')` yerine, güvenlik
// başlıkları ekleyen ve path traversal'a karşı EXPLICIT (express.static'in
// kendi içindeki dolaylı korumasına güvenmek yerine) savunma yapan özel bir
// route handler'ı.
//
// Bu route, `verifyToken`'ın MOUNT EDİLDİĞİ noktadan (server.js'te
// `/api/...` router'larından) ÖNCE, doğrudan `/uploads` altında bağlanır —
// yani kimlik doğrulaması GEREKTİRMEZ (fotoğraflar zaten `photo_path` olarak
// döndürülen, tahmin edilmesi güç rastgele dosya adlarıyla korunuyor —
// Flutter'ın Image.network çağrısının token göndermeden çalışabilmesi için
// bu tasarım BİLEREK korunuyor, SEC-04 kapsamında değiştirilmedi).
const express = require('express');
const path = require('path');
const fs = require('fs');
const router = express.Router();

const UPLOADS_ROOT = path.resolve(__dirname, '..', 'uploads');

router.get('/:folder/:filename', (req, res) => {
  const { folder, filename } = req.params;

  // Sadece bilinen alt klasörlere izin ver (whitelist) — isg (Modül 5),
  // workorders (Modül 1), profiles (Modül 8), bkz. server.js'teki mkdirSync
  // çağrıları.
  const allowedFolders = ['isg', 'workorders', 'profiles'];
  if (!allowedFolders.includes(folder)) {
    return res.status(404).json({ error: 'Bulunamadı' });
  }

  // path.basename ile filename'i temizle — herhangi bir "../" veya path
  // ayracı bileşenini at (örn. "..%2F..%2Fetc%2Fpasswd" decode edildikten
  // sonra Express tarafından zaten path.basename'e ULAŞMADAN reddedilir,
  // ama bu ikinci bir savunma katmanıdır).
  const safeFilename = path.basename(filename);
  const resolvedPath = path.resolve(UPLOADS_ROOT, folder, safeFilename);

  // Son bir güvenlik kontrolü: çözümlenen yol GERÇEKTEN UPLOADS_ROOT içinde
  // mi (path traversal'ın kesin engellenmesi) — path.basename tek başına
  // yeterli olsa da, bu savunma-derinliği (defense in depth) katmanı.
  if (!resolvedPath.startsWith(UPLOADS_ROOT)) {
    return res.status(400).json({ error: 'Geçersiz dosya yolu' });
  }

  if (!fs.existsSync(resolvedPath)) {
    return res.status(404).json({ error: 'Dosya bulunamadı' });
  }

  // Sadece izin verilen uzantılara servis ver. SEC-04 Kısım A sayesinde
  // BUNDAN SONRAKİ tüm yeni yüklemeler her zaman .jpeg/.png ile kaydedilir;
  // .jpg burada YİNE DE whitelist'te tutulur — Kısım A ÖNCESİ yüklenmiş
  // (yanlış uzantılı OLABİLECEK ama zaten geçerli resim olarak doğrulanmış)
  // eski dosyaların URL'lerinin bozulmaması için (bkz. görev notu).
  const ext = path.extname(safeFilename).toLowerCase();
  const allowedContentTypes = { '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png' };
  const contentType = allowedContentTypes[ext];
  if (!contentType) {
    return res.status(404).json({ error: 'Desteklenmeyen dosya tipi' });
  }

  // GÜVENLİK BAŞLIKLARI
  res.setHeader('X-Content-Type-Options', 'nosniff'); // tarayıcının içerik tipini "koklayıp" farklı yorumlamasını engeller
  res.setHeader('Content-Type', contentType); // her zaman sunucunun belirlediği, doğrulanmış tip — dosya adından tahmin ettirme
  res.setHeader('Content-Disposition', 'inline'); // tarayıcıda görüntülensin (indirilmeye zorlanmasın), resimler için uygun
  res.setHeader('Cache-Control', 'private, max-age=3600'); // makul bir önbellekleme, herkese açık CDN önbelleklemesi değil
  res.setHeader('X-Frame-Options', 'DENY'); // bu dosyanın başka bir sitede iframe içinde gösterilmesini engeller (clickjacking savunması)

  res.sendFile(resolvedPath);
});

module.exports = router;
