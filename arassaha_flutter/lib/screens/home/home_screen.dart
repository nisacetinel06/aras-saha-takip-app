import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/dashboard_summary.dart';
import '../../models/work_order.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/user_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_card.dart';
import '../../widgets/role_badge.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/work_order_card.dart' show formatRelativeTime;
import '../admin/user_management_list_screen.dart';
import '../devices/device_list_screen.dart';
import '../equipment/equipment_home_screen.dart';
import '../equipment/qr_scanner_screen.dart';
import '../equipment/suspicious_meters_screen.dart';
import '../isg/isg_report_list_screen.dart';
import '../maintenance/maintenance_recommendations_screen.dart';
import '../notifications/notifications_screen.dart';
import '../work_order_detail_screen.dart';
import '../work_orders/create_work_order_screen.dart';

const _weekdays = [
  'Pazartesi',
  'Salı',
  'Çarşamba',
  'Perşembe',
  'Cuma',
  'Cumartesi',
  'Pazar',
];
const _months = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];

String _formatToday() {
  final now = DateTime.now();
  return '${now.day} ${_months[now.month - 1]} ${now.year}, ${_weekdays[now.weekday - 1]}';
}

/// Ana Sayfa (Hub): tüm modüllere net şekilde yönlendiren merkezi ekran.
/// MainShell'in bir sekmesi olarak gösterilir; kendi Scaffold/AppBar'ı yoktur
/// (FAB hariç — bu, MainShell'in Scaffold'ından bağımsız olarak zaten öyleydi).
/// Bkz. DESIGN_SYSTEM.md Bölüm B.
///
/// Görsel dil, kullanıcının verdiği referans Flutter koduna göre klonlandı:
/// üstte hafif renkli bir gradyan şerit, karşılama satırı (avatar + isim +
/// rol rozeti + tarih + zil), yatay kaydırmalı istatistik kartları, yatay
/// hızlı işlemler şeridi, sabit yükseklikli modül kartları (tonal daire
/// ikonlar) ve son aktiviteler listesi.
///
/// İŞ MANTIĞI DEĞİŞMEDİ — yalnızca görsel yeniden düzenleme. Referans koddan
/// BİLEREK farklı uygulanan noktalar:
/// 1) "Yeni İş Emri Oluştur" hem hızlı işlem hem FAB olarak, referanstaki gibi
///    var — ama ikisi de gerçek `CreateWorkOrderScreen`e gider (referanstaki
///    gibi yerel/sahte bir bottom sheet DEĞİL); backend'e gerçekten kaydeder,
///    RBAC'a (yalnızca dispeçer/yönetici) uyar ve Modül 10'daki NLP öneri
///    özelliğini de içerir.
/// 2) İstatistik kartlarındaki "↘ Gecikmiş / ↗ Yolunda / ↗ Ortalamadan Hızlı"
///    gibi ifadeler backend'de karşılığı olmayan UYDURMA verilerdi (bkz.
///    ARCHITECTURE.md Temel Kalite İlkesi) — yalnızca gerçekten var olan
///    `priorityBreakdown[acil]` sayısı bir rozet olarak kullanıldı, diğer iki
///    kartta sahte bir trend metni YOK.
/// 3) Marka rengi olarak uygulamanın mevcut birincil rengi (AppColors.primary)
///    korundu — referans kodun kendi mavisi (#2563EB) yalnızca bu ekrana özel
///    uygulanmadı, çünkü bu tüm uygulamadaki (butonlar, diğer ekranlar)
///    tutarlılığı bozardı.
/// 4) Profil fotoğrafı hâlâ gerçek `UserAvatar` bileşeninden gelir (backend'den
///    gerçek fotoğraf ya da harf avatarı) — referanstaki sabit stok fotoğraf
///    (NetworkImage) kullanılmadı.
/// 5) DÜZELTME (merkezi header turu): Karşılama satırında BİR ARA bir bildirim
///    zili de vardı; bu, MainShell'in üst çubuğundaki zille (Ana Sayfa bu
///    çubuğun ALTINDA gösterildiği için) aynı ekranda İKİ KEZ görünen gerçek
///    bir tekrar bugıydı — kaldırıldı (bkz. widgets/app_top_bar.dart).
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final summary = context.watch<DashboardProvider>().summary;
    final auth = context.watch<AuthProvider>();
    final myProfile = context.watch<UserProvider>().myProfile;
    final unreadNotifications = context
        .watch<NotificationProvider>()
        .unreadCount;

    // Rol bazlı görünürlük (Modül 7 — RBAC): backend zaten bu endpoint'leri
    // rol bazlı engelliyor (requireRole), burada UI tarafında da aynı
    // ayrımı yansıtıyoruz — teknisyen/dispeçer bu kartları hiç görmez.
    final workOrdersCardTitle = auth.isTeknisyen
        ? 'Görevlerim'
        : 'Tüm İş Emirleri';
    final acilCount = summary?.priorityBreakdown[WorkOrderPriority.acil] ?? 0;

    void goToCreateWorkOrder() => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CreateWorkOrderScreen()));

    return Scaffold(
      body: SafeArea(
        child: Container(
          // Üstte hafif renkli bir gradyan, referans tasarımdaki header
          // arkaplanını taklit eder — %22'lik durakta zemin rengine döner.
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                scheme.primaryContainer.withValues(alpha: isDark ? 0.35 : 0.6),
                scheme.surface,
              ],
              stops: const [0.0, 0.22],
            ),
          ),
          child: RefreshIndicator(
            onRefresh: context.read<DashboardProvider>().fetchSummary,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xl + 56,
              ),
              children: [
                _GreetingRow(
                  name: auth.currentUser?.name ?? '',
                  role: auth.currentUser?.role ?? '',
                  roleLabel: auth.roleLabel,
                  photoPath: myProfile?.photoPath,
                  initials:
                      myProfile?.initials ??
                      (auth.currentUser?.name.isNotEmpty == true
                          ? auth.currentUser!.name[0].toUpperCase()
                          : '?'),
                  onAvatarTap: () => widget.onNavigate(4),
                ),
                const SizedBox(height: AppSpacing.lg),
                _StatsRow(summary: summary, acilCount: acilCount),
                const SizedBox(height: AppSpacing.lg),

                Text(
                  'Hızlı İşlemler',
                  style: AppTextStyles.headingMedium(color: scheme.onSurface),
                ),
                const SizedBox(height: AppSpacing.sm),
                _QuickActionsRow(
                  canCreateWorkOrder: auth.canCreateWorkOrders,
                  onCreateWorkOrder: goToCreateWorkOrder,
                  onScanQr: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const QrScannerScreen()),
                  ),
                  onReportIssue: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const IsgReportListScreen(),
                    ),
                  ),
                  onSync: () =>
                      context.read<DashboardProvider>().fetchSummary(),
                ),
                const SizedBox(height: AppSpacing.lg),

                Text(
                  'Modüller',
                  style: AppTextStyles.headingMedium(color: scheme.onSurface),
                ),
                const SizedBox(height: AppSpacing.sm),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: AppSpacing.sm,
                  crossAxisSpacing: AppSpacing.sm,
                  mainAxisExtent: 80,
                  children: [
                    _ModuleCard(
                      icon: Icons.assignment_outlined,
                      title: workOrdersCardTitle,
                      subtitle: summary != null
                          ? (acilCount > 0
                                ? '${summary.openCount} Açık, $acilCount Acil'
                                : '${summary.openCount} Açık')
                          : null,
                      color: AppColors.primary(context),
                      onTap: () => widget.onNavigate(1),
                    ),
                    _ModuleCard(
                      icon: Icons.location_on_outlined,
                      title: 'Harita Görünümü',
                      subtitle: 'Konum görünümü',
                      color: AppColors.accent(context),
                      onTap: () => widget.onNavigate(2),
                    ),
                    _ModuleCard(
                      icon: Icons.bar_chart_outlined,
                      title: 'Panel',
                      subtitle: 'Performans özeti',
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
                          MaterialPageRoute(
                            builder: (_) => const DeviceListScreen(),
                          ),
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
                          MaterialPageRoute(
                            builder: (_) => const UserManagementListScreen(),
                          ),
                        ),
                      ),
                    // Kayıp-Kaçak / Anormal Tüketim Tespiti (Modül 11) — bir
                    // yönetim raporudur (backend GET /api/meters/suspicious
                    // giriş yapmış herkese açık olsa da, kaçak/kayıp takibi
                    // yönetimsel bir sorumluluktur) — Cihaz/Kullanıcı Yönetimi
                    // ile AYNI RBAC deseniyle yalnızca yöneticiye gösterilir.
                    if (auth.isYonetici)
                      _ModuleCard(
                        icon: Icons.search,
                        title: 'Şüpheli Sayaçlar',
                        subtitle: 'Kayıp-kaçak / anomali tespiti',
                        color: AppColors.danger(context),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SuspiciousMetersScreen(),
                          ),
                        ),
                      ),
                    // Kestirimci Bakım Planlama (Modül 12) — Modül 9'un risk
                    // skorundan türetilen bakım önerilerini gösterir ve
                    // "Önleyici İş Emri Oluştur" aksiyonunu barındırır; bu
                    // yüzden iş emri oluşturma yetkisiyle AYNI role gated'dir
                    // (dispeçer/yönetici) — backend de aynı requireRole'ü
                    // kullanır (bkz. routes/maintenance.js).
                    if (auth.canCreateWorkOrders)
                      _ModuleCard(
                        icon: Icons.build_circle_outlined,
                        title: 'Bakım Planlama',
                        subtitle: 'Kestirimci bakım önerileri',
                        color: AppColors.success(context),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const MaintenanceRecommendationsScreen(),
                          ),
                        ),
                      ),
                    _ModuleCard(
                      icon: Icons.inventory_2_outlined,
                      title: 'Ekipman',
                      subtitle: 'Varlıkları tara veya ara',
                      color: AppColors.accent(context),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const EquipmentHomeScreen(),
                        ),
                      ),
                    ),
                    _ModuleCard(
                      icon: Icons.shield_outlined,
                      title: 'İş Güvenliği',
                      subtitle: 'Olay/Tehlike bildir',
                      color: AppColors.danger(context),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const IsgReportListScreen(),
                        ),
                      ),
                    ),
                    _ModuleCard(
                      icon: Icons.notifications_outlined,
                      title: 'Bildirimler',
                      subtitle: unreadNotifications > 0
                          ? '$unreadNotifications Yeni Uyarı'
                          : 'Güncel',
                      color: AppColors.primary(context),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const NotificationsScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                Text(
                  'Son Aktiviteler',
                  style: AppTextStyles.headingMedium(color: scheme.onSurface),
                ),
                const SizedBox(height: AppSpacing.sm),
                _RecentActivitySection(items: summary?.recentActivity),
              ],
            ),
          ),
        ),
      ),
      // "Yeni İş Emri Ata" yalnızca dispeçer/yönetici içindir — teknisyen bu
      // FAB'ı hiç görmez (backend zaten POST /api/workorders'ı requireRole
      // ile engelliyor, bkz. routes/workOrders.js).
      floatingActionButton: auth.canCreateWorkOrders
          ? FloatingActionButton.extended(
              onPressed: goToCreateWorkOrder,
              icon: const Icon(Icons.add),
              label: const Text('Yeni İş Emri Ata'),
            )
          : null,
    );
  }
}

