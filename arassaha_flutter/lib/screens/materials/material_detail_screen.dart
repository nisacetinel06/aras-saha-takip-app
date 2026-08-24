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
import '../../widgets/empty_state.dart';
import '../../widgets/work_order_card.dart' show formatRelativeTime;
import '../work_order_detail_screen.dart';

/// Malzeme / Yedek Parça Stok Takibi (Modül 13) — tek bir malzemenin detayı:
/// stok bilgisi, eşik değeri, uyumlu ekipman tipleri, ve (Cihaz Yönetimi'ndeki
/// "işlem geçmişi" tasarımıyla tutarlı) tam stok hareketi geçmişi.
class MaterialDetailScreen extends StatefulWidget {
  final int materialId;
  const MaterialDetailScreen({super.key, required this.materialId});

  @override
  State<MaterialDetailScreen> createState() => _MaterialDetailScreenState();
}

class _MaterialDetailScreenState extends State<MaterialDetailScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('MaterialDetailScreen');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MaterialProvider>().fetchMaterialDetail(widget.materialId);
    });
  }

  Future<void> _openRestockDialog(
    BuildContext context,
    MaterialItem material,
  ) async {
    final provider = context.read<MaterialProvider>();
    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) => _RestockDialog(material: material),
    );
    if (result == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final success = await provider.restockMaterial(material.id, result);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success
              ? '${formatMaterialQuantity(result)} ${material.unit.label} stok eklendi.'
              : (provider.submitErrorMessage ?? 'Stok ikmali yapılamadı.'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MaterialProvider>();
    final detail =
        provider.selectedMaterialDetail?.material.id == widget.materialId
        ? provider.selectedMaterialDetail
        : null;
    final isYonetici = context.watch<AuthProvider>().isYonetici;

    return Scaffold(
      appBar: const AppTopBar(title: 'Malzeme Detayı'),
      body: SafeArea(
        top: false,
        child: Builder(
          builder: (context) {
            if (detail == null && provider.detailErrorMessage != null) {
              return EmptyState(
                icon: Icons.error_outline,
                title: 'Malzeme yüklenemedi',
                subtitle: provider.detailErrorMessage!,
                onPrimaryAction: () => context
                    .read<MaterialProvider>()
                    .fetchMaterialDetail(widget.materialId),
                primaryActionLabel: 'Tekrar Dene',
                primaryActionVariant: AppButtonVariant.secondary,
              );
            }

            if (detail == null) {
              return const Center(child: CircularProgressIndicator());
            }

            final material = detail.material;
            final stripeColor = material.isLowStock
                ? AppColors.danger(context)
                : AppColors.success(context);

            return RefreshIndicator(
              onRefresh: () => context
                  .read<MaterialProvider>()
                  .fetchMaterialDetail(widget.materialId),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  Row(
                    children: [
                      Icon(
                        material.category.icon,
                        size: 28,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          material.name,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    material.category.label,
                    style: AppTextStyles.caption(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  AppCard(
                    statusStripeColor: stripeColor,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 18,
                              color: stripeColor,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Stok Bilgisi',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm + 4),
                        _InfoRow(
                          icon: Icons.numbers,
                          label: 'Mevcut Stok',
                          value:
                              '${formatMaterialQuantity(material.stockQuantity)} ${material.unit.label}',
                          valueColor: stripeColor,
                        ),
                        _InfoRow(
                          icon: Icons.warning_amber_rounded,
                          label: 'Kritik Eşik',
                          value:
                              '${formatMaterialQuantity(material.minStockThreshold)} ${material.unit.label}',
                        ),
                        if (material.unitCost != null)
                          _InfoRow(
                            icon: Icons.sell_outlined,
                            label: 'Birim Maliyet',
                            value: '${material.unitCost!.toStringAsFixed(2)} ₺',
                          ),
                        _InfoRow(
                          icon: Icons.electrical_services_outlined,
                          label: 'Uyumlu Ekipman',
                          value: material.compatibleEquipmentTypes.isEmpty
                              ? '—'
                              : material.compatibleEquipmentTypes
                                    .map((t) => t.label)
                                    .join(', '),
                        ),
                        if (isYonetici) ...[
                          const SizedBox(height: AppSpacing.sm + 4),
                          SizedBox(
                            width: double.infinity,
                            child: AppButton(
                              label: 'Stok Ekle (İkmal)',
                              icon: Icons.add_box_outlined,
                              variant: AppButtonVariant.secondary,
                              isLoading: provider.isSubmitting,
                              onPressed: () =>
                                  _openRestockDialog(context, material),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.history,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'İşlem Geçmişi',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm + 4),
                        _MovementHistorySection(
                          movements: detail.stockMovements,
                          unit: material.unit,
                        ),
                      ],
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

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

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
            width: 110,
            child: Text(
              label,
              style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MovementHistorySection extends StatelessWidget {
  final List<MaterialStockMovement> movements;
  final MaterialUnit unit;
  const _MovementHistorySection({required this.movements, required this.unit});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (movements.isEmpty) {
      return Text(
        'Henüz bir stok hareketi yok.',
        style: AppTextStyles.bodyMedium(color: scheme.onSurfaceVariant),
      );
    }

    return Column(
      children: [
        for (int i = 0; i < movements.length; i++) ...[
          if (i > 0) const Divider(height: 20),
          _MovementRow(movement: movements[i], unit: unit),
        ],
      ],
    );
  }
}

class _MovementRow extends StatelessWidget {
  final MaterialStockMovement movement;
  final MaterialUnit unit;
  const _MovementRow({required this.movement, required this.unit});

  ({IconData icon, Color color, String label}) _presentation(
    BuildContext context,
  ) {
    final qty = formatMaterialQuantity(movement.quantity.abs());
    switch (movement.movementType) {
      case MaterialMovementType.kullanim:
        return (
          icon: Icons.remove_circle_outline,
          color: AppColors.danger(context),
          label:
              '$qty ${unit.label} kullanıldı'
              '${movement.relatedWorkOrderId != null ? ' - İş Emri #${movement.relatedWorkOrderId}' : ''}',
        );
      case MaterialMovementType.ikmal:
        return (
          icon: Icons.add_circle_outline,
          color: AppColors.success(context),
          label: '$qty ${unit.label} ikmal edildi',
        );
      case MaterialMovementType.iade:
        return (
          icon: Icons.undo,
          color: AppColors.warning(context),
          label:
              '$qty ${unit.label} iade edildi (hatalı kullanım kaydı silindi)'
              '${movement.relatedWorkOrderId != null ? ' - İş Emri #${movement.relatedWorkOrderId}' : ''}',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final presentation = _presentation(context);
    final workOrderId = movement.relatedWorkOrderId;

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(presentation.icon, size: 18, color: presentation.color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                presentation.label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${movement.performedByName} · ${formatRelativeTime(movement.createdAt)}',
                style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        if (workOrderId != null)
          Icon(
            Icons.arrow_forward_ios,
            size: 12,
            color: scheme.onSurfaceVariant,
          ),
      ],
    );

    if (workOrderId == null) return content;

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.chip),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WorkOrderDetailScreen(workOrderId: workOrderId),
        ),
      ),
      child: content,
    );
  }
}

class _RestockDialog extends StatefulWidget {
  final MaterialItem material;
  const _RestockDialog({required this.material});

  @override
  State<_RestockDialog> createState() => _RestockDialogState();
}

class _RestockDialogState extends State<_RestockDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double? get _parsedQuantity =>
      double.tryParse(_controller.text.replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) {
    final qty = _parsedQuantity;
    return AlertDialog(
      title: Text('${widget.material.name} — Stok Ekle'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: 'Eklenecek Miktar (${widget.material.unit.label})',
          isDense: true,
        ),
      ),
      actions: [
        AppButton(
          label: 'Vazgeç',
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Ekle',
          onPressed: (qty != null && qty > 0)
              ? () => Navigator.of(context).pop(qty)
              : null,
        ),
      ],
    );
  }
}
