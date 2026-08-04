import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/managed_device.dart';
import '../../providers/auth_provider.dart';
import '../../providers/device_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/work_order_card.dart' show formatRelativeTime;
import 'device_detail_screen.dart';

enum _DeviceFilter { all, compliant, nonCompliant, pending }

/// Cihaz Yönetimi (MDM simülasyonu) — cihaz listesi ekranı.
///
/// ÖNEMLİ: Bu ekran ve bağlı olduğu backend gerçek bir cihaza komut
/// GÖNDERMEZ; yalnızca kendi veritabanındaki durumu simüle eder. Bkz.
/// DESIGN_SYSTEM.md "Cihaz Yönetimi Modülü" notu.
class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key});

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  _DeviceFilter _filter = _DeviceFilter.all;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('DeviceListScreen');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DeviceProvider>().fetchDevices();
    });
  }

  List<ManagedDevice> _applyFilter(List<ManagedDevice> devices) {
    switch (_filter) {
      case _DeviceFilter.all:
        return devices;
      case _DeviceFilter.compliant:
        return devices
            .where((d) => d.complianceStatus == DeviceComplianceStatus.uyumlu)
            .toList();
      case _DeviceFilter.nonCompliant:
        return devices
            .where((d) => d.complianceStatus == DeviceComplianceStatus.uyumsuz)
            .toList();
      case _DeviceFilter.pending:
        return devices
            .where(
              (d) => d.enrollmentStatus == DeviceEnrollmentStatus.beklemede,
            )
            .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    // İkinci koruma katmanı (bkz. ARCHITECTURE.md Modül 7): Ana Sayfa'da bu
    // ekrana giden kart zaten yalnızca yönetici rolüne gösteriliyor; ama bir
    // şekilde (deep link, state restore) yetkisiz bir rol buraya ulaşırsa
    // burada da engellenir. Backend requireRole('yonetici') ile ayrıca 403 döner.
    if (!auth.isYonetici) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bu ekrana erişim yetkiniz yok.')),
        );
        Navigator.of(context).pop();
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    final provider = context.watch<DeviceProvider>();

    return Scaffold(
      appBar: const AppTopBar(title: 'Cihaz Yönetimi'),
      body: SafeArea(
        top: false,
        child: Builder(
          builder: (context) {
            if (provider.isLoading && provider.devices.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            if (provider.errorMessage != null && provider.devices.isEmpty) {
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
                      Text(provider.errorMessage!, textAlign: TextAlign.center),
                      const SizedBox(height: AppSpacing.md),
                      AppButton(
                        label: 'Tekrar Dene',
                        onPressed: provider.fetchDevices,
                      ),
                    ],
                  ),
                ),
              );
            }

            final visibleDevices = _applyFilter(provider.devices);

            return RefreshIndicator(
              onRefresh: provider.fetchDevices,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  _SummaryStrip(devices: provider.devices),
                  const SizedBox(height: AppSpacing.md),
                  _FilterBar(
                    filter: _filter,
                    onChanged: (f) => setState(() => _filter = f),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (visibleDevices.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: AppSpacing.xl),
                      child: Center(child: Text('Bu filtreye uyan cihaz yok.')),
                    )
                  else
                    ...visibleDevices.map(
                      (device) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _DeviceCard(
                          device: device,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  DeviceDetailScreen(deviceId: device.id),
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
  final List<ManagedDevice> devices;
  const _SummaryStrip({required this.devices});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = devices.length;
    final nonCompliant = devices
        .where((d) => d.complianceStatus == DeviceComplianceStatus.uyumsuz)
        .length;
    final pending = devices
        .where((d) => d.enrollmentStatus == DeviceEnrollmentStatus.beklemede)
        .length;

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
            const TextSpan(text: ' cihaz kayıtlı, '),
            TextSpan(
              text: '$nonCompliant',
              style: AppTextStyles.headingMedium(
                color: AppColors.danger(context),
              ),
            ),
            const TextSpan(text: ' uyumsuz, '),
            TextSpan(
              text: '$pending',
              style: AppTextStyles.headingMedium(
                color: AppColors.warning(context),
              ),
            ),
            const TextSpan(text: ' beklemede'),
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final _DeviceFilter filter;
  final ValueChanged<_DeviceFilter> onChanged;
  const _FilterBar({required this.filter, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filters = <String, _DeviceFilter>{
      'Tümü': _DeviceFilter.all,
      'Uyumlu': _DeviceFilter.compliant,
      'Uyumsuz': _DeviceFilter.nonCompliant,
      'Beklemede': _DeviceFilter.pending,
    };

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: filters.entries.map((entry) {
          final isSelected = filter == entry.value;
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs + 4),
            child: ChoiceChip(
              label: Text(entry.key),
              selected: isSelected,
              showCheckmark: false,
              labelStyle: TextStyle(
                color: isSelected ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
              onSelected: (_) => onChanged(entry.value),
            ),
          );
        }).toList(),
      ),
    );
  }
}

Color _stripeColor(BuildContext context, ManagedDevice device) {
  if (device.enrollmentStatus == DeviceEnrollmentStatus.kayitDisi)
    return AppColors.textSecondary(context);
  if (device.enrollmentStatus == DeviceEnrollmentStatus.beklemede)
    return AppColors.warning(context);
  if (device.complianceStatus == DeviceComplianceStatus.uyumsuz)
    return AppColors.danger(context);
  return AppColors.success(context);
}

Color _batteryColor(BuildContext context, int level) {
  if (level <= 20) return AppColors.danger(context);
  if (level <= 50) return AppColors.warning(context);
  return AppColors.success(context);
}

IconData _batteryIcon(int level) {
  if (level <= 20) return Icons.battery_alert;
  if (level <= 50) return Icons.battery_4_bar;
  return Icons.battery_full;
}

class _DeviceCard extends StatelessWidget {
  final ManagedDevice device;
  final VoidCallback onTap;
  const _DeviceCard({required this.device, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isWiped = device.enrollmentStatus == DeviceEnrollmentStatus.kayitDisi;

    return Opacity(
      opacity: isWiped ? 0.6 : 1.0,
      child: AppCard(
        onTap: onTap,
        statusStripeColor: _stripeColor(context, device),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    device.deviceName,
                    style: Theme.of(context).textTheme.headlineSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (isWiped)
                  const _EnrollmentBadge()
                else
                  _ComplianceBadge(status: device.complianceStatus),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Icon(
                  Icons.person_outline,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    device.assignedUser?.name ?? 'Atanmamış',
                    style: AppTextStyles.caption(
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(
                  _batteryIcon(device.batteryLevel),
                  size: 16,
                  color: _batteryColor(context, device.batteryLevel),
                ),
                const SizedBox(width: 4),
                Text(
                  '%${device.batteryLevel}',
                  style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: AppSpacing.sm + 4),
                Icon(Icons.sync, size: 15, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    device.lastSyncAt != null
                        ? formatRelativeTime(device.lastSyncAt!)
                        : 'Hiç senkron olmadı',
                    style: AppTextStyles.caption(
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (device.isLocked) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.lock_outline,
                    size: 15,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EnrollmentBadge extends StatelessWidget {
  const _EnrollmentBadge();

  @override
  Widget build(BuildContext context) {
    final color = AppColors.textSecondary(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        'Kayıt Dışı',
        style: TextStyle(
          color: accessibleOnColor(color),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ComplianceBadge extends StatelessWidget {
  final DeviceComplianceStatus status;
  const _ComplianceBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = status == DeviceComplianceStatus.uyumlu
        ? AppColors.success(context)
        : AppColors.danger(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: accessibleOnColor(color),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
