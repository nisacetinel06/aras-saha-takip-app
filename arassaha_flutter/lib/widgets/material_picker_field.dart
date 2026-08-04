import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/material.dart';
import '../providers/material_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'app_card.dart';

/// Performanslı, arama yapılabilen (typeahead) malzeme seçici — Modül 4/12'deki
/// [EquipmentPickerField]/[EquipmentPickerField]-benzeri desenle AYNI mekanik
/// (bkz. widgets/equipment_picker_field.dart): kutucuğa dokunulduğu an tüm
/// malzemeler listelenir, yazmaya başlayınca ~400ms debounce sonrası
/// GET /api/materials?search=... ile daralır.
///
/// AKILLI SIRALAMA: [equipmentTypeHint] verilirse (içinde bulunulan iş
/// emrinin bağlı olduğu ekipmanın tipi — bkz. work_order_detail_screen.dart),
/// `compatible_equipment_types` alanında bu tip geçen malzemeler sonuç
/// listesinin BAŞINDA gösterilir (bkz. MaterialProvider._sortByEquipmentTypeHint).
/// Bu istemci tarafında yapılan bir YENİDEN SIRALAMADIR, backend'e ayrı bir
/// filtre parametresi olarak gönderilmez.
class MaterialPickerField extends StatefulWidget {
  final MaterialItem? initialValue;
  final String? equipmentTypeHint;
  final ValueChanged<MaterialItem?> onSelected;

  const MaterialPickerField({
    super.key,
    this.initialValue,
    this.equipmentTypeHint,
    required this.onSelected,
  });

  @override
  State<MaterialPickerField> createState() => _MaterialPickerFieldState();
}

class _MaterialPickerFieldState extends State<MaterialPickerField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  MaterialItem? _selected;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialValue;
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    setState(() => _isOpen = _focusNode.hasFocus);
    if (_focusNode.hasFocus) {
      // Kutucuğa dokunmak kendi başına bir aksiyondur — debounce'suz, anında
      // sorgulanır. Metin boşsa backend filtre uygulamadan TÜM malzemeleri döner.
      _debounce?.cancel();
      context.read<MaterialProvider>().searchMaterials(
        _controller.text.trim(),
        equipmentTypeHint: widget.equipmentTypeHint,
      );
    }
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      context.read<MaterialProvider>().searchMaterials(
        query.trim(),
        equipmentTypeHint: widget.equipmentTypeHint,
      );
    });
  }

  void _select(MaterialItem material) {
    _debounce?.cancel();
    _focusNode.unfocus();
    setState(() {
      _selected = material;
      _controller.clear();
    });
    context.read<MaterialProvider>().clearSearch();
    widget.onSelected(material);
  }

  void _changeSelection() {
    setState(() => _selected = null);
    widget.onSelected(null);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_selected != null) {
      return _SelectedMaterialCard(
        material: _selected!,
        onChange: _changeSelection,
      );
    }

    final provider = context.watch<MaterialProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText: 'Listeden seçin ya da malzeme adıyla arayın...',
            isDense: true,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: provider.isSearching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const Icon(Icons.arrow_drop_down),
          ),
        ),
        if (_isOpen) ...[
          const SizedBox(height: AppSpacing.sm),
          if (provider.searchErrorMessage != null)
            Text(
              provider.searchErrorMessage!,
              style: TextStyle(color: scheme.error, fontSize: 13),
            )
          else if (!provider.isSearching && provider.searchResults.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Eşleşen malzeme bulunamadı.',
                style: AppTextStyles.bodyMedium(color: scheme.onSurfaceVariant),
              ),
            )
          else if (provider.searchResults.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: AppCard(
                padding: EdgeInsets.zero,
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  itemCount: provider.searchResults.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final material = provider.searchResults[index];
                    return _MaterialResultTile(
                      material: material,
                      onTap: () => _select(material),
                    );
                  },
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _MaterialResultTile extends StatelessWidget {
  final MaterialItem material;
  final VoidCallback onTap;
  const _MaterialResultTile({required this.material, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Stok azsa teknisyen SEÇMEDEN ÖNCE görsün diye kırmızımsı renkle vurgulanır.
    final stockColor = material.isLowStock
        ? AppColors.danger(context)
        : scheme.onSurfaceVariant;

    return ListTile(
      onTap: onTap,
      dense: true,
      leading: Icon(material.category.icon, color: scheme.primary),
      title: Text(material.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        material.category.label,
        style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
      ),
      trailing: Text(
        '${formatMaterialQuantity(material.stockQuantity)} ${material.unit.label}',
        style: TextStyle(
          color: stockColor,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _SelectedMaterialCard extends StatelessWidget {
  final MaterialItem material;
  final VoidCallback onChange;
  const _SelectedMaterialCard({required this.material, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stockColor = material.isLowStock
        ? AppColors.danger(context)
        : AppColors.success(context);

    return AppCard(
      statusStripeColor: stockColor,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(material.category.icon, color: scheme.primary),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  material.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Stok: ${formatMaterialQuantity(material.stockQuantity)} ${material.unit.label}',
                  style: TextStyle(
                    color: stockColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onChange, child: const Text('Değiştir')),
        ],
      ),
    );
  }
}
