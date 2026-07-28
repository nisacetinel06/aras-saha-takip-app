# ArasSaha — Mimari Planlama Dokümanı

> **Proje:** ArasSaha — Aras EDAŞ saha ekipleri için staj prototip mobil uygulaması
> **Kapsam:** Arıza/iş emri takibi, harita, ekipman envanteri (QR), İSG bildirimi, bildirimler, raporlar
> **Not:** Bu doküman planlama aşamasıdır. Rastgele/sahte (mock/seed) veriyle çalışılacak, gerçek Aras EDAŞ üretim sistemlerine bağlanılmayacaktır.

---

## Temel Kalite İlkesi (Tüm Modüller İçin Geçerli)

**"Sahte veri" ≠ "sahte işlevsellik".** Bu proje rastgele/mock veriyle çalışan bir staj prototipidir, ancak bu, özelliklerin eksik veya yarım çalışabileceği anlamına gelmez. Uygulanan her özellik uçtan uca **eksiksiz ve doğru** çalışmalıdır:

- **Veri içeriği sahte olabilir:** Rastgele isimler, uydurma konumlar, sahte ekipman numaraları — bunlar gerçek Aras EDAŞ verisi değildir ve olmak zorunda değildir.
- **Veri akışı/mekanizması sahte OLAMAZ:** Bir özellik "varmış gibi" davranıp aslında çalışmıyor olamaz. Somut örnek: Bir saha teknisyeni bir iş emrine fotoğraf eklediğinde, bu fotoğraf backend'de gerçekten saklanmalı ve o iş emrine bakan **başka bir kullanıcı/cihaz** (örn. saha amiri, dispeçer) bu fotoğrafı görebilmelidir. Uygulama kapatılıp yeniden açıldığında ya da farklı bir cihazdan bağlanıldığında bu veri **kaybolmamalı veya erişilemez hale gelmemelidir**.
- Bu ilke; fotoğraf/dosya ekleme, durum güncelleme, İSG bildirimi, bildirimler — kısacası kullanıcının "bir şey kaydettim" dediği **her** özellik için geçerlidir. Sunucu tarafında kalıcı olarak saklanmayan ve tüm yetkili kullanıcılar tarafından erişilebilir olmayan bir "kayıt" özelliği eksik/hatalı sayılır.
- Bölüm 10'daki kısıtlamalar yalnızca **altyapısal gerçekçilik** (gerçek bulut servisleri, OS seviyesinde push bildirim, üretim ölçeği vb.) ile ilgilidir; bu kısıtlamalar bir özelliğin temel işlevini (kaydet → kalıcı sakla → yetkili herkese göster) atlamak için gerekçe olarak kullanılamaz.

---

## 1. Genel Sistem Mimarisi

Uygulama, birbirinden bağımsız üç katmandan oluşan klasik bir **istemci–sunucu–veritabanı** mimarisi kullanır:

```
+----------------------+        HTTP/JSON (REST)        +---------------------------+        SQL         +-------------------------+
|   Flutter Mobil Uygulama   | <---------------------------> |  Node.js + Express API   | <-----------------> |   SQLite Veritabanı     |
|  (Android/iOS istemci)     |     fetch/http paketi          |  (iş mantığı, doğrulama) |   better-sqlite3     |  (arassaha.db dosyası)  |
+----------------------+                                  +---------------------------+                     +-------------------------+
        |                                                            |                                                |
        | - UI / ekranlar                                            | - Route/Controller katmanı                    | - Kalıcı veri
        | - State management (Provider)                              | - Servis/iş mantığı katmanı                   | - Tek dosya, sunucuyla
        | - Yerel önbellek (basit)                                   | - SQLite erişim katmanı                       |   aynı dizinde durur
        | - QR okuma, konum, fotoğraf seçimi (cihaz API'leri)         | - Basit doğrulama ve hata yönetimi            |
+----------------------+                                  +---------------------------+                     +-------------------------+
```

**Veri akışı özeti:**
1. Kullanıcı Flutter uygulamasında bir ekranı açar (örn. iş emri listesi).
2. İlgili `Provider`, `ApiService` üzerinden Express API'sine HTTP isteği gönderir.
3. Express, isteği ilgili route/controller'a yönlendirir, iş mantığını çalıştırır ve `better-sqlite3` ile SQLite dosyasına sorgu atar.
4. Sonuç JSON olarak Flutter'a döner, Provider state'i günceller, UI yeniden çizilir.

