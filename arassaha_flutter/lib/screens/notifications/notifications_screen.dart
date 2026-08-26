import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_notification.dart';
import '../../models/manager_message.dart';
import '../../providers/manager_message_provider.dart';
import '../../providers/notification_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/cache_age_note.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/staggered_fade_in.dart';
import '../../widgets/work_order_card.dart' show formatRelativeTime;
import '../equipment/equipment_detail_screen.dart';
import '../isg/isg_report_detail_screen.dart';
import '../messages/manager_message_detail_screen.dart';
import '../sos/sos_alerts_screen.dart';
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
    AnalyticsService.logScreenView('NotificationsScreen');
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
          MaterialPageRoute(
            builder: (_) =>
                WorkOrderDetailScreen(workOrderId: notification.relatedId),
          ),
        );
      case NotificationRelatedType.isgReport:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                IsgReportDetailScreen(reportId: notification.relatedId),
          ),
        );
      case NotificationRelatedType.equipment:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                EquipmentDetailScreen(equipmentId: notification.relatedId),
          ),
        );
      case NotificationRelatedType.managerMessage:
        await _openManagerMessage(notification.relatedId);
      case NotificationRelatedType.sosAlert:
        // Bu bildirim yalnızca dispeçer/yönetici'ye gider (bkz.
        // routes/sosAlerts.js POST /) — SOS Uyarıları ekranı zaten TÜM
        // bildirimleri listeler, tek bir kayda özel bir detay ekranı yok.
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const SosAlertsScreen()));
    }
  }

  /// Bildirim yalnızca mesajın id'sini taşır (bkz. AppNotification.relatedId)
  /// — tam içerik GET /api/manager-messages listesinde gelir, ayrı bir
  /// "tek mesaj getir" endpoint'i yok (bkz. routes/managerMessages.js).
  /// Liste henüz çekilmediyse (örn. kullanıcı Bildirimler'i mesaj ekranını
  /// hiç açmadan gördüyse) burada bir kere çekilir.
  Future<void> _openManagerMessage(int messageId) async {
    final messageProvider = context.read<ManagerMessageProvider>();
    if (messageProvider.messages.isEmpty) {
      await messageProvider.fetchMyMessages();
    }
    if (!mounted) return;

    ManagerMessage? message;
    for (final m in messageProvider.messages) {
      if (m.id == messageId) {
        message = m;
        break;
      }
    }

    if (message == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Mesaj bulunamadı.')));
      return;
    }
    final resolvedMessage = message;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ManagerMessageDetailScreen(message: resolvedMessage),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationProvider>();

    return Scaffold(
      // showNotificationBell: false — bu ekran zilin GİTTİĞİ yer, zilin
      // KENDİSİNİ tekrar göstermek anlamsız/kafa karıştırıcı olurdu.
      appBar: const AppTopBar(
        title: 'Bildirimler',
        showNotificationBell: false,
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: provider.fetchNotifications,
          child: _buildBody(provider),
        ),
      ),
    );
  }

  Widget _buildBody(NotificationProvider provider) {
    if (provider.isLoading && provider.notifications.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.errorMessage != null && provider.notifications.isEmpty) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Bildirimler yüklenemedi',
        subtitle: provider.errorMessage!,
        onPrimaryAction: provider.fetchNotifications,
        primaryActionLabel: 'Tekrar Dene',
        primaryActionVariant: AppButtonVariant.secondary,
      );
    }

    if (provider.notifications.isEmpty) {
      return const EmptyState(
        icon: Icons.notifications_none,
        title: 'Henüz bir bildiriminiz yok',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      children: [
        // Okuma Önbelleği (Modül 17) — bkz. work_order_list_screen.dart
        // AYNI desen ve gerekçe notu.
        if (provider.isFromCache) ...[
          CacheAgeNote(cachedAt: provider.cachedAt!),
          const SizedBox(height: AppSpacing.sm),
        ],
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
        ...provider.notifications.asMap().entries.map(
          (entry) => Padding(
            key: ValueKey(entry.value.id),
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: StaggeredFadeIn(
              index: entry.key,
              child: _NotificationTile(
                notification: entry.value,
                onTap: () => _openNotification(entry.value),
              ),
            ),
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
    // Acil Durum (SOS) Modülü — bir SOS kaydı, listede diğer bildirim
    // türlerinden (iş emri, İSG, risk vb.) HER ZAMAN ayırt edilebilir olmalı
    // — okunmuş/çözülmüş olsa BİLE (bir yönetici geçmişe dönük tararken
    // "hangileri SOS'tu" sorusunu anında cevaplayabilsin diye). Bu yüzden
    // rengi salt okunma durumundan (isUnread) BAĞIMSIZ, tür bazında seçilir
    // — ama SosButton/_SosAlertsAccessCard'daki dolu-kırmızı blok DEĞİL,
    // AppCard'ın zaten var olan ince şerit/tint mekanizması kullanılır.
    final isSos = notification.relatedType == NotificationRelatedType.sosAlert;
    final accentColor = isSos
        ? AppColors.danger(context)
        : AppColors.primary(context);

    return AppCard(
      onTap: onTap,
      statusStripeColor: isSos ? accentColor : (isUnread ? accentColor : null),
      backgroundTint: isUnread ? accentColor : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSos
                  ? accentColor.withValues(alpha: isUnread ? 1 : 0.15)
                  : (isUnread ? accentColor : scheme.outlineVariant).withValues(
                      alpha: isUnread ? 1 : 0.4,
                    ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              notification.relatedType.icon,
              size: 18,
              color: isSos
                  ? (isUnread ? accessibleOnColor(accentColor) : accentColor)
                  : (isUnread
                        ? accessibleOnColor(accentColor)
                        : scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isSos) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                    ),
                    child: Text(
                      'ACİL',
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  notification.message,
                  style: AppTextStyles.bodyMedium(color: scheme.onSurface)
                      .copyWith(
                        fontWeight: isUnread
                            ? FontWeight.w700
                            : FontWeight.w400,
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
              decoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
