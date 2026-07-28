import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/dashboard_summary.dart';
import '../models/work_order.dart';
import '../providers/dashboard_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/bento_card.dart';
import '../widgets/status_badge.dart';
import '../widgets/work_order_card.dart' show formatRelativeTime;
import 'main_shell.dart';
import 'work_order_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DashboardProvider>().fetchSummary();
    });
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bu özellik yakında eklenecek.')),
    );
  }

  void _openList(WorkOrderStatus status) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MainShell(initialStatusFilter: status)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('ArasSaha'),
            Text(
              'Saha Operasyon Paneli',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Bildirimler',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => _showComingSoon('Bildirimler'),
          ),
          IconButton(
            tooltip: themeProvider.isDark ? 'Aydınlık moda geç' : 'Karanlık moda geç',
            icon: Icon(themeProvider.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: themeProvider.toggle,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Consumer<DashboardProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.summary == null) {
            return const _DashboardSkeleton();
          }

          if (provider.errorMessage != null && provider.summary == null) {
            return _ErrorState(message: provider.errorMessage!, onRetry: provider.fetchSummary);
          }

          final summary = provider.summary!;
          return RefreshIndicator(
            onRefresh: provider.fetchSummary,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _SummaryCardsRow(summary: summary, onCardTap: _openList),
                const SizedBox(height: 20),
                _QuickActionsRow(onComingSoon: _showComingSoon),
                const SizedBox(height: 24),
                const _SectionHeader('Durum Dağılımı'),
                _StatusPieChart(summary: summary),
                const SizedBox(height: 24),
                const _SectionHeader('Öncelik Dağılımı'),
                _PriorityBarChart(summary: summary),
                const SizedBox(height: 24),
                const _SectionHeader('Son Aktiviteler'),
                _RecentActivityList(items: summary.recentActivity),
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

  const _SummaryCardsRow({required this.summary, required this.onCardTap});

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

  const _SummaryCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return BentoCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      child: Column(
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
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  final void Function(String feature) onComingSoon;
  const _QuickActionsRow({required this.onComingSoon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => onComingSoon('Yeni Arıza Gir'),
            icon: const Icon(Icons.add),
            label: const Text('Yeni Arıza Gir'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => onComingSoon('İSG Bildirimi'),
            icon: const Icon(Icons.shield_outlined),
            label: const Text('İSG Bildirimi'),
          ),
        ),
      ],
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

    return BentoCard(
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

    return BentoCard(
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
                    color: priorityChartColor(context, priority),
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

    return BentoCard(
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

class _EmptyChartCard extends StatelessWidget {
  final String message;
  const _EmptyChartCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return BentoCard(
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
            ElevatedButton(onPressed: onRetry, child: const Text('Tekrar Dene')),
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
