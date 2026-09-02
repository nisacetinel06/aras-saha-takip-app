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

### Kritik Yol Tablosu

> **Durum notu (TEST-17):** Bu tablo daha önce hiç bu dosyada yer almamıştı —
> "TEST-13/14/15/16" etiketleri repoda yalnızca ilgili test dosyalarının
> başına yazılan inline yorumlardı (bkz. `test/integration/sosAlerts.test.js`,
> `test/integration/auth.test.js`), gerçek bir README tablosuna hiç
> dönüştürülmemişlerdi. TEST-17 kapsamında bu ilk kez oluşturuldu: TEST-13
> sonrası eklenen tüm modüller tek tek denetlendi (git geçmişi + test
> dosyaları üzerinden), test dosyası olup tabloya girmemiş olanlar buraya
> eklendi. Trello kart numaraları elimizde olmayanlar için test dosyasının
> adı referans olarak kullanıldı — gerçek kart numarasını biliyorsanız bu
> tabloyu güncelleyin.

| Kritik Alan | İlgili Dosya(lar) | Hangi Test Kapsadı |
|---|---|---|
| Authentication | `middleware/auth.js`, `routes/auth.js` | TEST-03, TEST-06 |
| RBAC | `middleware/auth.js`, tüm route dosyaları | TEST-03, SEC-01 |
| WorkOrder Visibility | `routes/workOrders.js` | SEC-02 |
| Stock Transaction | `routes/materials.js` | TEST-07 |
| Idempotency | `routes/workOrders.js` | TEST-08 |
| Input Validation | `routes/users.js`, `routes/workOrders.js`, `routes/materials.js`, `routes/isg.js` | TEST-09 |
| Dashboard/Bildirim/Rapor Erişimi | `routes/dashboard.js`, `routes/notifications.js`, `routes/reports.js` | TEST-10 |
| Dosya Yükleme Güvenliği (temel) | `middleware/multer` kullanımı, `utils/fileTypeValidator.js` | SEC-03 |
| Hata İşleyici Bilgi İfşası | `middleware/errorHandler.js`, `utils/asyncHandler.js` | SEC-05 — `errorHandling.test.js` |
| Login Brute-Force Koruması | `middleware/loginRateLimit.js`, `middleware/rateLimiting.js` | `loginRateLimit.test.js` |
| 2FA (TOTP) | `routes/twoFactor.js` | `twoFactor.test.js` |
| Refresh Token Rotasyonu | `utils/refreshToken.js`, `routes/auth.js` (`/refresh`, `/logout`) | `refreshToken.test.js` |
| KVKK Anonimleştirme/Silme | `routes/kvkk.js` | `kvkk.test.js` |
| Orphan Dosya Temizleme | `jobs/orphanFilePurge.js` | `orphanFilePurge.test.js` |
| Retention Purge Job (saklama süresi sonu temizlik) | `jobs/retentionPurge.js` | `retentionPurge.test.js` |
| Purge Admin Endpoint | `jobs/purgeLog.js`, ilgili admin route'u | `purgeAdminEndpoint.test.js` |
| Dosya Yükleme İçerik Doğrulama Sıkılaştırma (uzantı normalizasyonu, statik rota) | `middleware/validateImageContent.js`, `routes/uploads.js` | `uploadsSecurity.test.js`, `fileUploadSecurity.test.js` |
| RBAC Boşlukları + Atayan Yönetici | `routes/workOrders.js`, `utils/workOrderAccess.js` | `workOrderAssignedBy.test.js` |
| Profil Fotoğrafı Yetkilendirme Denetimi | `routes/users.js` (`POST /:id/photo`) | `profilePhotoAuthorization.test.js` |
| Denetim Kaydı (Audit Log) | `routes/auditLog.js`, `services/auditLogAggregator.js` | `auditLog.test.js`, `auditLogAggregator.test.js` |
| Malzeme — Atanmamış İş Emrine Kayıt (Hesap Verebilirlik) | `routes/materials.js` | `materialOffAssignment.test.js` |
| Mesajlaşma RBAC/Sahiplik | `routes/managerMessages.js` | TEST-14 |
| SOS Güvenlik/Sahiplik | `routes/sosAlerts.js` | TEST-15 |
| FCM Token Güvenliği | `routes/auth.js` (`register-fcm-token`) | TEST-16 |
| **Kendi Şifreni Değiştirme** | `routes/auth.js` (`POST /change-password`) | ❌ **TEST YOK** — ayrı bir kart açılmalı (bkz. aşağıdaki "Bilinen Kısıtlar" notu) |
| Gerçek Geri Bildirim Döngüsü (Risk Tahmini Sonuç Takibi) | `routes/risk.js`, `jobs/riskOutcomeExpiry.js`, `database.js` (`risk_prediction_outcomes`) | TEST-19 — `riskPredictionOutcomes.test.js` |
| Gerçek Geri Bildirim Döngüsü (Hasar Tespiti İnsan Doğrulaması) | `routes/isg.js` (`PATCH /:id/verify-damage`), `routes/risk.js` (`GET /ml/damage-model-performance`), `database.js` (`isg_reports.human_verified_damage`) | TEST-20 — `damageFeedbackLoop.test.js` |

