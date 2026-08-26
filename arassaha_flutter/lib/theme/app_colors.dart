import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/audit_log_entry.dart';
import '../models/equipment.dart';
import '../models/equipment_risk.dart';
import '../models/work_order.dart';

/// Uygulamanın tek renk kaynağı. Tüm ekranlar (liste, detay, harita pin'i,
/// dashboard grafiği) statü/öncelik renklerini buradan okur — DESIGN_SYSTEM.md
/// Bölüm A.1'de tarif edilen paletle birebir eşleşir. `ColorScheme` (app_theme.dart)
/// da bu sabitlerden türetilir; ama statü/öncelik fonksiyonları burada doğrudan
/// bu sabitlere bakar — M3'ün genel `primary`/`secondary` rollerini "statü rengi"
/// anlamıyla karıştırıp yan etki (örn. seçili chip rengini değiştirme) yaratmamak için.
class AppColors {
  AppColors._();

  // --- Açık tema ---
  // v2 (canlı palet): mobile-design skill'inin "sahada, güneş altında okunabilirlik"
  // önceliğine göre doygunluk artırıldı — pastel/donuk tonlar yerine yüksek
  // kontrastlı, solid renkler (bkz. mobile-color-system.md "Outdoor Visibility").
  //
  // v3 (marka revizyonu — turuncu kaldırıldı): `accent` (turuncu) artık genel
  // arayüzde HİÇBİR yerde kullanılmıyor — mavi (`lightPrimary`) tek birincil
  // marka/aksiyon rengi. `lightPositive`, durum rengi `lightSuccess`'ten
  // BİLİNÇLİ olarak farklı, daha canlı bir yeşil: "Aktifleştir" gibi ikincil
  // olumlu aksiyon butonlarında kullanılır — statü rozetleriyle (çözüldü,
  // uyumlu, aktif) aynı ton olsaydı "bu bir durum mu yoksa tıklanabilir bir
  // buton mu" karışıklığı yaratırdı.
  static const lightPrimary = Color(0xFF0D5FA8);
  static const lightPositive = Color(0xFF13B562);
  static const lightSuccess = Color(0xFF16A34A);
  static const lightWarning = Color(0xFFF2A900);
  static const lightDanger = Color(0xFFE0263F);
  static const lightBackground = Color(0xFFF6F7F9);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightTextPrimary = Color(0xFF1A1D23);
  static const lightTextSecondary = Color(0xFF6B7280);

  // --- Koyu tema ---
  // Skill kuralı: koyu zeminde AYNI doygunlukta renk kullanmak "gözü yakar"
  // (bkz. mobile-color-system.md "Color Inversion Rules") — bu yüzden koyu
  // tondaki karşılıklar birebir aynı değil, hafif açılmış/yumuşatılmış.
  static const darkPrimary = Color(0xFF5B9BE0);
  static const darkPositive = Color(0xFF34D980);
  static const darkSuccess = Color(0xFF3ECC7A);
  static const darkWarning = Color(0xFFFBBF24);
  static const darkDanger = Color(0xFFF16B7A);
  // OLED/AMOLED optimizasyonu (C3): koyu gri (#121316) yerine TAM SİYAH —
  // OLED panellerde siyah piksel hiç ışık yaymadığı için gerçek pil tasarrufu
  // sağlar (koyu gri bir piksel hâlâ ışık yayar). Kartlar bu saf siyahtan
  // hafifçe ayrışsın diye `app_theme.dart`'taki `surfaceContainerLowest`
  // (AppCard'ın okuduğu ton) ayrı, biraz daha açık bir gri (#0E1013) olarak
  // tutuluyor — tamamen aynı renk olsaydı kartlar arka planda kaybolurdu.
  static const darkBackground = Color(0xFF000000);
  static const darkSurface = Color(0xFF1E2126);
  static const darkTextPrimary = Color(0xFFE8EAED);
  static const darkTextSecondary = Color(0xFF9AA0A8);

