import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/dashboard_summary.dart';
import '../models/equipment_risk.dart';
import '../models/work_order.dart';
import '../providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/risk_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/status_badge.dart';
import '../widgets/work_order_card.dart' show formatRelativeTime;
import 'equipment/equipment_detail_screen.dart';
import 'work_order_detail_screen.dart';

/// Dashboard sekmesi: Modül 2'nin detaylı analiz görünümü (grafikler, son
/// aktiviteler). MainShell'in ortak app bar'ı altında gösterilir; kendi
/// Scaffold/AppBar'ı yoktur (WorkOrderListScreen ile aynı desen).
class DashboardScreen extends StatefulWidget {
  /// Özet kartlardan İş Emirleri/Harita sekmesine, ilgili statü filtresiyle
  /// geçmek için MainShell'e iletilir.
  final void Function(int tabIndex, {WorkOrderStatus? statusFilter}) onNavigate;

  const DashboardScreen({super.key, required this.onNavigate});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DashboardProvider>().fetchSummary();
      // "Riskli Ekipmanlar" bir yönetim raporudur; backend GET
      // /api/dashboard/risky-equipment'i requireRole('yonetici') ile korur
      // (bkz. routes/risk.js) — teknisyen/dispeçer için bu isteği hiç atmayız.
      if (context.read<AuthProvider>().isYonetici) {
        context.read<RiskProvider>().fetchRiskyEquipment();
      }
    });
  }

  void _openList(WorkOrderStatus status) => widget.onNavigate(1, statusFilter: status);

  void _openMap(WorkOrderStatus status) => widget.onNavigate(2, statusFilter: status);

  @override
  Widget build(BuildContext context) {
    final isYonetici = context.watch<AuthProvider>().isYonetici;

    return Consumer<DashboardProvider>(
      builder: (context, provider, _) {
        if (provider.errorMessage != null && provider.summary == null) {
          return _ErrorState(message: provider.errorMessage!, onRetry: provider.fetchSummary);
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
              _SummaryCardsRow(summary: summary, onCardTap: _openList, onMapTap: _openMap),
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
            ],
          ),
        );
      },
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

  const _SummaryCardsRow({required this.summary, required this.onCardTap, required this.onMapTap});

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
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          // Modüller arası bağlantı: bu ikon, ilgili statü filtresi önceden
          // uygulanmış şekilde doğrudan Harita sekmesine götürür.
          Positioned(
            top: -8,
            right: -6,
            child: IconButton(
              icon: const Icon(Icons.map_outlined),
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
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
    final entries = summary.statusBreakdown.entries.where((e) => e.value > 0).toList();
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);

    if (total == 0) {
      return const _EmptyChartCard(message: 'Gösterilecek veri yok.');
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
                        decoration: BoxDecoration(color: statusColor(context, e.key), shape: BoxShape.circle),
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
    final maxVal = entries.fold<int>(0, (max, e) => e.value > max ? e.value : max);

    if (maxVal == 0) {
      return const _EmptyChartCard(message: 'Gösterilecek veri yok.');
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
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 || index >= entries.length) return const SizedBox.shrink();
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
      return const _EmptyChartCard(message: 'Henüz bir aktivite yok.');
    }

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              title: Text(items[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(formatRelativeTime(items[i].updatedAt)),
              trailing: StatusBadge(status: items[i].status),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => WorkOrderDetailScreen(workOrderId: items[i].id)),
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

    if (provider.riskyListErrorMessage != null && provider.riskyEquipment.isEmpty) {
      return _EmptyChartCard(message: provider.riskyListErrorMessage!);
    }

    if (provider.riskyEquipment.isEmpty) {
      return const _EmptyChartCard(message: 'Henüz risk skoru hesaplanmış ekipman yok.');
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
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
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
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EquipmentDetailScreen(equipmentId: item.id)),
      ),
    );
  }
}

class _EmptyChartCard extends StatelessWidget {
  final String message;
  const _EmptyChartCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          message,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text('Veriler yüklenemedi: $message', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            AppButton(label: 'Tekrar Dene', onPressed: onRetry),
          ],
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

class _DashboardSkeletonState extends State<_DashboardSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _box({required double height}) {
    return FadeTransition(
      opacity: Tween(begin: 0.4, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
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
