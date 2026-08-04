import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/equipment.dart';
import '../providers/equipment_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'app_card.dart';

/// Performanslı, arama yapılabilen (typeahead) ekipman seçici — "Yeni İş
/// Emri Oluştur" formunun konum tutarlılığının temelidir (bkz.
/// create_work_order_screen.dart üstündeki gerekçe notu). Kullanıcı bir
/// ekipman aratıp seçer; konum bilgisi ARTIK elle girilmez, seçilen
/// ekipmandan otomatik gelir.
///
/// Kutucuğa DOKUNULDUĞU AN (yazı yazmadan), kayıtlı TÜM ekipmanların listesi
/// açılır — kullanıcı QR kodunu ezbere bilmek zorunda kalmadan gözden
/// geçirip seçebilir. Yazmaya başlarsa bu liste, kullanıcı yazmayı
/// bıraktıktan ~400ms sonra (debounce, burada bir [Timer] ile yönetilir)
/// GET /api/equipment?search=... isteğiyle daralır — arama VE gözden
/// geçirme (browse) AYNI mekanizmayı (EquipmentProvider.searchEquipment)
/// kullanır: boş sorgu backend'de filtre uygulanmadığı için tüm kayıtlı
/// ekipmanı döner (bkz. routes/equipment.js). EquipmentProvider.searchEquipment
/// yalnızca API çağrısını yapar, debounce mantığını taşımaz (bkz.
/// providers/equipment_provider.dart).
class EquipmentPickerField extends StatefulWidget {
  final Equipment? initialValue;
  final ValueChanged<Equipment?> onSelected;

  const EquipmentPickerField({
    super.key,
    this.initialValue,
    required this.onSelected,
  });

  @override
  State<EquipmentPickerField> createState() => _EquipmentPickerFieldState();
}

class _EquipmentPickerFieldState extends State<EquipmentPickerField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  Equipment? _selected;
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
      // Kutucuğa dokunmak KENDİ BAŞINA bir aksiyondur (yazmayı bekleyen bir
      // tuş vuruşu değil) — bu yüzden debounce'suz, anında sorgulanır. Metin
      // boşsa backend filtre uygulamadan TÜM ekipmanı döner (bkz. yukarısı).
      _debounce?.cancel();
      context.read<EquipmentProvider>().searchEquipment(
        _controller.text.trim(),
      );
    }
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      context.read<EquipmentProvider>().searchEquipment(query.trim());
    });
  }

  void _select(Equipment equipment) {
    _debounce?.cancel();
    _focusNode.unfocus();
    setState(() {
      _selected = equipment;
      _controller.clear();
    });
    context.read<EquipmentProvider>().clearSearch();
    widget.onSelected(equipment);
  }

  void _changeSelection() {
    setState(() => _selected = null);
    widget.onSelected(null);
    // Bir sonraki karede (build tamamlandıktan sonra) alana odaklanılır ki
    // liste kullanıcı ikinci kez dokunmadan hemen açılsın.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_selected != null) {
      return _SelectedEquipmentCard(
        equipment: _selected!,
        onChange: _changeSelection,
      );
    }

    final provider = context.watch<EquipmentProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText:
                'Listeden seçin ya da QR kod/il/ilçe/mahalle ile arayın...',
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
                'Eşleşen ekipman bulunamadı.',
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
                    final equipment = provider.searchResults[index];
                    return _EquipmentResultTile(
                      equipment: equipment,
                      onTap: () => _select(equipment),
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

class _EquipmentResultTile extends StatelessWidget {
  final Equipment equipment;
  final VoidCallback onTap;
  const _EquipmentResultTile({required this.equipment, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      dense: true,
      leading: Icon(equipment.equipmentType.icon, color: scheme.primary),
      title: Text(
        equipment.qrCode,
        style: AppTextStyles.dataMono(
          color: scheme.onSurface,
        ).copyWith(fontSize: 13),
      ),
      subtitle: Text(
        equipment.locationName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: equipmentStatusColor(
            context,
            equipment.status,
          ).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          equipment.status.label,
          style: TextStyle(
            color: equipmentStatusColor(context, equipment.status),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _SelectedEquipmentCard extends StatelessWidget {
  final Equipment equipment;
  final VoidCallback onChange;
  const _SelectedEquipmentCard({
    required this.equipment,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      statusStripeColor: equipmentStatusColor(context, equipment.status),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(equipment.equipmentType.icon, color: scheme.primary),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${equipment.equipmentType.label} · ${equipment.qrCode}',
                  style: AppTextStyles.dataMono(
                    color: scheme.onSurface,
                  ).copyWith(fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  equipment.locationName,
                  style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
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
