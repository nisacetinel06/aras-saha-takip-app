import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/work_order.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_top_bar.dart';
import '../admin/analytics_screen.dart';
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

/// Tüm Modüller (Ana Sayfa radikal sadeleştirmesi): eskiden Ana Sayfa'nın
/// modül ızgarasında duran, "öne çıkanlar"a girmeyen HER modül artık burada
/// — arama çubuğu + kategori başlıkları ile. RBAC, Ana Sayfa'daki (eski)
/// modül ızgarasıyla BİREBİR aynı kurallarla burada da uygulanır: backend
/// zaten bu endpoint'leri requireRole ile koruduğu için, bir teknisyenin bu
/// listede yönetici-only bir modülü GÖRMESİ bile yanlış olurdu (bkz.
/// _allEntries içindeki `roles` alanları).
class AllModulesScreen extends StatefulWidget {
  /// Harita/Panel gibi eskiden MainShell sekmesi olan hedefler için — Panel
  /// (DashboardScreen) İş Emirleri sekmesine geçiş yapabilmek için bu
  /// callback'e ihtiyaç duyar (bkz. main_shell.dart _navigateToTab).
  final void Function(int tabIndex, {WorkOrderStatus? statusFilter}) onNavigate;

  const AllModulesScreen({super.key, required this.onNavigate});

  @override
  State<AllModulesScreen> createState() => _AllModulesScreenState();
}

class _ModuleEntry {
  final IconData icon;
  final String title;
  final String subtitle;
  final String category;
  final Color Function(BuildContext) color;
  final WidgetBuilder screenBuilder;

  const _ModuleEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.color,
    required this.screenBuilder,
  });
}

class _AllModulesScreenState extends State<AllModulesScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_ModuleEntry> _entries(AuthProvider auth) {
    return [
      _ModuleEntry(
        icon: Icons.location_on_outlined,
        title: 'Harita',
        subtitle: 'İş emirlerini konum üzerinde gör',
        category: 'Operasyon',
        color: AppColors.primary,
        screenBuilder: (_) => const MapScreen(),
      ),
      _ModuleEntry(
        icon: Icons.bar_chart_outlined,
        title: 'Panel',
        subtitle: 'Grafikler ve özet göstergeler',
        category: 'Operasyon',
        color: AppColors.positive,
        screenBuilder: (_) => DashboardScreen(onNavigate: widget.onNavigate),
      ),
      _ModuleEntry(
        icon: Icons.inventory_2_outlined,
        title: 'Ekipman',
        subtitle: 'Varlıkları tara veya ara',
        category: 'Operasyon',
        color: AppColors.primary,
        screenBuilder: (_) => const EquipmentHomeScreen(),
      ),
      _ModuleEntry(
        icon: Icons.shield_outlined,
        title: 'İş Güvenliği',
        subtitle: 'Olay/Tehlike bildir',
        category: 'Operasyon',
        color: AppColors.positive,
        screenBuilder: (_) => const IsgReportListScreen(),
      ),
      _ModuleEntry(
        icon: Icons.warehouse_outlined,
        title: 'Stok / Malzeme',
        subtitle: 'Yedek parça envanteri',
        category: 'Operasyon',
        color: AppColors.primary,
        screenBuilder: (_) => const MaterialListScreen(),
      ),
      // Bakım Planlama, Ana Sayfa'daki eski kartla AYNI RBAC'a sahip
      // (dispeçer/yönetici) — "Önleyici İş Emri Oluştur" aksiyonunu
      // barındırdığı için iş emri oluşturma yetkisiyle eşleniktir.
      if (auth.canCreateWorkOrders)
        _ModuleEntry(
          icon: Icons.build_circle_outlined,
          title: 'Bakım Planlama',
          subtitle: 'Kestirimci bakım önerileri',
          category: 'Operasyon',
          color: AppColors.positive,
          screenBuilder: (_) => const MaintenanceRecommendationsScreen(),
        ),
      if (auth.isYonetici) ...[
        _ModuleEntry(
          icon: Icons.manage_accounts_outlined,
          title: 'Kullanıcı Yönetimi',
          subtitle: 'Ekle · Düzenle',
          category: 'Yönetim',
          color: AppColors.primary,
          screenBuilder: (_) => const UserManagementListScreen(),
        ),
        _ModuleEntry(
          icon: Icons.phonelink_lock_outlined,
          title: 'Cihaz Yönetimi',
          subtitle: 'Kilitle · Senkronize et',
          category: 'Yönetim',
          color: AppColors.positive,
          screenBuilder: (_) => const DeviceListScreen(),
        ),
        _ModuleEntry(
          icon: Icons.query_stats_outlined,
          title: 'Raporlar',
          subtitle: 'Bölgesel risk · Eğilimler',
          category: 'Yönetim',
          color: AppColors.primary,
          screenBuilder: (_) => const ReportsScreen(),
        ),
        _ModuleEntry(
          icon: Icons.search,
          title: 'Şüpheli Sayaçlar',
          subtitle: 'Kayıp-kaçak / anomali tespiti',
          category: 'Yönetim',
          color: AppColors.positive,
          screenBuilder: (_) => const SuspiciousMetersScreen(),
        ),
        _ModuleEntry(
          icon: Icons.analytics_outlined,
          title: 'Kullanım Analitiği',
          subtitle: 'En çok kullanılan ekran/butonlar',
          category: 'Yönetim',
          color: AppColors.primary,
          screenBuilder: (_) => const AnalyticsScreen(),
        ),
      ],
      _ModuleEntry(
        icon: Icons.notifications_outlined,
        title: 'Bildirimler',
        subtitle: 'Tüm uyarılar',
        category: 'Sistem',
        color: AppColors.primary,
        screenBuilder: (_) => const NotificationsScreen(),
      ),
      _ModuleEntry(
        icon: Icons.settings_outlined,
        title: 'Ayarlar',
        subtitle: 'Tema, bildirimler, çevrimdışı mod',
        category: 'Sistem',
        color: AppColors.positive,
        screenBuilder: (_) => const SettingsScreen(),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final query = _query.trim().toLowerCase();
    final entries = _entries(auth)
        .where((e) => query.isEmpty || e.title.toLowerCase().contains(query))
        .toList();

    final categories = <String>['Operasyon', 'Yönetim', 'Sistem'];

    return Scaffold(
      appBar: const AppTopBar(title: 'Tüm Modüller'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Modül ara…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      'Aramanla eşleşen bir modül bulunamadı.',
                      style: AppTextStyles.bodyMedium(
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      0,
                      AppSpacing.md,
                      AppSpacing.xl,
                    ),
                    children: [
                      for (final category in categories)
                        if (entries.any((e) => e.category == category)) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.sm,
                            ),
                            child: Text(
                              category,
                              style: AppTextStyles.headingMedium(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                          for (final entry in entries.where(
                            (e) => e.category == category,
                          ))
                            _ModuleTile(entry: entry),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  final _ModuleEntry entry;
  const _ModuleTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = entry.color(context);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: entry.screenBuilder)),
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: color.withValues(alpha: isDark ? 0.28 : 0.15),
          child: Icon(entry.icon, size: 20, color: color),
        ),
        title: Text(
          entry.title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(entry.subtitle),
        trailing: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
