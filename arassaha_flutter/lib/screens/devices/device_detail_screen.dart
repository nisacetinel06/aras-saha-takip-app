import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/managed_device.dart';
import '../../providers/device_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../services/device_telemetry_service.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/work_order_card.dart' show formatRelativeTime;

/// Cihaz Yönetimi — cihaz detay ekranı.
///
/// "Kilitle / Kilidi Aç / Hesabı Sil" bu backend'in kendi veritabanındaki
/// durumu değiştirir; gerçek bir cihaza UZAKTAN komut göndermez (bkz.
/// DESIGN_SYSTEM.md "Cihaz Yönetimi Modülü" notu). "Zorla Senkronize Et" ise
/// uygulamanın o an çalıştığı cihazın GERÇEK pil/model/OS bilgisini okuyup
/// backend'e gönderir.
class DeviceDetailScreen extends StatefulWidget {
  final int deviceId;
  const DeviceDetailScreen({super.key, required this.deviceId});

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DeviceProvider>().fetchDeviceDetail(widget.deviceId);
    });
  }

  Future<void> _runAction(String actionType, {String? confirmMessage, DeviceTelemetry? telemetry}) async {
    if (confirmMessage != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Emin misin?'),
          content: Text(confirmMessage),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('İptal')),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: Theme.of(dialogContext).colorScheme.error),
              child: const Text('Sil'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      if (!mounted) return;
    }

    final provider = context.read<DeviceProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final success = await provider.performAction(widget.deviceId, actionType, telemetry: telemetry);

    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(success ? _successMessage(actionType) : (provider.detailErrorMessage ?? 'İşlem başarısız oldu.')),
      ),
    );
  }

  /// Bu cihazın (uygulamanın çalıştığı fiziksel cihazın) GERÇEK pil/model/OS
  /// bilgisini okuyup senkronizasyonu tetikler. Okuma başarısız olursa (örn.
  /// desteklenmeyen platform) telemetrisiz devam eder — backend bu durumda
  /// yalnızca senkron zamanını günceller.
  Future<void> _forceSyncWithRealTelemetry() async {
    DeviceTelemetry? telemetry;
    try {
      telemetry = await DeviceTelemetryService().readCurrentDevice();
    } catch (_) {
      telemetry = null;
    }
    if (!mounted) return;
    await _runAction('force-sync', telemetry: telemetry);
  }

  String _successMessage(String actionType) {
    switch (actionType) {
      case 'lock':
        return 'Cihaz kilitlendi.';
      case 'unlock':
        return 'Cihazın kilidi açıldı.';
      case 'wipe':
        return 'Hesap silindi, cihaz kayıt dışı bırakıldı.';
      case 'force-sync':
        return 'Senkronize edildi — bu cihazın gerçek pil/model/OS bilgisi gönderildi.';
      default:
        return 'İşlem tamamlandı.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final provider = context.watch<DeviceProvider>();
    final device = provider.selectedDevice?.id == widget.deviceId ? provider.selectedDevice : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cihaz Detayı'),
        actions: [
          IconButton(
            tooltip: themeProvider.isDark ? 'Aydınlık moda geç' : 'Karanlık moda geç',
            icon: Icon(themeProvider.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: themeProvider.toggle,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (device == null && provider.detailErrorMessage != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 56, color: Theme.of(context).colorScheme.error),
                    const SizedBox(height: AppSpacing.sm + 4),
                    Text(provider.detailErrorMessage!, textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.md),
                    AppButton(
                      label: 'Tekrar Dene',
                      onPressed: () => provider.fetchDeviceDetail(widget.deviceId),
                    ),
                  ],
                ),
              ),
            );
          }

          if (device == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return RefreshIndicator(
            onRefresh: () => provider.fetchDeviceDetail(widget.deviceId),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Text(device.deviceName, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  device.assignedUser?.name ?? 'Atanmamış',
                  style: AppTextStyles.bodyMedium(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.lg),

                _SectionCard(
                  title: 'Cihaz Bilgileri',
                  icon: Icons.smartphone_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InfoRow(label: 'Model', value: device.deviceModel),
                      _InfoRow(label: 'İşletim Sistemi', value: device.osVersion),
                      _InfoRow(label: 'Uygulama Sürümü', value: device.appVersion),
                      _InfoRow(label: 'Kayıt Durumu', value: device.enrollmentStatus.label),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                _SectionCard(
                  title: 'Durum',
                  icon: Icons.monitor_heart_outlined,
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      _StatusChip(
                        label: device.enrollmentStatus.label,
                        color: switch (device.enrollmentStatus) {
                          DeviceEnrollmentStatus.kayitli => AppColors.success(context),
                          DeviceEnrollmentStatus.beklemede => AppColors.warning(context),
                          DeviceEnrollmentStatus.kayitDisi => AppColors.danger(context),
                        },
                        icon: switch (device.enrollmentStatus) {
                          DeviceEnrollmentStatus.kayitli => Icons.verified_outlined,
                          DeviceEnrollmentStatus.beklemede => Icons.hourglass_empty,
                          DeviceEnrollmentStatus.kayitDisi => Icons.link_off,
                        },
                      ),
                      _StatusChip(
                        label: device.complianceStatus.label,
                        color: device.complianceStatus == DeviceComplianceStatus.uyumlu
                            ? AppColors.success(context)
                            : AppColors.danger(context),
                        icon: device.complianceStatus == DeviceComplianceStatus.uyumlu
                            ? Icons.check_circle_outline
                            : Icons.warning_amber_rounded,
                      ),
                      _StatusChip(
                        label: device.isLocked ? 'Kilitli' : 'Kilitli Değil',
                        color: device.isLocked ? AppColors.warning(context) : AppColors.textSecondary(context),
                        icon: device.isLocked ? Icons.lock_outline : Icons.lock_open_outlined,
                      ),
                      _StatusChip(
                        label: '%${device.batteryLevel} pil',
                        color: AppColors.primary(context),
                        icon: Icons.battery_std_outlined,
                      ),
                      _StatusChip(
                        label: device.lastSyncAt != null
                            ? 'Son senkron: ${formatRelativeTime(device.lastSyncAt!)}'
                            : 'Hiç senkron olmadı',
                        color: AppColors.textSecondary(context),
                        icon: Icons.sync,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                _SectionCard(
                  title: 'Aksiyonlar',
                  icon: Icons.bolt_outlined,
                  child: device.enrollmentStatus == DeviceEnrollmentStatus.kayitDisi
                      ? Row(
                          children: [
                            Icon(Icons.link_off, size: 18, color: AppColors.danger(context)),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                'Bu cihazın hesabı silindi, kayıt dışı bırakıldı. Yeni bir aksiyon alınamaz.',
                                style: AppTextStyles.bodyMedium(color: Theme.of(context).colorScheme.onSurface),
                              ),
                            ),
                          ],
                        )
                      : Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: [
                            if (device.isLocked)
                              AppButton(
                                label: 'Kilidi Aç',
                                icon: Icons.lock_open_outlined,
                                isLoading: provider.isPerformingAction,
                                onPressed: () => _runAction('unlock'),
                              )
                            else
                              AppButton(
                                label: 'Kilitle',
                                icon: Icons.lock_outline,
                                isLoading: provider.isPerformingAction,
                                onPressed: () => _runAction('lock'),
                              ),
                            AppButton(
                              label: 'Zorla Senkronize Et',
                              icon: Icons.sync,
                              variant: AppButtonVariant.secondary,
                              isLoading: provider.isPerformingAction,
                              onPressed: _forceSyncWithRealTelemetry,
                            ),
                            AppButton(
                              label: 'Hesabı Sil',
                              icon: Icons.delete_outline,
                              variant: AppButtonVariant.secondary,
                              color: Theme.of(context).colorScheme.error,
                              isLoading: provider.isPerformingAction,
                              onPressed: () => _runAction(
                                'wipe',
                                confirmMessage:
                                    'Bu cihazdaki ArasSaha hesabı kalıcı olarak silinecek ve cihaz kayıt dışı bırakılacak. Emin misiniz?',
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: AppSpacing.md),

                _SectionCard(
                  title: 'İşlem Geçmişi',
                  icon: Icons.history,
                  child: device.logs.isEmpty
                      ? Text(
                          'Henüz bir işlem yapılmadı.',
                          style: AppTextStyles.bodyMedium(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        )
                      : Column(
                          children: [
                            for (int i = 0; i < device.logs.length; i++) ...[
                              if (i > 0) const Divider(height: 20),
                              _LogRow(log: device.logs[i]),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _SectionCard({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
          const SizedBox(height: AppSpacing.sm + 4),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: AppTextStyles.caption(color: scheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value, style: AppTextStyles.dataMono(color: scheme.onSurface)),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _StatusChip({required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  final DeviceActionLog log;
  const _LogRow({required this.log});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.circle, size: 8, color: scheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(log.label, style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface)),
              const SizedBox(height: 2),
              Text(
                '${log.performedBy} · ${formatRelativeTime(log.createdAt)}',
                style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
