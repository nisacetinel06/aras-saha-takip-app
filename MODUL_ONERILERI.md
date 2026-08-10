# ArasSaha — Yeni Modül/Özellik Önerileri Raporu

**Tarih:** 2026-08-10
**Kapsam:** `arassaha-backend/`, `arassaha-ml/`, `arassaha_flutter/` — kod değişikliği yapılmadı, salt analiz.
**Yöntem:** Flutter ekranları tek tek gezildi (UX/açıklayıcılık), backend + istemci OWASP Mobile Top 10 / API Security Top 10 referansıyla denetlendi, bağımlılıklar (`npm audit`, `pubspec.yaml`, `requirements.txt`) ve KVKK açısından veri saklama/silme mekanizmaları tarandı.

---

## Özet

- **Toplam öneri:** 20 modül/özellik
- **Öncelik dağılımı:** Yüksek: 7 · Orta: 9 · Düşük: 4
- **Kategori dağılımı:** Kullanıcı Deneyimi: 6 · Güvenlik: 13 · Karma: 1

### En kritik 3 güvenlik açığı

1. **Login endpoint'inde brute-force koruması yok.** `arassaha-backend/routes/auth.js:12` — `express-rate-limit` veya benzeri hiçbir throttling paketi projede yok (`package.json` içinde de yok, node_modules'te de yok). Sicil no + şifre kombinasyonu ağ hızında otomatik denenebilir.
2. **JWT, telefonda düz metin olarak saklanıyor.** `arassaha_flutter/lib/providers/auth_provider.dart:63` — `SharedPreferences.setString(_tokenKey, _token!)`. Proje `flutter_secure_storage` bağımlılığı hiç içermiyor; token 7 gün geçerli ve rol bilgisini taşıyor, rootlu cihazda veya yedekte düz metin okunabilir.
3. **Dosya yüklemede içerik doğrulaması yok, RBAC'ta iki somut boşluk var.** `multer` `fileFilter`'ı yalnızca istemcinin beyan ettiği (sahte olabilecek) `Content-Type`'a bakıyor, dosya uzantısı istemcinin gönderdiği isimden alınıyor ve beyaz listeye tabi değil (`routes/workOrders.js:21-39`, `routes/isg.js:27-46`, `routes/users.js:23-40`) — `.html`/`.svg` gibi dosyalar `image/*` beyanıyla yüklenip `express.static` üzerinden servis edilebilir. Ayrıca `PATCH /api/isg-reports/:id/status` (`routes/isg.js:195`) rol kontrolü olmadan herkese açık, `POST/GET /api/workorders/:id[/photos]` (`routes/workOrders.js:285,459`) ise diğer uçlardaki görünürlük filtresine (`applyVisibilityFilter`) tabi değil — bir teknisyen kendisine atanmamış iş emrini görüp fotoğraf ekleyebiliyor.

### En kritik 3 UX eksiği

1. **Uygulama genelinde hiç onboarding/ilk kullanım rehberi yok.** `lib/` içinde "onboarding/tutorial/walkthrough/first_launch" için sıfır eşleşme. Tek istisna, ArasAI sohbet ekranındaki örnek soru çipleri (`assistant_chat_screen.dart:334-345`) — bu da yalnızca o ekranla sınırlı.
2. **ML çıktılarının (risk skoru, anomali) açıklayıcılığı ekrandan ekrana tutarsız.** Ekipman Detay ekranında risk skoru her zaman bir açıklama cümlesiyle geliyor (`equipment_detail_screen.dart:504-507`), ama aynı skor Ekipman Listesi'nde sadece uzun-basmayla görünen bir tooltip'e (`equipment_list_screen.dart:464-465`), Dashboard'daki "Riskli Ekipman" kartında ise hiçbir açıklama olmadan çıplak bir sayıya (`dashboard_screen.dart:535-582`) düşüyor. Ayrıca kod yorumlarında defalarca geçen "modeller sentetik veriyle eğitildi" dürüstlük notu (`equipment_detail_screen.dart:420-422` ve diğerleri) hiçbir ekranda kullanıcıya gösterilmiyor — İSG hasar rozetindeki bilgi ikonu (`isg_report_detail_screen.dart:272-289`) bunun tek istisnası.
3. **Filtrelenmiş liste boş durumları jenerik ve yol göstermiyor.** İş Emirleri, Ekipman Listesi, Bakım Önerileri gibi 2-4 filtre çipine sahip ekranlarda boş sonuç geldiğinde sadece "Bu filtreye uyan X yok." / "Kayıt bulunamadı" yazıyor (`work_order_list_screen.dart:227`, `equipment_list_screen.dart:109`, `maintenance_recommendations_screen.dart:257-290`) — filtreyi temizlemesi gerektiği kullanıcıya hiç söylenmiyor, bu da "hiç veri yok mu yoksa filtre mi çok dar" belirsizliğine yol açıyor.

