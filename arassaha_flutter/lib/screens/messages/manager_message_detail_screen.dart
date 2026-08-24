import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/manager_message.dart';
import '../../providers/manager_message_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/role_helper.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/role_badge.dart';
import '../../widgets/work_order_card.dart' show formatRelativeTime;

/// Yöneticiden Çalışana Duyuru/Mesaj Sistemi — çalışan görünümü, TAM İÇERİK.
///
/// SALT OKUNUR: bu ekranda hiçbir yerde bir "cevap yaz" alanı/gönder butonu
/// YOK — bu modülün kavramsal modeli TEK YÖNLÜ (yönetici -> çalışan). Açıldığı
/// anda mesaj otomatik okundu işaretlenir (bkz. initState) — kullanıcının
/// ayrıca "okundu yap" gibi bir aksiyon alması gerekmez, tıpkı bir SMS'i
/// açmak gibi.
class ManagerMessageDetailScreen extends StatefulWidget {
  final ManagerMessage message;

  const ManagerMessageDetailScreen({super.key, required this.message});

  @override
  State<ManagerMessageDetailScreen> createState() =>
      _ManagerMessageDetailScreenState();
}

class _ManagerMessageDetailScreenState
    extends State<ManagerMessageDetailScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('ManagerMessageDetailScreen');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ManagerMessageProvider>().markAsRead(widget.message.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final message = widget.message;

    return Scaffold(
      appBar: AppTopBar(title: message.title ?? 'Mesaj'),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          message.senderName,
                          style: AppTextStyles.bodyMedium(
                            color: scheme.onSurface,
                          ).copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      RoleBadge(
                        role: message.senderRole,
                        label: roleLabel(message.senderRole),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatRelativeTime(message.createdAt),
                    style: AppTextStyles.caption(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Divider(height: AppSpacing.lg + AppSpacing.sm),
                  if (message.title != null) ...[
                    Text(
                      message.title!,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  Text(
                    message.content,
                    style: AppTextStyles.bodyMedium(color: scheme.onSurface),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
