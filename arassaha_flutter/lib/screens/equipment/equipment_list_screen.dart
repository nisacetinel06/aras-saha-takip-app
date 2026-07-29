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
import 'equipment_detail_screen.dart';

/// Ekipman envanterinin tam listesi — tip ve durum filtresi destekler.
/// Filtreler backend'e ayrı ayrı ?type=/&status= sorgusu olarak gider (bkz.
/// EquipmentProvider), veri seti küçük olsa da bu, Modül 4'ün API sözleşmesini
/// gerçek anlamda kullanır (İş Emirleri listesindeki statü filtresiyle aynı desen).
class EquipmentListScreen extends StatefulWidget {
  const EquipmentListScreen({super.key});

  @override
  State<EquipmentListScreen> createState() => _EquipmentListScreenState();
}

class _EquipmentListScreenState extends State<EquipmentListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EquipmentProvider>().fetchEquipmentList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final provider = context.watch<EquipmentProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ekipmanlar'),
        actions: [
          IconButton(
            tooltip: themeProvider.isDark ? 'Aydınlık moda geç' : 'Karanlık moda geç',
            icon: Icon(themeProvider.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: themeProvider.toggle,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          _TypeFilterBar(provider: provider),
          _StatusFilterBar(provider: provider),
          Expanded(
            child: Builder(
              builder: (context) {
                if (provider.isListLoading && provider.equipmentList.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (provider.listErrorMessage != null && provider.equipmentList.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline, size: 56, color: Theme.of(context).colorScheme.error),
                          const SizedBox(height: AppSpacing.sm + 4),
                          Text(provider.listErrorMessage!, textAlign: TextAlign.center),
                          const SizedBox(height: AppSpacing.md),
                          AppButton(label: 'Tekrar Dene', onPressed: provider.fetchEquipmentList),
                        ],
                      ),
                    ),
                  );
                }

                if (provider.equipmentList.isEmpty) {
                  return Center(
                    child: Text(
                      'Bu filtreye uyan ekipman yok.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: provider.fetchEquipmentList,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.sm,
                      AppSpacing.md,
                      AppSpacing.md,
                    ),
                    itemCount: provider.equipmentList.length,
                    itemBuilder: (context, index) {
                      final equipment = provider.equipmentList[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _EquipmentCard(
                          equipment: equipment,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => EquipmentDetailScreen(equipmentId: equipment.id)),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Color _statusStripeColor(BuildContext context, EquipmentStatus status) {
  switch (status) {
    case EquipmentStatus.aktif:
      return AppColors.success(context);
    case EquipmentStatus.bakimda:
      return AppColors.warning(context);
    case EquipmentStatus.devreDisi:
      return AppColors.textSecondary(context);
  }
}

class _TypeFilterBar extends StatelessWidget {
  final EquipmentProvider provider;
  const _TypeFilterBar({required this.provider});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filters = <String, EquipmentType?>{
      'Tümü': null,
      'Trafo': EquipmentType.trafo,
      'Direk': EquipmentType.direk,
      'Kesici': EquipmentType.kesici,
      'Sayaç': EquipmentType.sayac,
    };

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: filters.entries.map((entry) {
          final isSelected = provider.typeFilter == entry.value;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: ChoiceChip(
              label: Text(entry.key),
              selected: isSelected,
              showCheckmark: false,
              labelStyle: TextStyle(color: isSelected ? scheme.onPrimary : scheme.onSurfaceVariant),
              onSelected: (_) => provider.setTypeFilter(entry.value),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _StatusFilterBar extends StatelessWidget {
  final EquipmentProvider provider;
  const _StatusFilterBar({required this.provider});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filters = <String, EquipmentStatus?>{
      'Tümü': null,
      'Aktif': EquipmentStatus.aktif,
      'Bakımda': EquipmentStatus.bakimda,
      'Devre Dışı': EquipmentStatus.devreDisi,
    };

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: filters.entries.map((entry) {
          final isSelected = provider.statusFilter == entry.value;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: ChoiceChip(
              label: Text(entry.key),
              selected: isSelected,
              showCheckmark: false,
              labelStyle: TextStyle(color: isSelected ? scheme.onPrimary : scheme.onSurfaceVariant, fontSize: 12),
              onSelected: (_) => provider.setStatusFilter(entry.value),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _EquipmentCard extends StatelessWidget {
  final Equipment equipment;
  final VoidCallback onTap;
  const _EquipmentCard({required this.equipment, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      onTap: onTap,
      statusStripeColor: _statusStripeColor(context, equipment.status),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Icon(equipment.equipmentType.icon, size: 20, color: scheme.primary),
          ),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        equipment.equipmentType.label,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    Text(
                      equipment.status.label,
                      style: TextStyle(
                        color: _statusStripeColor(context, equipment.status),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.qr_code_2_outlined, size: 14, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(equipment.qrCode, style: AppTextStyles.dataMono(color: scheme.onSurfaceVariant).copyWith(fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.location_on_outlined, size: 14, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        equipment.locationName,
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (equipment.installDate != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.event_outlined, size: 14, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        '${equipment.installDate!.year} kurulum',
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
