import 'package:flutter/material.dart';
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
  static const lightPrimary = Color(0xFF0D5FA8);
  static const lightAccent = Color(0xFFFF6A1A);
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
  static const darkAccent = Color(0xFFFF9152);
  static const darkSuccess = Color(0xFF3ECC7A);
  static const darkWarning = Color(0xFFFBBF24);
  static const darkDanger = Color(0xFFF16B7A);
  static const darkBackground = Color(0xFF121316);
  static const darkSurface = Color(0xFF1E2126);
  static const darkTextPrimary = Color(0xFFE8EAED);
  static const darkTextSecondary = Color(0xFF9AA0A8);

  // --- Rol rozeti paleti (Modül 8 — Profil / Kullanıcı Yönetimi) ---
  // BİLİNÇLİ olarak yukarıdaki statü/öncelik renklerinden (danger/warning/
  // primary/success) FARKLI tonlar: bir rozet "iş emri durumu" mu yoksa
  // "kullanıcı rolü" mü gösteriyor karışmasın diye ayrı bir palet. Profil
  // ekranındaki rol rozeti ve Ana Sayfa'daki karşılamadaki rozet hep buradan
  // okur (bkz. roleColor).
  static const lightRoleTeknisyen = Color(0xFF2563EB); // indigo/mavi — primary'den farklı ton
  static const lightRoleDispecer = Color(0xFF7C3AED); // mor
  static const lightRoleYonetici = Color(0xFFC2410C); // koyu/bronz turuncu — accent/warning'den farklı ton

  static const darkRoleTeknisyen = Color(0xFF60A5FA);
  static const darkRoleDispecer = Color(0xFFA78BFA);
  static const darkRoleYonetici = Color(0xFFFB923C);

  static Color primary(BuildContext c) => _pick(c, lightPrimary, darkPrimary);
  static Color accent(BuildContext c) => _pick(c, lightAccent, darkAccent);
  static Color success(BuildContext c) => _pick(c, lightSuccess, darkSuccess);
  static Color warning(BuildContext c) => _pick(c, lightWarning, darkWarning);
  static Color danger(BuildContext c) => _pick(c, lightDanger, darkDanger);
  static Color textSecondary(BuildContext c) => _pick(c, lightTextSecondary, darkTextSecondary);

  static Color _pick(BuildContext context, Color light, Color dark) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }
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

/// Statü renginin üzerine gelecek metin/ikon rengi (kontrast için).
/// warning (amber) zemin üzerinde beyaz düşük kontrasta düşüyor; koyu metin kullanılır.
Color onStatusColor(BuildContext context, WorkOrderStatus status) {
  if (status == WorkOrderStatus.yolda) return const Color(0xFF3A2500);
  return Colors.white;
}

/// Öncelik rengi: acil=danger, normal=accent, dusuk=textSecondary.
Color priorityColor(BuildContext context, WorkOrderPriority priority) {
  switch (priority) {
    case WorkOrderPriority.acil:
      return AppColors.danger(context);
    case WorkOrderPriority.normal:
      return AppColors.accent(context);
    case WorkOrderPriority.dusuk:
      return AppColors.textSecondary(context);
  }
}

Color onPriorityColor(BuildContext context, WorkOrderPriority priority) {
  return Colors.white;
}

/// Kullanıcı rolü rengi (Modül 8 — Profil / Kullanıcı Yönetimi): teknisyen,
/// dispeçer, yönetici. `role`, backend'deki `users.role` alanıyla birebir
/// eşleşen ham string'dir ('teknisyen' | 'dispecer' | 'yonetici').
Color roleColor(BuildContext context, String role) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  switch (role) {
    case 'teknisyen':
      return isDark ? AppColors.darkRoleTeknisyen : AppColors.lightRoleTeknisyen;
    case 'dispecer':
      return isDark ? AppColors.darkRoleDispecer : AppColors.lightRoleDispecer;
    case 'yonetici':
      return isDark ? AppColors.darkRoleYonetici : AppColors.lightRoleYonetici;
    default:
      return AppColors.textSecondary(context);
  }
}

/// Rol rengi zemininin üzerine gelecek metin/ikon rengi — üç rol rengi de
/// yeterince koyu/doygun olduğu için her zaman beyaz.
Color onRoleColor(BuildContext context, String role) => Colors.white;
