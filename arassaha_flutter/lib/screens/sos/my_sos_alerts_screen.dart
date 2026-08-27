import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/sos_alert.dart';
import '../../providers/sos_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/staggered_fade_in.dart';

String _formatDateTime(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

Color _statusColor(BuildContext context, SosAlertStatus status) {
  switch (status) {
    case SosAlertStatus.aktif:
      return AppColors.danger(context);
    case SosAlertStatus.onaylandi:
      return AppColors.warning(context);
    case SosAlertStatus.kapatildi:
      return AppColors.textSecondary(context);
  }
}

String _statusLabel(SosAlertStatus status) {
  switch (status) {
    case SosAlertStatus.aktif:
      return 'AKTİF — henüz görülmedi';
    case SosAlertStatus.onaylandi:
      return 'GÖRÜLDÜ — ilgileniliyor';
    case SosAlertStatus.kapatildi:
      return 'KAPATILDI';
  }
}

/// "Gönderdiğim SOS Bildirimleri" — teknisyenin Profil ekranından açtığı,
/// SADECE KENDİ gönderdiği SOS bildirimlerinin durumunu (görüldü mü,
/// kapatıldı mı) takip edebildiği salt-okunur liste. Backend zaten GET /
/// api/sos-alerts'i role göre filtreliyor (bkz. routes/sosAlerts.js —
/// teknisyen için triggered_by_user_id = kendisi), bu ekran ekstra bir
/// istemci-taraflı filtre YAPMAZ, SosProvider'ın döndürdüğü listeyi
/// olduğu gibi gösterir. dispeçer/yönetici ekranındaki (sos_alerts_screen.dart)
/// harita/ara/onayla/kapat aksiyonları BİLEREK yok — bu, yalnızca "acaba
/// yöneticim gördü mü" sorusuna cevap veren pasif bir görünüm.
class MySosAlertsScreen extends StatefulWidget {
  const MySosAlertsScreen({super.key});

  @override
  State<MySosAlertsScreen> createState() => _MySosAlertsScreenState();
}

class _MySosAlertsScreenState extends State<MySosAlertsScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('MySosAlertsScreen');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SosProvider>().fetchActiveAlerts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SosProvider>();

    return Scaffold(
      appBar: const AppTopBar(title: 'Gönderdiğim SOS Bildirimleri'),
      body: RefreshIndicator(
        onRefresh: provider.fetchActiveAlerts,
        child: Builder(
          builder: (context) {
            if (provider.isListLoading && provider.alerts.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (provider.listErrorMessage != null && provider.alerts.isEmpty) {
              return EmptyState(
                icon: Icons.error_outline,
                title: 'SOS bildirimleriniz yüklenemedi',
                subtitle: provider.listErrorMessage!,
                onPrimaryAction: provider.fetchActiveAlerts,
                primaryActionLabel: 'Tekrar Dene',
                primaryActionVariant: AppButtonVariant.secondary,
              );
            }
            if (provider.alerts.isEmpty) {
              return const EmptyState(
                icon: Icons.check_circle_outline,
                title: 'Henüz bir SOS bildirimi göndermediniz.',
              );
            }

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: provider.alerts.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final alert = provider.alerts[index];
                return StaggeredFadeIn(
                  key: ValueKey(alert.id),
                  index: index,
                  child: _MySosAlertCard(alert: alert),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _MySosAlertCard extends StatelessWidget {
  final SosAlert alert;

  const _MySosAlertCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = _statusColor(context, alert.status);

    return AppCard(
      statusStripeColor: statusColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _formatDateTime(alert.createdAt),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Text(
                  _statusLabel(alert.status),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (alert.acknowledgedAt != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Görüldü: ${_formatDateTime(alert.acknowledgedAt!)}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
          if (alert.status == SosAlertStatus.kapatildi && alert.closedAt != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Kapatıldı: ${_formatDateTime(alert.closedAt!)}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
          if (alert.closedNote != null && alert.closedNote!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: Text(
                'Çözüm notu: ${alert.closedNote}',
                style: TextStyle(fontSize: 13, color: scheme.onSurface),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
