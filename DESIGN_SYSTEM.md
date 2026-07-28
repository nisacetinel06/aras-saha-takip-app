# ArasSaha — Tasarım Sistemi

Bu doküman, uygulamanın dağınık/amatör görünümünü düzeltmek için kurulacak tasarım sisteminin planını özetler. **Onay öncesi hiçbir ekran dosyası değiştirilmedi** — bu sadece plan dokümanıdır. Onay sonrası B) bölümündeki sırayla uygulanacaktır.

## Mevcut Durum Tespiti (neden bu plan)

- `lib/theme/app_theme.dart` zaten bir M3 `ColorScheme` + `GoogleFonts` (Plus Jakarta Sans / Work Sans) kurmuş durumda — ama renk kodları promptta istenen palet **değil** (örn. primary `#00294F`, istenen `#1B3A5C`), font ailesi de istenen (Manrope/Inter/JetBrains Mono) **değil** (Plus Jakarta Sans/Work Sans). Bu yüzden "ekranlar arası ufak renk farkı" hissi buradan geliyor: bazı yerler `Theme.of(context).colorScheme`'i kullanıyor, bazı yerler (örn. `_EquipmentChip` içinde `GoogleFonts.jetBrainsMono(...)`) doğrudan sabit kodluyor.
- Statü/öncelik renkleri `lib/widgets/status_badge.dart` içinde merkezi ama `AppTheme.accentOrange` / `AppTheme.accentPurple` gibi tema dışı sabitlere karışık şekilde bağlı.
- Taşma sorunu somut olarak `work_order_detail_screen.dart` → `_StatusUpdateSection` içinde: `Row(children: [Expanded(Text(...)), ElevatedButton.icon(label: Text("${nextStatus.label}'a Geçir"))])` — buton `Expanded` içinde değil, dar ekranda `RenderFlex overflow` veriyor. Etiket de uzun ("Yolda'a Geçir", "Sahada'a Geçir").
- `BentoCard` (kart) ve doğrudan `ElevatedButton`/`OutlinedButton` her ekranda ayrı ayrı çağrılıyor, ortak bir `AppButton`/`AppCard` bileşeni yok.
- Ana giriş noktası (`main.dart` → `home:`) doğrudan `DashboardScreen`; merkezi bir yönlendirme (hub) ekranı yok, `MainShell` içindeki bottom nav da Dashboard'ı değil `WorkOrderListScreen`'i ilk sekme yapıyor.

## A) Tasarım Sistemi

### 1. Renk Paleti — `lib/theme/app_colors.dart`

Promptta verilen ham hex değerleri **birebir** sabit olarak tanımlanacak (light + dark), sonra `AppTheme` bu sabitlerden bir `ColorScheme` üretecek (M3 uyumluluğu için gerekli `container`/`on*` türevleri buradan hesaplanacak, ama kaynak tek yer `app_colors.dart` olacak).

| Token | Light | Dark |
|---|---|---|
| primary | `#1B3A5C` | `#4A7FB5` |
| accent | `#F2994A` | `#F2994A` |
| success | `#2E8B57` | `#3EAE74` |
| warning | `#E0A106` | `#E0B33C` |
| danger | `#D64545` | `#E06565` |
| background | `#F6F7F9` | `#14161A` |
| surface | `#FFFFFF` | `#1E2126` |
| textPrimary | `#1A1D23` | `#E8EAED` |
| textSecondary | `#6B7280` | `#9AA0A8` |

