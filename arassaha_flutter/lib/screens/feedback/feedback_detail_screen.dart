import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/feedback_item.dart';
import '../../providers/auth_provider.dart';
import '../../providers/feedback_provider.dart';
import '../../services/analytics_service.dart';
import '../../services/api_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/empty_state.dart';

// bekliyor=sarı, incelendi=mavi, kapatildi=yeşil — feedback_list_screen.dart
// içindeki _statusColor ile AYNI eşleme; isg_report_detail_screen.dart'taki
// AYNI "her ekran kendi küçük kopyasını tutar" deseni.
Color _statusColor(BuildContext context, FeedbackStatus status) {
  switch (status) {
    case FeedbackStatus.bekliyor:
      return AppColors.warning(context);
    case FeedbackStatus.incelendi:
      return AppColors.primary(context);
    case FeedbackStatus.kapatildi:
      return AppColors.success(context);
  }
}

/// Öneri / Şikayet Kutusu (Modül 17) — bildirim detay ekranı. İSG bildirim
/// detayının (screens/isg/isg_report_detail_screen.dart) doğrudan bir
/// kopyası — aynı bölüm kartları, aynı durum güncelleme akışı. İSG'de
/// OLMAYAN konum/CV analizi bölümleri burada YOK (bir öneri/şikayetin konumu
/// veya görüntü analizi kavramı yok); fotoğraf İSG'nin aksine opsiyonel
/// olduğu için boş durumu "Bu bildirime fotoğraf eklenmemiş." ile aynı dille
/// gösterilir.
class FeedbackDetailScreen extends StatefulWidget {
  final int feedbackId;
  const FeedbackDetailScreen({super.key, required this.feedbackId});

  @override
  State<FeedbackDetailScreen> createState() => _FeedbackDetailScreenState();
}

