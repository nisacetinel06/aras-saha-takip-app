import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/dashboard_summary.dart';
import '../../models/work_order.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/user_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_card.dart';
import '../../widgets/role_badge.dart';
import '../../widgets/user_avatar.dart';
import '../admin/user_management_list_screen.dart';
import '../devices/device_list_screen.dart';
import '../equipment/equipment_home_screen.dart';
import '../isg/isg_report_list_screen.dart';
import '../work_orders/create_work_order_screen.dart';

const _weekdays = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];
const _months = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
];

String _formatToday() {
  final now = DateTime.now();
  return '${now.day} ${_months[now.month - 1]} ${now.year}, ${_weekdays[now.weekday - 1]}';
}

/// Ana Sayfa (Hub): tüm modüllere net şekilde yönlendiren merkezi ekran.
/// MainShell'in bir sekmesi olarak gösterilir; kendi Scaffold/AppBar'ı yoktur.
/// Bkz. DESIGN_SYSTEM.md Bölüm B.
class HomeScreen extends StatefulWidget {
  /// MainShell'e "şu sekmeye, isteğe bağlı şu statü filtresiyle geç" demek
  /// için kullanılır (örn. İş Emirleri modül kartı -> sekme 1).
  final void Function(int tabIndex, {WorkOrderStatus? statusFilter}) onNavigate;

  const HomeScreen({super.key, required this.onNavigate});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DashboardProvider>().fetchSummary();
    });
  }

  void _showComingSoon(String moduleName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$moduleName modülü yakında eklenecek.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final summary = context.watch<DashboardProvider>().summary;
    final auth = context.watch<AuthProvider>();
    final myProfile = context.watch<UserProvider>().myProfile;

    // Rol bazlı görünürlük (Modül 7 — RBAC): backend zaten bu endpoint'leri
    // rol bazlı engelliyor (requireRole), burada UI tarafında da aynı
    // ayrımı yansıtıyoruz — teknisyen/dispeçer bu kartları hiç görmez.
    final workOrdersCardTitle = auth.isTeknisyen ? 'Görevlerim' : 'Tüm İş Emirleri';

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xl + 56),
          children: [
            // Karşılama (Modül 8 — Profil): isim + rol rozeti + avatar; avatara
            // dokununca doğrudan Profil sekmesine (index 4) geçilir.
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Merhaba, ${auth.currentUser?.name ?? ''}',
                        style: AppTextStyles.displayLarge(color: scheme.onSurface),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      RoleBadge(role: auth.currentUser?.role ?? '', label: auth.roleLabel),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                GestureDetector(
                  onTap: () => widget.onNavigate(4),
                  child: UserAvatar(
                    photoPath: myProfile?.photoPath,
                    initials: myProfile?.initials ?? (auth.currentUser?.name.isNotEmpty == true ? auth.currentUser!.name[0].toUpperCase() : '?'),
                    role: auth.currentUser?.role ?? '',
                    radius: 26,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(_formatToday(), style: AppTextStyles.bodyMedium(color: scheme.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.lg),
            _CompactSummaryStrip(summary: summary),
            const SizedBox(height: AppSpacing.lg),
            Text('Modüller', style: AppTextStyles.headingMedium(color: scheme.onSurface)),
            const SizedBox(height: AppSpacing.sm),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: AppSpacing.sm,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio: 2.3,
              children: [
                _ModuleCard(
                  icon: Icons.assignment_outlined,
                  title: workOrdersCardTitle,
                  subtitle: summary != null ? '${summary.openCount} açık' : null,
                  color: AppColors.primary(context),
                  onTap: () => widget.onNavigate(1),
                ),
                _ModuleCard(
                  icon: Icons.location_on_outlined,
                  title: 'Harita',
                  subtitle: 'Konum görünümü',
                  color: AppColors.accent(context),
                  onTap: () => widget.onNavigate(2),
                ),
                _ModuleCard(
                  icon: Icons.bar_chart_outlined,
                  title: 'Dashboard',
                  subtitle: 'Raporlar / Analiz',
                  color: AppColors.success(context),
                  onTap: () => widget.onNavigate(3),
                ),
                // Cihaz Yönetimi yalnızca yönetici rolüne görünür — dispeçer
                // ve teknisyen bu kartı hiç görmez (backend zaten requireRole
                // ile engelliyor, bkz. routes/devices.js).
                if (auth.isYonetici)
                  _ModuleCard(
                    icon: Icons.phonelink_lock_outlined,
                    title: 'Cihaz Yönetimi',
                    subtitle: 'Kilitle · Senkronize et',
                    color: AppColors.warning(context),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const DeviceListScreen()),
                    ),
                  ),
                // Kullanıcı Yönetimi de yalnızca yönetici rolüne görünür
                // (bkz. ARCHITECTURE.md Modül 8) — backend requireRole ile
                // ayrıca engelliyor.
                if (auth.isYonetici)
                  _ModuleCard(
                    icon: Icons.manage_accounts_outlined,
                    title: 'Kullanıcı Yönetimi',
                    subtitle: 'Ekle · Düzenle',
                    color: roleColor(context, 'yonetici'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const UserManagementListScreen()),
                    ),
                  ),
                _ModuleCard(
                  icon: Icons.inventory_2_outlined,
                  title: 'Ekipman',
                  subtitle: 'QR ile sorgula',
                  color: AppColors.accent(context),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const EquipmentHomeScreen()),
                  ),
                ),
                _ModuleCard(
                  icon: Icons.shield_outlined,
                  title: 'İSG Bildirimi',
                  subtitle: 'Risk bildir',
                  color: AppColors.danger(context),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const IsgReportListScreen()),
                  ),
                ),
                _ModuleCard(
                  icon: Icons.notifications_outlined,
                  title: 'Bildirimler',
                  subtitle: 'Yakında',
                  color: AppColors.primary(context),
                  comingSoon: true,
                  onTap: () => _showComingSoon('Bildirimler'),
                ),
              ],
            ),
          ],
        ),
      ),
      // "Yeni İş Emri Ata" yalnızca dispeçer/yönetici içindir — teknisyen bu
      // FAB'ı hiç görmez (backend zaten POST /api/workorders'ı requireRole
      // ile engelliyor, bkz. routes/workOrders.js).
      floatingActionButton: auth.canCreateWorkOrders
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CreateWorkOrderScreen()),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Yeni İş Emri Ata'),
            )
          : null,
    );
  }
}

