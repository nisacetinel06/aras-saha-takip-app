# Güvenlik Notları

Bu dosya, kod incelemeleri/test görevleri sırasında tespit edilen, o görevin
kapsamında ÇÖZÜLMEYEN (bilinçli olarak ertelenen) güvenlik bulgularını
biriktirir. Her madde ayrı bir backlog kartına dönüşene kadar burada durur.

## Login endpoint'inde rate limiting / brute-force koruması yok (TEST-06)

`POST /api/auth/login` (bkz. [routes/auth.js](routes/auth.js)), art arda
yapılan başarısız giriş denemelerini SINIRLAMIYOR. Bir saldırgan, bilinen bir
sicil_no için şifreyi otomatik olarak deneme yanılma (brute-force) ile
sınırsız sayıda deneyebilir.

Bu, TEST-06 (login akışının uçtan uca test edilmesi) kapsamında bilinçli
olarak ele ALINMADI — kart notunda "brute-force koruması bu kartın kapsamı
dışında" belirtilmişti. Ayrı bir güvenlik görevi olarak backlog'a eklenmeli.

**Öneri:** `express-rate-limit` paketiyle `/api/auth/login` endpoint'ine
(örn. IP başına 15 dakikada 5-10 deneme) bir rate limit middleware'i eklemek.

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
