import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/dashboard_summary.dart';
import '../models/equipment_risk.dart';
import '../models/material.dart';
import '../models/work_order.dart';
import '../providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/map_provider.dart';
import '../providers/material_provider.dart';
import '../providers/risk_provider.dart';
import '../services/analytics_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/status_badge.dart';
import '../widgets/work_order_card.dart' show formatRelativeTime;
import 'equipment/equipment_detail_screen.dart';
import 'map/map_screen.dart';
import 'materials/material_detail_screen.dart';
import 'materials/material_list_screen.dart';
import 'work_order_detail_screen.dart';

/// Panel (Dashboard): Modül 2'nin detaylı analiz görünümü (grafikler, son
/// aktiviteler). Ana Sayfa revizyonundan önce MainShell'in kalıcı bir
/// sekmesiydi; artık Ana Sayfa'nın "öne çıkanlar" kartından ya da "Tüm
/// Modüller" ekranından normal bir sayfa olarak PUSH ediliyor — bu yüzden
/// (WorkOrderListScreen/MapScreen'in AKSİNE) kendi Scaffold/AppBar'ı vardır.
class DashboardScreen extends StatefulWidget {
  /// Özet kartlardan İş Emirleri sekmesine, ilgili statü filtresiyle geçmek
  /// için MainShell'e iletilir (bkz. main_shell.dart _navigateToTab).
  final void Function(int tabIndex, {WorkOrderStatus? statusFilter}) onNavigate;

