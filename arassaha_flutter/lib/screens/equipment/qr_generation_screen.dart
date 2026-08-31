import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/equipment.dart';
import '../../providers/qr_generation_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/sticky_form_footer.dart';
import 'qr_preview_screen.dart';

/// QR Kod Üretimi — henüz fiziksel etiketi basılmamış (qr_printed_at IS
/// NULL) ekipmanları listeler, çoklu seçim yapıp Önizleme/PDF ekranına
/// geçirir. Yalnızca yönetici erişir (Ana Sayfa'daki giriş noktası zaten
/// sadece yönetici görünümünde, bkz. home_screen.dart; backend'deki
/// `qr_printed` filtresi de ayrıca requireRole('yonetici') ile korunur, bkz.
/// routes/equipment.js).
class QrGenerationScreen extends StatefulWidget {
  const QrGenerationScreen({super.key});

  @override
  State<QrGenerationScreen> createState() => _QrGenerationScreenState();
}

class _QrGenerationScreenState extends State<QrGenerationScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<QrGenerationProvider>().fetchUnprintedEquipment();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<QrGenerationProvider>();

    return Scaffold(
      appBar: const AppTopBar(title: 'QR Kod Üret'),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _TypeFilterBar(provider: provider),
            _IlFilterBar(provider: provider),
            Expanded(
              child: Builder(
                builder: (context) {
                  if (provider.isLoadingList &&
                      provider.unprintedEquipment.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (provider.listErrorMessage != null &&
                      provider.unprintedEquipment.isEmpty) {
                    return EmptyState(
                      icon: Icons.error_outline,
                      title: 'Ekipmanlar yüklenemedi',
                      subtitle: provider.listErrorMessage!,
                      onPrimaryAction: provider.fetchUnprintedEquipment,
                      primaryActionLabel: 'Tekrar Dene',
                      primaryActionVariant: AppButtonVariant.secondary,
                    );
                  }

                  if (provider.unprintedEquipment.isEmpty) {
                    final hasFilter =
                        provider.typeFilter != null ||
                        provider.ilFilter != null;
                    return EmptyState(
                      icon: Icons.qr_code_2_outlined,
                      title: hasFilter
                          ? 'Bu filtreye uyan basılmamış ekipman yok'
                          : 'Basılmamış QR etiketi yok',
                      subtitle: hasFilter
                          ? null
                          : 'Sistemdeki tüm ekipmanların QR etiketi en az bir kez basılmış.',
                      activeFilters: hasFilter
                          ? [
                              if (provider.typeFilter != null)
                                ActiveFilterChip(
                                  label: 'Tip: ${provider.typeFilter!.label}',
                                  onRemove: () =>
                                      provider.setTypeFilter(null),
                                ),
                              if (provider.ilFilter != null)
                                ActiveFilterChip(
                                  label: 'İl: ${provider.ilFilter}',
                                  onRemove: () => provider.setIlFilter(null),
                                ),
                            ]
                          : null,
                    );
                  }

                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.sm,
                          AppSpacing.md,
                          0,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${provider.unprintedEquipment.length} ekipman için QR kodu henüz basılmadı',
                                style: AppTextStyles.bodyMedium(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.xs,
                          AppSpacing.md,
                          AppSpacing.xs,
                        ),
                        child: Row(
                          children: [
                            TextButton(
                              onPressed: provider.selectAll,
                              child: const Text('Tümünü Seç'),
                            ),
                            if (provider.selectedCount > 0)
                              TextButton(
                                onPressed: provider.clearSelection,
                                child: const Text('Seçimi Temizle'),
                              ),
                            const Spacer(),
                            if (provider.selectedCount > 0)
                              Text(
                                '${provider.selectedCount} seçildi',
                                style: AppTextStyles.caption(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: provider.fetchUnprintedEquipment,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.md,
                              0,
                              AppSpacing.md,
                              AppSpacing.md,
                            ),
                            itemCount: provider.unprintedEquipment.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: AppSpacing.sm),
                            itemBuilder: (context, index) {
                              final equipment =
                                  provider.unprintedEquipment[index];
                              return _QrEquipmentCard(
                                equipment: equipment,
                                selected: provider.selectedIds.contains(
                                  equipment.id,
                                ),
                                onChanged: () =>
                                    provider.toggleSelection(equipment.id),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: provider.unprintedEquipment.isEmpty
          ? null
          : StickyFormFooter(
              child: SizedBox(
                width: double.infinity,
                child: AppButton(
                  label: 'Seçilenler İçin QR Üret (${provider.selectedCount})',
                  icon: Icons.qr_code_2,
                  onPressed: provider.selectedCount == 0
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => QrPreviewScreen(
                              equipmentList: provider.selectedEquipment,
                            ),
                          ),
                        ),
                ),
              ),
            ),
    );
  }
}

class _TypeFilterBar extends StatelessWidget {
  final QrGenerationProvider provider;
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
              labelStyle: TextStyle(
                color: isSelected ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
              onSelected: (_) => provider.setTypeFilter(entry.value),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Backend'deki utils/location.js VALID_ILLER ile BİREBİR aynı 7 hizmet ili
/// — bkz. equipment_list_screen.dart _IlFilterBar'daki AYNI gerekçe notu.
const _ilOptions = [
  'Erzurum',
  'Erzincan',
  'Ağrı',
  'Kars',
  'Iğdır',
  'Ardahan',
  'Bayburt',
];

class _IlFilterBar extends StatelessWidget {
  final QrGenerationProvider provider;
  const _IlFilterBar({required this.provider});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filters = <String, String?>{
      'Tümü': null,
      for (final il in _ilOptions) il: il,
    };

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: filters.entries.map((entry) {
          final isSelected = provider.ilFilter == entry.value;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: ChoiceChip(
              label: Text(entry.key),
              selected: isSelected,
              showCheckmark: false,
              labelStyle: TextStyle(
                color: isSelected ? scheme.onPrimary : scheme.onSurfaceVariant,
                fontSize: 12,
              ),
              onSelected: (_) => provider.setIlFilter(entry.value),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// equipment_list_screen.dart'taki `_EquipmentCard` ile GÖRSEL OLARAK
/// tutarlı (AppCard, durum şeridi, tip ikonu) — tek fark, çoklu seçim için
/// başta bir checkbox. `_EquipmentCard` o dosyada private olduğu için burada
/// AYNI yapı kasıtlı olarak yeniden üretildi (paylaşılan bir widget'a
/// çıkarmak bu tek kullanım için gereksiz bir soyutlama olurdu).
class _QrEquipmentCard extends StatelessWidget {
  final Equipment equipment;
  final bool selected;
  final VoidCallback onChanged;

  const _QrEquipmentCard({
    required this.equipment,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      onTap: onChanged,
      statusStripeColor: equipmentStatusColor(context, equipment.status),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Checkbox(
            value: selected,
            onChanged: (_) => onChanged(),
          ),
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Icon(
              equipment.equipmentType.icon,
              size: 20,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  equipment.equipmentType.label,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.qr_code_2_outlined,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      equipment.qrCode,
                      style: AppTextStyles.dataMono(
                        color: scheme.onSurfaceVariant,
                      ).copyWith(fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        equipment.locationName,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
