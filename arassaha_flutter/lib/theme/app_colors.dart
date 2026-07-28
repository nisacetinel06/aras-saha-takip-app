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
  static const lightPrimary = Color(0xFF1B3A5C);
  static const lightAccent = Color(0xFFF2994A);
  static const lightSuccess = Color(0xFF2E8B57);
  static const lightWarning = Color(0xFFE0A106);
  static const lightDanger = Color(0xFFD64545);
  static const lightBackground = Color(0xFFF6F7F9);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightTextPrimary = Color(0xFF1A1D23);
  static const lightTextSecondary = Color(0xFF6B7280);

  // --- Koyu tema ---
  static const darkPrimary = Color(0xFF4A7FB5);
  static const darkAccent = Color(0xFFF2994A);
  static const darkSuccess = Color(0xFF3EAE74);
  static const darkWarning = Color(0xFFE0B33C);
  static const darkDanger = Color(0xFFE06565);
  static const darkBackground = Color(0xFF14161A);
  static const darkSurface = Color(0xFF1E2126);
  static const darkTextPrimary = Color(0xFFE8EAED);
  static const darkTextSecondary = Color(0xFF9AA0A8);

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
