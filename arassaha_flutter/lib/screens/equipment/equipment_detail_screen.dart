import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/equipment.dart';
import '../../providers/equipment_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/work_order_card.dart' show formatRelativeTime;
import '../work_order_detail_screen.dart';

/// Ekipman / Envanter (Modül 4) — ekipman detay ekranı.
///
/// Konum/kurulum/bakım/üretici/kapasite bilgisinin yanında, bu ekipmana bağlı
/// geçmiş iş emirlerini (arıza kayıtlarını) GET /api/equipment/:id/history
/// üzerinden ayrıca çeker ve listeler. Bir geçmiş kayda tıklanınca Modül 1'in
/// (İş Emirleri) detay ekranına gidilir — modüller arası gerçek bağlantı.
class EquipmentDetailScreen extends StatefulWidget {
  final int equipmentId;
  const EquipmentDetailScreen({super.key, required this.equipmentId});

  @override
  State<EquipmentDetailScreen> createState() => _EquipmentDetailScreenState();
}

class _EquipmentDetailScreenState extends State<EquipmentDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<EquipmentProvider>();
      provider.fetchEquipmentDetail(widget.equipmentId);
      provider.fetchEquipmentHistory(widget.equipmentId);
    });
  }

  String _installedAgoLabel(DateTime installDate) {
    final days = DateTime.now().difference(installDate).inDays;
    if (days < 30) return '$days gün önce kuruldu';
    final months = (days / 30).floor();
    if (months < 12) return '$months ay önce kuruldu';
    final years = (days / 365).floor();
    return '$years yıl önce kuruldu';
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final provider = context.watch<EquipmentProvider>();
    final equipment = provider.selectedEquipment?.id == widget.equipmentId ? provider.selectedEquipment : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ekipman Detayı'),
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
          if (equipment == null && provider.detailErrorMessage != null) {
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
                      onPressed: () => provider.fetchEquipmentDetail(widget.equipmentId),
                    ),
                  ],
                ),
              ),
            );
          }

          if (equipment == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return RefreshIndicator(
            onRefresh: () async {
              await provider.fetchEquipmentDetail(widget.equipmentId);
              await provider.fetchEquipmentHistory(widget.equipmentId);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Row(
                  children: [
                    Icon(equipment.equipmentType.icon, size: 28, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(equipment.equipmentType.label, style: Theme.of(context).textTheme.headlineMedium),
                    ),
                    _EquipmentStatusBadge(status: equipment.status),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Icon(Icons.qr_code_2_outlined, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      equipment.qrCode,
                      style: AppTextStyles.dataMono(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                _SectionCard(
                  title: 'Ekipman Bilgileri',
                  icon: Icons.info_outline,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InfoRow(icon: Icons.location_on_outlined, label: 'Konum', value: equipment.locationName),
                      _InfoRow(
                        icon: Icons.event_outlined,
                        label: 'Kurulum Tarihi',
                        value: equipment.installDate != null
                            ? '${_formatDate(equipment.installDate!)} (${_installedAgoLabel(equipment.installDate!)})'
                            : 'Bilinmiyor',
                      ),
                      _InfoRow(
                        icon: Icons.build_outlined,
                        label: 'Son Bakım',
                        value: equipment.lastMaintenanceDate != null
                            ? '${_formatDate(equipment.lastMaintenanceDate!)} (${formatRelativeTime(equipment.lastMaintenanceDate!)})'
                            : 'Hiç bakım kaydı yok',
                      ),
                      _InfoRow(
                        icon: Icons.factory_outlined,
                        label: 'Üretici',
                        value: equipment.manufacturer.isNotEmpty ? equipment.manufacturer : 'Bilinmiyor',
                      ),
                      _InfoRow(
                        icon: Icons.settings_outlined,
                        label: 'Kapasite',
                        value: equipment.capacityInfo?.isNotEmpty == true ? equipment.capacityInfo! : '—',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                _SectionCard(
                  title: 'Geçmiş Arıza Kayıtları',
                  icon: Icons.history,
                  child: _HistorySection(equipmentId: widget.equipmentId),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }
}

class _EquipmentStatusBadge extends StatelessWidget {
  final EquipmentStatus status;
  const _EquipmentStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      EquipmentStatus.aktif => AppColors.success(context),
      EquipmentStatus.bakimda => AppColors.warning(context),
      EquipmentStatus.devreDisi => AppColors.textSecondary(context),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(
        status.label,
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
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
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: Text(label, style: AppTextStyles.caption(color: scheme.onSurfaceVariant)),
          ),
          Expanded(child: Text(value, style: TextStyle(color: scheme.onSurface))),
        ],
      ),
    );
  }
}

class _HistorySection extends StatelessWidget {
  final int equipmentId;
  const _HistorySection({required this.equipmentId});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EquipmentProvider>();
    final scheme = Theme.of(context).colorScheme;

    if (provider.isHistoryLoading && provider.history.isEmpty && provider.historyErrorMessage == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (provider.historyErrorMessage != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(provider.historyErrorMessage!, style: TextStyle(color: scheme.error)),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Tekrar Dene',
            variant: AppButtonVariant.secondary,
            onPressed: () => provider.fetchEquipmentHistory(equipmentId),
          ),
        ],
      );
    }

    if (provider.history.isEmpty) {
      return Text(
        'Bu ekipmanın kayıtlı arıza geçmişi bulunmuyor.',
        style: AppTextStyles.bodyMedium(color: scheme.onSurfaceVariant),
      );
    }

    return Column(
      children: [
        for (int i = 0; i < provider.history.length; i++) ...[
          if (i > 0) const Divider(height: 20),
          _HistoryRow(entry: provider.history[i]),
        ],
      ],
    );
  }
}

/// Modül 1'deki iş emri kartının küçültülmüş versiyonu: başlık, statü, tarih.
/// Tıklanınca Modül 1'in (İş Emirleri) tam detay ekranına gider — modüller
/// arası gerçek bağlantı.
class _HistoryRow extends StatelessWidget {
  final EquipmentHistoryEntry entry;
  const _HistoryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.chip),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => WorkOrderDetailScreen(workOrderId: entry.id)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      StatusBadge(status: entry.status),
                      const SizedBox(width: 8),
                      Text(
                        formatRelativeTime(entry.createdAt),
                        style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_ios, size: 14, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
