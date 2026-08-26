import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
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
      return 'AKTİF';
    case SosAlertStatus.onaylandi:
      return 'İLGİLENİLİYOR';
    case SosAlertStatus.kapatildi:
      return 'KAPATILDI';
  }
}

/// Acil Durum (SOS) Modülü — Dispeçer/Yönetici Uyarılar Ekranı.
///
/// Modül 3'teki (map_screen.dart) flutter_map kurulumu YENİDEN kullanılır —
/// ama pin görseli BİLİNÇLİ olarak Modül 14'teki risk bubble map'inden farklı,
/// "acil" hissi veren bir kırmızı işaretleyici (bkz. _buildMarker). Liste,
/// en yeni bildirim en üstte olacak şekilde backend'in zaten sıraladığı
/// haliyle (created_at DESC) gösterilir.
class SosAlertsScreen extends StatefulWidget {
  const SosAlertsScreen({super.key});

  @override
  State<SosAlertsScreen> createState() => _SosAlertsScreenState();
}

class _SosAlertsScreenState extends State<SosAlertsScreen> {
  final MapController _mapController = MapController();
  static const LatLng _regionCenter = LatLng(39.90, 41.27);
  static const double _regionZoom = 7.3;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('SosAlertsScreen');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SosProvider>().fetchActiveAlerts();
    });
  }

  Future<void> _call(String? phone) async {
    if (phone == null || phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu kullanıcı için kayıtlı bir telefon numarası yok.'),
        ),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      final opened = await launchUrl(Uri.parse('tel:${phone.trim()}'));
      if (!opened) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Arama uygulaması açılamadı.')),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Arama uygulaması açılamadı.')),
      );
    }
  }

  Future<void> _confirmClose(SosAlert alert) async {
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bildirimi Kapat'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Opsiyonel bir çözüm notu ekleyebilirsiniz.'),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Örn. Ekip sahaya ulaştı, durum çözüldü.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final note = noteController.text.trim();
      await context.read<SosProvider>().closeAlert(
        alert.id,
        note: note.isEmpty ? null : note,
      );
    }
  }

  Marker _buildMarker(SosAlert alert) {
    final color = _statusColor(context, alert.status);
    final size = alert.isActive ? 52.0 : 40.0;
    return Marker(
      point: LatLng(alert.lat, alert.lng),
      width: size,
      height: size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _mapController.move(LatLng(alert.lat, alert.lng), 13),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Icon(
            Icons.sos_rounded,
            color: accessibleOnColor(color),
            size: size * 0.55,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SosProvider>();

    return Scaffold(
      appBar: const AppTopBar(title: 'SOS Uyarıları'),
      body: RefreshIndicator(
        onRefresh: provider.fetchActiveAlerts,
        child: Column(
          children: [
            SizedBox(
              height: 220,
              child: FlutterMap(
                mapController: _mapController,
                options: const MapOptions(
                  initialCenter: _regionCenter,
                  initialZoom: _regionZoom,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.arasedas.arassaha_flutter',
                  ),
                  MarkerLayer(
                    markers: provider.alerts.map(_buildMarker).toList(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Builder(
                builder: (context) {
                  if (provider.isListLoading && provider.alerts.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (provider.listErrorMessage != null &&
                      provider.alerts.isEmpty) {
                    return EmptyState(
                      icon: Icons.error_outline,
                      title: 'SOS uyarıları yüklenemedi',
                      subtitle: provider.listErrorMessage!,
                      onPrimaryAction: provider.fetchActiveAlerts,
                      primaryActionLabel: 'Tekrar Dene',
                      primaryActionVariant: AppButtonVariant.secondary,
                    );
                  }
                  if (provider.alerts.isEmpty) {
                    return const EmptyState(
                      icon: Icons.check_circle_outline,
                      title: 'Şu anda kayıtlı bir SOS bildirimi yok.',
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: provider.alerts.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final alert = provider.alerts[index];
                      return StaggeredFadeIn(
                        key: ValueKey(alert.id),
                        index: index,
                        child: _SosAlertCard(
                          alert: alert,
                          onCall: () => _call(alert.reporterPhone),
                          onAcknowledge: () => context
                              .read<SosProvider>()
                              .acknowledgeAlert(alert.id),
                          onClose: () => _confirmClose(alert),
                          onLocate: () => _mapController.move(
                            LatLng(alert.lat, alert.lng),
                            13,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SosAlertCard extends StatelessWidget {
  final SosAlert alert;
  final VoidCallback onCall;
  final VoidCallback onAcknowledge;
  final VoidCallback onClose;
  final VoidCallback onLocate;

  const _SosAlertCard({
    required this.alert,
    required this.onCall,
    required this.onAcknowledge,
    required this.onClose,
    required this.onLocate,
  });

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
                  alert.reporterName,
                  style: TextStyle(
                    fontSize: 16,
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
          const SizedBox(height: 2),
          Text(
            _formatDateTime(alert.createdAt),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xs),
          InkWell(
            onTap: onLocate,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: scheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  '${alert.lat.toStringAsFixed(5)}, ${alert.lng.toStringAsFixed(5)} — Haritada Gör',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (alert.note != null && alert.note!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: Text(
                alert.note!,
                style: TextStyle(fontSize: 13, color: scheme.onSurface),
              ),
            ),
          ],
          if (alert.status == SosAlertStatus.kapatildi &&
              alert.closedNote != null &&
              alert.closedNote!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Çözüm notu: ${alert.closedNote}',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm + 2),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Ara',
                  icon: Icons.call,
                  color: AppColors.danger(context),
                  onPressed: onCall,
                ),
              ),
              if (alert.status != SosAlertStatus.kapatildi) ...[
                const SizedBox(width: AppSpacing.sm),
                if (alert.status == SosAlertStatus.aktif)
                  Expanded(
                    child: AppButton(
                      label: 'Gördüm',
                      icon: Icons.visibility_outlined,
                      variant: AppButtonVariant.secondary,
                      onPressed: onAcknowledge,
                    ),
                  ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: AppButton(
                    label: 'Kapat',
                    icon: Icons.check_circle_outline,
                    variant: AppButtonVariant.secondary,
                    onPressed: onClose,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