Bu tabloyu güncel tutma kuralı için bkz. [CONTRIBUTING.md](CONTRIBUTING.md)
"Kritik Yol Tablosu Güncelleme Kuralı".

## Gerçek Geri Bildirim Döngüsü (Modül 9 — Risk Tahmini)

Arıza Risk Tahmini (bkz. `arassaha-ml/README.md` "Dürüstlük Notu") sentetik
veriyle eğitilmiş bir modelden geliyor — bu döngü, zamanla GERÇEK arıza
sonuçlarını biriktirip modelin gerçek dünyada ne kadar isabetli olduğunu
ölçmenin (ve ileride yeniden eğitmenin) altyapısını kurar. Tamamen otomatik,
kimse elle bir şey işaretlemez:

1. **Tahmin kaydı** — bir ekipmanın risk skoru her hesaplandığında
   (`routes/risk.js` `computeAndSaveRisk`), `risk_prediction_outcomes`
   tablosuna `actual_fault_occurred = NULL` ("henüz sonuçlanmadı") ile yeni
   bir satır eklenir. Aynı ekipman için 24 saat içinde zaten sonuçlanmamış
   bir kayıt varsa tekrar açılmaz (gereksiz yineleme koruması).
2. **Otomatik "arızalandı" eşleştirmesi** — `POST /api/workorders` ile yeni
   bir arıza iş emri açıldığında, o ekipman için son 90 gün içindeki
   sonuçlanmamış tahmin otomatik olarak `actual_fault_occurred = 1` yapılır
   (`recordFaultOutcomeIfPredicted`).
3. **90 gün sonra "arızalanmadı" işaretleme** — `jobs/riskOutcomeExpiry.js`,
   `jobs/orphanFilePurge.js`/`retentionPurge.js` ile AYNI node-cron deseniyle
   (her gün 03:00, bkz. `jobs/scheduler.js`) 90 günü aşmış ve hâlâ
   sonuçlanmamış tahminleri `actual_fault_occurred = 0` yapar — bu, modelin
   YANLIŞ ALARM verdiği durumları da yakalar, yalnızca isabetli tahminleri
   değil.
4. **Dürüst performans özeti** — `GET /api/ml/risk-model-performance`
   (yalnızca yönetici) bu tablodan GERÇEK isabet oranlarını hesaplar
   ("yüksek risk dediklerimizin %X'i gerçekten arızalandı" gibi) — en az 20
   sonuçlanmış tahmin birikmeden `has_enough_data: false` döner, Flutter
   tarafı (Raporlar > Bölgesel Görünüm > "Risk Modeli Performansı") bu
   durumda dürüst bir "henüz yeterli veri yok" mesajı gösterir.

Bkz. `arassaha-ml/train_model.py` `retrain_with_real_outcomes()` — bu
tabloda yeterli (50+) gerçek sonuç birikince modelin gerçek veriyle yeniden
eğitilmesi için yazılmış ama henüz devreye alınmamış bir altyapı.

### CI/CD Gate — testler production deploy'unu engeller

> **Kararın evrimi:** İlk kurulumda (bkz. proje geçmişi) test suite'ini
> bilinçli olarak deploy sürecinin dışında tutmuştuk — bu, altyapıyı
> bozmadan önce test altyapısını oturtmak için doğru bir sıralamaydı. Bu
> artık değişti: testler artık production deploy'unu gerçekten kapılıyor
> (gate) — bu bir çelişki değil, planlı bir evrim.

**Testler kırmızıysa merge/build kırmızı yanar.** Ayrıca, backend/ML
servisi/Flutter bağımlılıklarında yüksek/kritik önemde bilinen bir güvenlik
açığı bulunursa CI pipeline'ı da durur (bkz. aşağıdaki "Bağımlılık Güvenlik
Taraması (Dependency Audit) Gate'i" bölümü).

