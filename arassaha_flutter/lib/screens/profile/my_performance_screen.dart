import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/my_performance.dart';
import '../../providers/my_performance_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/empty_state.dart';

/// Performansım (Modül 16) — teknisyenin KENDİ tamamladığı iş emirleri
/// üzerinden hesaplanan özet. Yeni bir veri kaynağı DEĞİL: Dashboard (Modül 2)
/// ve Raporlar'ın (Modül 14) ZATEN var olan work_orders/isg_reports
/// sorgularının, giriş yapmış kullanıcıya sabitlenmiş bir görünümü — bu
/// yüzden görsel dili de BİLİNÇLİ olarak o iki ekrandan BİREBİR ödünç alındı
/// (özet kart stili -> DashboardScreen._SummaryCard, pasta grafik ->
/// DashboardScreen._StatusPieChart, çizgi grafik -> ReportsScreen._FaultTrendChart).
class MyPerformanceScreen extends StatefulWidget {
  const MyPerformanceScreen({super.key});

  @override
  State<MyPerformanceScreen> createState() => _MyPerformanceScreenState();
}

class _MyPerformanceScreenState extends State<MyPerformanceScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('MyPerformanceScreen');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MyPerformanceProvider>().fetchMyPerformance();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppTopBar(title: 'Performansım'),
      body: Consumer<MyPerformanceProvider>(
        builder: (context, provider, _) {
          final summary = provider.summary;

          if (provider.errorMessage != null && summary == null) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'Performans verileri yüklenemedi',
              subtitle: provider.errorMessage!,
              onPrimaryAction: provider.fetchMyPerformance,
              primaryActionLabel: 'Tekrar Dene',
              primaryActionVariant: AppButtonVariant.secondary,
            );
          }

          if (summary == null) {
            return const Center(child: CircularProgressIndicator());
          }

          // Madde 3 (Boş Durum): hiç tamamlanmış iş yoksa grafikleri sıfır
          // değerlerle göstermek yanıltıcı olurdu — tüm ekran tek bir
          // EmptyState'e döner. RefreshIndicator burada da korunur ki
          // kullanıcı ilk işini tamamladıktan sonra aşağı çekip yenileyebilsin.
          if (summary.totalCompletedAllTime == 0) {
            return RefreshIndicator(
              onRefresh: provider.fetchMyPerformance,
              child: EmptyState(
                icon: Icons.assignment_turned_in_outlined,
                title: 'Henüz tamamlanmış bir iş kaydınız yok',
                subtitle:
                    'İlk işinizi tamamladığınızda burada performans '
                    'özetiniz görünecek.',
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: provider.fetchMyPerformance,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                _SummaryCardsRow(summary: summary),
                const SizedBox(height: AppSpacing.lg),
                const _SectionHeader('Öncelik Dağılımı'),
                _PriorityPieChart(summary: summary),
                const SizedBox(height: AppSpacing.lg),
                const _SectionHeader('Aylık Tamamlama Trendi'),
                _MonthlyTrendChart(data: summary.monthlyTrend),
                const SizedBox(height: AppSpacing.lg),
                _IsgReportsCard(count: summary.isgReportsCount),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// DashboardScreen._SectionHeader ile BİREBİR AYNI — modüller arası tutarlılık.
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

/// DashboardScreen._SummaryCardsRow/_SummaryCard ile AYNI kart dili — tek
/// fark, buradaki kartların bir listeye/haritaya GÖTÜRMEMESİ (bu zaten
/// kullanıcının kendi özeti, tıklanacak başka bir görünüm yok) — bu yüzden
/// `onTap`/harita ikonu YOK.
class _SummaryCardsRow extends StatelessWidget {
  final MyPerformanceSummary summary;
  const _SummaryCardsRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            icon: Icons.calendar_month_outlined,
            iconColor: scheme.primary,
            value: '${summary.completedThisMonth}',
            label: 'Bu Ay Tamamlanan',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            icon: Icons.check_circle_outline,
            iconColor: AppColors.success(context),
            value: '${summary.totalCompletedAllTime}',
            label: 'Toplam Tamamlanan',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            icon: Icons.schedule,
            iconColor: scheme.secondary,
            value: summary.avgResolutionHours != null
                ? '${summary.avgResolutionHours!.toStringAsFixed(1)} sa'
                : '—',
            label: 'Ort. Çözüm Süresi',
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

  const _SummaryCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      child: Column(
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
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// DashboardScreen._StatusPieChart ile AYNI pasta grafik + lejant düzeni —
/// yalnızca statü yerine öncelik kırılımı gösteriyor (priorityColor).
class _PriorityPieChart extends StatelessWidget {
  final MyPerformanceSummary summary;
  const _PriorityPieChart({required this.summary});

  @override
  Widget build(BuildContext context) {
    final entries = summary.priorityBreakdown.entries
        .where((e) => e.value > 0)
        .toList();

    if (entries.isEmpty) {
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
                  final color = priorityColor(context, e.key);
                  return PieChartSectionData(
                    value: e.value.toDouble(),
                    color: color,
                    title: '${e.value}',
                    radius: 40,
                    titleStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: accessibleOnColor(color),
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
                          color: priorityColor(context, e.key),
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

/// ReportsScreen._FaultTrendChart ile AYNI çizgi grafik düzeni (bkz.
/// reports_screen.dart Sekme 2 — Eğilimler) — yalnızca arıza sayısı yerine
/// tamamlanan iş emri sayısını gösteriyor.
class _MonthlyTrendChart extends StatelessWidget {
  final List<MonthlyCompletionCount> data;
  const _MonthlyTrendChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final maxY = data
        .map((d) => d.completedCount)
        .fold<int>(0, (max, c) => c > max ? c : max);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(8, 20, 20, 8),
      child: SizedBox(
        height: 180,
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: (maxY + 1).toDouble(),
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
                    if (index < 0 || index >= data.length)
                      return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        data[index].shortLabel,
                        style: TextStyle(fontSize: 11, color: onSurface),
                      ),
                    );
                  },
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) =>
                    Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: [
                  for (int i = 0; i < data.length; i++)
                    FlSpot(i.toDouble(), data[i].completedCount.toDouble()),
                ],
                isCurved: true,
                color: AppColors.primary(context),
                barWidth: 3,
                dotData: const FlDotData(show: true),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppColors.primary(context).withValues(alpha: 0.15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// İSG bildirimi sayısı — küçük, motive edici bir detay (madde 2). Diğer
/// bölümlerden FARKLI olarak bir grafik değil, tek satırlık bir vurgu kartı;
/// yine de AppCard'ın standart görsel dilini (aynı radius/gölge) korur.
class _IsgReportsCard extends StatelessWidget {
  final int count;
  const _IsgReportsCard({required this.count});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = AppColors.positive(context);

    return AppCard(
      statusStripeColor: color,
      child: Row(
        children: [
          Icon(Icons.health_and_safety_outlined, color: color, size: 28),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Text(
              count > 0
                  ? '$count İSG bildirimi yaptınız'
                  : 'Henüz İSG bildirimi yapmadınız',
              style: AppTextStyles.bodyMedium(
                color: scheme.onSurface,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
