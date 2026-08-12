# ArasSaha Backend

İş emri / arıza takip sistemi backend API'si (Node.js + Express + SQLite, `node:sqlite`).

## Kurulum ve Çalıştırma

```
npm install
npm run seed   # demo verisini aras_saha.db'ye yükler
npm start
```

## Testler

Testler Node.js'in yerleşik test çalıştırıcısını (`node:test`) ve yerleşik
doğrulama modülünü (`node:assert`) kullanır — Jest veya başka bir test
framework'ü gerekmez. HTTP endpoint testleri için `supertest` kullanılır.

- Tüm testleri çalıştır: `npm test`
- Coverage ile çalıştır: `npm run test:coverage`
- Değişiklikleri izleyerek çalıştır: `npm run test:watch`

Testler ayrı, bellek içi bir test veritabanı kullanır (`NODE_ENV=test` ⇒
`database.js` gerçek `aras_saha.db` yerine `:memory:` SQLite bağlantısı açar,
bkz. `database.js`). Bu sayede test suite'i **production verisine hiçbir
zaman dokunmaz** — `test/unit/databaseIsolation.test.js`, `aras_saha.db`
dosyasının değişme zamanının (mtime) test çalışırken değişmediğini
doğrudan doğrular. `npm` script'leri Windows/Mac/Linux'ta aynı şekilde
çalışması için `cross-env` ile `NODE_ENV` set eder.

### Debug: gözle görülebilir bir test veritabanı kullanma

Bir test hatasını incelerken veritabanının SON HALİNİ gözle görmek isterseniz,
`DB_PATH` ile testleri bellek yerine gerçek bir dosyaya yazdırabilirsiniz —
bu, yalnızca geliştirici debug'ı için bir kaçış kapısıdır, production'ı hiç
etkilemez (`DB_PATH` tanımlıysa `NODE_ENV`'den bile önceliklidir, bkz.
`database.js` `resolveDbPath()`):

```
DB_PATH=./test/manual_debug.db npm test
```

Bu komuttan sonra `test/manual_debug.db` dosyasını herhangi bir SQLite
istemcisiyle açıp testlerin son bıraktığı durumu inceleyebilirsiniz. Dosya
`.gitignore`'da değildir — debug bittiğinde elle silin.

### Klasör yapısı

```
test/
  setup.js              -- NODE_ENV=test güvenlik kontrolü
  helpers/
    testDb.js            -- resetTestDatabase() / seedMinimalTestData()
    authHelper.js         -- getTestToken(role) — RBAC testleri için JWT üretir
  unit/                   -- HTTP/DB gerektirmeyen saf fonksiyon testleri
  integration/            -- supertest ile uçtan uca endpoint testleri
```

### CI

Her push/PR'da (`arassaha-backend/` altında değişiklik varsa) testler
`.github/workflows/test.yml` üzerinden otomatik çalışır. Bu, Railway
deploy sürecinden tamamen bağımsızdır — Dockerfile yalnızca `node seed.js`
ve `node server.js` çalıştırır, `npm test` build/deploy adımının bir
parçası DEĞİLDİR.
