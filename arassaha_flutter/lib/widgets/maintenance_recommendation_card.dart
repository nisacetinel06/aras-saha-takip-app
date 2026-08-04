import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/equipment_risk.dart' show RiskLevel;
import '../models/maintenance_recommendation.dart';
import '../models/work_order.dart';
import '../providers/auth_provider.dart';
import '../providers/maintenance_provider.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../screens/work_order_detail_screen.dart';
import 'app_button.dart';
import 'app_card.dart';

String _formatDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
}

String _urgencyLabel(RiskLevel level) {
  switch (level) {
    case RiskLevel.dusuk:
      return 'Düşük Öncelik';
    case RiskLevel.orta:
      return 'Orta Öncelik';
    case RiskLevel.yuksek:
      return 'Yüksek Öncelik';
  }
}

/// Kestirimci Bakım Planlama (Modül 12) — tek bir bakım önerisi kartı.
///
/// Hem merkezi liste ekranında (maintenance_recommendations_screen.dart) hem
/// de Ekipman Detayı'ndaki bağlam içi kartta (equipment_detail_screen.dart)
/// AYNI bileşen kullanılır — kart görünümü, aksiyonlar ve diyaloglar TEK
/// yerde tanımlıdır, iki ekran arasında kopyalanmaz.
class MaintenanceRecommendationCard extends StatelessWidget {
  final MaintenanceRecommendation recommendation;
  const MaintenanceRecommendationCard({
    super.key,
    required this.recommendation,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<MaintenanceProvider>();
    final isMutating = provider.isMutating(recommendation.id);
    final color = riskLevelColor(context, recommendation.urgencyLevel);
    final equipment = recommendation.equipment;

    return AppCard(
      statusStripeColor: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                equipment.equipmentType.icon,
                size: 22,
                color: scheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${equipment.equipmentType.label} · ${equipment.qrCode}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
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
                            style: AppTextStyles.caption(
                              color: scheme.onSurfaceVariant,
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
              const SizedBox(width: AppSpacing.sm),
              _UrgencyBadge(level: recommendation.urgencyLevel),
            ],
          ),
          const SizedBox(height: AppSpacing.sm + 4),
          Row(
            children: [
              _StatChip(
                icon: Icons.speed,
                label: 'Risk Skoru: ${recommendation.riskScoreAtCreation}',
                color: color,
              ),
              const SizedBox(width: AppSpacing.sm),
              _StatChip(
                icon: Icons.event_outlined,
                label:
                    'Önerilen: ${_formatDate(recommendation.recommendedDate)}',
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            recommendation.reason,
            style: AppTextStyles.bodyMedium(color: scheme.onSurface),
          ),
          const SizedBox(height: AppSpacing.sm + 4),

          if (recommendation.status ==
              MaintenanceRecommendationStatus.planlandi)
            _PlannedBadge(workOrderId: recommendation.relatedWorkOrderId)
          else if (recommendation.status ==
                  MaintenanceRecommendationStatus.onerildi &&
              auth.canCreateWorkOrders) ...[
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Önleyici İş Emri Oluştur',
                    icon: Icons.build_circle_outlined,
                    isLoading: isMutating,
                    onPressed: isMutating
                        ? null
                        : () => _openCreateWorkOrderDialog(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                label: 'Reddet',
                variant: AppButtonVariant.text,
                onPressed: isMutating ? null : () => _confirmDismiss(context),
              ),
            ),
          ] else if (recommendation.status !=
              MaintenanceRecommendationStatus.onerildi)
            _StatusOnlyBadge(status: recommendation.status),
        ],
      ),
    );
  }

  Future<void> _openCreateWorkOrderDialog(BuildContext context) async {
    final maintenanceProvider = context.read<MaintenanceProvider>();
    await showDialog<void>(
      context: context,
      builder: (_) => _CreateWorkOrderDialog(
        recommendation: recommendation,
        onConfirm: (assignedUserId, priority) async {
          final navigator = Navigator.of(context);
          final messenger = ScaffoldMessenger.of(context);
          final workOrder = await maintenanceProvider
              .createWorkOrderFromRecommendation(
                recommendation.id,
                assignedUserId: assignedUserId,
                priority: priority,
              );
          navigator.pop();
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                workOrder != null
                    ? 'Önleyici iş emri oluşturuldu.'
                    : (maintenanceProvider.mutationErrorMessage ??
                          'İş emri oluşturulamadı.'),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmDismiss(BuildContext context) async {
    final maintenanceProvider = context.read<MaintenanceProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Öneriyi Reddet'),
        content: const Text('Bu öneriyi reddetmek istediğinize emin misiniz?'),
        actions: [
          AppButton(
            label: 'Vazgeç',
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppButton(
            label: 'Reddet',
            variant: AppButtonVariant.destructive,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final ok = await maintenanceProvider.dismissRecommendation(
      recommendation.id,
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Öneri reddedildi.'
              : (maintenanceProvider.mutationErrorMessage ??
                    'Öneri reddedilemedi.'),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _UrgencyBadge extends StatelessWidget {
  final RiskLevel level;
  const _UrgencyBadge({required this.level});

  @override
  Widget build(BuildContext context) {
    final color = riskLevelColor(context, level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        _urgencyLabel(level),
        style: TextStyle(
          color: accessibleOnColor(color),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StatusOnlyBadge extends StatelessWidget {
  final MaintenanceRecommendationStatus status;
  const _StatusOnlyBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          status.label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Öneri bir iş emrine dönüştürüldüğünde ("planlandi") gösterilen rozet —
/// tıklanınca Modül 1'in iş emri detay ekranına gider (modüller arası gerçek
/// bağlantı, mock/placeholder DEĞİL).
class _PlannedBadge extends StatelessWidget {
  final int? workOrderId;
  const _PlannedBadge({required this.workOrderId});

  @override
  Widget build(BuildContext context) {
    final success = AppColors.success(context);
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle, size: 16, color: success),
        const SizedBox(width: 6),
        Text(
          'İş Emri Oluşturuldu',
          style: TextStyle(
            color: success,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        if (workOrderId != null) ...[
          const SizedBox(width: 6),
          Icon(Icons.arrow_forward, size: 14, color: success),
        ],
      ],
    );

    if (workOrderId == null) return content;

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.chip),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WorkOrderDetailScreen(workOrderId: workOrderId!),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: content,
      ),
    );
  }
}

/// "Önleyici İş Emri Oluştur" diyaloğu: teknisyen seçimi (yalnızca aktif
/// teknisyenler — CreateWorkOrderScreen ile AYNI desen) + öncelik onayı
/// (varsayılan urgency_level'dan türer, istenirse değiştirilebilir).
class _CreateWorkOrderDialog extends StatefulWidget {
  final MaintenanceRecommendation recommendation;
  final Future<void> Function(int assignedUserId, String priority) onConfirm;

  const _CreateWorkOrderDialog({
    required this.recommendation,
    required this.onConfirm,
  });

  @override
  State<_CreateWorkOrderDialog> createState() => _CreateWorkOrderDialogState();
}

class _CreateWorkOrderDialogState extends State<_CreateWorkOrderDialog> {
  List<AssignedUser> _technicians = [];
  AssignedUser? _selectedTechnician;
  bool _isLoadingTechnicians = true;
  String? _technicianError;

  late WorkOrderPriority _priority;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // urgency_level'dan türet: yuksek -> acil, diğerleri -> normal — backend
    // POST .../create-work-order ile AYNI varsayılan kural (bkz. routes/maintenance.js).
    _priority = widget.recommendation.urgencyLevel == RiskLevel.yuksek
        ? WorkOrderPriority.acil
        : WorkOrderPriority.normal;
    _loadTechnicians();
  }

  Future<void> _loadTechnicians() async {
    setState(() {
      _isLoadingTechnicians = true;
      _technicianError = null;
    });
    try {
      final users = await ApiService().getUsers(
        roleFilter: 'teknisyen',
        activeOnly: true,
      );
      if (!mounted) return;
      setState(() => _technicians = users);
    } catch (e) {
      if (!mounted) return;
      setState(() => _technicianError = e.toString());
    } finally {
      if (mounted) setState(() => _isLoadingTechnicians = false);
    }
  }

  Future<void> _confirm() async {
    if (_selectedTechnician == null || _isSubmitting) return;
    setState(() => _isSubmitting = true);
    await widget.onConfirm(_selectedTechnician!.id, _priority.toJson());
    if (mounted) setState(() => _isSubmitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Önleyici İş Emri Oluştur'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.recommendation.equipment.equipmentType.label} · ${widget.recommendation.equipment.qrCode}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Atanacak Teknisyen',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.xs),
            _buildTechnicianField(),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Öncelik',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.xs),
            DropdownButtonFormField<WorkOrderPriority>(
              initialValue: _priority,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true),
              items: WorkOrderPriority.values
                  .map((p) => DropdownMenuItem(value: p, child: Text(p.label)))
                  .toList(),
              onChanged: (p) {
                if (p != null) setState(() => _priority = p);
              },
            ),
          ],
        ),
      ),
      actions: [
        AppButton(
          label: 'Vazgeç',
          variant: AppButtonVariant.text,
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Oluştur',
          isLoading: _isSubmitting,
          onPressed: _selectedTechnician == null || _isSubmitting
              ? null
              : _confirm,
        ),
      ],
    );
  }

  Widget _buildTechnicianField() {
    if (_isLoadingTechnicians) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_technicianError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_technicianError!, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: AppSpacing.xs),
          AppButton(
            label: 'Tekrar Dene',
            variant: AppButtonVariant.secondary,
            onPressed: _loadTechnicians,
          ),
        ],
      );
    }

    return DropdownButtonFormField<AssignedUser>(
      initialValue: _selectedTechnician,
      isExpanded: true,
      decoration: const InputDecoration(
        hintText: 'Teknisyen seçin',
        isDense: true,
      ),
      items: _technicians
          .map((user) => DropdownMenuItem(value: user, child: Text(user.name)))
          .toList(),
      onChanged: (user) => setState(() => _selectedTechnician = user),
    );
  }
}
