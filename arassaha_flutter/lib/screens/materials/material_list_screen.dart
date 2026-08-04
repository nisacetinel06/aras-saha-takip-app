import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/material.dart';
import '../../providers/auth_provider.dart';
import '../../providers/material_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import 'material_create_screen.dart';
import 'material_detail_screen.dart';

/// Malzeme / Yedek Parça Stok Takibi (Modül 13) — depodaki tüm malzemelerin
/// listesi. TÜM roller erişebilir (yalnızca görüntüleme amaçlı — teknisyen de
/// "depoda ne var" diye bakabilmeli, bkz. ARCHITECTURE.md Modül 13 RBAC notu);
/// yeni malzeme TİPİ ekleme FAB'ı ise yalnızca yöneticiye görünür.
class MaterialListScreen extends StatefulWidget {
  const MaterialListScreen({super.key});

  @override
  State<MaterialListScreen> createState() => _MaterialListScreenState();
}

class _MaterialListScreenState extends State<MaterialListScreen> {
  MaterialCategory? _categoryFilter;
  bool _onlyLowStock = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('MaterialListScreen');
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() {
    return context.read<MaterialProvider>().fetchMaterials(
      category: _categoryFilter?.toJson(),
      lowStockOnly: _onlyLowStock,
    );
  }

  void _setCategory(MaterialCategory? category) {
    setState(() => _categoryFilter = category);
    _reload();
  }

  void _setOnlyLowStock(bool value) {
    setState(() => _onlyLowStock = value);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MaterialProvider>();
    final isYonetici = context.watch<AuthProvider>().isYonetici;

    return Scaffold(
      appBar: const AppTopBar(title: 'Stok / Malzeme'),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _CategoryFilterBar(
              selected: _categoryFilter,
              onSelected: _setCategory,
            ),
            _LowStockToggleBar(
              value: _onlyLowStock,
              onChanged: _setOnlyLowStock,
            ),
            Expanded(
              child: Builder(
                builder: (context) {
                  if (provider.isLoadingList && provider.materials.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (provider.listErrorMessage != null &&
                      provider.materials.isEmpty) {
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
                            AppButton(label: 'Tekrar Dene', onPressed: _reload),
                          ],
                        ),
                      ),
                    );
                  }

                  if (provider.materials.isEmpty) {
                    return Center(
                      child: Text(
                        'Bu filtreye uyan malzeme yok.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: _reload,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.sm,
                        AppSpacing.md,
                        AppSpacing.xl + 56,
                      ),
                      itemCount: provider.materials.length,
                      itemBuilder: (context, index) {
                        final material = provider.materials[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: _MaterialListCard(
                            material: material,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => MaterialDetailScreen(
                                  materialId: material.id,
                                ),
                              ),
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
      ),
      floatingActionButton: isYonetici
          ? FloatingActionButton.extended(
              onPressed: () async {
                final created = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => const MaterialCreateScreen(),
                  ),
                );
                if (created == true) _reload();
              },
              icon: const Icon(Icons.add),
              label: const Text('Yeni Malzeme Ekle'),
            )
          : null,
    );
  }
}

class _CategoryFilterBar extends StatelessWidget {
  final MaterialCategory? selected;
  final ValueChanged<MaterialCategory?> onSelected;
  const _CategoryFilterBar({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filters = <String, MaterialCategory?>{
      'Tümü': null,
      for (final category in MaterialCategory.values) category.label: category,
    };

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: filters.entries.map((entry) {
          final isSelected = selected == entry.value;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: ChoiceChip(
              label: Text(entry.key),
              selected: isSelected,
              showCheckmark: false,
              labelStyle: TextStyle(
                color: isSelected ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
              onSelected: (_) => onSelected(entry.value),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _LowStockToggleBar extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _LowStockToggleBar({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FilterChip(
          label: const Text('Sadece Kritik Stok'),
          avatar: Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: value ? scheme.onPrimary : AppColors.danger(context),
          ),
          selected: value,
          showCheckmark: false,
          labelStyle: TextStyle(
            color: value ? scheme.onPrimary : scheme.onSurfaceVariant,
          ),
          onSelected: onChanged,
        ),
      ),
    );
  }
}

class _MaterialListCard extends StatelessWidget {
  final MaterialItem material;
  final VoidCallback onTap;
  const _MaterialListCard({required this.material, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stripeColor = material.isLowStock
        ? AppColors.danger(context)
        : AppColors.success(context);

    return AppCard(
      onTap: onTap,
      statusStripeColor: stripeColor,
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
            child: Icon(
              material.category.icon,
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
                  material.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  material.category.label,
                  style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 14,
                      color: stripeColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${formatMaterialQuantity(material.stockQuantity)} ${material.unit.label}',
                      style: TextStyle(
                        color: stripeColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(eşik: ${formatMaterialQuantity(material.minStockThreshold)} ${material.unit.label})',
                      style: AppTextStyles.caption(
                        color: scheme.onSurfaceVariant,
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