**GitHub Actions** (`.github/workflows/backend-tests.yml`) — her
`push`/`pull_request`'te (main/master) `npm ci`, `npm test`,
`npm run test:coverage` VE `npm audit --audit-level=high` çalışır. Bu dört
adımdan HERHANGİ biri başarısız olursa (non-zero exit code) workflow
kırmızı yanar.

> **Not:** Proje daha önce Railway'e canlı olarak dağıtılıyordu ve
> `railway.json`'daki build zinciri aynı gate'i (test + audit başarısız
> olursa deploy durur) Railway tarafında da uyguluyordu. Canlı Railway
> dağıtımı artık kullanılmıyor (proje yalnızca lokal çalışacak şekilde
> yapılandırıldı) — bu yüzden `railway.json` kaldırıldı; GitHub Actions
> gate'i tek başına geçerli.

Yerel olarak aynı zinciri simüle edip doğrulamak için:

```bash
npm ci && npm audit --audit-level=high && npm test && npm start
```

### Bağımlılık Güvenlik Taraması (Dependency Audit) Gate'i

Yukarıdaki test gate'ine EK olarak, üç bağımlılık ağacının (backend, ML
servisi, Flutter) üçü de ayrı bir CI adımında bilinen güvenlik açıklarına
karşı taranır — biri kırmızı yanarsa build/deploy durur, tıpkı testler gibi.

