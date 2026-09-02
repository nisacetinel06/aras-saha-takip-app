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
import 'manager_message_detail_screen.dart';

/// Yöneticiden Çalışana Duyuru/Mesaj Sistemi — çalışan görünümü, mesaj
/// listesi.
///
/// SALT OKUNUR: bu ekranda (ve açtığı detay ekranında) hiçbir yerde bir
/// "cevap yaz"/"gönder" bileşeni YOK — çalışanlar birbirine de yöneticiye de
/// mesaj gönderemez, bu modülün kavramsal modeli BİLİNÇLİ olarak tek yönlü.
class ManagerMessagesScreen extends StatefulWidget {
  /// true ise alt navigasyondaki "Mesajlar" sekmesi içinde gösterilir (bkz.
  /// main_shell.dart) — kendi [AppTopBar]'ını ÇİZMEZ, çünkü MainShell zaten
  /// ortak bir üst çubuk taşıyor; ikisi aynı anda görünseydi ekranda iki üst
  /// çubuk üst üste binerdi. Varsayılan false: Ana Sayfa'nın "Yöneticiden
  /// Mesajlar" Çabuk Erişim kartından PUSH edilen mevcut kullanım (kendi geri
  /// tuşu/başlığıyla) DEĞİŞMEDEN kalır.
  final bool embedded;

  const ManagerMessagesScreen({super.key, this.embedded = false});

  @override
  State<ManagerMessagesScreen> createState() => _ManagerMessagesScreenState();
}

class _ManagerMessagesScreenState extends State<ManagerMessagesScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('ManagerMessagesScreen');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ManagerMessageProvider>().fetchMyMessages();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ManagerMessageProvider>();

    return Scaffold(
      appBar: widget.embedded
          ? null
          : const AppTopBar(title: 'Yöneticiden Mesajlar'),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: provider.fetchMyMessages,
          child: _buildBody(provider),
        ),
      ),
    );
  }

  Widget _buildBody(ManagerMessageProvider provider) {
    if (provider.isListLoading && provider.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.listErrorMessage != null && provider.messages.isEmpty) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Mesajlar yüklenemedi',
        subtitle: provider.listErrorMessage!,
        onPrimaryAction: provider.fetchMyMessages,
        primaryActionLabel: 'Tekrar Dene',
        primaryActionVariant: AppButtonVariant.secondary,
      );
    }

    if (provider.messages.isEmpty) {
      return const EmptyState(
        icon: Icons.mail_outline,
        title: 'Henüz bir mesajınız yok',
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
        for (final message in provider.messages)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _MessageTile(
              message: message,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ManagerMessageDetailScreen(message: message),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MessageTile extends StatelessWidget {
  final ManagerMessage message;
  final VoidCallback onTap;

  const _MessageTile({required this.message, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUnread = !message.isRead;

    return AppCard(
      onTap: onTap,
      statusStripeColor: isUnread ? AppColors.primary(context) : null,
      backgroundTint: isUnread ? AppColors.primary(context) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  message.senderName,
                  style: AppTextStyles.caption(
                    color: scheme.onSurfaceVariant,
                  ).copyWith(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              RoleBadge(
                role: message.senderRole,
                label: roleLabel(message.senderRole),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  message.title ?? message.content,
                  style: AppTextStyles.bodyMedium(color: scheme.onSurface)
                      .copyWith(
                        fontWeight: isUnread
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isUnread) ...[
                const SizedBox(width: AppSpacing.xs),
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary(context),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
          if (message.title != null) ...[
            const SizedBox(height: 2),
            Text(
              message.content,
              style: AppTextStyles.bodyMedium(color: scheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 4),
          Text(
            formatRelativeTime(message.createdAt),
            style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
