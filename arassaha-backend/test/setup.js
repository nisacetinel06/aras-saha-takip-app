// Test ortamı için ortak güvenlik kontrolü. Her test dosyası (doğrudan ya da
// test/helpers/* üzerinden, dolayısıyla server.js -> database.js zincirinden
// ÖNCE) bunu require eder — NODE_ENV=test olmadan çalıştırılan bir `node
// --test` çağrısının yanlışlıkla gerçek aras_saha.db dosyasını açmasını
// engeller (bkz. database.js'teki dbPath koşulu). npm test/test:coverage/
// test:watch script'leri zaten cross-env ile NODE_ENV=test set eder; bu
// kontrol yalnızca elle (script dışı) çalıştırma hatalarına karşı bir
// güvenlik ağıdır.
if (process.env.NODE_ENV !== 'test') {
  throw new Error(
    "Testler yalnızca NODE_ENV=test ile çalıştırılmalı (bkz. package.json 'test' script'i). " +
      'Bu kontrol, gerçek aras_saha.db dosyasına yanlışlıkla dokunulmasını önlemek için var.'
  );
}

module.exports = {};
