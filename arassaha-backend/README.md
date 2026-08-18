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

### CI/CD Gate — testler production deploy'unu engeller

> **Kararın evrimi:** İlk kurulumda (bkz. proje geçmişi) test suite'ini
> bilinçli olarak deploy sürecinin dışında tutmuştuk — bu, altyapıyı
> bozmadan önce test altyapısını oturtmak için doğru bir sıralamaydı. Bu
> artık değişti: testler artık production deploy'unu gerçekten kapılıyor
> (gate) — bu bir çelişki değil, planlı bir evrim.

**Testler kırmızıysa production'a hiçbir şey deploy edilmez.**

İki ayrı, birbirini tamamlayan mekanizma var:

1. **GitHub Actions** (`.github/workflows/backend-tests.yml`) — her
   `push`/`pull_request`'te (main/master) `npm ci`, `npm test` ve
   `npm run test:coverage` çalışır. `npm test` başarısız olursa (non-zero
   exit code) workflow kırmızı yanar.
2. **Railway build zinciri** (`railway.json`) — `buildCommand`,
   `"npm ci && npm test"` olarak zincirlenmiştir; `startCommand` ise
   `"npm start"`dir. `npm test` başarısız olursa `&&` zinciri durur,
   Railway'in build fazı başarısız sayılır ve `npm start`'a — dolayısıyla
   yeni sürümün canlıya alınmasına — ASLA geçilmez. Bu, GitHub branch
   protection gibi ekstra bir yapılandırmaya ihtiyaç duymadan en doğrudan
   deploy-engelleme yoludur.

Yerel olarak aynı zinciri simüle edip doğrulamak için:

```bash
npm ci && npm test && npm start
```

Bir test kasıtlı olarak bozulduğunda bu komut `npm start`'a hiç ulaşmaz
(sunucu hiç dinlemeye başlamaz) — bu, gerçek Railway ortamında da aynı
davranışın (build fazının başarısız sayılıp deploy'un durmasının)
güvenilir bir yerel kanıtıdır.

**Önemli — NODE_ENV izolasyonu korunur:** `npm test` kendi içinde
`cross-env NODE_ENV=test` kullanır (bkz. yukarıdaki "Testler" bölümü) —
bu, yalnızca `node --test` alt sürecine özgüdür, `npm start`'a miras
KALMAZ. Yani build fazında test'lerin `:memory:` veritabanı kullanması,
sonraki `npm start` adımının production `NODE_ENV`'i ve gerçek
`aras_saha.db` dosyasıyla çalışmasını hiçbir şekilde etkilemez.
