import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../models/usage_analytics.dart';
import '../../services/analytics_service.dart';
import '../../services/api_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';

/// Kullanım Analitiği (UX standardizasyonu turu, bölüm E) — YALNIZCA yönetici.
///
/// AYRIM: Bu gerçek bir Hotjar/ısı haritası paneli DEĞİLDİR — ücretli/harici
/// bir davranış analizi aracı kurmak yerine, backend'deki `usage_logs`
/// tablosundan (bkz. routes/analytics.js) beslenen, en çok ziyaret edilen 5
/// ekranı ve en çok tıklanan 5 birincil butonu gösteren basit ama GERÇEK
/// (çalışan, canlı veriye dayalı) bir özet ekranıdır.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  UsageAnalyticsSummary? _summary;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('AnalyticsScreen');
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final summary = await ApiService().getAnalyticsSummary();
      if (!mounted) return;
      setState(() => _summary = summary);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppTopBar(title: 'Kullanım Analitiği'),
      body: SafeArea(
        top: false,
        child: Builder(
          builder: (context) {
            if (_isLoading && _summary == null) {
              return const Center(child: CircularProgressIndicator());
            }

            if (_errorMessage != null && _summary == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 56,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: AppSpacing.sm + 4),
                      Text(_errorMessage!, textAlign: TextAlign.center),
                      const SizedBox(height: AppSpacing.md),
                      AppButton(label: 'Tekrar Dene', onPressed: _load),
                    ],
                  ),
                ),
              );
            }

            final summary = _summary!;
            return RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  Text(
                    'En Çok Ziyaret Edilen Ekranlar',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _TopScreensChart(screens: summary.topScreens),
                  const SizedBox(height: AppSpacing.lg),

                  Text(
                    'En Çok Tıklanan Butonlar',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _TopButtonsList(buttons: summary.topButtons),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TopScreensChart extends StatelessWidget {
  final List<ScreenViewCount> screens;
  const _TopScreensChart({required this.screens});

  @override
  Widget build(BuildContext context) {
    if (screens.isEmpty) {
      return AppCard(
        child: Text(
          'Henüz kayıtlı ekran görüntülemesi yok.',
          style: AppTextStyles.bodyMedium(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final maxVal = screens.fold<int>(
      0,
      (max, s) => s.viewCount > max ? s.viewCount : max,
    );
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final primary = AppColors.primary(context);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(8, 20, 16, 12),
      child: SizedBox(
        height: 220,
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
                  reservedSize: 64,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 || index >= screens.length)
                      return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Transform.rotate(
                        angle: -0.5,
                        child: Text(
                          screens[index].screenName,
                          style: TextStyle(fontSize: 11, color: onSurface),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                    BarTooltipItem(
                      '${screens[group.x].viewCount}',
                      TextStyle(
                        color: accessibleOnColor(primary),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
              ),
            ),
            barGroups: screens.asMap().entries.map((entry) {
              return BarChartGroupData(
                x: entry.key,
                barRods: [
                  BarChartRodData(
                    toY: entry.value.viewCount.toDouble(),
                    color: primary,
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

class _TopButtonsList extends StatelessWidget {
  final List<ButtonTapCount> buttons;
  const _TopButtonsList({required this.buttons});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (buttons.isEmpty) {
      return AppCard(
        child: Text(
          'Henüz kayıtlı buton tıklaması yok.',
          style: AppTextStyles.bodyMedium(color: scheme.onSurfaceVariant),
        ),
      );
    }

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (int i = 0; i < buttons.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.primary(context),
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    color: accessibleOnColor(AppColors.primary(context)),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              title: Text(
                buttons[i].elementName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                buttons[i].screenName,
                style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                '${buttons[i].tapCount}',
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
