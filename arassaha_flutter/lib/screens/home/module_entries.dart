import 'package:flutter/material.dart';
import '../../models/work_order.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_colors.dart';
import '../admin/analytics_screen.dart';
import '../admin/deletion_requests_screen.dart';
import '../admin/user_management_list_screen.dart';
import '../dashboard_screen.dart';
import '../devices/device_list_screen.dart';
import '../equipment/equipment_home_screen.dart';
import '../equipment/suspicious_meters_screen.dart';
import '../isg/isg_report_list_screen.dart';
import '../maintenance/maintenance_recommendations_screen.dart';
import '../map/map_screen.dart';
import '../materials/material_list_screen.dart';
import '../notifications/notifications_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/settings_screen.dart';

/// Uygulamadaki HER modülün TEK kaynağı — Ana Sayfa'nın hamburger menü
/// panelinde ([AppNavigationDrawer]) rol bazlı filtrelenerek gösterilir.
/// Eskiden bu liste "Tüm Modüller" ekranının (AllModulesScreen, artık
/// kaldırıldı) içinde tutulurdu; menü paneli de aynı modülleri göstermesi
/// gerektiği için tek kaynağa (buraya) taşındı — iki ayrı yerde birbirinden
/// bağımsız kopyalar tutmak, biri güncellenip diğeri unutulduğunda modüllerin
/// panelden "sessizce" kaybolmasına yol açardı.
class ModuleEntry {
  final IconData icon;
  final String title;
  final String subtitle;
  final String category;
  final Color Function(BuildContext) color;
  final WidgetBuilder screenBuilder;

  const ModuleEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.color,
    required this.screenBuilder,
  });
}

/// RBAC, backend'deki `requireRole` kurallarıyla BİREBİR aynıdır (bkz.
/// routes/*.js) — bir teknisyenin bu listede yönetici-only bir modülü
/// GÖRMESİ bile yanlış olurdu, bu yüzden filtre burada, tek yerde uygulanır.
List<ModuleEntry> buildModuleEntries(
  AuthProvider auth,
  void Function(int tabIndex, {WorkOrderStatus? statusFilter}) onNavigate,
) {
  return [
    ModuleEntry(
      icon: Icons.location_on_outlined,
      title: 'Harita',
      subtitle: 'İş emirlerini konum üzerinde gör',
      category: 'Operasyon',
      color: AppColors.primary,
      screenBuilder: (_) => const MapScreen(),
    ),
    ModuleEntry(
      icon: Icons.bar_chart_outlined,
      title: 'Panel',
      subtitle: 'Grafikler ve özet göstergeler',
      category: 'Operasyon',
      color: AppColors.positive,
      screenBuilder: (_) => DashboardScreen(onNavigate: onNavigate),
    ),
    ModuleEntry(
      icon: Icons.inventory_2_outlined,
      title: 'Ekipman',
      subtitle: 'Varlıkları tara veya ara',
      category: 'Operasyon',
      color: AppColors.primary,
      screenBuilder: (_) => const EquipmentHomeScreen(),
    ),
    ModuleEntry(
      icon: Icons.shield_outlined,
      title: 'İş Güvenliği',
      subtitle: 'Olay/Tehlike bildir',
      category: 'Operasyon',
      color: AppColors.positive,
      screenBuilder: (_) => const IsgReportListScreen(),
    ),
    ModuleEntry(
      icon: Icons.warehouse_outlined,
      title: 'Stok / Malzeme',
      subtitle: 'Yedek parça envanteri',
      category: 'Operasyon',
      color: AppColors.primary,
      screenBuilder: (_) => const MaterialListScreen(),
    ),
    // Bakım Planlama, iş emri oluşturma yetkisiyle eşleniktir — "Önleyici İş
    // Emri Oluştur" aksiyonunu barındırdığı için (dispeçer/yönetici).
    if (auth.canCreateWorkOrders)
      ModuleEntry(
        icon: Icons.build_circle_outlined,
        title: 'Bakım Planlama',
        subtitle: 'Kestirimci bakım önerileri',
        category: 'Operasyon',
        color: AppColors.positive,
        screenBuilder: (_) => const MaintenanceRecommendationsScreen(),
      ),
    if (auth.isYonetici) ...[
      ModuleEntry(
        icon: Icons.manage_accounts_outlined,
        title: 'Kullanıcı Yönetimi',
        subtitle: 'Ekle · Düzenle',
        category: 'Yönetim',
        color: AppColors.primary,
        screenBuilder: (_) => const UserManagementListScreen(),
      ),
      ModuleEntry(
        icon: Icons.phonelink_lock_outlined,
        title: 'Cihaz Yönetimi',
        subtitle: 'Kilitle · Senkronize et',
        category: 'Yönetim',
        color: AppColors.positive,
        screenBuilder: (_) => const DeviceListScreen(),
      ),
      ModuleEntry(
        icon: Icons.query_stats_outlined,
        title: 'Raporlar',
        subtitle: 'Bölgesel risk · Eğilimler',
        category: 'Yönetim',
        color: AppColors.primary,
        screenBuilder: (_) => const ReportsScreen(),
      ),
      ModuleEntry(
        icon: Icons.search,
        title: 'Şüpheli Sayaçlar',
        subtitle: 'Kayıp-kaçak / anomali tespiti',
        category: 'Yönetim',
        color: AppColors.positive,
        screenBuilder: (_) => const SuspiciousMetersScreen(),
      ),
      ModuleEntry(
        icon: Icons.analytics_outlined,
        title: 'Kullanım Analitiği',
        subtitle: 'En çok kullanılan ekran/butonlar',
        category: 'Yönetim',
        color: AppColors.primary,
        screenBuilder: (_) => const AnalyticsScreen(),
      ),
      // KVKK Uyum Modülü — bkz. routes/kvkk.js, screens/kvkk/*.
      ModuleEntry(
        icon: Icons.delete_forever_outlined,
        title: 'Silme Talepleri',
        subtitle: 'KVKK veri silme/anonimleştirme onayı',
        category: 'Yönetim',
        color: AppColors.positive,
        screenBuilder: (_) => const DeletionRequestsScreen(),
      ),
    ],
    ModuleEntry(
      icon: Icons.notifications_outlined,
      title: 'Bildirimler',
      subtitle: 'Tüm uyarılar',
      category: 'Sistem',
      color: AppColors.primary,
      screenBuilder: (_) => const NotificationsScreen(),
    ),
    ModuleEntry(
      icon: Icons.settings_outlined,
      title: 'Ayarlar',
      subtitle: 'Tema, bildirimler, çevrimdışı mod',
      category: 'Sistem',
      color: AppColors.positive,
      screenBuilder: (_) => const SettingsScreen(),
    ),
  ];
}