  // --- Rol rozeti paleti (Modül 8 — Profil / Kullanıcı Yönetimi) ---
  // BİLİNÇLİ olarak yukarıdaki statü/öncelik renklerinden (danger/warning/
  // primary/success) FARKLI tonlar: bir rozet "iş emri durumu" mu yoksa
  // "kullanıcı rolü" mü gösteriyor karışmasın diye ayrı bir palet. Profil
  // ekranındaki rol rozeti ve Ana Sayfa'daki karşılamadaki rozet hep buradan
  // okur (bkz. roleColor).
  static const lightRoleTeknisyen = Color(
    0xFF2563EB,
  ); // indigo/mavi — primary'den farklı ton
  static const lightRoleDispecer = Color(0xFF7C3AED); // mor
  static const lightRoleYonetici = Color(
    0xFFC2410C,
  ); // koyu/bronz turuncu — accent/warning'den farklı ton

  static const darkRoleTeknisyen = Color(0xFF60A5FA);
  static const darkRoleDispecer = Color(0xFFA78BFA);
  static const darkRoleYonetici = Color(0xFFFB923C);

  // --- Denetim Logu kategori paleti (bkz. screens/admin/audit_log_screen.dart) ---
  // BİLİNÇLİ olarak durum renklerinden (danger/warning/success/primary)
  // AYRI: bu kategoriler "iyi/kötü/acil" bir DURUMU değil, yalnızca HANGİ
  // MODÜLE ait olduğunu gösterir — nötr, göz yormayan, birbirinden ayırt
  // edilebilir ama "alarm" hissi vermeyen tonlar. Yalnızca başarısız giriş
  // denemesi (giris_basarisiz) AYRICA `AppColors.danger` ile vurgulanır
  // (audit_log_screen.dart'taki kenar şeridi) — bu bir KATEGORİ rengi değil,
  // güvenlik açısından dikkat çekici bir OLAY vurgusudur, burada tekrar
  // tanımlanmaz.
  static const lightAuditGiris = Color(0xFF0891B2); // camgöbeği
  static const lightAuditKullaniciYonetimi = Color(0xFF64748B); // slate
  static const lightAuditCihazYonetimi = Color(
    0xFF7C3AED,
  ); // mor (rol paletindeki dispeçer moruyla AYNI aile, kasıtlı — ikisi de "yönetimsel" bir işlemi imler)
  static const lightAuditStok = Color(0xFF0D9488); // teal
  static const lightAuditKvkk = Color(0xFFA16207); // amber-kahve
  static const lightAuditDosyaTemizleme = Color(0xFF475569); // koyu slate

  static const darkAuditGiris = Color(0xFF67E8F9);
  static const darkAuditKullaniciYonetimi = Color(0xFF94A3B8);
  static const darkAuditCihazYonetimi = Color(0xFFC4B5FD);
  static const darkAuditStok = Color(0xFF5EEAD4);
  static const darkAuditKvkk = Color(0xFFD9A441);
  static const darkAuditDosyaTemizleme = Color(0xFFCBD5E1);

  static Color primary(BuildContext c) => _pick(c, lightPrimary, darkPrimary);
  static Color positive(BuildContext c) =>
      _pick(c, lightPositive, darkPositive);
  static Color success(BuildContext c) => _pick(c, lightSuccess, darkSuccess);
  static Color warning(BuildContext c) => _pick(c, lightWarning, darkWarning);
  static Color danger(BuildContext c) => _pick(c, lightDanger, darkDanger);
  static Color textSecondary(BuildContext c) =>
      _pick(c, lightTextSecondary, darkTextSecondary);

  static Color _pick(BuildContext context, Color light, Color dark) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }
}