**GERÇEKLİK NOTU (Flutter tarafı):** Node.js'in `npm audit`'i veya Python'ın
`pip-audit`'i gibi, Dart/Flutter ekosisteminde resmi/yerleşik bir "audit"
komutu YOKTUR (`dart pub audit` diye bir şey yok). Bunun yerine Google'ın
[OSV-Scanner](https://github.com/google/osv-scanner) aracı kullanılıyor —
`pubspec.lock`'u OSV (Open Source Vulnerabilities) veritabanına karşı
tarayan, npm/PyPI/Pub dahil birden fazla ekosistemi destekleyen genel bir
araç. `flutter pub get` de pub.dev'in GitHub Advisory Database
entegrasyonu sayesinde bilinen açıkları bilgilendirme amaçlı gösterir, ama
build'i KIRMAZ (fail edilebilir bir exit code/eşik davranışı yoktur) — asıl
CI gate'i bu yüzden OSV-Scanner'dır.

**Şiddet Seviyesi Politikası** — üç aracın da varsayılan "ne zaman başarısız
ol" davranışı farklıdır; bu BİLİNÇLİ bir tutarsızlık, keyfi değil:

| Araç | Nerede | Eşik | Not |
|---|---|---|---|
| `npm audit` | Backend (`backend-tests.yml`) | `--audit-level=high` | Yalnızca yüksek/kritik önem build'i kırar; düşük/orta önem raporlanır ama build'i durdurmaz |
| `pip-audit` | ML servisi (`ml-service-tests.yml`) | Herhangi bir bilinen açık | Varsayılan davranış; gerekirse `pip-audit --ignore-vuln <VULN_ID>` ile istisna tanımlanabilir |
| OSV-Scanner | Flutter (`flutter-tests.yml`) | Herhangi bir bilinen açık | Benzer şekilde; istisnalar `.osv-scanner.toml` ile tanımlanabilir |

**Neden backend'de daha toleranslı?** `node_modules` ağacı çok derin
(yüzlerce transitive bağımlılık) — düşük önemli/yalnızca-geliştirme-zamanı
bağımlılıklarında (ör. bir test yardımcı paketinin transitive bir
bağımlılığı) sık sık düşük/orta önemli bulgu çıkar ve bunların hepsini anlık
olarak çözmek pratik değildir; bu yüzden yalnızca yüksek/kritik önem build'i
kırar. Python (`requirements.txt`, ~11 doğrudan paket) ve Flutter
(`pubspec.yaml`) bağımlılık ağaçları görece çok daha sığ olduğu için daha
sıkı bir eşik (herhangi bir bilinen açık) uygulanabilir oldu. **Not:** zamanla
bu gerçekçi olmadığı ortaya çıkarsa (çok fazla yanlış pozitif/gürültü, sık
sık geçici `--ignore-vuln` eklemek zorunda kalmak gibi), eşiği backend'deki
gibi gevşetmek (`--audit-level=high` benzeri bir eşiğe geçmek) meşru bir
karar olur — bu bir "ileride tekrar gözden geçirilecek" notu olarak burada
bırakılıyor.

## Bilinen Kısıtlar / Gelecek İyileştirmeler

### TEST-17 bulgusu: iki kritik dosyada satır coverage'ı %70 eşiğinin altında

`npm run test:coverage` çalıştırıldığında (bkz. yukarıdaki "Kritik Yol
Tablosu"), tablodaki dosyaların neredeyse tamamı %80+ satır coverage'a sahip
— ama iki kritik dosya %70 eşiğinin ALTINDA kaldı, bu görev kapsamında
düzeltilmedi ama görünür kılınıyor:

- **`routes/notifications.js` — %60.98 satır, %60.00 fonksiyon** (kapsanmayan
  satırlar: 28-30, 43-45, 50-68, 73-79). "Dashboard/Bildirim/Rapor Erişimi"
  (TEST-10) kapsamında `notificationsEndpoints.test.js` yalnızca `GET
  /api/notifications`'ı test ediyor — dosyadaki diğer endpoint'ler (ör.
  okundu işaretleme) test edilmemiş görünüyor.
- **`routes/users.js` — %68.86 satır** (kapsanmayan satırlar: 37-38, 76-88,
  97-98, 101-103, 114-129, 153-155, ... 432-441, 457-466, 478-479, 496-498).
  `usersValidation.test.js` ve `profilePhotoAuthorization.test.js` mevcut ama
  `GET /me/supervisor`, `PATCH /:id/reactivate`, `DELETE /:id` gibi
  endpoint'lerin bir kısmı kapsam dışı kalmış görünüyor.

Ayrıca `routes/auth.js` genel olarak %79.47 ile eşiğin üzerinde olsa da,
içindeki `POST /change-password` endpoint'i (satır 259-310) **tamamen**
kapsam dışı — bkz. [CONTRIBUTING.md](CONTRIBUTING.md)'deki ilgili not ve
yukarıdaki tablodaki "Kendi Şifreni Değiştirme" satırı.

**Öneri:** Bu üç bulgu (notifications.js, users.js'in kapsanmayan kısımları,
change-password'un hiç test edilmemesi) ayrı görev kartları olarak ele
alınmalı — bu görevin kapsamı yalnızca bunları görünür kılmaktı, düzeltmek
değildi.

### İki Faktörlü Doğrulama (2FA) — `totp_secret` düz metin saklanıyor

`users.totp_secret` (bkz. `routes/twoFactor.js`, `database.js`) **şifrelenmemiş
düz metin** olarak saklanır — bu bilinçli bir prototip kısıtıdır, ihmal değil.

Sebep: `password_hash`'ten farklı olarak `totp_secret` **tek yönlü hash'lenemez**.
Şifre doğrulaması "kullanıcının girdiği değer ile saklanan hash eşleşiyor mu?"
sorusuna bakar (bcrypt tek yönlü, geri döndürülemez); TOTP doğrulaması ise
her seferinde **sunucunun kendisinin** o anki geçerli 6 haneli kodu secret'tan
**yeniden üretip** kullanıcının girdiğiyle karşılaştırmasını gerektirir — bu,
secret'ın geri döndürülebilir (reversible) bir biçimde saklanmasını zorunlu
kılar. (Yedek kodlar bu kısıtın dışındadır — bkz. `totp_backup_codes.code_hash`,
onlar TEK kullanımlık olduğu için bcrypt ile hash'lenerek saklanır.)

**TODO (production öncesi yapılması gereken):** `totp_secret` uygulama
seviyesinde şifrelenmelidir — örn. AES-256-GCM ile, veritabanı dosyasından
**ayrı** bir yerde (ortam değişkeni / secrets manager) tutulan bir
encryption key kullanılarak. Bu, veritabanı dosyasının (`aras_saha.db`)
tek başına sızması durumunda secret'ların da doğrudan kullanılabilir
olmasını engeller — şu anki haliyle `aras_saha.db` dosyasına erişen biri,
2FA etkin bir yöneticinin hesabı için sınırsız sayıda geçerli TOTP kodu
üretebilir (2FA'yı fiilen anlamsız kılar).

**Önemli — NODE_ENV izolasyonu korunur:** `npm test` kendi içinde
`cross-env NODE_ENV=test` kullanır (bkz. yukarıdaki "Testler" bölümü) —
bu, yalnızca `node --test` alt sürecine özgüdür, `npm start`'a miras
KALMAZ. Yani build fazında test'lerin `:memory:` veritabanı kullanması,
sonraki `npm start` adımının production `NODE_ENV`'i ve gerçek
`aras_saha.db` dosyasıyla çalışmasını hiçbir şekilde etkilemez.
