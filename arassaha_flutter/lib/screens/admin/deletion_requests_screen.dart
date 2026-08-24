import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/kvkk_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/kvkk_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/empty_state.dart';

Color _statusColor(BuildContext context, KvkkRequestStatus status) {
  switch (status) {
    case KvkkRequestStatus.beklemede:
      return AppColors.warning(context);
    case KvkkRequestStatus.onaylandi:
    case KvkkRequestStatus.tamamlandi:
      return AppColors.success(context);
    case KvkkRequestStatus.reddedildi:
      return AppColors.danger(context);
  }
}

String _formatDateTime(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

/// Yönetici — Veri Silme Talepleri Paneli (KVKK Uyum Modülü). Sadece
/// yönetici rolüne açık — bkz. user_management_list_screen.dart'taki AYNI
/// ikinci koruma katmanı deseni (bir teknisyen/dispeçer deep link ile buraya
/// ulaşırsa build() içinde geri yönlendirilir).
class DeletionRequestsScreen extends StatefulWidget {
  const DeletionRequestsScreen({super.key});

  @override
  State<DeletionRequestsScreen> createState() =>
      _DeletionRequestsScreenState();
}

class _DeletionRequestsScreenState extends State<DeletionRequestsScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('DeletionRequestsScreen');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<KvkkProvider>().fetchAllDeletionRequests();
    });
  }

  Future<void> _approve(KvkkDeletionRequest request) async {
    // Anonimleştirme GERİ ALINAMAZ bir işlem olduğu için ek bir onay dialogu
    // — "Onayla" butonuna tek dokunuşla kazara tetiklenmesin diye.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Talebi Onayla'),
        content: Text(
          request.requestType == KvkkRequestType.tumKisiselVerileriSil
              ? 'Bu talebi onaylarsanız ${request.user?.name ?? 'kullanıcının'} verileri kalıcı olarak anonimleştirilecek, emin misiniz?'
              : 'Bu talebi onaylarsanız ${request.user?.name ?? 'kullanıcının'} profil fotoğrafı diskten kalıcı olarak silinecek, emin misiniz?',
        ),
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
            child: const Text('Onayla'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final provider = context.read<KvkkProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final success = await provider.approveRequest(request.id);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Talep onaylandı ve işlendi.'
              : (provider.processErrorMessage ?? 'Talep onaylanamadı.'),
        ),
      ),
    );
  }

  Future<void> _reject(KvkkDeletionRequest request) async {
    // Gerekçe ZORUNLU — dialog kendi içinde doğrular, boşken "Reddet" butonu
    // pasif kalır (bkz. görev talimatı: gerekçesiz red mümkün olmamalı).
    final noteController = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final trimmed = noteController.text.trim();
          return AlertDialog(
            title: const Text('Talebi Reddet'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Red gerekçesi zorunludur (örn. "Yasal saklama süresi dolmadığı için reddedildi").'),
                const SizedBox(height: AppSpacing.sm + 4),
                TextField(
                  controller: noteController,
                  autofocus: true,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Red gerekçesi...',
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Vazgeç'),
              ),
              TextButton(
                onPressed: trimmed.isEmpty
                    ? null
                    : () => Navigator.of(dialogContext).pop(trimmed),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(dialogContext).colorScheme.error,
                ),
                child: const Text('Reddet'),
              ),
            ],
          );
        },
      ),
    );
    noteController.dispose();
    if (note == null || note.isEmpty || !mounted) return;

    final provider = context.read<KvkkProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final success = await provider.rejectRequest(request.id, note);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Talep reddedildi.'
              : (provider.processErrorMessage ?? 'Talep reddedilemedi.'),
        ),
      ),
    );
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

    final provider = context.watch<KvkkProvider>();

    return Scaffold(
      appBar: const AppTopBar(title: 'Veri Silme Talepleri'),
      body: Builder(
        builder: (context) {
          if (provider.isLoadingRequests && provider.allRequests.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.requestsErrorMessage != null &&
              provider.allRequests.isEmpty) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'Silme talepleri yüklenemedi',
              subtitle: provider.requestsErrorMessage!,
              onPrimaryAction: () => provider.fetchAllDeletionRequests(),
              primaryActionLabel: 'Tekrar Dene',
              primaryActionVariant: AppButtonVariant.secondary,
            );
          }

          if (provider.allRequests.isEmpty) {
            return const EmptyState(
              icon: Icons.delete_outline,
              title: 'Henüz hiçbir veri silme talebi yok',
            );
          }

          // Bekleyen talepler her zaman EN ÜSTTE — yöneticinin dikkat etmesi
          // gereken (aksiyon bekleyen) satırlar, zaten sonuçlanmış olanların
          // arasında kaybolmasın diye.
          final sorted = [...provider.allRequests]..sort((a, b) {
            final aPending = a.status == KvkkRequestStatus.beklemede;
            final bPending = b.status == KvkkRequestStatus.beklemede;
            if (aPending != bPending) return aPending ? -1 : 1;
            return b.createdAt.compareTo(a.createdAt);
          });

          return RefreshIndicator(
            onRefresh: () => provider.fetchAllDeletionRequests(),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: sorted.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final request = sorted[index];
                return _RequestCard(
                  request: request,
                  isProcessing: provider.isProcessingRequest,
                  onApprove: () => _approve(request),
                  onReject: () => _reject(request),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final KvkkDeletionRequest request;
  final bool isProcessing;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  const _RequestCard({
    required this.request,
    required this.isProcessing,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = _statusColor(context, request.status);
    final isPending = request.status == KvkkRequestStatus.beklemede;

    return AppCard(
      statusStripeColor: statusColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  request.user != null
                      ? '${request.user!.name} · Sicil No: ${request.user!.sicilNo}'
                      : 'Kullanıcı #${request.userId}',
                  style: Theme.of(context).textTheme.headlineSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _StatusPill(status: request.status),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            request.requestType.label,
            style: AppTextStyles.bodyMedium(color: scheme.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            'Talep tarihi: ${_formatDateTime(request.createdAt)}',
            style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
          ),
          if (request.reason != null && request.reason!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Gerekçe: ${request.reason}',
              style: AppTextStyles.bodyMedium(color: scheme.onSurfaceVariant),
            ),
          ],
          if (!isPending && request.reviewerNote != null &&
              request.reviewerNote!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'İnceleme notu: ${request.reviewerNote}',
              style: AppTextStyles.bodyMedium(color: scheme.onSurfaceVariant),
            ),
          ],
          if (isPending) ...[
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  label: 'Reddet',
                  icon: Icons.close,
                  variant: AppButtonVariant.destructive,
                  isLoading: isProcessing,
                  onPressed: onReject,
                ),
                const SizedBox(width: AppSpacing.sm),
                AppButton(
                  label: 'Onayla',
                  icon: Icons.check,
                  isLoading: isProcessing,
                  onPressed: onApprove,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final KvkkRequestStatus status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: accessibleOnColor(color),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