/// WCAG bağıl parlaklık formülüne göre, verilen bir arka plan renginin
/// üzerine en okunabilir metin/ikon rengini (siyah ya da beyaz) seçer.
///
/// GEREKÇE (D1 kontrast denetimi bulgusu): Koyu temadaki success/warning/
/// accent/primary/rol tonları BİLİNÇLİ olarak açık/pastel seçildi — bir KOYU
/// ZEMİN ÜZERİNDE METİN olarak okunsun diye. Ama aynı renkler rozet/avatar
/// gibi SOLID DOLGU olup üzerine SABİT `Colors.white` konunca bu açıklık tam
/// tersine dönüp WCAG AA eşiğinin (4.5:1) çok altına düşürüyordu — ölçtüğümüz
/// somut örnekler: beyaz üzerine koyu tema warning'i (#FBBF24) yalnızca
/// 1.67:1, beyaz üzerine koyu tema success'i (#3ECC7A) yalnızca 2.07:1, beyaz
/// üzerine AppButton'ın (eskiden hep beyaz varsayan) primary rengi koyu
/// temada yalnızca 2.91:1. Palet renklerinin kendisini (iki farklı amaç için
/// iki ayrı ton tanımlayarak) karmaşıklaştırmak yerine, DOĞRU metin rengini
/// HESAPLAYARAK tek bir yerden garanti eder — hangi renk gelirse gelsin.
Color accessibleOnColor(Color background) {
  double channel(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  final luminance =
      0.2126 * channel(background.r) +
      0.7152 * channel(background.g) +
      0.0722 * channel(background.b);
  final contrastWithWhite = 1.05 / (luminance + 0.05);
  final contrastWithBlack = (luminance + 0.05) / 0.05;
  return contrastWithBlack >= contrastWithWhite ? Colors.black : Colors.white;
}

/// Statü rengi: acik=danger, yolda=warning, sahada=primary, cozuldu=success.
/// Tüm modüller (liste kartı, detay, harita pin'i, dashboard grafiği) bu tek
/// fonksiyonu çağırır.
Color statusColor(BuildContext context, WorkOrderStatus status) {
  switch (status) {
    case WorkOrderStatus.acik:
      return AppColors.danger(context);
    case WorkOrderStatus.yolda:
      return AppColors.warning(context);
    case WorkOrderStatus.sahada:
      return AppColors.primary(context);
    case WorkOrderStatus.cozuldu:
      return AppColors.success(context);
  }
}

/// Statü renginin üzerine gelecek metin/ikon rengi — bkz. [accessibleOnColor].
Color onStatusColor(BuildContext context, WorkOrderStatus status) =>
    accessibleOnColor(statusColor(context, status));

/// Öncelik rengi: acil=danger (kırmızı), normal=warning (sarı/amber),
/// dusuk=textSecondary. `normal` daha önce ayrı bir "accent" (turuncu)
/// tonundaydı — marka revizyonuyla turuncu tamamen kaldırıldığı için, "orta
/// öncelik" durum rengi kuralına (sarı/amber) taşındı.
Color priorityColor(BuildContext context, WorkOrderPriority priority) {
  switch (priority) {
    case WorkOrderPriority.acil:
      return AppColors.danger(context);
    case WorkOrderPriority.normal:
      return AppColors.warning(context);
    case WorkOrderPriority.dusuk:
      return AppColors.textSecondary(context);
  }
}

/// bkz. [accessibleOnColor].
Color onPriorityColor(BuildContext context, WorkOrderPriority priority) =>
    accessibleOnColor(priorityColor(context, priority));

/// Kullanıcı rolü rengi (Modül 8 — Profil / Kullanıcı Yönetimi): teknisyen,
/// dispeçer, yönetici. `role`, backend'deki `users.role` alanıyla birebir
/// eşleşen ham string'dir ('teknisyen' | 'dispecer' | 'yonetici').
Color roleColor(BuildContext context, String role) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  switch (role) {
    case 'teknisyen':
      return isDark
          ? AppColors.darkRoleTeknisyen
          : AppColors.lightRoleTeknisyen;
    case 'dispecer':
      return isDark ? AppColors.darkRoleDispecer : AppColors.lightRoleDispecer;
    case 'yonetici':
      return isDark ? AppColors.darkRoleYonetici : AppColors.lightRoleYonetici;
    default:
      return AppColors.textSecondary(context);
  }
}