**Statü renkleri** (tek kaynak, `status_badge.dart` bunlardan besklenecek):
- `acik` → danger
- `yolda` → warning
- `sahada` → primary (mevcutta "sahada" mor/accentPurple kullanıyordu — bu paletle uyumsuz olduğu için primary'ye çekiliyor, ayırt edilebilirlik chip/pin şeklinde değil renkte kalacak)
- `cozuldu` → success

**Öncelik renkleri:**
- `acil` → danger
- `normal` → accent
- `dusuk` → textSecondary

Bu eşleme; liste kartı, detay ekranı, harita pin'i, dashboard grafiği (pasta/çubuk) dahil **her yerde** aynı sabitlerden okunacak — şu an `priorityChartColor` gibi ayrı bir "grafik için farklı palet" fonksiyonu var, bu kaldırılıp tek kaynağa indirilecek.

### 2. Tipografi — `lib/theme/app_text_styles.dart`

`google_fonts` paketi zaten `pubspec.yaml`'da mevcut (ek kurulum gerekmiyor), sadece font ailesi değişiyor: Plus Jakarta Sans/Work Sans → **Manrope** (başlık) / **Inter** (gövde) / **JetBrains Mono** (veri).

| Stil | Font | Boyut | Ağırlık | Kullanım |
|---|---|---|---|---|
| `displayLarge` | Manrope | 32sp | Bold | Ana Sayfa başlığı |
| `headingMedium` | Manrope | 20sp | SemiBold | Ekran başlıkları |
| `bodyMedium` | Inter | 14sp | Regular | Gövde metni |
| `caption` | Inter | 12sp | Regular, textSecondary | Alt açıklamalar |
| `dataMono` | JetBrains Mono | 13sp | Medium | Koordinat, seri no, tarih-saat |

Mevcut `TextTheme` (`headlineLarge`, `bodyMedium` vb. M3 isimleri) bu yeni stillerle güncellenecek; `app_text_styles.dart` bunları hem M3 `TextTheme` alanlarına eşler hem de doğrudan erişim için (`AppTextStyles.dataMono` gibi) statik alanlar sunar — `_EquipmentChip` gibi şu an sabit `GoogleFonts.jetBrainsMono(...)` çağıran yerler bu merkezi stile taşınacak.

### 3. Spacing / Radius — `lib/theme/app_spacing.dart`

```dart
class AppSpacing {
  static const xs = 4.0, sm = 8.0, md = 16.0, lg = 24.0, xl = 32.0;
}
class AppRadius {
  static const card = 12.0, button = 10.0, chip = 8.0, pill = 999.0;
}
```
Ekranlardaki rastgele `EdgeInsets`/`SizedBox` değerleri (örn. mevcut kodda `18`, `14`, `6` gibi serbest sayılar var) bu ölçekten seçilecek şekilde gözden geçirilecek. Bire bir her sayıyı değiştirmek yerine, **yeni yazılan/değiştirilen** her widget bu ölçeği kullanacak; dokunulmayan iç detaylarda küçük sapmalar (örn. `Divider(height: 24)`) görsel kırılma yaratmıyorsa olduğu gibi bırakılabilir.

### 4. Buton Sistemi — `lib/widgets/app_button.dart`

```dart
enum AppButtonVariant { primary, secondary, text }

class AppButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final AppButtonVariant variant;
  final VoidCallback? onPressed;
  final bool isLoading;
}
```
Kurallar:
- İçerik `Flexible(child: Text(label, overflow: TextOverflow.ellipsis, maxLines: 1))` ile sarmalanır — metin asla taşmaz, gerekirse `...` ile kısalır.
- Minimum yükseklik `48` (`ConstrainedBox`), yatay padding `AppSpacing.md`.
- `primary`: dolu zemin (accent ya da primary, bağlama göre), `secondary`: `AppRadius.button` köşeli outline, `text`: sadece `TextButton` stilinde, düşük vurgulu.
- Buton bir `Row` içinde `Expanded`'sız kullanılıyorsa çağıran taraf `Expanded`/`Wrap` ile sarmalamaktan sorumlu — `AppButton`'ın kendisi dış kısıtlamaya (`intrinsic width` değil, mevcut alanı doldurma) uyar.

**Durum güncelleme butonları (Modül 1 detay ekranı) — somut çözüm:**
`_StatusUpdateSection` şu an `"${nextStatus.label}'a Geçir"` gibi değişken uzunlukta ("Sahada'a Geçir" gibi dilbilgisel olarak da bozuk) bir etiket üretiyor. Yeni sistemde durum başına **sabit, kısa** etiket + ikon tanımlanacak:

| Sonraki durum | Etiket | İkon |
|---|---|---|
| yolda | "Yolda" | `Icons.directions_car_outlined` |
| sahada | "Sahadayım" | `Icons.location_on_outlined` |
| cozuldu | "Çözüldü" | `Icons.check_circle_outline` |

Satır artık `Wrap` içinde: durum metni üstte ayrı satır, `AppButton` altta tam genişlikte (veya geniş ekranda yan yana) — dar ekranlarda (320–360px) asla taşmayacak şekilde.

### 5. Kart Sistemi — `lib/widgets/app_card.dart`

`BentoCard`'ın yerini alacak (aynı görsel dili korur: `AppRadius.card`, aynı gölge tarifi, `surface` rengi) ama isim ve konum netleşiyor; `work_order_card.dart`, dashboard özet kartları, harita bilgi balonu, ileride Ekipman kartı hep bunun üzerine kurulacak. `BentoCard` kaldırılıp kullanım yerleri `AppCard`'a taşınacak (iki paralel kart bileşeni bırakılmayacak).

### 6. İmza Öğesi — Durum Şeridi (Status Stripe)

`AppCard`'a opsiyonel `Color? statusStripeColor` parametresi eklenecek: verilirse kartın sol kenarında 4px genişliğinde, kartın tam yüksekliğinde renkli bir şerit çizilir (`Row(children: [Container(width:4, color: statusStripeColor), Expanded(child: ...padding...)])`). Kullanım yerleri: iş emri kartı, harita bilgi balonu (bottom sheet), dashboard "Son Aktiviteler" listesi, ileride Ekipman kartı. Ana Sayfa'daki modül erişim kartlarında **kullanılmayacak** (promptta belirtildiği gibi, o kartlar durum taşımıyor).

## B) Ana Sayfa (Hub) Ekranı — `lib/screens/home/home_screen.dart`

Yukarıdan aşağı:
1. **Karşılama başlığı** — "ArasSaha Saha Operasyon Paneli" + bugünün tarihi, `displayLarge`.
2. **Özet şerit** — Dashboard'daki 3 `_SummaryCard`'ın küçük/yatay hali (yeniden kullanılabilir bir `CompactSummaryStrip` widget'ı olarak, `DashboardProvider`'dan beslenir).
3. **Modül ızgarası** — 2 sütunlu `GridView`, 6 kart: İş Emirleri (canlı "N açık" rozetiyle), Harita, Dashboard/Raporlar, Ekipman (yakında/soluk), İSG Bildirimi (yakında/soluk), Bildirimler (yakında/soluk). "Yakında" kartları `onTap`'te SnackBar gösterir, gerçek navigasyon yapmaz.
4. **Hızlı Aksiyon FAB** — "Yeni Arıza Gir", sabit FAB; modül ekranlarındaki dağınık "Yeni Arıza Gir" butonları kaldırılacak (Dashboard'daki `_QuickActionsRow`'dan bu buton çıkarılacak, sadece Hub'da kalacak).

### Navigasyon değişikliği
- `main.dart` → `home: const HomeScreen()`.
- `MainShell`: 4 sekme — Ana Sayfa | İş Emirleri | Harita | Dashboard (Ekipman/İSG/Bildirimler bottom bar'a **eklenmiyor**, sadece Hub ızgarasından "yakında" olarak erişiliyor).
- Ortak `AppBar`: sol başlık + sağ dark/light toggle. Şu an toggle sadece `DashboardScreen`'de var (`ThemeProvider` ile) — `MainShell` seviyesine taşınacak ki her sekmede görünsün.

## Etkilenecek Dosyalar (özet — B aşamasında)

**Yeni:**
`lib/theme/app_colors.dart`, `lib/theme/app_text_styles.dart`, `lib/theme/app_spacing.dart`, `lib/widgets/app_button.dart`, `lib/widgets/app_card.dart`, `lib/screens/home/home_screen.dart`

**Değişecek:**
`lib/theme/app_theme.dart` (yeni token'lardan üretilecek), `lib/widgets/status_badge.dart` (renkler `app_colors.dart`'tan), `lib/widgets/bento_card.dart` → kaldırılıp `app_card.dart` ile değiştirilecek, `lib/widgets/work_order_card.dart`, `lib/screens/work_order_detail_screen.dart` (buton taşması + kart geçişi), `lib/screens/work_order_list_screen.dart`, `lib/screens/dashboard_screen.dart` (özet kart + FAB kaldırma), `lib/screens/map/map_screen.dart` (pin renkleri + bilgi balonu kart/şerit), `lib/screens/main_shell.dart` (4. sekme, ortak app bar), `lib/main.dart` (home değişikliği)

---

Onayınla birlikte sırayla ilerleyeceğim: (1) tema dosyaları → (2) `AppButton`/`AppCard` → (3) Ana Sayfa → (4) mevcut ekranların geçişi, her adımda `flutter analyze` ile doğrulayarak.

## C) Cihaz Yönetimi Modülü (MDM Simülasyonu) — Sunum Notu

Bu modül (`screens/devices/`, `routes/devices.js`, `managed_devices`/`device_action_logs` tabloları) bir **Mobile Device Management (MDM) kavramının simülasyonudur**. "Kilitle", "Kilidi Aç", "Hesabı Sil", "Zorla Senkronize Et" aksiyonları yalnızca backend'in kendi veritabanındaki durumu değiştirir; hiçbir gerçek cihaza komut göndermez. Bu, ekranlarda ("Bu bir simülasyondur, gerçek cihaza komut gönderilmez" notu) ve backend kodundaki yorumlarda açıkça belirtilmiştir.

**Gerçek üretim sisteminde** bu modül, Google'ın **Android Management API**'sine (Android Enterprise) bağlanarak cihazlara gerçek zamanlı, uçtan uca şifreli komutlar gönderebilirdi (uzaktan kilitleme, kurumsal veri silme, parola politikası zorlama vb.). Bunun için organizasyonun bir **Google Workspace / Android Enterprise kaydı** yapması ve bu entegrasyon için **IT/güvenlik onayı** alması gerekir — bu prototipte kapsam dışı bırakılmıştır.

Ayrıca bu ekran, gerçek bir üründe yalnızca **yönetici (admin) rolündeki kullanıcılara** açık olurdu; Ana Sayfa'daki modül kartının yanındaki "Yönetici" etiketi bu kavramsal kısıtlamayı temsil eder (henüz gerçek bir rol/yetki sistemi kurulmadı, bkz. ARCHITECTURE.md Bölüm 11.3).