/// Karşılama satırı: avatar + isim + rol rozeti + bugünün tarihi.
///
/// BİLEREK bildirim zili YOK — bu, MainShell'in üst çubuğundaki
/// [NotificationBellButton] ile birebir aynı ekranda (Ana Sayfa sekmesi
/// MainShell'in Scaffold'ı içinde gösterildiği için) aynı anda görünüp
/// gerçek bir tekrar/çakışma bugı oluşturuyordu — bkz. widgets/app_top_bar.dart.
/// Kullanıcının rolü de yalnızca burada (RoleBadge ile) gösterilir; MainShell
/// artık kullanıcı adı/rolü hiç göstermez (bkz. main_shell.dart).
/// Avatara dokununca Profil sekmesine (index 4) geçilir.
class _GreetingRow extends StatelessWidget {
  final String name;
  final String role;
  final String roleLabel;
  final String? photoPath;
  final String initials;
  final VoidCallback onAvatarTap;

  const _GreetingRow({
    required this.name,
    required this.role,
    required this.roleLabel,
    required this.photoPath,
    required this.initials,
    required this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onAvatarTap,
          child: UserAvatar(
            photoPath: photoPath,
            initials: initials,
            role: role,
            radius: 28,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Merhaba, $name',
                style: AppTextStyles.headingMedium(color: scheme.onSurface),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              RoleBadge(role: role, label: roleLabel),
              const SizedBox(height: 6),
              Text(
                _formatToday(),
                style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Yatay kaydırılabilir istatistik kartları — Dashboard'daki tam grafiklerin
/// küçültülmüş bir önizlemesi. Yalnızca GERÇEKTEN var olan alanlar gösterilir;
/// "gecikmiş/yolunda/ortalamadan hızlı" gibi backend'de karşılığı olmayan
/// uydurma trend etiketleri kullanılmaz (bkz. ARCHITECTURE.md Temel Kalite
/// İlkesi). Tek istisna: ilk karttaki "Acil" rozeti — bu,
/// `priorityBreakdown[acil]` üzerinden GERÇEK bir sayı.
class _StatsRow extends StatelessWidget {
  final DashboardSummary? summary;
  final int acilCount;
  const _StatsRow({required this.summary, required this.acilCount});

  @override
  Widget build(BuildContext context) {
    if (summary == null) {
      return const AppCard(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _StatTile(
            icon: Icons.assignment_outlined,
            value: '${summary!.openCount}',
            label: 'Açık İş Emirleri',
            color: AppColors.primary(context),
            trend: acilCount > 0 ? '↘ $acilCount Acil' : null,
            trendColor: AppColors.danger(context),
          ),
          const SizedBox(width: AppSpacing.sm),
          _StatTile(
            icon: Icons.check_circle_outline,
            value: '${summary!.resolvedTodayCount}',
            label: 'Bugün Tamamlanan',
            color: AppColors.success(context),
          ),
          const SizedBox(width: AppSpacing.sm),
          _StatTile(
            icon: Icons.timer_outlined,
            value: '${summary!.avgResolutionHours.toStringAsFixed(1)} sa',
            label: 'Ort. Çözüm Süresi',
            color: AppColors.warning(context),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final String? trend;
  final Color? trendColor;

  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.trend,
    this.trendColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 150,
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                    maxLines: 2,
                  ),
                ),
                Icon(icon, size: 18, color: scheme.onSurface),
              ],
            ),
            const SizedBox(height: AppSpacing.sm + 2),
            Text(
              value,
              style: AppTextStyles.headingMedium(
                color: scheme.onSurface,
              ).copyWith(fontSize: 22),
            ),
            const SizedBox(height: 4),
            Text(
              trend ?? ' ',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: trendColor ?? Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Yatay kaydırılabilir hızlı işlemler şeridi. "İş Emri Oluştur" yalnızca
/// dispeçer/yönetici rolüne görünür (aynı FAB kısıtlaması) — teknisyen bu
/// çipi hiç görmez.
class _QuickActionsRow extends StatelessWidget {
  final bool canCreateWorkOrder;
  final VoidCallback onCreateWorkOrder;
  final VoidCallback onScanQr;
  final VoidCallback onReportIssue;
  final VoidCallback onSync;

  const _QuickActionsRow({
    required this.canCreateWorkOrder,
    required this.onCreateWorkOrder,
    required this.onScanQr,
    required this.onReportIssue,
    required this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (canCreateWorkOrder) ...[
            _QuickActionChip(
              icon: Icons.add,
              label: 'İş Emri Oluştur',
              onTap: onCreateWorkOrder,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          _QuickActionChip(
            icon: Icons.qr_code_scanner_outlined,
            label: 'QR Kod Tara',
            onTap: onScanQr,
          ),
          const SizedBox(width: AppSpacing.sm),
          _QuickActionChip(
            icon: Icons.report_problem_outlined,
            label: 'Sorun Bildir',
            onTap: onReportIssue,
          ),
          const SizedBox(width: AppSpacing.sm),
          // "Senkronize" burada bir cihaza komut göndermez (bu, DESIGN_SYSTEM.md'de
          // tarif edilen Cihaz Yönetimi'nin işi) — yalnızca Dashboard özetini
          // (zaten var olan fetchSummary) manuel olarak yeniler.
          _QuickActionChip(
            icon: Icons.sync,
            label: 'Senkronize',
            onTap: onSync,
          ),
        ],
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: scheme.onSurface),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Modül erişim ızgarasındaki tek kart — ikon, referans tasarımdaki gibi
/// tonal bir daire içinde (soluk zemin + doygun renkte ikon), yanında
/// başlık/alt başlık.
class _ModuleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ModuleCard({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 4,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: color.withValues(alpha: isDark ? 0.28 : 0.15),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: AppTextStyles.caption(
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Son Aktiviteler — GET /api/dashboard/summary yanıtındaki `recent_activity`
/// alanından gelir (backend, en son güncellenen 5 iş emrini döner). Bu veri
/// zaten DashboardProvider tarafından çekiliyordu; burada yalnızca
/// GÖRÜNTÜLENMEYE başlandı — yeni bir endpoint/iş mantığı eklenmedi.
class _RecentActivitySection extends StatelessWidget {
  final List<RecentActivityItem>? items;
  const _RecentActivitySection({required this.items});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (items == null) {
      return const AppCard(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (items!.isEmpty) {
      return AppCard(
        child: Text(
          'Henüz bir aktivite yok.',
          style: AppTextStyles.bodyMedium(color: scheme.onSurfaceVariant),
        ),
      );
    }

    return Column(
      children: [
        for (int i = 0; i < items!.length && i < 3; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          _RecentActivityTile(item: items![i]),
        ],
      ],
    );
  }
}

class _RecentActivityTile extends StatelessWidget {
  final RecentActivityItem item;
  const _RecentActivityTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = statusColor(context, item.status);
    final isResolved = item.status == WorkOrderStatus.cozuldu;

    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WorkOrderDetailScreen(workOrderId: item.id),
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm + 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: color.withValues(alpha: isDark ? 0.28 : 0.15),
            child: Icon(
              isResolved
                  ? Icons.check_circle_rounded
                  : Icons.play_circle_fill_rounded,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.status.label} · ${formatRelativeTime(item.updatedAt)}',
                  style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
