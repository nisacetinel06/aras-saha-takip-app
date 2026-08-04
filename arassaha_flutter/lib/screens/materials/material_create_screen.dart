import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/equipment.dart' show EquipmentType;
import '../../models/material.dart';
import '../../providers/auth_provider.dart';
import '../../providers/material_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/sticky_form_footer.dart';

/// Yeni Malzeme Ekleme (Modül 13) — YALNIZCA yönetici erişebilir. Backend
/// zaten requireRole('yonetici') ile POST /api/materials'ı korur (bkz.
/// routes/materials.js); bu ekran da CreateWorkOrderScreen ile AYNI ikinci
/// koruma katmanı desenini uygular (bkz. build).
class MaterialCreateScreen extends StatefulWidget {
  const MaterialCreateScreen({super.key});

  @override
  State<MaterialCreateScreen> createState() => _MaterialCreateScreenState();
}

class _MaterialCreateScreenState extends State<MaterialCreateScreen> {
  final _nameController = TextEditingController();
  final _stockController = TextEditingController();
  final _thresholdController = TextEditingController();
  final _unitCostController = TextEditingController();

  MaterialCategory _category = MaterialCategory.diger;
  MaterialUnit _unit = MaterialUnit.adet;
  final Set<EquipmentType> _compatibleTypes = {};

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('MaterialCreateScreen');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _stockController.dispose();
    _thresholdController.dispose();
    _unitCostController.dispose();
    super.dispose();
  }

  double? _parse(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

  bool get _canSubmit {
    final provider = context.read<MaterialProvider>();
    final stock = _parse(_stockController.text);
    final threshold = _parse(_thresholdController.text);
    return _nameController.text.trim().isNotEmpty &&
        stock != null &&
        stock >= 0 &&
        threshold != null &&
        threshold >= 0 &&
        _compatibleTypes.isNotEmpty &&
        !provider.isSubmitting;
  }

  Future<void> _submit() async {
    final stock = _parse(_stockController.text);
    final threshold = _parse(_thresholdController.text);
    if (!_canSubmit || stock == null || threshold == null) return;

    final provider = context.read<MaterialProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final success = await provider.createMaterial(
      name: _nameController.text.trim(),
      category: _category,
      unit: _unit,
      stockQuantity: stock,
      minStockThreshold: threshold,
      compatibleEquipmentTypes: _compatibleTypes.toList(),
      unitCost: _unitCostController.text.trim().isNotEmpty
          ? _parse(_unitCostController.text)
          : null,
    );

    if (!mounted) return;

    if (success) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Malzeme oluşturuldu.')),
      );
      navigator.pop(true);
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            provider.submitErrorMessage ?? 'Malzeme oluşturulamadı.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

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

    final provider = context.watch<MaterialProvider>();

    return Scaffold(
      appBar: const AppTopBar(title: 'Yeni Malzeme Ekle'),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Text('İsim', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _nameController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Örn. 100A Trafo Sigortası',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            Text('Kategori', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: MaterialCategory.values.map((category) {
                return _SingleSelectChip(
                  label: category.label,
                  icon: category.icon,
                  selected: _category == category,
                  onTap: () => setState(() => _category = category),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.lg),

            Text('Birim', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<MaterialUnit>(
              initialValue: _unit,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true),
              items: MaterialUnit.values
                  .map(
                    (unit) =>
                        DropdownMenuItem(value: unit, child: Text(unit.label)),
                  )
                  .toList(),
              onChanged: (unit) {
                if (unit != null) setState(() => _unit = unit);
              },
            ),
            const SizedBox(height: AppSpacing.lg),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Başlangıç Stok',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: _stockController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: '0',
                          suffixText: _unit.label,
                          isDense: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Kritik Eşik',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: _thresholdController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: '0',
                          suffixText: _unit.label,
                          isDense: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            Text(
              'Birim Maliyet (₺, opsiyonel)',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _unitCostController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(hintText: 'Örn. 145.00'),
            ),
            const SizedBox(height: AppSpacing.lg),

            Text(
              'Uyumlu Ekipman Tipleri',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Bu malzeme tipik olarak hangi ekipmanlarla kullanılır? (birden fazla seçebilirsiniz)',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: EquipmentType.values.map((type) {
                final selected = _compatibleTypes.contains(type);
                return _SingleSelectChip(
                  label: type.label,
                  icon: type.icon,
                  selected: selected,
                  onTap: () => setState(() {
                    if (selected) {
                      _compatibleTypes.remove(type);
                    } else {
                      _compatibleTypes.add(type);
                    }
                  }),
                );
              }).toList(),
            ),
            if (_compatibleTypes.isEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'En az bir ekipman tipi seçilmeli.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      // B1 (baş parmak ergonomisi): birincil aksiyon ekranın altında SABİT —
      // form ne kadar uzun olursa olsun kullanıcı yukarı/aşağı kaydırmadan
      // her zaman erişebilir (bkz. widgets/sticky_form_footer.dart).
      bottomNavigationBar: StickyFormFooter(
        child: SizedBox(
          width: double.infinity,
          child: AppButton(
            label: 'Malzemeyi Kaydet',
            icon: Icons.save_outlined,
            isLoading: provider.isSubmitting,
            onPressed: _canSubmit ? _submit : null,
          ),
        ),
      ),
    );
  }
}

/// Tek-seçimli VE çoklu-seçimli chip grupları için ortak görsel dil —
/// [AppCard] + `backgroundTint` (bkz. work_order_detail_screen.dart'taki
/// `_PriorityChip`/user_edit_screen.dart'taki `_RoleChip` ile AYNI aile).
/// Çoklu seçim burada `onTap`'in DIŞARIDA (Set üzerinde toggle yaparak)
/// yönetilmesiyle elde edilir — bileşenin kendisi tek/çoklu seçim
/// farkını bilmez, yalnızca "seçili mi" durumunu gösterir.
class _SingleSelectChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _SingleSelectChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = AppColors.primary(context);

    return AppCard(
      onTap: onTap,
      backgroundTint: selected ? color : null,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 4,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: selected ? color : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? color : scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
