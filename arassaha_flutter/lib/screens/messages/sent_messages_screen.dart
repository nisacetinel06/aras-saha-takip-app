import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/manager_message.dart';
import '../../providers/manager_message_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/work_order_card.dart' show formatRelativeTime;
import 'send_manager_message_screen.dart';
import 'sent_message_read_status_screen.dart';

/// Yöneticiden Çalışana Duyuru/Mesaj Sistemi — yönetici görünümü,
/// gönderilen mesajlar listesi. Yalnızca YÖNETİCİNİN KENDİ gönderdiği
/// mesajlar (bkz. GET /api/manager-messages/sent — sender_user_id filtresi).
class SentMessagesScreen extends StatefulWidget {
  /// true ise alt navigasyondaki "Mesajlar" sekmesi içinde gösterilir (bkz.
  /// main_shell.dart) — [ManagerMessagesScreen.embedded] ile AYNI gerekçe:
  /// kendi [AppTopBar]'ını çizmez, MainShell'in ortak üst çubuğuyla çakışmasın
  /// diye. Varsayılan false: SendManagerMessageScreen'in üst çubuğundaki
  /// "Gönderilen Mesajlar" ikonundan PUSH edilen mevcut kullanım DEĞİŞMEDEN kalır.
  final bool embedded;

  const SentMessagesScreen({super.key, this.embedded = false});

  @override
  State<SentMessagesScreen> createState() => _SentMessagesScreenState();
}

class _SentMessagesScreenState extends State<SentMessagesScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('SentMessagesScreen');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ManagerMessageProvider>().fetchSentMessages();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ManagerMessageProvider>();

    return Scaffold(
      appBar: widget.embedded
          ? null
          : const AppTopBar(title: 'Gönderilen Mesajlar'),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: provider.fetchSentMessages,
          child: _buildBody(provider),
        ),
      ),
      // Yönetici için "Yeni Mesaj Gönder" — bkz. görev talimatı: Mesajlar
      // sekmesinde yöneticinin gönderilenler listesinden doğrudan gönderme
      // ekranına geçişi. SendManagerMessageScreen'in kendi üst çubuğundaki
      // "Gönderilen Mesajlar" ikonuyla AYNI hedefe TERS yönden ulaşan bir
      // kısayol — bilinçli olarak hem PUSH edilmiş hem embedded kullanımda
      // gösterilir, iki giriş noktası birbirini DIŞLAMAZ.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SendManagerMessageScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Yeni Mesaj Gönder'),
      ),
    );
  }

  Widget _buildBody(ManagerMessageProvider provider) {
    if (provider.isSentListLoading && provider.sentMessages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.sentListErrorMessage != null &&
        provider.sentMessages.isEmpty) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Gönderilen mesajlar yüklenemedi',
        subtitle: provider.sentListErrorMessage!,
        onPrimaryAction: provider.fetchSentMessages,
        primaryActionLabel: 'Tekrar Dene',
        primaryActionVariant: AppButtonVariant.secondary,
      );
    }

    if (provider.sentMessages.isEmpty) {
      return const EmptyState(
        icon: Icons.outgoing_mail,
        title: 'Henüz bir mesaj göndermediniz',
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
        for (final message in provider.sentMessages)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _SentMessageTile(
              message: message,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      SentMessageReadStatusScreen(messageId: message.id),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SentMessageTile extends StatelessWidget {
  final SentManagerMessage message;
  final VoidCallback onTap;

  const _SentMessageTile({required this.message, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final allRead =
        message.recipientCount > 0 &&
        message.readCount == message.recipientCount;

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.title != null) ...[
            Text(
              message.title!,
              style: AppTextStyles.bodyMedium(
                color: scheme.onSurface,
              ).copyWith(fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
          ],
          Text(
            message.content,
            style: AppTextStyles.bodyMedium(
              color: message.title != null
                  ? scheme.onSurfaceVariant
                  : scheme.onSurface,
            ),
            maxLines: message.title != null ? 1 : 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Icon(
                allRead ? Icons.check_circle_outline : Icons.mail_outline,
                size: 14,
                color: allRead
                    ? AppColors.success(context)
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                '${message.recipientCount} kişiden ${message.readCount}\'i okudu',
                style: AppTextStyles.caption(
                  color: allRead
                      ? AppColors.success(context)
                      : scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                formatRelativeTime(message.createdAt),
                style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