**Neden SQLite?**
- **Kurulum gerektirmez:** Ayrı bir veritabanı sunucusu (PostgreSQL/MySQL servisi vb.) kurup yönetmeye gerek yoktur; `better-sqlite3` paketi Node.js sürecinin içinde çalışır.
- **Dosya tabanlıdır:** Tüm veritabanı tek bir `.db` dosyasıdır; yedekleme, sıfırlama veya farklı bir bilgisayara taşıma tek dosya kopyalamaktan ibarettir — staj ortamı ve demo sunumları için idealdir.
- **Prototip için yeterlidir:** Beklenen kullanıcı sayısı ve veri hacmi çok düşük (birkaç sahte teknisyen, birkaç yüz iş emri); SQLite'ın eşzamanlılık ve ölçek sınırları bu senaryoda hiçbir zaman sorun teşkil etmez.

---

## 2. Teknoloji Yığını (Tech Stack)

| Katman | Teknoloji | Seçim Gerekçesi |
|---|---|---|
| Mobil | **Flutter (Dart)** | Tek kod tabanıyla Android/iOS desteği, zengin widget kütüphanesi, hızlı prototipleme. |
| Backend | **Node.js + Express** | Hafif, hızlı kurulan, JSON tabanlı REST API'ler için endüstri standardı; JavaScript/TypeScript ile hızlı geliştirme. |
| Veritabanı | **SQLite (better-sqlite3)** | Kurulumsuz, dosya tabanlı, senkron API'si sayesinde basit ve hatasız sorgu yazımı (bkz. Bölüm 1). |
| State Management | **Provider** | Flutter'ın resmi olarak önerdiği, öğrenme eğrisi düşük, orta ölçekli uygulamalar için yeterli ve yaygın kullanılan bir state management çözümü. |
| Harita | **flutter_map** | Google Maps API anahtarı ve faturalandırma gerektirmez (OpenStreetMap tile'ları kullanır); bir staj prototipinde API key yönetimi/billing derdi olmadan harita gösterimi sağlar. `google_maps_flutter` yerine tercih edilmiştir. |
| QR Okuma | **mobile_scanner** | Aktif geliştirilen, hızlı ve güncel bir Flutter QR/barkod tarama paketi; ekipman etiketlerini okumak için kullanılacaktır. |
| Grafik | **fl_chart** | Raporlar/analitik ekranında bölgeye ve ekipman türüne göre dağılım grafiklerini (bar/pie chart) çizmek için esnek ve yaygın kullanılan bir Flutter grafik kütüphanesi. |
| Fotoğraf | **image_picker** | İş emri ve İSG bildirimlerine kamera veya galeriden fotoğraf eklemek için standart Flutter çözümü. |

---

## 3. Modül Listesi ve Öncelik Sırası

30 iş günlük (6 haftalık) staj planına göre dağıtılmıştır. **Hafta 1** ortak altyapı kurulumuna ayrılmıştır (proje iskeleti, veritabanı şeması, seed script, API iskeleti, Flutter proje kurulumu, auth ekranı).

| # | Modül | Amaç | Öncelik | Hafta |
|---|---|---|---|---|
| — | **Altyapı Kurulumu** | Flutter ve Node.js proje iskeletlerinin oluşturulması, SQLite şemasının kurulması, sahte veri (seed) üretimi, temel auth akışının hazırlanması. | — | Hafta 1 |
| 1 | **İş Emri / Arıza Yönetimi** | Saha ekiplerinin kendilerine atanan arıza/iş emirlerini görüntülemesi, durumunu güncellemesi ve fotoğraf eklemesi; uygulamanın çekirdek işlevi. | Çekirdek (Zorunlu) | Hafta 2 |
| 2 | **Dashboard / Ana Sayfa** | Kullanıcıya giriş sonrası özet bilgi (açık arıza sayısı, bugün çözülenler, ortalama çözüm süresi) sunarak uygulamanın ilk izlenimini oluşturur. | Zorunlu (İlk İzlenim) | Hafta 3 |
| 3 | **Harita / Konum Görselleştirme** | Açık iş emirlerini harita üzerinde konumlarıyla göstererek saha ekiplerinin coğrafi durum farkındalığını artırır. | Yüksek | Hafta 3 |
| 4 | **Ekipman / Envanter (QR Kod)** | Saha ekipmanlarının (trafo, direk, sayaç vb.) QR kod ile hızlıca tanımlanmasını ve geçmiş arıza/bakım kayıtlarının görüntülenmesini sağlar. | Orta-Yüksek | Hafta 4 |
| 5 | **İSG Bildirimi** | Sahada tespit edilen iş sağlığı ve güvenliği risklerinin fotoğraf ve konumla birlikte hızlıca raporlanmasını sağlar. | Orta | Hafta 4 |
| 6 | **Bildirimler / Push Notification Simülasyonu** | Kullanıcıya yeni atanan iş emri veya İSG bildirim durumu değişikliği gibi olayları uygulama içi bildirim listesiyle simüle eder. | Düşük-Orta | Hafta 5 |
| 7 | **Raporlar / Analitik Sayfası** | Bölgeye ve ekipman türüne göre arıza dağılımını grafiklerle görselleştirerek yönetici/dispeçer rolüne özet sunar. | Düşük-Orta | Hafta 5 |
| 8 | **Profil / Ayarlar / Çevrimdışı Mod** | Kullanıcı profil bilgisi, uygulama ayarları ve çevrimdışı durumun arayüzde simüle edilmesi. | En Düşük | Hafta 6 |
| — | **Genel Test / Sunum Hazırlığı** | Uçtan uca test, hata düzeltme, demo senaryosu ve sunum materyali hazırlığı. | — | Hafta 6 |

---

## 4. Veritabanı Şeması

### 4.1 Tablolar

**`users`** — Kullanıcılar (Modül: Auth / tüm modüller)
| Alan | Tip | Açıklama |
|---|---|---|
| id | INTEGER PK | Otomatik artan kimlik |
| name | TEXT | Ad soyad |
| role | TEXT | `teknisyen` \| `dispecer` \| `yonetici` |
| sicil_no | TEXT UNIQUE | Personel sicil numarası (giriş için kullanılır) |
| password_hash | TEXT | Şifrenin hash'lenmiş hâli |

> **Zorunlu kural:** "Kişiler" (personel/teknisyen listesi) uygulamanın hiçbir katmanında (backend kodu, Flutter kodu, seed script'i hariç) sabit kodlanmış (hardcoded) bir isim dizisi olarak tutulamaz. Personel bilgisi yalnızca bu `users` tablosundan, gerçek bir API endpoint'i (`GET /api/users`) üzerinden okunur. Seed script'i (`seed.js`) bu tabloyu rastgele isimlerle doldurabilir — bu "sahte veri" ilkesine uygundur — ama uygulama çalışırken kişi listesi her zaman veritabanından çekilir, koda gömülü olamaz. Bkz. Bölüm 11.

**`work_orders`** — İş emirleri (Modül 1)
| Alan | Tip | Açıklama |
|---|---|---|
| id | INTEGER PK | Otomatik artan kimlik |
| title | TEXT | İş emri başlığı |
| description | TEXT | Detaylı açıklama |
| status | TEXT | `acik` \| `atandi` \| `devam_ediyor` \| `cozuldu` \| `iptal` |
| priority | TEXT | `dusuk` \| `orta` \| `yuksek` \| `acil` |
| location_name | TEXT | Konum adı (mahalle/sokak vb.) |
| lat | REAL | Enlem |
| lng | REAL | Boylam |
| assigned_user_id | INTEGER FK | Atanan teknisyen — `users.id`'ye referans veren gerçek bir foreign key olmalı, serbest metin (isim string'i) OLAMAZ |
| equipment_id | INTEGER FK NULL | İlişkili ekipman (varsa) |
| created_at | TEXT (ISO 8601) | Oluşturulma zamanı |
| updated_at | TEXT (ISO 8601) | Son güncellenme zamanı |

**`work_order_photos`** — İş emri fotoğrafları (Modül 1)
| Alan | Tip | Açıklama |
|---|---|---|
| id | INTEGER PK | Otomatik artan kimlik |
| work_order_id | INTEGER FK | İlişkili iş emri |
| photo_path | TEXT | Fotoğrafın (simüle edilmiş) yolu/URL'i |
| created_at | TEXT (ISO 8601) | Eklenme zamanı |

**`equipment`** — Ekipman envanteri (Modül 4)
| Alan | Tip | Açıklama |
|---|---|---|
| id | INTEGER PK | Otomatik artan kimlik |
| qr_code | TEXT UNIQUE | QR koda gömülü benzersiz kod |
| type | TEXT | Ekipman türü (trafo, direk, sayaç, kesici vb.) |
| serial_no | TEXT | Seri numarası |
| install_date | TEXT (ISO 8601) | Kurulum tarihi |
| last_maintenance_date | TEXT (ISO 8601) NULL | Son bakım tarihi |
| location_name | TEXT | Konum adı |
| lat | REAL | Enlem |
| lng | REAL | Boylam |

**`equipment_history`** — Ekipman geçmişi (Modül 4)
| Alan | Tip | Açıklama |
|---|---|---|
| id | INTEGER PK | Otomatik artan kimlik |
| equipment_id | INTEGER FK | İlişkili ekipman |
| work_order_id | INTEGER FK NULL | İlişkili iş emri (varsa) |
| event_description | TEXT | Olay açıklaması (arıza, bakım vb.) |
| created_at | TEXT (ISO 8601) | Kayıt zamanı |

**`isg_reports`** — İSG bildirimleri (Modül 5)
| Alan | Tip | Açıklama |
|---|---|---|
| id | INTEGER PK | Otomatik artan kimlik |
| user_id | INTEGER FK | Bildirimi oluşturan kullanıcı |
| description | TEXT | Risk/olay açıklaması |
| photo_path | TEXT NULL | Fotoğraf yolu (simüle) |
| lat | REAL | Enlem |
| lng | REAL | Boylam |
| status | TEXT | `bekliyor` \| `incelendi` |
| created_at | TEXT (ISO 8601) | Oluşturulma zamanı |

**`notifications`** — Bildirimler (Modül 6)
| Alan | Tip | Açıklama |
|---|---|---|
| id | INTEGER PK | Otomatik artan kimlik |
| user_id | INTEGER FK | Bildirimin hedef kullanıcısı |
| message | TEXT | Bildirim metni |
| related_type | TEXT | `work_order` \| `isg_report` |
| related_id | INTEGER | İlgili kaydın id'si |
| is_read | INTEGER (0/1) | Okunma durumu |
| created_at | TEXT (ISO 8601) | Oluşturulma zamanı |

### 4.2 İlişkiler (Foreign Key'ler)

- `work_orders.assigned_user_id` → `users.id`
- `work_orders.equipment_id` → `equipment.id`
- `work_order_photos.work_order_id` → `work_orders.id`
- `equipment_history.equipment_id` → `equipment.id`
- `equipment_history.work_order_id` → `work_orders.id`
- `isg_reports.user_id` → `users.id`
- `notifications.user_id` → `users.id`
- `notifications.related_id` → `work_orders.id` **veya** `isg_reports.id` (`related_type` alanına göre değişen çoklu-hedefli ilişki; veritabanı düzeyinde tekil bir FK ile zorlanmaz, uygulama katmanında yönetilir)

---

## 5. API Endpoint Listesi

| Modül | Metod | Endpoint | Açıklama | Örnek Request / Response |
|---|---|---|---|---|
| Auth | POST | `/api/auth/login` | Sicil no + şifre ile giriş | Req: `{ "sicil_no": "1234", "password": "..." }` → Res: `{ "token": "...", "user": { "id":1, "name":"...", "role":"teknisyen" } }` |
| Auth | GET | `/api/auth/me` | Giriş yapmış kullanıcının bilgisi | Res: `{ "id":1, "name":"...", "role":"teknisyen" }` |
| İş Emri | GET | `/api/workorders` | Tüm iş emirlerini listele (status, priority, assigned_user_id filtresi destekler) | Res: `[ { "id":1, "title":"...", "status":"acik", ... } ]` |
| İş Emri | GET | `/api/workorders/:id` | Tek iş emri detayı (fotoğraflar dahil) | Res: `{ "id":1, "title":"...", "photos":[...] }` |
| İş Emri | POST | `/api/workorders` | Yeni iş emri oluştur (dispeçer/yönetici) | Req: `{ "title":"...", "lat":..., "lng":..., "assigned_user_id":2 }` |
| İş Emri | PATCH | `/api/workorders/:id/status` | Durum güncelleme | Req: `{ "status": "devam_ediyor" }` |
| İş Emri | POST | `/api/workorders/:id/photos` | Fotoğraf ekleme (simüle path/base64) | Req: `{ "photo_path": "local://..." }` |
| Dashboard | GET | `/api/dashboard/summary` | Özet istatistikler (açık arıza sayısı, bugün çözülen, ort. süre) | Res: `{ "open_count":5, "resolved_today":2, "avg_resolution_hours":3.4 }` |
| Harita | GET | `/api/workorders/map` | Sadece lat/lng ve temel bilgilerle hafif liste | Res: `[ { "id":1, "lat":..., "lng":..., "status":"acik" } ]` |
| Ekipman | GET | `/api/equipment` | Tüm ekipmanları listele (type filtresi destekler) | Res: `[ { "id":1, "qr_code":"EQ-001", ... } ]` |
| Ekipman | GET | `/api/equipment/:qrCode` | QR koduna göre ekipman detayı | Res: `{ "id":1, "qr_code":"EQ-001", "type":"trafo", ... }` |
| Ekipman | GET | `/api/equipment/:id/history` | Ekipmanın geçmiş arıza/bakım kayıtları | Res: `[ { "event_description":"...", "created_at":"..." } ]` |
| İSG | POST | `/api/isg-reports` | Yeni İSG bildirimi oluştur | Req: `{ "description":"...", "lat":..., "lng":..., "photo_path":"..." }` |
| İSG | GET | `/api/isg-reports` | İSG bildirim listesi (status filtresi destekler) | Res: `[ { "id":1, "status":"bekliyor", ... } ]` |
| İSG | GET | `/api/isg-reports/:id` | Tek İSG bildirimi detayı | Res: `{ "id":1, "description":"...", ... }` |
| İSG | PATCH | `/api/isg-reports/:id/status` | Bildirim durumunu güncelle | Req: `{ "status": "incelendi" }` |
| Bildirimler | GET | `/api/notifications` | Kullanıcının bildirimlerini listele | Res: `[ { "id":1, "message":"...", "is_read":0 } ]` |
| Bildirimler | PATCH | `/api/notifications/:id/read` | Okundu işaretle | Res: `{ "id":1, "is_read":1 }` |
| Raporlar | GET | `/api/reports/by-region` | Bölgeye göre arıza dağılımı | Res: `[ { "location_name":"Kepez", "count":12 } ]` |
| Raporlar | GET | `/api/reports/by-equipment-type` | Ekipman türüne göre arıza sıklığı | Res: `[ { "type":"trafo", "count":7 } ]` |
| Profil | GET | `/api/users/:id` | Kullanıcı profil bilgisi | Res: `{ "id":1, "name":"...", "role":"teknisyen" }` |

---

## 6. Flutter Uygulama Klasör Yapısı

Tüm modüller tamamlandığındaki nihai yapı:

```
lib/
  models/
    user.dart
    work_order.dart
    work_order_photo.dart
    equipment.dart
    equipment_history.dart
    isg_report.dart
    notification.dart
  services/
    api_service.dart
    auth_service.dart
  providers/
    auth_provider.dart
    work_order_provider.dart
    equipment_provider.dart
    isg_provider.dart
    notification_provider.dart
    dashboard_provider.dart
  screens/
    auth/
      login_screen.dart
    dashboard/
      dashboard_screen.dart
    work_orders/
      work_order_list_screen.dart
      work_order_detail_screen.dart
    map/
      map_screen.dart
    equipment/
      qr_scan_screen.dart
      equipment_detail_screen.dart
    isg/
      isg_report_form_screen.dart
      isg_report_list_screen.dart
    notifications/
      notification_list_screen.dart
    reports/
      reports_screen.dart
    settings/
      settings_screen.dart
      profile_screen.dart
  widgets/
    work_order_card.dart
    status_badge.dart
    priority_badge.dart
    loading_indicator.dart
    empty_state.dart
  utils/
    constants.dart
    date_formatter.dart
    role_helper.dart
  main.dart
```

---

## 7. Ekran Listesi ve Kullanıcı Akışı

**Genel akış:**
```
Login
  → Dashboard
      → İş Emri Listesi → İş Emri Detay → Fotoğraf Ekle / Durum Güncelle
      → Harita → İş Emri Detay
      → QR Tara (Ekipman) → Ekipman Detay → Ekipman Geçmişi
      → İSG Bildirim Listesi → Yeni İSG Bildirimi Oluştur
      → Bildirimler → İlgili Kayda Git (İş Emri Detay / İSG Bildirim Detay)
      → Raporlar (bölge / ekipman türü grafikleri)
      → Ayarlar → Profil
```

**Modül bazında ekranlar:**
- **Auth:** Login Screen
- **Dashboard:** Dashboard Screen (özet kartlar + hızlı erişim menüsü)
- **İş Emri:** İş Emri Listesi → İş Emri Detay → (Fotoğraf Ekle, Durum Güncelle alt akışları)
- **Harita:** Harita Screen (pin'e tıklayınca İş Emri Detay'a geçiş)
- **Ekipman:** QR Tarama Screen → Ekipman Detay Screen → Ekipman Geçmişi (aynı ekranda liste olarak)
- **İSG:** İSG Bildirim Listesi → Yeni Bildirim Formu (fotoğraf + konum ekleme)
- **Bildirimler:** Bildirim Listesi → tıklanınca ilgili kayda yönlendirme
- **Raporlar:** Raporlar Screen (bölge grafiği + ekipman türü grafiği sekmeli veya alt alta)
- **Profil/Ayarlar:** Ayarlar Screen → Profil Screen, çevrimdışı mod göstergesi (simüle)

---

## 8. Kullanıcı Rolleri ve Yetkilendirme

> Not: Prototipte backend tarafında gerçek/katı yetkilendirme (JWT rol kontrolü vb.) zorunlu değildir; ancak arayüz ve API tasarımı bu ayrımı yansıtacak şekilde kurgulanır.

| Ekran / Endpoint | Teknisyen | Dispeçer | Yönetici |
|---|---|---|---|
| Login | ✅ | ✅ | ✅ |
| Dashboard | ✅ (kendi özeti) | ✅ (genel özet) | ✅ (genel özet) |
| İş Emri Listesi/Detay (görüntüleme) | ✅ (kendine atananlar) | ✅ (tümü) | ✅ (tümü) |
| İş Emri Oluşturma | ❌ | ✅ | ✅ |
| İş Emri Durum Güncelleme | ✅ (kendine atanan) | ✅ | ✅ |
| İş Emri Fotoğraf Ekleme | ✅ | ✅ | ✅ |
| Harita | ✅ | ✅ | ✅ |
| Ekipman QR Tarama / Detay | ✅ | ✅ | ✅ |
| İSG Bildirimi Oluşturma | ✅ | ✅ | ✅ |
| İSG Bildirim Durumu Güncelleme (incelendi) | ❌ | ✅ | ✅ |
| Bildirimler | ✅ (kendi bildirimleri) | ✅ | ✅ |
| Raporlar / Analitik | ❌ | ✅ | ✅ |
| Profil / Ayarlar | ✅ | ✅ | ✅ |

---

## 9. Geliştirme Sırası ve Bağımlılıklar

Geliştirme sırası, modüller arası veri bağımlılıklarına göre belirlenmiştir:

- **İş Emri Yönetimi (Modül 1)** herhangi bir modüle bağımlı değildir; `users` ve temel `work_orders` şeması üzerine kurulur. Bu nedenle ilk geliştirilen modüldür ve diğer tüm modüller doğrudan veya dolaylı olarak buna dayanır.
- **Dashboard (Modül 2)**, özet istatistiklerini `work_orders` tablosundan hesapladığı için Modül 1'e bağımlıdır.
- **Harita (Modül 3)**, `work_orders.lat` / `work_orders.lng` alanlarına bağımlıdır; iş emri verisi olmadan haritada gösterilecek anlamlı bir veri olmaz.
- **Ekipman (Modül 4)**, `work_orders.equipment_id` alanı üzerinden iş emirleriyle ilişkilendirildiği için Modül 1'den sonra gelir; ekipman geçmişi de iş emri kayıtlarını referans alır.
- **İSG Bildirimi (Modül 5)**, veri modeli olarak `users` dışında başka bir modüle bağımlı değildir, ancak öncelik sırası itibarıyla çekirdek iş emri/ekipman akışlarından sonra ele alınması planlanmıştır (staj süresinin ilk yarısı çekirdek işlevlere ayrılmıştır).
- **Bildirimler (Modül 6)**, `related_type` alanı üzerinden hem `work_orders` hem `isg_reports` kayıtlarına referans verdiği için Modül 1 ve Modül 5'in tamamlanmasını gerektirir.
- **Raporlar (Modül 7)**, bölgeye ve ekipman türüne göre dağılım hesapladığı için hem Modül 1 (`work_orders`) hem Modül 4 (`equipment`) verisine bağımlıdır; bu nedenle bu iki modülden sonra geliştirilir.
- **Profil / Ayarlar / Çevrimdışı Mod (Modül 8)**, tüm diğer modüllerden bağımsızdır ve en düşük öncelikli olduğu için son sıraya bırakılmıştır; genel test ve sunum hazırlığıyla aynı haftaya denk gelir.

Bu bağımlılık zinciri, Bölüm 3'teki haftalık dağılımın gerekçesini oluşturur: önce veriyi üreten çekirdek modül (İş Emri), ardından bu veriyi tüketen/gösteren modüller (Dashboard, Harita), sonra ilişkili yan modüller (Ekipman, İSG), en son da bunların üzerine kurulu türetilmiş modüller (Bildirimler, Raporlar) ve bağımsız modüller (Profil/Ayarlar) geliştirilir.

---

## 10. Bilinen Kısıtlamalar / Prototip Notları

Bu uygulama bir **staj prototipidir** ve gerçek üretim sistemine bağlanmaz. Aşağıdaki noktalar, dokümanın başındaki **"Temel Kalite İlkesi"**ni ihlal etmeyecek şekilde, bilinçli olarak basitleştirilmiştir — yani "özellik çalışmıyor" değil, "gerçek bir bulut/altyapı sağlayıcısı kullanılmıyor" anlamına gelirler:

- **Gerçek bulut depolama (S3 vb.) kullanılmaz, ama dosyalar gerçekten ve kalıcı olarak saklanır:** Fotoğraflar backend sunucusunun kendi diskinde (`uploads/` klasörü) tutulur ve statik bir HTTP endpoint'i üzerinden servis edilir. Mobil istemci fotoğrafı backend'e gerçekten yükler (multipart/form-data); `work_order_photos.photo_path` alanında cihaza özel bir yerel yol değil, backend'in servis ettiği bir URL/dosya adı tutulur. Böylece bir kullanıcının eklediği fotoğraf, **her cihazdan/kullanıcıdan** (örn. saha amiri, dispeçer) görüntülenebilir ve sunucu ya da uygulama yeniden başlatıldığında **kaybolmaz**. (Not: Bu, önceki bir sürümde "sadece path string'i tutulur, gerçek upload yapılmaz" şeklinde planlanmıştı; Temel Kalite İlkesi gereği bu karar geri alınmış ve gerçek dosya kalıcılığı zorunlu kılınmıştır. **Bölüm 11'e bakınız: mevcut kod hâlâ eski/placeholder davranışını uyguluyor, bu bir plan sapması ve acil düzeltme kalemidir.**)
- **Gerçek push notification altyapısı yoktur:** Firebase Cloud Messaging gibi bir servis entegre edilmez; "bildirimler" modülü, veritabanındaki `notifications` tablosunun periyodik olarak sorgulanmasıyla (polling) uygulama içi bir liste şeklinde simüle edilir.
- **Gerçek offline senkronizasyon yoktur:** Çevrimdışı mod, gerçek bir yerel veritabanı senkronizasyon mekanizması (conflict resolution vb.) içermez; yalnızca UI üzerinde "çevrimdışısınız" göstergesi ve arayüzün buna göre davranışının simülasyonu yapılır.
- **Kimlik doğrulama basittir:** JWT kullanılabilir ancak refresh token, oturum süresi yönetimi gibi production-grade güvenlik mekanizmaları kapsam dışıdır.
- **Veri sahtedir:** Tüm kullanıcı, iş emri, ekipman ve İSG verileri seed script'leri ile üretilmiş rastgele/sahte verilerdir; gerçek Aras EDAŞ müşteri veya altyapı bilgisi içermez.
- **Ölçek ve performans üretim seviyesinde değildir:** SQLite ve tek Express süreci, gerçek saha ölçeğinde (binlerce eşzamanlı kullanıcı) çalışacak şekilde tasarlanmamıştır; bu bilinçli bir prototip tercihidir.

Bu bölümün amacı, sunum sırasında "neden bazı şeyler gerçek değil" sorusuna net ve hazırlıklı bir cevap verebilmektir: bu kısıtlamalar teknik eksiklik değil, **prototip kapsamının bilinçli bir tasarım kararıdır**.

---

## 11. Mevcut Kod Durumu — Plandan Sapmalar (Acil Düzeltilmesi Gereken Kalemler)

> **Güncelleme:** 11.1 ve 11.2 uygulanmıştır (bkz. madde başlarındaki ✅). 11.3 (rol bazlı yetkilendirme/auth ekranları) henüz uygulanmamıştır; `users.role` alanı ve API'de rol filtresi mevcuttur ama giriş ekranı ve rol bazlı görüntüleme filtresi yoktur.

Bu bölüm, mevcut kod tabanının (`arassaha-backend/`) yukarıdaki plandan **nerede saptığını** somut dosya/satır referanslarıyla listeler. Bu maddeler "gelecekte yapılacak" değil, **Temel Kalite İlkesi'ni şu anda ihlal eden, düzeltilmesi zorunlu** teknik borçlardır. Rastgele/sahte veri kullanılması sorun değildir (bkz. Bölüm 10); buradaki sorun, veri akışının/mekanizmasının eksik veya sahte çalışmasıdır.

### 11.1 ✅ Kişiler (personel) sabit kodlanmış, veritabanından çekilmiyor — DÜZELTİLDİ
- **Sorun:** `seed.js` içinde `personnel` sabit bir isim dizisidir (`['Ahmet Yılmaz', 'Mehmet Demir', ...]`); `work_orders.assigned_to` bu diziden rastgele seçilen bir **düz metin (TEXT)** olarak saklanır. Gerçek bir `users` tablosu hiç yoktur.
- **Plana göre olması gereken:** Bölüm 4.1'de tanımlanan `users` tablosu `database.js`'te oluşturulmalı, `seed.js` bu tabloyu doldurmalı, `work_orders.assigned_user_id` bu tabloya gerçek bir FK olmalı ve `GET /api/users` endpoint'i eklenmelidir. Flutter tarafında personel/kişi bilgisi her zaman bu endpoint'ten çekilmeli, hiçbir ekranda sabit kodlanmış isim listesi kullanılmamalıdır.
- **Etkilenen dosyalar:** `arassaha-backend/database.js`, `arassaha-backend/seed.js`, `arassaha-backend/routes/workOrders.js`, yeni `arassaha-backend/routes/users.js`, Flutter `lib/models/work_order.dart`, `lib/screens/work_order_detail_screen.dart`.
- **Uygulandı:** `users` tablosu oluşturuldu; `work_orders.assigned_user_id` gerçek bir FK; `GET /api/users` ve `GET /api/workorders`/`:id` artık `assigned_user: {id, name, role}` nesnesini JOIN ile döner. Flutter tarafında `AssignedUser` modeli ve ilgili ekranlar güncellendi; hiçbir yerde sabit isim listesi kalmadı (seed script'i hariç, o zaten sahte veri üretimi için var).

### 11.2 ✅ Fotoğraf ekleme gerçek dosya yüklemiyor, sadece placeholder metin kaydediyor — DÜZELTİLDİ
- **Sorun:** `routes/workOrders.js` içindeki `POST /:id/photos` endpoint'i, kodun kendi yorumunda da itiraf edildiği gibi ("Gerçek dosya upload'ı yapılmaz; sadece path/placeholder string kaydedilir") yalnızca istemcinin gönderdiği bir `photo_path` string'ini veritabanına yazar. `server.js`'te multipart/form-data işleyen bir middleware (örn. `multer`) veya statik dosya servisi (`uploads/` klasörü + `express.static`) yoktur.
- **Neden kritik:** Bu, dokümanın en başındaki Temel Kalite İlkesi'nin verdiği somut örneğin ta kendisidir — bir teknisyen fotoğraf "ekledi" görünür ama aslında hiçbir dosya sunucuya ulaşmaz; farklı bir cihazdan bağlanan saha amiri gerçek bir fotoğraf göremez, sadece anlamsız bir path string'i görür.
- **Plana göre olması gereken (Bölüm 10'daki karar):** `multer` (veya eşdeğeri) ile gerçek multipart upload yapılmalı, dosya `uploads/` klasörüne yazılmalı, `server.js`'e `app.use('/uploads', express.static(...))` eklenmeli, `photo_path` alanına bu servis edilen URL/dosya adı yazılmalıdır. Böylece amir/dispeçer, iş emri detayını açtığında fotoğrafı gerçekten görüntüleyebilir.
- **Etkilenen dosyalar:** `arassaha-backend/server.js`, `arassaha-backend/routes/workOrders.js`, Flutter `lib/services/api_service.dart` (çoklu-part istek göndermeli).
- **Uygulandı:** `multer` ile gerçek multipart upload eklendi; dosyalar `arassaha-backend/uploads/` klasörüne yazılıyor, `server.js` bunu `/uploads` altında statik servis ediyor. `photo_path` artık `/uploads/<dosya>` gibi kalıcı bir URL. Flutter tarafı `http.MultipartRequest` ile gerçek dosya gönderiyor ve `Image.network` ile sunucudan çekilen fotoğrafı gösteriyor (önceden `Image.file` ile cihazın kendi yerel dosyasını gösteriyordu — bu yüzden başka bir cihaz/amir hiçbir şey göremiyordu). Uçtan uca test edildi: dosya yüklendi, diskte oluştu, HTTP 200 ile servis edildi, iş emri detayında göründü.

### 11.3 Rol bazlı yetkilendirme ve amir/yönetici ekranı henüz kodda yok
- **Sorun:** Bölüm 8'deki yetkilendirme matrisi ve `users.role` alanı henüz backend'de veya Flutter'da uygulanmamıştır; şu an tüm istemciler aynı `GET /api/workorders` uç noktasını, rol ayrımı olmadan kullanır.
- **Plana göre olması gereken:** 11.1 tamamlandıktan sonra, giriş yapan kullanıcının rolüne göre (teknisyen: kendine atananlar, amir/dispeçer/yönetici: tümü) filtreleme uygulanmalı; amirin tüm iş emirlerini ve eklenen fotoğrafları kendi ekranından görebildiği doğrulanmalıdır (manuel test: bir cihazdan fotoğraf ekle, ikinci bir cihaz/oturumdan aynı iş emrini aç, fotoğrafın göründüğünü doğrula).
- **Etkilenen dosyalar:** `arassaha-backend/routes/workOrders.js`, yeni auth route'ları, Flutter auth/rol katmanı (henüz oluşturulmadı).

**Öncelik sırası:** 11.1 → 11.2 → 11.3 (kişiler tablosu olmadan fotoğraf/iş emri ilişkilendirmesi ve rol bazlı görüntüleme anlamlı şekilde test edilemez).