class _FeedbackDetailScreenState extends State<FeedbackDetailScreen> {
  final _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('FeedbackDetailScreen');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FeedbackProvider>().fetchItemDetail(widget.feedbackId);
    });
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _updateStatus(FeedbackStatus newStatus) async {
    final provider = context.read<FeedbackProvider>();
    final messenger = ScaffoldMessenger.of(context);

    final success = await provider.updateItemStatus(
      widget.feedbackId,
      newStatus,
      reviewerNote: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
    );

    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Durum "${newStatus.label}" olarak güncellendi.'
              : (provider.detailErrorMessage ?? 'Güncellenemedi.'),
        ),
      ),
    );
    if (success) _noteController.clear();
  }

  String _formatDateTime(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FeedbackProvider>();
    final auth = context.watch<AuthProvider>();
    final item = provider.selectedItem?.id == widget.feedbackId
        ? provider.selectedItem
        : null;

    return Scaffold(
      appBar: const AppTopBar(title: 'Öneri / Şikayet Detayı'),
      body: Builder(
        builder: (context) {
          if (item == null && provider.detailErrorMessage != null) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'Bildirim yüklenemedi',
              subtitle: provider.detailErrorMessage!,
              onPrimaryAction: () =>
                  provider.fetchItemDetail(widget.feedbackId),
              primaryActionLabel: 'Tekrar Dene',
              primaryActionVariant: AppButtonVariant.secondary,
            );
          }

          if (item == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return RefreshIndicator(
            onRefresh: () => provider.fetchItemDetail(widget.feedbackId),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Row(
                  children: [
                    Icon(
                      item.category.icon,
                      size: 26,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        item.category.label,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    _StatusPill(status: item.status),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                _SectionCard(
                  title: 'Fotoğraf',
                  icon: Icons.photo_outlined,
                  child: _PhotoPreview(photoPath: item.photoPath),
                ),
                const SizedBox(height: AppSpacing.md),

                _SectionCard(
                  title: 'Açıklama',
                  icon: Icons.description_outlined,
                  child: Text(
                    item.description,
                    style: const TextStyle(height: 1.4),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                _SectionCard(
                  title: 'Bildirim Bilgisi',
                  icon: Icons.info_outline,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InfoRow(
                        icon: item.isAnonymous
                            ? Icons.person_off_outlined
                            : Icons.person_outline,
                        label: 'Bildiren',
                        // Tek gerçek fark (bkz. görev talimatı madde 5):
                        // anonimse gerçek isim yerine nötr bir etiket.
                        value: item.isAnonymous
                            ? 'Anonim Kullanıcı'
                            : (item.submittedBy?.name ?? 'Bilinmiyor'),
                      ),
                      _InfoRow(
                        icon: Icons.event_outlined,
                        label: 'Bildirim Tarihi',
                        value: _formatDateTime(item.createdAt),
                      ),
                      if (item.reviewedAt != null)
                        _InfoRow(
                          icon: Icons.fact_check_outlined,
                          label: 'İnceleme Tarihi',
                          value: _formatDateTime(item.reviewedAt!),
                        ),
                      if (item.reviewedBy != null)
                        _InfoRow(
                          icon: Icons.verified_user_outlined,
                          label: 'İnceleyen',
                          value: item.reviewedBy!.name,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                if (item.reviewerNote?.isNotEmpty == true) ...[
                  _SectionCard(
                    title: 'İnceleme Notu',
                    icon: Icons.notes_outlined,
                    child: Text(
                      item.reviewerNote!,
                      style: const TextStyle(height: 1.4),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                // Yönetici İnceleme Akışı (bkz. görev talimatı madde 6) —
                // yalnızca dispeçer/yönetici görür: backend zaten
                // requireRole('dispecer', 'yonetici') ile bu aksiyonu
                // kısıtlıyor (bkz. routes/feedback.js PATCH /:id/status), bu
                // UI kararı o yetki modeliyle tutarlı tutulur.
                if (auth.isDispecer || auth.isYonetici)
                  _SectionCard(
                    title: 'Durum Güncelle',
                    icon: Icons.sync_alt,
                    child: _StatusUpdateSection(
                      item: item,
                      noteController: _noteController,
                      onUpdate: _updateStatus,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  final String? photoPath;
  const _PhotoPreview({required this.photoPath});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (photoPath == null || photoPath!.isEmpty) {
      return Container(
        width: double.infinity,
        height: 140,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_not_supported_outlined,
              color: scheme.onSurfaceVariant,
              size: 32,
            ),
            const SizedBox(height: 6),
            Text(
              'Bu bildirime fotoğraf eklenmemiş.',
              style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        ApiService.photoUrl(photoPath!),
        width: double.infinity,
        height: 220,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            height: 220,
            alignment: Alignment.center,
            color: scheme.surfaceContainerHigh,
            child: const CircularProgressIndicator(strokeWidth: 2),
          );
        },
        errorBuilder: (context, error, stackTrace) => Container(
          height: 140,
          alignment: Alignment.center,
          color: scheme.surfaceContainerHigh,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.broken_image_outlined,
                color: scheme.onSurfaceVariant,
                size: 32,
              ),
              const SizedBox(height: 6),
              Text(
                'Fotoğraf yüklenemedi.',
                style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final FeedbackStatus status;
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

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
          const SizedBox(height: AppSpacing.sm + 4),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

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
            child: Text(value, style: TextStyle(color: scheme.onSurface)),
          ),
        ],
      ),
    );
  }
}

/// Bekliyor -> İncelendi -> Kapatıldı akışı — isg_report_detail_screen.dart
/// _StatusUpdateSection ile AYNI desen, yalnızca etiketler farklı (bkz. görev
/// talimatı madde 6).
class _StatusUpdateSection extends StatelessWidget {
  final FeedbackItem item;
  final TextEditingController noteController;
  final ValueChanged<FeedbackStatus> onUpdate;
  const _StatusUpdateSection({
    required this.item,
    required this.noteController,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FeedbackProvider>();
    final scheme = Theme.of(context).colorScheme;
    final nextStatus = item.status.nextStatus;

    if (nextStatus == null) {
      return Text(
        'Bu bildirim kapatıldı olarak işaretlenmiş, daha ileri bir aşama yok.',
        style: TextStyle(color: scheme.onSurfaceVariant),
      );
    }

    final actionLabel = nextStatus == FeedbackStatus.incelendi
        ? 'İncelendi Olarak İşaretle'
        : 'Kapatıldı Olarak İşaretle';
    final actionIcon = nextStatus == FeedbackStatus.incelendi
        ? Icons.fact_check_outlined
        : Icons.check_circle_outline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Mevcut durum: ${item.status.label}'),
        const SizedBox(height: AppSpacing.sm + 4),
        TextField(
          controller: noteController,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: 'İnceleme notu ekleyin (opsiyonel)...',
            isDense: true,
          ),
        ),
        const SizedBox(height: AppSpacing.sm + 4),
        SizedBox(
          width: double.infinity,
          child: AppButton(
            label: actionLabel,
            icon: actionIcon,
            isLoading: provider.isUpdatingStatus,
            onPressed: () => onUpdate(nextStatus),
          ),
        ),
      ],
    );
  }
}
