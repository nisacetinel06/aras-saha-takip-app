# Güvenlik Notları

Bu dosya, kod incelemeleri/test görevleri sırasında tespit edilen, o görevin
kapsamında ÇÖZÜLMEYEN (bilinçli olarak ertelenen) güvenlik bulgularını
biriktirir. Her madde ayrı bir backlog kartına dönüşene kadar burada durur.

## Login endpoint'inde rate limiting / brute-force koruması yoktu — düzeltildi

`POST /api/auth/login` (bkz. [routes/auth.js](routes/auth.js)) art arda
yapılan başarısız giriş denemelerini SINIRLAMIYORDU. Bir saldırgan, bilinen
bir sicil_no için şifreyi otomatik olarak deneme yanılma (brute-force) ile
sınırsız sayıda deneyebiliyordu. Bu, TEST-06 (login akışının uçtan uca test
edilmesi) kapsamında bilinçli olarak ele ALINMAMIŞTI.

Düzeltme (bkz. [test/integration/loginRateLimit.test.js](test/integration/loginRateLimit.test.js)):

- `login_attempts` tablosu (bkz. [database.js](database.js)) her giriş
  denemesini (başarılı/başarısız, sicil_no, IP, zaman) kaydeder.
- [middleware/loginRateLimit.js](middleware/loginRateLimit.js) —
  `checkLoginRateLimit`: sicil_no + IP kombinasyonu bazında, son 15 dakikada
  5 başarısız deneme varsa 429 döner. Kullanıcı numaralandırmayı önlemek için
  sicil_no'nun DB'de var olup olmadığına BAKMAKSIZIN uygulanır.
- `express-rate-limit` ile ayrıca genel bir IP bazlı katman (dakikada 20
  istek) — sicil_no bazlı sayaç mantığını çok sayıda farklı sicil_no
  deneyerek atlatmaya çalışan bir saldırgana karşı.
- `app.set('trust proxy', 1)` (bkz. [server.js](server.js)) — Railway gibi
  bir proxy arkasında `req.ip`'nin gerçek istemci IP'sini yansıtması için
  zorunlu; aksi halde tüm istekler proxy'nin IP'siyle geliyormuş gibi görünür
  ve IP bazlı hiçbir kontrol anlamlı çalışmaz.

## Pasif kullanıcı girişi engellenmiyordu — TEST-06 kapsamında düzeltildi

TEST-06 için yapılan kod incelemesinde, `routes/auth.js`'teki login akışının
şifre doğrulamasından SONRA `user.is_active` alanını HİÇ kontrol etmediği
tespit edildi — yani Modül 8'de pasifleştirilmiş (`is_active = 0`) bir
kullanıcı, doğru şifresini bildiği sürece login endpoint'inden token almaya
devam edebiliyordu. Pasifleştirme özelliğinin güvenlik amacını (erişimi
kesmek) fiilen boşa çıkaran bir açıktı.

Düzeltme: şifre doğrulandıktan, token üretilmeden ÖNCE `is_active === 0` ise
`403` ile reddedilecek şekilde bir kontrol eklendi (bkz.
[routes/auth.js](routes/auth.js), `POST /api/auth/login`). Bkz.
[test/integration/authLogin.test.js](test/integration/authLogin.test.js)
"pasif kullanıcı" senaryosu.