  const DashboardScreen({super.key, required this.onNavigate});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('DashboardScreen');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DashboardProvider>().fetchSummary();
      // "Riskli Ekipmanlar" bir yönetim raporudur; backend GET
      // /api/dashboard/risky-equipment'i requireRole('yonetici') ile korur
      // (bkz. routes/risk.js) — teknisyen/dispeçer için bu isteği hiç atmayız.
      if (context.read<AuthProvider>().isYonetici) {
        context.read<RiskProvider>().fetchRiskyEquipment();
      }
      // Kritik Stoktaki Malzemeler (Modül 13) — Riskli Ekipmanlar'ın aksine
      // bir yönetim raporu DEĞİLDİR (backend GET /api/dashboard/low-stock-materials
      // giriş yapmış HERKESE açık, bkz. routes/materials.js) — teknisyen/
      // dispeçer için de çekilir.
      context.read<MaterialProvider>().fetchLowStockMaterials();
    });
  }

  /// Bu ekran artık PUSH edilen bir sayfa olduğu için, İş Emirleri sekmesine
  /// geçmeden önce kendisini kapatır (aksi halde İş Emirleri sekmesi altında,
  /// hâlâ ekranda asılı kalırdı) — bkz. AssistantChatScreen._handleNavigation
  /// içindeki AYNI "önce pop, sonra sekme değiştir" deseni.
  void _openList(WorkOrderStatus status) {
    Navigator.of(context).pop();
    widget.onNavigate(1, statusFilter: status);
  }

  /// Harita artık bir MainShell sekmesi DEĞİL (bkz. main_shell.dart) — bu
  /// yüzden statü filtresi önce MapProvider'a uygulanır, Dashboard kapatılır,
  /// sonra Harita normal bir sayfa olarak push edilir.
  void _openMap(WorkOrderStatus status) {
    context.read<MapProvider>().fetchMapData(statusFilter: status.toJson());
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute(builder: (_) => const MapScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final isYonetici = context.watch<AuthProvider>().isYonetici;

    return Scaffold(
      appBar: const AppTopBar(title: 'Panel'),
      body: Consumer<DashboardProvider>(
        builder: (context, provider, _) {
          if (provider.errorMessage != null && provider.summary == null) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'Panel verileri yüklenemedi',
              subtitle: provider.errorMessage!,
              onPrimaryAction: provider.fetchSummary,
              primaryActionLabel: 'Tekrar Dene',
              primaryActionVariant: AppButtonVariant.secondary,
            );
          }

          final summary = provider.summary;
          if (summary == null) {
            return const _DashboardSkeleton();
          }
          return RefreshIndicator(
            onRefresh: provider.fetchSummary,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                _SummaryCardsRow(
                  summary: summary,
                  onCardTap: _openList,
                  onMapTap: _openMap,
                ),
                const SizedBox(height: AppSpacing.lg),
                const _SectionHeader('Durum Dağılımı'),
                _StatusPieChart(summary: summary),
                const SizedBox(height: AppSpacing.lg),
                const _SectionHeader('Öncelik Dağılımı'),
                _PriorityBarChart(summary: summary),
                const SizedBox(height: AppSpacing.lg),
                const _SectionHeader('Son Aktiviteler'),
                _RecentActivityList(items: summary.recentActivity),
                // Riskli Ekipmanlar bir yönetim raporudur (bkz. initState) —
                // yalnızca yönetici rolüne gösterilir.
                if (isYonetici) ...[
                  const SizedBox(height: AppSpacing.lg),
                  const _SectionHeader('Riskli Ekipmanlar'),
                  const _RiskyEquipmentSection(),
                ],
                const SizedBox(height: AppSpacing.lg),
                const _SectionHeader('Kritik Stoktaki Malzemeler'),
                const _LowStockMaterialsSection(),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
    );
  }
}

class _SummaryCardsRow extends StatelessWidget {
  final DashboardSummary summary;
  final void Function(WorkOrderStatus status) onCardTap;
  final void Function(WorkOrderStatus status) onMapTap;

  const _SummaryCardsRow({
    required this.summary,
    required this.onCardTap,
    required this.onMapTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            icon: Icons.warning_amber_rounded,
            iconColor: scheme.error,
            value: '${summary.openCount}',
            label: 'Açık Arızalar',
            onTap: () => onCardTap(WorkOrderStatus.acik),
            onMapTap: () => onMapTap(WorkOrderStatus.acik),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            icon: Icons.check_circle_outline,
            iconColor: scheme.secondary,
            value: '${summary.resolvedTodayCount}',
            label: 'Bugün Çözülen',
            onTap: () => onCardTap(WorkOrderStatus.cozuldu),
            onMapTap: () => onMapTap(WorkOrderStatus.cozuldu),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            icon: Icons.schedule,
            iconColor: scheme.primary,
            value: '${summary.avgResolutionHours.toStringAsFixed(1)} sa',
            label: 'Ort. Çözüm Süresi',
            onTap: () => onCardTap(WorkOrderStatus.cozuldu),
            onMapTap: () => onMapTap(WorkOrderStatus.cozuldu),
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final VoidCallback onTap;
  final VoidCallback onMapTap;

  const _SummaryCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    required this.onTap,
    required this.onMapTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            children: [
              Icon(icon, color: iconColor, size: 26),
              const SizedBox(height: 10),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          // Modüller arası bağlantı: bu ikon, ilgili statü filtresi önceden
          // uygulanmış şekilde doğrudan Harita sekmesine götürür.
          // B2 (dokunma alanı): tıklanabilir alan 48x48 dp'ye çıkarıldı
          // (öncesi 30x30 dp'ydi) — görsel ikon küçük (16dp) kalmaya devam
          // eder, yalnızca dokunma alanı büyüdü; konumlandırma buna göre
          // (-8/-6 yerine -4/-2) hafifletildi ki kart dışına taşması artmasın.
          Positioned(
            top: -4,
            right: -2,
            child: IconButton(
              icon: const Icon(Icons.map_outlined),
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              color: colorScheme.onSurfaceVariant,
              tooltip: 'Haritada Gör',
              onPressed: onMapTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPieChart extends StatelessWidget {
  final DashboardSummary summary;
  const _StatusPieChart({required this.summary});

  @override
  Widget build(BuildContext context) {
    final entries = summary.statusBreakdown.entries
        .where((e) => e.value > 0)
        .toList();
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);

    if (total == 0) {
      return const AppCard(
        child: EmptyState(
          icon: Icons.bar_chart_outlined,
          title: 'Gösterilecek veri yok',
        ),
      );
    }

    return AppCard(
      child: Row(
        children: [
          SizedBox(
            width: 130,
            height: 130,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 28,
                sections: entries.map((e) {
                  return PieChartSectionData(
                    value: e.value.toDouble(),
                    color: statusColor(context, e.key),
                    title: '${e.value}',
                    radius: 40,
                    titleStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: onStatusColor(context, e.key),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: entries.map((e) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: statusColor(context, e.key),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text('${e.key.label}: ${e.value}')),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _PriorityBarChart extends StatelessWidget {
  final DashboardSummary summary;
  const _PriorityBarChart({required this.summary});

  @override
  Widget build(BuildContext context) {
    final entries = WorkOrderPriority.values
        .map((p) => MapEntry(p, summary.priorityBreakdown[p] ?? 0))
        .toList();
    final maxVal = entries.fold<int>(
      0,
      (max, e) => e.value > max ? e.value : max,
    );

    if (maxVal == 0) {
      return const AppCard(
        child: EmptyState(
          icon: Icons.bar_chart_outlined,
          title: 'Gösterilecek veri yok',
        ),
      );
    }

    final onSurface = Theme.of(context).colorScheme.onSurface;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(8, 20, 16, 8),
      child: SizedBox(
        height: 160,
        child: BarChart(
          BarChartData(
            maxY: (maxVal + 1).toDouble(),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 || index >= entries.length)
                      return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        entries[index].key.label,
                        style: TextStyle(fontSize: 12, color: onSurface),
                      ),
                    );
                  },
                ),
              ),
            ),
            barGroups: entries.asMap().entries.map((entry) {
              final i = entry.key;
              final priority = entry.value.key;
              final count = entry.value.value;
              return BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: count.toDouble(),
                    color: priorityColor(context, priority),
                    width: 28,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _RecentActivityList extends StatelessWidget {
  final List<RecentActivityItem> items;
  const _RecentActivityList({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const AppCard(
        child: EmptyState(
          icon: Icons.history_outlined,
          title: 'Henüz bir aktivite yok',
        ),
      );
    }

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              title: Text(
                items[i].title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(formatRelativeTime(items[i].updatedAt)),
              trailing: StatusBadge(status: items[i].status),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        WorkOrderDetailScreen(workOrderId: items[i].id),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Arıza Risk Tahmini (Modül 9) — Dashboard'un "Riskli Ekipmanlar" bölümü.
/// GET /api/dashboard/risky-equipment'ten gelen ilk 5 kaydı kompakt bir liste
/// olarak gösterir; bir öğeye tıklanınca Ekipman Detayı'na gidilir (modüller
/// arası bağlantı).
///
/// DÜRÜSTLÜK NOTU: Risk skorları, ArasSaha'nın henüz gerçek bir arıza
/// geçmişi biriktirmemiş olması nedeniyle SENTETİK bir veri setiyle eğitilmiş
/// bir modelden gelir (bkz. arassaha-ml/README.md).
class _RiskyEquipmentSection extends StatelessWidget {
  const _RiskyEquipmentSection();

  Color _colorFor(BuildContext context, RiskLevel level) {
    switch (level) {
      case RiskLevel.dusuk:
        return AppColors.success(context);
      case RiskLevel.orta:
        return AppColors.warning(context);
      case RiskLevel.yuksek:
        return AppColors.danger(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RiskProvider>();

    if (provider.isRiskyListLoading && provider.riskyEquipment.isEmpty) {
      return const AppCard(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (provider.riskyListErrorMessage != null &&
        provider.riskyEquipment.isEmpty) {
      return AppCard(
        child: EmptyState(
          icon: Icons.error_outline,
          title: 'Riskli ekipmanlar yüklenemedi',
          subtitle: provider.riskyListErrorMessage!,
          onPrimaryAction: provider.fetchRiskyEquipment,
          primaryActionLabel: 'Tekrar Dene',
          primaryActionVariant: AppButtonVariant.secondary,
        ),
      );
    }

    if (provider.riskyEquipment.isEmpty) {
      return const AppCard(
        child: EmptyState(
          icon: Icons.query_stats_outlined,
          title: 'Henüz risk skoru hesaplanmış ekipman yok',
        ),
      );
    }

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (int i = 0; i < provider.riskyEquipment.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _RiskyEquipmentTile(
              item: provider.riskyEquipment[i],
              color: _colorFor(context, provider.riskyEquipment[i].riskLevel),
            ),
          ],
        ],
      ),
    );
  }
}

class _RiskyEquipmentTile extends StatelessWidget {
  final RiskyEquipmentSummary item;
  final Color color;
  const _RiskyEquipmentTile({required this.item, required this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color,
        radius: 18,
        child: Text(
          '${item.riskScore}',
          style: TextStyle(
            color: accessibleOnColor(color),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      title: Text(
        '${item.equipmentType.label} · ${item.qrCode}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        item.locationName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
      ),
      trailing: Text(
        item.riskLevel.label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EquipmentDetailScreen(equipmentId: item.id),
        ),
      ),
    );
  }
}

/// Kritik Stoktaki Malzemeler (Modül 13) — [_RiskyEquipmentSection] ile AYNI
/// desen (loading/error/empty/list durumları, AppCard + Divider satırları),
/// yalnızca farklı bir provider/veri kaynağından besleniyor. Riskli
/// Ekipmanlar'dan FARKLI olarak yönetici gated değildir — herkese görünür.
class _LowStockMaterialsSection extends StatelessWidget {
  const _LowStockMaterialsSection();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MaterialProvider>();

    if (provider.isLoadingLowStock && provider.lowStockMaterials.isEmpty) {
      return const AppCard(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (provider.lowStockErrorMessage != null &&
        provider.lowStockMaterials.isEmpty) {
      return AppCard(
        child: EmptyState(
          icon: Icons.error_outline,
          title: 'Kritik stok verileri yüklenemedi',
          subtitle: provider.lowStockErrorMessage!,
          onPrimaryAction: provider.fetchLowStockMaterials,
          primaryActionLabel: 'Tekrar Dene',
          primaryActionVariant: AppButtonVariant.secondary,
        ),
      );
    }

    if (provider.lowStockMaterials.isEmpty) {
      return const AppCard(
        child: EmptyState(
          icon: Icons.inventory_2_outlined,
          title: 'Kritik stokta malzeme yok',
        ),
      );
    }

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (int i = 0; i < provider.lowStockMaterials.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _LowStockMaterialTile(material: provider.lowStockMaterials[i]),
          ],
          InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MaterialListScreen()),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Tümünü Gör',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LowStockMaterialTile extends StatelessWidget {
  final MaterialItem material;
  const _LowStockMaterialTile({required this.material});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = AppColors.danger(context);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color,
        radius: 18,
        child: Icon(
          material.category.icon,
          size: 16,
          color: accessibleOnColor(color),
        ),
      ),
      title: Text(material.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        'Eşik: ${formatMaterialQuantity(material.minStockThreshold)} ${material.unit.label}',
        style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
      ),
      trailing: Text(
        '${formatMaterialQuantity(material.stockQuantity)} ${material.unit.label}',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MaterialDetailScreen(materialId: material.id),
        ),
      ),
    );
  }
}

/// Veri gelene kadar kartların/grafiklerin yerinde gösterilen basit bir
/// nabız (pulse) animasyonu — ek bir shimmer paketi gerektirmez.
class _DashboardSkeleton extends StatefulWidget {
  const _DashboardSkeleton();

  @override
  State<_DashboardSkeleton> createState() => _DashboardSkeletonState();
}

class _DashboardSkeletonState extends State<_DashboardSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _box({required double height}) {
    return FadeTransition(
      opacity: Tween(
        begin: 0.4,
        end: 1.0,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(child: _box(height: 110)),
            const SizedBox(width: 12),
            Expanded(child: _box(height: 110)),
            const SizedBox(width: 12),
            Expanded(child: _box(height: 110)),
          ],
        ),
        const SizedBox(height: 20),
        _box(height: 48),
        const SizedBox(height: 24),
        _box(height: 180),
        const SizedBox(height: 24),
        _box(height: 180),
        const SizedBox(height: 24),
        _box(height: 220),
      ],
    );
  }
}