/// Rol rengi zemininin üzerine gelecek metin/ikon rengi — bkz. [accessibleOnColor].
Color onRoleColor(BuildContext context, String role) =>
    accessibleOnColor(roleColor(context, role));

/// Ekipman durumu rengi: aktif=success, bakımda=warning, devreDışı=textSecondary.
/// Önceden equipment_list_screen.dart ve equipment_detail_screen.dart bu eşlemeyi
/// birbirinden bağımsız olarak kopyalıyordu (equipment_picker_field.dart bunu
/// bir ÜÇÜNCÜ yerde tekrarlayacaktı) — statusColor/priorityColor ile AYNI
/// "tek gerçek kaynak" ilkesiyle buraya taşındı.
Color equipmentStatusColor(BuildContext context, EquipmentStatus status) {
  switch (status) {
    case EquipmentStatus.aktif:
      return AppColors.success(context);
    case EquipmentStatus.bakimda:
      return AppColors.warning(context);
    case EquipmentStatus.devreDisi:
      return AppColors.textSecondary(context);
  }
}

/// Ekipman durumu renginin üzerine gelecek metin/ikon rengi — bkz. [accessibleOnColor].
Color onEquipmentStatusColor(BuildContext context, EquipmentStatus status) =>
    accessibleOnColor(equipmentStatusColor(context, status));

/// Risk seviyesi rengi: dusuk=success, orta=warning, yuksek=danger (Modül 9).
/// Kestirimci Bakım Planlama (Modül 12) önerilerinin urgency_level'ı da AYNI
/// üç değeri (RiskLevel) kullandığı için (bkz. models/maintenance_recommendation.dart),
/// bu tek fonksiyon her iki modülde de kullanılır — "Modül 9'daki risk
/// renkleriyle birebir tutarlı" ilkesi böylece kod düzeyinde garanti edilir.
Color riskLevelColor(BuildContext context, RiskLevel level) {
  switch (level) {
    case RiskLevel.dusuk:
      return AppColors.success(context);
    case RiskLevel.orta:
      return AppColors.warning(context);
    case RiskLevel.yuksek:
      return AppColors.danger(context);
  }
}

/// Risk seviyesi renginin üzerine gelecek metin/ikon rengi — bkz. [accessibleOnColor].
Color onRiskLevelColor(BuildContext context, RiskLevel level) =>
    accessibleOnColor(riskLevelColor(context, level));

/// Denetim Logu kategori rengi — bkz. AppColors'taki "Denetim Logu kategori
/// paleti" notu. `category` null ise (backend'in tanımadığı/yeni bir
/// kategori) nötr [AppColors.textSecondary] döner — UI hiçbir zaman çökmez.
Color auditCategoryColor(BuildContext context, AuditLogCategory? category) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  switch (category) {
    case AuditLogCategory.giris:
      return isDark ? AppColors.darkAuditGiris : AppColors.lightAuditGiris;
    case AuditLogCategory.kullaniciYonetimi:
      return isDark
          ? AppColors.darkAuditKullaniciYonetimi
          : AppColors.lightAuditKullaniciYonetimi;
    case AuditLogCategory.cihazYonetimi:
      return isDark
          ? AppColors.darkAuditCihazYonetimi
          : AppColors.lightAuditCihazYonetimi;
    case AuditLogCategory.stok:
      return isDark ? AppColors.darkAuditStok : AppColors.lightAuditStok;
    case AuditLogCategory.kvkk:
      return isDark ? AppColors.darkAuditKvkk : AppColors.lightAuditKvkk;
    case AuditLogCategory.dosyaTemizleme:
      return isDark
          ? AppColors.darkAuditDosyaTemizleme
          : AppColors.lightAuditDosyaTemizleme;
    case null:
      return AppColors.textSecondary(context);
  }
}

/// Kategori renginin üzerine gelecek metin/ikon rengi — bkz. [accessibleOnColor].
Color onAuditCategoryColor(BuildContext context, AuditLogCategory? category) =>
    accessibleOnColor(auditCategoryColor(context, category));
