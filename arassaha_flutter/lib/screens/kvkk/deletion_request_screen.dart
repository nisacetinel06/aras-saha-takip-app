import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/kvkk_models.dart';
import '../../providers/kvkk_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';

const _seriousActionWarning =
    'Bu işlem geri alınamaz, hesabınız pasif hale gelecek ve kişisel '
    'bilgileriniz anonimleştirilecektir. Devam etmeden önce yöneticinizle '
    'görüşmenizi öneririz.';

/// Veri Silme Talebi Formu — iki seçenek: yalnızca profil fotoğrafını sil,
/// ya da tüm kişisel verileri sil (hesap KALICI olarak anonimleştirilir).
///
/// İkinci seçenek geri alınamaz bir sonuç doğurduğu için (bkz. routes/kvkk.js
/// approve akışı), kazara seçimi/gönderimi önlemek amacıyla BİLİNÇLİ bir
/// sürtünme noktası eklendi: seçilince belirgin bir uyarı banner'ı görünür,
/// gönderilirken AYRICA bir onay dialogu açılır.
class DeletionRequestScreen extends StatefulWidget {
  const DeletionRequestScreen({super.key});

  @override
  State<DeletionRequestScreen> createState() => _DeletionRequestScreenState();
}

class _DeletionRequestScreenState extends State<DeletionRequestScreen> {
  KvkkRequestType _selectedType = KvkkRequestType.profilFotografiSil;
  final _reasonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('DeletionRequestScreen');
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<bool> _confirmSeriousAction() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Emin misiniz?'),
        content: const Text(_seriousActionWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Yine de Gönder'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _submit() async {
    if (_selectedType == KvkkRequestType.tumKisiselVerileriSil) {
      final confirmed = await _confirmSeriousAction();
      if (!confirmed || !mounted) return;
    }

    final provider = context.read<KvkkProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final success = await provider.submitDeletionRequest(
      requestType: _selectedType,
      reason: _reasonController.text.trim().isEmpty
          ? null
          : _reasonController.text.trim(),
    );

    if (!mounted) return;

    if (success) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Talebiniz yöneticinize iletildi, onay sonrası işlenecektir.',
          ),
        ),
      );
      navigator.pop();
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(provider.submitErrorMessage ?? 'Talep oluşturulamadı.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<KvkkProvider>();
    final scheme = Theme.of(context).colorScheme;
    final isSeriousSelection =
        _selectedType == KvkkRequestType.tumKisiselVerileriSil;

    return Scaffold(
      appBar: const AppTopBar(title: 'Veri Silme Talebi'),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(
            'Ne yapmak istiyorsunuz?',
            style: AppTextStyles.headingMedium(color: scheme.onSurface),
          ),
          const SizedBox(height: AppSpacing.sm + 4),
          ...KvkkRequestType.values.map(
            (type) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _RequestTypeOption(
                type: type,
                selected: _selectedType == type,
                onSelected: () => setState(() => _selectedType = type),
              ),
            ),
          ),
          if (isSeriousSelection) ...[
            const SizedBox(height: AppSpacing.sm),
            const _SeriousWarningBanner(),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Gerekçe (opsiyonel)',
            style: AppTextStyles.headingMedium(color: scheme.onSurface),
          ),
          const SizedBox(height: AppSpacing.sm + 4),
          TextField(
            controller: _reasonController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Talebinizin nedenini kısaca açıklayabilirsiniz...',
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            width: double.infinity,
            child: AppButton(
              label: 'Talebi Gönder',
              icon: Icons.send_outlined,
              variant: isSeriousSelection
                  ? AppButtonVariant.destructive
                  : AppButtonVariant.primary,
              isLoading: provider.isSubmitting,
              onPressed: _submit,
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestTypeOption extends StatelessWidget {
  final KvkkRequestType type;
  final bool selected;
  final VoidCallback onSelected;
  const _RequestTypeOption({
    required this.type,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      onTap: onSelected,
      statusStripeColor: selected ? scheme.primary : null,
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Text(
              type.label,
              style: AppTextStyles.bodyMedium(color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeriousWarningBanner extends StatelessWidget {
  const _SeriousWarningBanner();

  @override
  Widget build(BuildContext context) {
    final dangerColor = AppColors.danger(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: dangerColor.withValues(alpha: isDark ? 0.22 : 0.14),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: dangerColor.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: dangerColor, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              _seriousActionWarning,
              style: TextStyle(
                color: dangerColor,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