/// Dashboard'daki 3 özet kartının küçültülmüş, yatay şeridi. Tam grafikler
/// burada tekrarlanmaz — o detaylar Dashboard sekmesinde kalır.
class _CompactSummaryStrip extends StatelessWidget {
  final DashboardSummary? summary;
  const _CompactSummaryStrip({required this.summary});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (summary == null) {
      return AppCard(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
          ),
        ),
      );
    }

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 4, horizontal: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: _StripStat(
              value: '${summary!.openCount}',
              label: 'Açık Arıza',
              color: AppColors.danger(context),
            ),
          ),
          _StripDivider(),
          Expanded(
            child: _StripStat(
              value: '${summary!.resolvedTodayCount}',
              label: 'Bugün Çözülen',
              color: AppColors.success(context),
            ),
          ),
          _StripDivider(),
          Expanded(
            child: _StripStat(
              value: '${summary!.avgResolutionHours.toStringAsFixed(1)} sa',
              label: 'Ort. Süre',
              color: AppColors.primary(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _StripDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 32,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

class _StripStat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _StripStat({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(value, style: AppTextStyles.headingMedium(color: color)),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Modül erişim ızgarasındaki tek kart. Durum şeridi (imza öğesi) burada
/// KULLANILMAZ — bu kartlar bir statü taşımıyor. Bunun yerine her modülün
/// kendi rengiyle tonlanmış küçük bir ikon rozeti kullanılır — ızgaranın
/// tek renkli/donuk değil, canlı görünmesini sağlar.
class _ModuleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;
  final bool comingSoon;
  final VoidCallback onTap;

  const _ModuleCard({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.color,
    this.comingSoon = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final contentOpacity = comingSoon ? 0.55 : 1.0;

    return Opacity(
      opacity: contentOpacity,
      child: AppCard(
        onTap: onTap,
        backgroundTint: color,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AppRadius.chip),
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 3))],
              ),
              child: Icon(icon, size: 18, color: Colors.white),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: AppTextStyles.headingMedium(color: scheme.onSurface).copyWith(fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      subtitle!,
                      style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
