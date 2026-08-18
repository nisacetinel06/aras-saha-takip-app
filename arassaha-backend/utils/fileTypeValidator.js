// Fotoğraf yükleme güvenliği: dosyanın GERÇEK içeriğini (ilk birkaç
// byte'ındaki "magic number"/dosya imzası) kontrol eder — istemcinin beyan
// ettiği Content-Type (multer'ın `file.mimetype`'ı) veya dosya uzantısı BU
// KONTROLE DAHİL DEĞİLDİR, çünkü ikisi de istemci tarafından serbestçe
// sahtelenebilir (bkz. middleware/validateImageContent.js üstündeki not).
// Harici bir dosya tipi tespit paketine (file-type gibi) ihtiyaç yok —
// yalnızca JPEG/PNG kabul edildiği için manuel imza kontrolü yeterli.
//
// SEC-04: önceden yalnızca true/false dönen isValidImageBuffer(), artık
// tespit edilen GERÇEK tipi (uzantı normalizasyonu için gerekli, bkz.
// validateImageContent.js) döndüren detectImageType()'a genişletildi.
// isValidImageBuffer geriye dönük uyumluluk için korunur.
function detectImageType(buffer) {
  if (!buffer || buffer.length < 8) return null;

  // JPEG imzası: FF D8 FF
  const isJpeg = buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff;
  if (isJpeg) return 'jpeg';

  // PNG imzası: 89 50 4E 47 0D 0A 1A 0A
  const pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  const isPng = pngSignature.every((byte, i) => buffer[i] === byte);
  if (isPng) return 'png';

  return null; // ne JPEG ne PNG, geçersiz
}

function isValidImageBuffer(buffer) {
  return detectImageType(buffer) !== null;
}

module.exports = { detectImageType, isValidImageBuffer };
