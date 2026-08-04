import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/isg_report.dart';
import '../../providers/isg_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/work_order_card.dart' show formatRelativeTime;
import 'isg_report_detail_screen.dart';
import 'isg_report_form_screen.dart';

Color _statusColor(BuildContext context, IsgStatus status) {
  switch (status) {
    case IsgStatus.bekliyor:
      return AppColors.warning(context);
    case IsgStatus.incelendi:
      return AppColors.primary(context);
    case IsgStatus.cozuldu:
      return AppColors.success(context);
  }
}

/// İSG (İş Sağlığı ve Güvenliği) Bildirimi (Modül 5) — bildirim listesi.
class IsgReportListScreen extends StatefulWidget {
  const IsgReportListScreen({super.key});

  @override
  State<IsgReportListScreen> createState() => _IsgReportListScreenState();
}

class _IsgReportListScreenState extends State<IsgReportListScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('IsgReportListScreen');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<IsgProvider>().fetchReports();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IsgProvider>();

    return Scaffold(
      appBar: const AppTopBar(title: 'İSG Bildirimleri'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const IsgReportFormScreen()),
          );
          if (context.mounted) context.read<IsgProvider>().fetchReports();
        },
        icon: const Icon(Icons.add_alert_outlined),
        label: const Text('Yeni Bildirim'),
      ),
      body: SafeArea(
        top: false,
        child: Builder(
          builder: (context) {
            if (provider.isListLoading && provider.reports.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            if (provider.listErrorMessage != null && provider.reports.isEmpty) {
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
                      Text(
                        provider.listErrorMessage!,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppButton(
                        label: 'Tekrar Dene',
                        onPressed: provider.fetchReports,
                      ),
                    ],
                  ),
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: provider.fetchReports,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.xl + 64,
                ),
                children: [
                  _SummaryStrip(reports: provider.reports),
                  const SizedBox(height: AppSpacing.md),
                  _FilterBar(provider: provider),
                  const SizedBox(height: AppSpacing.sm),
                  if (provider.reports.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: AppSpacing.xl),
                      child: Center(
                        child: Text('Bu filtreye uyan bildirim yok.'),
                      ),
                    )
                  else
                    ...provider.reports.map(
                      (report) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _IsgReportCard(
                          report: report,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  IsgReportDetailScreen(reportId: report.id),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  final List<IsgReport> reports;
  const _SummaryStrip({required this.reports});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = reports.length;
    final bekliyor = reports
        .where((r) => r.status == IsgStatus.bekliyor)
        .length;
    final incelendi = reports
        .where((r) => r.status == IsgStatus.incelendi)
        .length;
    final cozuldu = reports.where((r) => r.status == IsgStatus.cozuldu).length;

    return AppCard(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.sm + 4,
        horizontal: AppSpacing.sm,
      ),
      child: Text.rich(
        TextSpan(
          style: AppTextStyles.bodyMedium(color: scheme.onSurface),
          children: [
            TextSpan(
              text: '$total',
              style: AppTextStyles.headingMedium(
                color: AppColors.primary(context),
              ),
            ),
            const TextSpan(text: ' bildirim, '),
            TextSpan(
              text: '$bekliyor',
              style: AppTextStyles.headingMedium(
                color: AppColors.warning(context),
              ),
            ),
            const TextSpan(text: ' bekliyor, '),
            TextSpan(
              text: '$incelendi',
              style: AppTextStyles.headingMedium(
                color: AppColors.primary(context),
              ),
            ),
            const TextSpan(text: ' incelendi, '),
            TextSpan(
              text: '$cozuldu',
              style: AppTextStyles.headingMedium(
                color: AppColors.success(context),
              ),
            ),
            const TextSpan(text: ' çözüldü'),
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final IsgProvider provider;
  const _FilterBar({required this.provider});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filters = <String, IsgStatus?>{
      'Tümü': null,
      'Bekliyor': IsgStatus.bekliyor,
      'İncelendi': IsgStatus.incelendi,
      'Çözüldü': IsgStatus.cozuldu,
    };

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: filters.entries.map((entry) {
          final isSelected = provider.filterStatus == entry.value;
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs + 4),
            child: ChoiceChip(
              label: Text(entry.key),
              selected: isSelected,
              showCheckmark: false,
              labelStyle: TextStyle(
                color: isSelected ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
              onSelected: (_) => provider.setFilter(entry.value),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _IsgReportCard extends StatelessWidget {
  final IsgReport report;
  final VoidCallback onTap;
  const _IsgReportCard({required this.report, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      onTap: onTap,
      statusStripeColor: _statusColor(context, report.status),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(report.category.icon, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  report.category.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              _StatusBadge(status: report.status),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            report.description,
            style: Theme.of(context).textTheme.bodyLarge,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.person_outline,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  report.reportedBy?.name ?? 'Bilinmiyor',
                  style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                formatRelativeTime(report.createdAt),
                style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final IsgStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: accessibleOnColor(color),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
