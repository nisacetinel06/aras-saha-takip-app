// Fotoğraf yükleme güvenliği: dosyanın GERÇEK içeriğini (ilk birkaç
// byte'ındaki "magic number"/dosya imzası) kontrol eder — istemcinin beyan
// ettiği Content-Type (multer'ın `file.mimetype`'ı) veya dosya uzantısı BU
// KONTROLE DAHİL DEĞİLDİR, çünkü ikisi de istemci tarafından serbestçe
// sahtelenebilir (bkz. middleware/validateImageContent.js üstündeki not).
// Harici bir dosya tipi tespit paketine (file-type gibi) ihtiyaç yok —
// yalnızca JPEG/PNG kabul edildiği için manuel imza kontrolü yeterli.
function isValidImageBuffer(buffer) {
  if (!buffer || buffer.length < 8) return false;

  // JPEG imzası: FF D8 FF
  const isJpeg = buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff;

  // PNG imzası: 89 50 4E 47 0D 0A 1A 0A
  const pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  const isPng = pngSignature.every((byte, i) => buffer[i] === byte);

  return isJpeg || isPng;
}

module.exports = { isValidImageBuffer };
