import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_notification.dart';
import '../../providers/notification_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/work_order_card.dart' show formatRelativeTime;
import '../equipment/equipment_detail_screen.dart';
import '../isg/isg_report_detail_screen.dart';
import '../work_order_detail_screen.dart';

/// Bildirim Sistemi (Modül 6) — bildirimler ekranı.
///
/// Bu veri, gerçek bir push (FCM) altyapısından değil, backend'in
/// `notifications` tablosundan gelir (bkz. NotificationProvider). Cihazın
/// bildirim çubuğundaki yerel bildirim yalnızca "yeni bildiriminiz var" gibi
/// genel bir uyarıdır — spesifik içerik (mesaj, ilgili kayıt) kullanıcı bu
/// ekranı açtığında tam listeyle görülür.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationProvider>().fetchNotifications();
    });
  }

  Future<void> _openNotification(AppNotification notification) async {
    final provider = context.read<NotificationProvider>();
    if (!notification.isRead) {
      await provider.markAsRead(notification.id);
    }

    if (!mounted) return;

    switch (notification.relatedType) {
      case NotificationRelatedType.workOrder:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => WorkOrderDetailScreen(workOrderId: notification.relatedId)),
        );
      case NotificationRelatedType.isgReport:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => IsgReportDetailScreen(reportId: notification.relatedId)),
        );
      case NotificationRelatedType.equipment:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => EquipmentDetailScreen(equipmentId: notification.relatedId)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bildirimler'),
      ),
      body: RefreshIndicator(
        onRefresh: provider.fetchNotifications,
        child: _buildBody(provider, scheme),
      ),
    );
  }

  Widget _buildBody(NotificationProvider provider, ColorScheme scheme) {
    if (provider.isLoading && provider.notifications.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.errorMessage != null && provider.notifications.isEmpty) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                Icon(Icons.error_outline, size: 48, color: scheme.error),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  provider.errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.error),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppButton(
                  label: 'Tekrar Dene',
                  variant: AppButtonVariant.secondary,
                  onPressed: provider.fetchNotifications,
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (provider.notifications.isEmpty) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 120),
            child: Column(
              children: [
                Icon(Icons.notifications_none, size: 56, color: scheme.outline),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Henüz bir bildiriminiz yok',
                  style: AppTextStyles.bodyMedium(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xl),
      children: [
        if (provider.unreadCount > 0) ...[
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              label: 'Tümünü Okundu Yap',
              icon: Icons.done_all,
              variant: AppButtonVariant.secondary,
              onPressed: provider.markAllAsRead,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        ...provider.notifications.map(
          (n) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _NotificationTile(notification: n, onTap: () => _openNotification(n)),
          ),
        ),
      ],
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const _NotificationTile({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUnread = !notification.isRead;

    return AppCard(
      onTap: onTap,
      statusStripeColor: isUnread ? AppColors.primary(context) : null,
      backgroundTint: isUnread ? AppColors.primary(context) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (isUnread ? AppColors.primary(context) : scheme.outlineVariant).withValues(alpha: isUnread ? 1 : 0.4),
              shape: BoxShape.circle,
            ),
            child: Icon(
              notification.relatedType.icon,
              size: 18,
              color: isUnread ? Colors.white : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notification.message,
                  style: AppTextStyles.bodyMedium(color: scheme.onSurface).copyWith(
                    fontWeight: isUnread ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatRelativeTime(notification.createdAt),
                  style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (isUnread) ...[
            const SizedBox(width: AppSpacing.xs),
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(color: AppColors.primary(context), shape: BoxShape.circle),
            ),
          ],
        ],
      ),
    );
  }
}