### Teslim edilen dosyalar

- `MODUL_ONERILERI.md` (bu dosya) — tam analiz + öneriler
- `trello_import.csv` — Trello'ya import edilecek 20 kart (Liste = Öncelik, Etiket = Kategori)

Her ikisi de proje kök dizininde: `c:\Users\nisac\ArasSaha\`

---

## AŞAMA 1 — Kullanıcı Deneyimi ve Açıklayıcılık Bulguları

### Genel / Çapraz kesen bulgular

- **Onboarding tamamen yok.** Yeni bir teknisyen uygulamayı ilk açtığında ArasAI, Risk Tahmini rozetleri, QR tarama gibi özellikleri deneme-yanılmayla öğrenmek zorunda.
- **Hata mesajları genelde iyi ve spesifik** — `lib/services/api_service.dart` içindeki `ApiException` + `_extractError()` deseni, backend'den gelen Türkçe mesajı tercih edip endpoint'e özel fallback kullanıyor (ör. `'İş emri oluşturulamadı.'`). Tek tekrar eden zayıflık: ağ hatalarında ham `Exception` metni kullanıcıya sızıyor — `'Sunucuya bağlanılamadı: $e'` deseni `api_service.dart:138` ve dosya genelinde ~40 kez tekrarlanıyor (ör. `SocketException: Failed host lookup...` gibi teknik metin doğrudan ekrana düşebiliyor).
- **Form rehberliği genel olarak iyi** — çoğu formda (İş Emri Oluştur, İSG Bildirimi, Malzeme Oluştur, Kullanıcı Düzenle) hintText/helperText ve alan kısıtlarını açıklayan satırlar mevcut. İSG formundaki konum izni hata ayrımı (`isg_report_form_screen.dart:106-142`, GPS kapalı / izin reddedildi / kalıcı reddedildi / genel hata için 4 ayrı mesaj + "Ayarları Aç" butonu) uygulamadaki en iyi örnek.

### Ekran bazlı öne çıkan bulgular

| Ekran | Bulgu | Etki |
|---|---|---|
| Login (`login_screen.dart`) | Ağ hatasında ham exception metni gösteriliyor (satır 138); Sicil No alanında format ipucu yok | Teknik olmayan kullanıcı hata mesajını anlamıyor |
| İş Emirleri Liste (`work_order_list_screen.dart:227`) | Boş durum sadece "Kayıt bulunamadı", 5 filtre çipi var ama temizleme önerisi yok | Kullanıcı "hiç iş emri yok" ile "filtre çok dar" ayrımını yapamıyor |
| İş Emri Detay (`work_order_detail_screen.dart`) | `_RiskContextNote` (441-502), offline blok mesajları (715-724), senkron bekliyor rozeti (667-703) — **iyi örnekler** | — |
| İş Emri Oluştur (`create_work_order_screen.dart`) | AI sınıflandırma önerisi "(yapay zeka önerisi)" etiketiyle açık şekilde ayrıştırılmış (562-569); ML servis kapalıyken kullanıcı formu yine de doldurabileceği konusunda bilgilendiriliyor (288-296) — **iyi örnek** | — |
| ArasAI Sohbet (`assistant_chat_screen.dart`) | Geçmiş yükleme hatasında retry butonu yok (274-286), gönderme hatası düşük görünürlükte (253-263) | Diğer ekranlardaki tutarlı "Tekrar Dene" deseninden sapma |
| Ekipman Detay / Liste / Dashboard | Risk skoru açıklayıcılığı ekrana göre tutarsız (bkz. kritik bulgu #2) | Aynı veri farklı ekranlarda farklı güven seviyesiyle sunuluyor |
| Şüpheli Sayaçlar (`suspicious_meters_screen.dart`) | Anomali rozeti (üçgen ikon) ile risk rozetinin (daire) farkı sadece kod yorumunda açıklanmış, UI'da değil | Kullanıcı iki farklı ML özelliğini karıştırabilir |
| QR Tarayıcı (`qr_scanner_screen.dart`) | Kamera izni reddedildiğinde sistem ayarlarına yönlendiren buton yok (İSG'deki `openAppSettings` deseninden farklı) | Tutarsız izin-kurtarma deneyimi |

---

## AŞAMA 2 — Güvenli Yazılım Geliştirme Bulguları (OWASP Mobile/API Top 10 referanslı)

| Alan | Bulgu | Dosya:Satır |
|---|---|---|
| Kimlik doğrulama | JWT 7 gün geçerli, refresh mekanizması yok; 401'de otomatik logout var (iyi) | `routes/auth.js:12-45`, `auth_provider.dart:20-25` |
| Token saklama | **Düz metin** `SharedPreferences`, `flutter_secure_storage` projede yok | `auth_provider.dart:63,88-89,112-113` |
| Brute-force | Rate limiting **yok** — hiçbir throttling paketi kurulu değil | proje geneli (`package.json` + grep) |
| Girdi doğrulama | Örneklenen 4 endpoint'te (iş emri, İSG, malzeme, kullanıcı) elle yazılmış ama sağlam whitelist/tip kontrolü var | `routes/workOrders.js:153-235`, `routes/isg.js:119-190`, `routes/materials.js:371-463`, `routes/users.js:157-212` |
| Dosya yükleme | Boyut limiti var (10MB/5MB), dosya adı path traversal'a kapalı (server-üretimi isim); **ancak** MIME sadece istemci beyanına dayanıyor, uzantı whitelist'i yok | `routes/workOrders.js:21-39`, `routes/isg.js:27-46`, `routes/users.js:23-40` |
| Log/hata sızıntısı | Route'lar içindeki `catch` blokları jenerik Türkçe mesaj döndürüyor (iyi); ama global bir Express error-handler yok ve `NODE_ENV` hiç kullanılmıyor — yakalanmayan hatalarda Express'in varsayılan handler'ı stack trace döndürebilir | `server.js` (global handler yok), proje geneli grep |
| RBAC | `İSG durum güncelleme` (rol kontrolü eksik) ve `İş Emri detay/foto` (görünürlük filtresi eksik) dışında tarama edilen tüm state-changing endpoint'ler doğru korunuyor | `routes/isg.js:195`, `routes/workOrders.js:285,459` |
| KVKK | Ad, telefon, e-posta, sicil no, profil/İSG/iş emri fotoğrafları, GPS konumu, cihaz telemetrisi, sohbet logları toplanıyor; **hiçbir** KVKK/GDPR referansı, saklama süresi politikası veya kullanıcı veri silme talebi akışı yok; kullanıcı silme sadece `is_active=0` soft-delete, dosyalar diskte kalıcı olarak kalıyor (`fs.unlink` hiç çağrılmıyor) | `database.js` (şema), `routes/users.js:424-449` |
| Bağımlılıklar | Backend `npm audit`: **0 açık**. Flutter: güncel sürümler, `flutter_secure_storage` eksik. ML: sadece `tensorflow==2.18.0` pinlenmiş, diğer tüm paketler pin'siz (reproducibility riski) | `arassaha-backend/package.json`, `arassaha_flutter/pubspec.yaml`, `arassaha-ml/requirements.txt` |
| CI/CD | `.github/workflows` yok, `.railway/` boş, Dependabot/Snyk/npm audit hiçbir pipeline'a bağlı değil | proje kökü taraması |

---

## AŞAMA 3 — Modül/Özellik Önerileri

Öncelik ve efor tahminleriyle birlikte tam liste aşağıda; Trello'ya aktarılabilir hali `trello_import.csv` içinde.

### Kullanıcı Deneyimi

**1. Uygulama İçi Onboarding / İlk Kullanım Rehberi**
İlk girişte 4-5 adımlık, atlanabilir bir tur (ArasAI, risk rozetleri, QR tarama, İSG bildirimi gibi karmaşık özellikleri tek cümlelik açıklamalarla tanıtan overlay/tooltip dizisi). `shared_preferences`'ta bir `has_seen_onboarding` bayrağıyla tetiklenir.
*Dayanak:* Aşama 1 — onboarding sıfır, kritik bulgu #1.
*Öncelik:* Yüksek · *Efor:* Orta (3-5 gün)

**2. Filtrelenmiş Liste Boş Durumu İyileştirmesi**
İş Emirleri, Ekipman Listesi ve Bakım Önerileri ekranlarındaki jenerik "Bu filtreye uyan X yok" mesajlarını, aktif filtreleri özetleyen ve tek dokunuşla temizleyen bir aksiyon içeren ortak bir `EmptyState` bileşenine dönüştür.
*Dayanak:* Aşama 1 — kritik bulgu #3.
*Öncelik:* Orta · *Efor:* Küçük (1-2 gün)

**3. ML Çıktıları İçin Tutarlı Bağlamsal Yardım Katmanı**
Risk skoru, anomali tespiti ve hasar olasılığı gösterilen HER ekranda (Dashboard, Ekipman Listesi, Ekipman Detay, Şüpheli Sayaçlar) aynı bilgi ikonu + açıklama deseni kullanılsın; modelin sentetik veriyle eğitildiğine dair "dürüstlük notu" kod yorumlarından çıkıp kullanıcıya (en azından yöneticilere) gösterilsin. İSG hasar rozetindeki mevcut desen (`isg_report_detail_screen.dart:272-289`) referans alınabilir.
*Dayanak:* Aşama 1 — kritik bulgu #2.
*Öncelik:* Yüksek · *Efor:* Orta (3-5 gün)

**4. Kullanıcı Dostu Ağ Hatası Mesajları**
`api_service.dart` genelinde tekrarlanan `'Sunucuya bağlanılamadı: $e'` deseni, ham exception metnini göstermek yerine sabit, anlaşılır bir mesaja ("İnternet bağlantınızı kontrol edin ve tekrar deneyin.") çevrilsin; teknik detay sadece debug modda loglansın.
*Dayanak:* Aşama 1 — çapraz kesen bulgu, `api_service.dart:138` ve ~40 tekrar.
*Öncelik:* Orta · *Efor:* Küçük (1-2 gün)

**5. ArasAI Sohbet Hata/Retry Tutarlılığı**
Sohbet geçmişi yükleme hatasına diğer ekranlardaki gibi görünür bir "Tekrar Dene" butonu eklensin; gönderme hatası caption yerine ikonlu/daha görünür bir uyarı olarak gösterilsin.
*Dayanak:* Aşama 1 — ArasAI Sohbet ekranı bulguları.
*Öncelik:* Düşük · *Efor:* Küçük (1-2 gün)

**6. QR Tarayıcı İzin Akışı Tutarlılığı**
Kamera izni reddedildiğinde İSG formundaki (`Geolocator.openAppSettings`) desene paralel olarak doğrudan sistem ayarlarını açan bir buton eklensin.
*Dayanak:* Aşama 1 — QR Tarayıcı ekranı bulgusu.
*Öncelik:* Düşük · *Efor:* Küçük (1-2 gün)

### Karma

**7. Kapsamlı Hata Mesajı ve Boş Durum Standardizasyonu (Tasarım Sistemi)**
2, 4 ve 5 numaralı öğeleri kapsayan şemsiye bir çalışma: tüm hata/boş durum bileşenleri tek bir paylaşılan widget setine taşınsın; bu set hem daha açıklayıcı olacak hem de hiçbir zaman ham exception/stack trace metni kullanıcıya sızdırmayacak şekilde tasarlanacak (UX + güvenlik/log sızıntısı önleme kesişimi).
*Dayanak:* Aşama 1 (tutarsız hata dili) + Aşama 2 (hassas/teknik veri sızıntısı riski).
*Öncelik:* Orta · *Efor:* Orta (3-5 gün)

### Güvenlik

**8. Giriş Denemesi Sınırlama (Rate Limiting / Brute-force Koruması)**
`POST /api/auth/login`'e `express-rate-limit` ile IP+sicil_no bazlı deneme sınırı (ör. 5 deneme / 15 dakika) ve kısa süreli hesap kilidi eklensin.
*Dayanak:* Aşama 2 — kritik güvenlik açığı #1, `routes/auth.js:12`.
*Öncelik:* Yüksek · *Efor:* Küçük (1-2 gün)

**9. Güvenli Token Saklama (flutter_secure_storage Geçişi)**
JWT'nin `SharedPreferences` yerine Android Keystore/iOS Keychain destekli `flutter_secure_storage`'da saklanmasına geçilsin.
*Dayanak:* Aşama 2 — kritik güvenlik açığı #2, `auth_provider.dart:63`.
*Öncelik:* Yüksek · *Efor:* Orta (3-5 gün, mevcut oturumların migration'ı dahil)

**10. RBAC Boşluklarının Kapatılması**
`PATCH /api/isg-reports/:id/status`'a `requireRole('dispecer','yonetici')` eklensin; `GET /api/workorders/:id` ve `POST /api/workorders/:id/photos` diğer uçlarda kullanılan `applyVisibilityFilter`/atanma kontrolüne tabi tutulsun.
*Dayanak:* Aşama 2 — kritik güvenlik açığı #3, `routes/isg.js:195`, `routes/workOrders.js:285,459`.
*Öncelik:* Yüksek · *Efor:* Küçük (1-2 gün)

**11. Dosya Yükleme İçerik Doğrulama Sıkılaştırma**
Multer `fileFilter`'ları, istemci beyanına ek olarak dosyanın gerçek baytlarını (magic number) doğrulasın; kaydedilen uzantı istemci dosya adından değil, doğrulanmış MIME tipinden türetilsin; `/uploads` statik rotasına `X-Content-Type-Options: nosniff` ve `Content-Disposition` başlıkları eklensin.
*Dayanak:* Aşama 2 — kritik güvenlik açığı #3, `routes/workOrders.js:21-39`, `routes/isg.js:27-46`, `routes/users.js:23-40`.
*Öncelik:* Yüksek · *Efor:* Orta (3-5 gün)

**12. Merkezi Hata Yönetimi ve Prodüksiyon Sertleştirmesi**
`server.js`'in sonuna global bir Express error-handling middleware eklensin (stack trace'i asla client'a döndürmeyen); Railway dağıtım ortamında `NODE_ENV=production` açıkça set edilsin ve kodda doğrulansın.
*Dayanak:* Aşama 2 — log/hata sızıntısı bulgusu.
*Öncelik:* Orta · *Efor:* Küçük (1-2 gün)

**13. KVKK Uyum Modülü (Veri Saklama Politikası + Veri Silme Talebi)**
Kullanıcıya (veya yöneticiye onun adına) kişisel verilerinin (fotoğraflar, konum geçmişi, sohbet logları) neler olduğunu gösteren ve silme talebi başlatabileceği bir ekran; arka planda talep onaylandığında ilişkili fotoğraf dosyalarını diskten silen ve/veya anonimleştiren bir iş akışı; aydınlatma metni ekranı.
*Dayanak:* Aşama 2 — KVKK bulgusu, sıfır KVKK/GDPR referansı, `fs.unlink` hiç çağrılmıyor.
*Öncelik:* Yüksek · *Efor:* Büyük (1 haftadan fazla)

**14. Otomatik Dosya Temizleme / Orphan Upload Purge Job**
Kullanıcı/iş emri/İSG kaydı deaktive edildiğinde veya belirlenen bir saklama süresi (ör. 2 yıl) dolduğunda ilişkili yüklenmiş dosyaları diskten temizleyen zamanlanmış bir görev (13 numaralı KVKK modülünün teknik alt bileşeni, ama tek başına da devreye alınabilir).
*Dayanak:* Aşama 2 — KVKK bulgusu, `fs.unlink`/`fs.rm` grep sonucu sıfır.
*Öncelik:* Orta · *Efor:* Küçük (1-2 gün)

**15. Merkezi Güvenlik/Denetim Logu Paneli**
Yönetici rolü için, hangi kullanıcının ne zaman hangi state-changing işlemi (giriş, rol değişikliği, iş emri atama, malzeme silme, cihaz uzaktan silme vb.) yaptığını gösteren merkezi bir log görüntüleme ekranı — bazı modüllerde (cihaz yönetimi, kullanıcı işlemleri) kayıt zaten tutuluyor, bunları tek ekranda birleştir.
*Dayanak:* Aşama 2 — RBAC/denetlenebilirlik ihtiyacı, kullanıcının önerdiği yön listesi.
*Öncelik:* Orta · *Efor:* Orta (3-5 gün)

**16. Yönetici Hesapları İçin İki Faktörlü Kimlik Doğrulama (2FA)**
`yonetici` rolündeki hesaplar için girişte SMS/e-posta OTP veya TOTP tabanlı ikinci faktör eklensin — en yüksek yetkiye sahip hesaplar brute-force/token çalınması senaryolarında ekstra korumaya sahip olsun.
*Dayanak:* Aşama 2 — kimlik doğrulama zafiyetleri (#8, #9) için savunma derinliği.
*Öncelik:* Orta · *Efor:* Orta (3-5 gün)

**17. CI/CD Bağımlılık Güvenlik Taraması**
Backend için `npm audit --audit-level=high`, ML servisi için `pip-audit`, Flutter için `flutter pub outdated`/Dependabot; bunları GitHub Actions'a (veya mevcut Railway deploy akışına) bir gate olarak ekle. Şu an hiçbir pipeline'da otomatik tarama yok.
*Dayanak:* Aşama 2 — CI/CD bulgusu, `.github/workflows` yok, Dependabot yok.
*Öncelik:* Orta · *Efor:* Küçük (1-2 gün)

**18. ML Servisi Bağımlılık Sabitleme**
`arassaha-ml/requirements.txt`'teki `tensorflow` dışındaki tüm paketler (`fastapi`, `uvicorn`, `scikit-learn`, `pandas`, `numpy`, `pillow` vb.) `==` ile pinlensin ve bir lockfile (`pip-compile`) eklensin; her Docker build'de rastgele en güncel sürümün çekilmesi engellenmiş olur.
*Dayanak:* Aşama 2 — bağımlılık taraması, ML requirements.txt neredeyse tamamen pin'siz.
*Öncelik:* Düşük · *Efor:* Küçük (1-2 gün)

**19. Malzeme Kullanım Kaydı Sahiplik Kontrolü**
`POST /api/workorders/:workOrderId/materials` şu an herhangi bir teknisyenin kendisine atanmamış bir iş emrine malzeme kaydı işlemesine izin veriyor (bilinçli tasarım kararı olarak yorumlanmış ama denetlenebilirlik açısından zayıf); en azından işlemi yapan kullanıcının kimliği/rolü kayda daha belirgin şekilde düşürülsün ya da atanmamış iş emirlerinde bir uyarı/onay adımı eklensin.
*Dayanak:* Aşama 2 — RBAC taraması, `routes/materials.js:371` küçük BOLA riski.
*Öncelik:* Düşük · *Efor:* Küçük (1-2 gün)

**20. JWT Süresi Kısaltma + Refresh Token Mekanizması**
Access token ömrü 7 günden (ör.) 1-2 saate indirilsin; kullanıcı deneyimini bozmadan oturumu canlı tutmak için ayrı, daha uzun ömürlü ve `flutter_secure_storage`'da saklanan bir refresh token akışı eklensin. Bu, çalınan bir token'ın kullanım penceresini büyük ölçüde daraltır.
*Dayanak:* Aşama 2 — kimlik doğrulama/oturum güvenliği bulgusu, `routes/auth.js:12-45` (7 günlük token, refresh yok).
*Öncelik:* Orta · *Efor:* Orta (3-5 gün)

---

## Ek: Öncelik/Efor Matrisi

| # | Modül | Kategori | Öncelik | Efor |
|---|---|---|---|---|
| 1 | Onboarding / İlk Kullanım Rehberi | UX | Yüksek | Orta |
| 2 | Filtrelenmiş Boş Durum İyileştirmesi | UX | Orta | Küçük |
| 3 | ML Çıktıları Bağlamsal Yardım Katmanı | UX | Yüksek | Orta |
| 4 | Kullanıcı Dostu Ağ Hatası Mesajları | UX | Orta | Küçük |
| 5 | ArasAI Sohbet Hata/Retry Tutarlılığı | UX | Düşük | Küçük |
| 6 | QR Tarayıcı İzin Akışı Tutarlılığı | UX | Düşük | Küçük |
| 7 | Hata/Boş Durum Standardizasyonu | Karma | Orta | Orta |
| 8 | Giriş Denemesi Sınırlama | Güvenlik | Yüksek | Küçük |
| 9 | Güvenli Token Saklama | Güvenlik | Yüksek | Orta |
| 10 | RBAC Boşluklarının Kapatılması | Güvenlik | Yüksek | Küçük |
| 11 | Dosya Yükleme İçerik Doğrulama | Güvenlik | Yüksek | Orta |
| 12 | Merkezi Hata Yönetimi / Prod Sertleştirme | Güvenlik | Orta | Küçük |
| 13 | KVKK Uyum Modülü | Güvenlik | Yüksek | Büyük |
| 14 | Otomatik Dosya Temizleme | Güvenlik | Orta | Küçük |
| 15 | Merkezi Güvenlik/Denetim Logu Paneli | Güvenlik | Orta | Orta |
| 16 | Yönetici 2FA | Güvenlik | Orta | Orta |
| 17 | CI/CD Bağımlılık Taraması | Güvenlik | Orta | Küçük |
| 18 | ML Servisi Bağımlılık Sabitleme | Güvenlik | Düşük | Küçük |
| 19 | Malzeme Kaydı Sahiplik Kontrolü | Güvenlik | Düşük | Küçük |
| 20 | JWT Süresi Kısaltma + Refresh Token | Güvenlik | Orta | Orta |
