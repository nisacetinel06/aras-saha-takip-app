import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/manager_message.dart';
import '../../providers/manager_message_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/role_helper.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/role_badge.dart';
import '../../widgets/work_order_card.dart' show formatRelativeTime;

/// Yöneticiden Çalışana Duyuru/Mesaj Sistemi — okundu takibi detayı.
///
/// Hangi çalışanın mesajı okuyup hangisinin henüz okumadığını (ve ne zaman
/// okuduğunu) gösterir — örn. bir güvenlik/İSG duyurusunun GERÇEKTEN herkese
/// ulaştığını doğrulamak için (bkz. görev tanımı). Yalnızca mesajı gönderen
/// yönetici bu ekrana erişebilir; backend başka bir yönetici/alıcı için
/// 403/404 döner (bkz. routes/managerMessages.js GET /:id/read-status).
class SentMessageReadStatusScreen extends StatefulWidget {
  final int messageId;

  const SentMessageReadStatusScreen({super.key, required this.messageId});

  @override
  State<SentMessageReadStatusScreen> createState() =>
      _SentMessageReadStatusScreenState();
}

class _SentMessageReadStatusScreenState
    extends State<SentMessageReadStatusScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('SentMessageReadStatusScreen');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ManagerMessageProvider>().fetchReadStatus(widget.messageId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ManagerMessageProvider>();

    return Scaffold(
      appBar: const AppTopBar(title: 'Okundu Takibi'),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () => provider.fetchReadStatus(widget.messageId),
          child: _buildBody(provider),
        ),
      ),
    );
  }

  Widget _buildBody(ManagerMessageProvider provider) {
    if (provider.isReadStatusLoading && provider.selectedReadStatus == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.readStatusErrorMessage != null &&
        provider.selectedReadStatus == null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Okundu bilgisi yüklenemedi',
        subtitle: provider.readStatusErrorMessage!,
        onPrimaryAction: () => provider.fetchReadStatus(widget.messageId),
        primaryActionLabel: 'Tekrar Dene',
        primaryActionVariant: AppButtonVariant.secondary,
      );
    }

    final status = provider.selectedReadStatus!;
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (status.title != null) ...[
                Text(
                  status.title!,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              Text(
                status.content,
                style: AppTextStyles.bodyMedium(color: scheme.onSurface),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${status.readCount} / ${status.recipients.length} kişi okudu · '
                '${formatRelativeTime(status.createdAt)} gönderildi',
                style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final recipient in status.recipients)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _RecipientTile(recipient: recipient),
          ),
      ],
    );
  }
}

class _RecipientTile extends StatelessWidget {
  final MessageRecipientStatus recipient;
  const _RecipientTile({required this.recipient});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isRead = recipient.isRead;

    return AppCard(
      statusStripeColor: isRead
          ? AppColors.success(context)
          : AppColors.warning(context),
      child: Row(
        children: [
          Icon(
            isRead ? Icons.check_circle_outline : Icons.schedule_outlined,
            size: 20,
            color: isRead
                ? AppColors.success(context)
                : AppColors.warning(context),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recipient.name,
                  style: AppTextStyles.bodyMedium(
                    color: scheme.onSurface,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  isRead
                      ? '${formatRelativeTime(recipient.readAt!)} okundu'
                      : 'Henüz okunmadı',
                  style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          RoleBadge(role: recipient.role, label: roleLabel(recipient.role)),
        ],
      ),
    );
  }
}
