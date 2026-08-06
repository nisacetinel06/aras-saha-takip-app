import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/chat_message.dart';
import '../../models/work_order.dart';
import '../../providers/assistant_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_top_bar.dart';
import '../admin/analytics_screen.dart';
import '../admin/user_management_list_screen.dart';
import '../devices/device_list_screen.dart';
import '../equipment/equipment_home_screen.dart';
import '../equipment/qr_scanner_screen.dart';
import '../equipment/suspicious_meters_screen.dart';
import '../isg/isg_report_list_screen.dart';
import '../maintenance/maintenance_recommendations_screen.dart';
import '../materials/material_list_screen.dart';
import '../notifications/notifications_screen.dart';
import '../reports/reports_screen.dart';
import '../work_orders/create_work_order_screen.dart';

/// Asistanın "beni X sayfasına götür" (navigate_to_screen) yanıtlarında
/// dönebileceği ekran anahtarları — bkz. backend services/assistantIntents.js
/// NAV_TARGETS. Anahtarlar İKİ TARAFTA da (backend + Flutter) AYNI olmak
/// zorunda; burada yalnızca "hangi anahtar hangi ekrana karşılık gelir"i
/// çözer, yetki kontrolünü ZATEN backend yapmıştır (asistan yalnızca
/// erişimi olan bir ekran için `action` döner) — bu yüzden burada AYRICA
/// bir rol kontrolü yok.
typedef AssistantTabNavigator =
    void Function(int tabIndex, {WorkOrderStatus? statusFilter});

const _exampleQuestions = [
  'Kaç açık arıza var?',
  'Acil iş emirlerini listele',
  'En riskli ekipmanlar?',
  'Kritik stoktakiler?',
  'Beni iş emirlerine götür',
];

/// AI Asistan / Sohbet Arayüzü (Modül 16). Tüm roller erişebilir — asistan
/// her kullanıcının SADECE kendi RBAC kapsamındaki veriyi döner (bkz.
/// services/assistantQueries.js), bu yüzden ekranın kendisinde ayrıca bir rol
/// kısıtlaması yok.
class AssistantChatScreen extends StatefulWidget {
  /// MainShell'in sekme geçiş callback'i (bkz. main_shell.dart
  /// _navigateToTab) — asistan "beni iş emirlerine/haritaya/panele/profile
  /// götür" derse bu ÇAĞRILIR. `null` bırakılırsa (örn. bu ekran bir
  /// MainShell sekmesi bağlamı olmadan açıldıysa) tab tabanlı hedefler
  /// sessizce yok sayılır — yalnızca sayfa açan (pushed) hedefler çalışır.
  final AssistantTabNavigator? onNavigateToTab;

  const AssistantChatScreen({super.key, this.onNavigateToTab});

  @override
  State<AssistantChatScreen> createState() => _AssistantChatScreenState();
}

class _AssistantChatScreenState extends State<AssistantChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('AssistantChatScreen');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AssistantProvider>().fetchHistory().then(
        (_) => _scrollToBottom(),
      );
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _send([String? presetMessage]) async {
    final text = presetMessage ?? _inputController.text;
    if (text.trim().isEmpty) return;
    _inputController.clear();

    final provider = context.read<AssistantProvider>();
    // Navigator'ı ÖNCE yakala: sendMessage'ın await'i sırasında bu widget
    // pop edilmiş/dispose olmuş olsa bile (kullanıcı geri gidip başka bir
    // ekrana geçtiyse) elimizdeki NavigatorState referansı geçerli kalır.
    final navigator = Navigator.of(context);
    _scrollToBottom();

    final navigation = await provider.sendMessage(text);
    if (!mounted) return;
    _scrollToBottom();

    if (navigation != null) {
      _handleNavigation(navigator, navigation.screen, navigation.status);
    }
  }

  /// Asistanın navigate_to_screen yanıtını gerçek bir ekran geçişine çevirir.
  /// Önce sohbet ekranını kapatır (kullanıcı hedef ekrandan "geri" bastığında
  /// sohbete değil, altındaki asıl ekrana dönsün diye), sonra hedefe göre ya
  /// MainShell sekmesi değiştirir ya da yeni bir ekran push eder.
  void _handleNavigation(
    NavigatorState navigator,
    String screen,
    String? status,
  ) {
    navigator.pop();

    switch (screen) {
      case 'ana_sayfa':
        widget.onNavigateToTab?.call(0);
        return;
      case 'is_emirleri':
        widget.onNavigateToTab?.call(
          1,
          statusFilter: status != null ? WorkOrderStatus.fromJson(status) : null,
        );
        return;
      case 'harita':
        widget.onNavigateToTab?.call(2);
        return;
      case 'dashboard':
        widget.onNavigateToTab?.call(3);
        return;
      case 'profil':
        widget.onNavigateToTab?.call(4);
        return;
      case 'ekipman':
        navigator.push(
          MaterialPageRoute(builder: (_) => const EquipmentHomeScreen()),
        );
        return;
      case 'stok':
        navigator.push(
          MaterialPageRoute(builder: (_) => const MaterialListScreen()),
        );
        return;
      case 'isg':
        navigator.push(
          MaterialPageRoute(builder: (_) => const IsgReportListScreen()),
        );
        return;
      case 'bildirimler':
        navigator.push(
          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
        );
        return;
      case 'qr_tara':
        navigator.push(
          MaterialPageRoute(builder: (_) => const QrScannerScreen()),
        );
        return;
      case 'is_emri_olustur':
        navigator.push(
          MaterialPageRoute(builder: (_) => const CreateWorkOrderScreen()),
        );
        return;
      case 'bakim_planlama':
        navigator.push(
          MaterialPageRoute(
            builder: (_) => const MaintenanceRecommendationsScreen(),
          ),
        );
        return;
      case 'raporlar':
        navigator.push(MaterialPageRoute(builder: (_) => const ReportsScreen()));
        return;
      case 'cihaz_yonetimi':
        navigator.push(
          MaterialPageRoute(builder: (_) => const DeviceListScreen()),
        );
        return;
      case 'kullanici_yonetimi':
        navigator.push(
          MaterialPageRoute(builder: (_) => const UserManagementListScreen()),
        );
        return;
      case 'supheli_sayaclar':
        navigator.push(
          MaterialPageRoute(builder: (_) => const SuspiciousMetersScreen()),
        );
        return;
      case 'kullanim_analitigi':
        navigator.push(
          MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
        );
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AssistantProvider>();
    final scheme = Theme.of(context).colorScheme;

    // Provider her notifyListeners()'da (yeni mesaj/typing/history) burası
    // yeniden çizilir — her seferinde en alta kaydırmak, kullanıcı yeni bir
    // mesaj gördüğü anda otomatik scroll standart sohbet UX'idir.
    _scrollToBottom();

    return Scaffold(
      appBar: const AppTopBar(title: 'AI Asistan'),
      body: Column(
        children: [
          Expanded(child: _buildBody(context, provider)),
          if (provider.isTyping) _TypingIndicator(),
          if (provider.sendErrorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: Text(
                provider.sendErrorMessage!,
                style: AppTextStyles.caption(
                  color: AppColors.danger(context),
                ),
              ),
            ),
          _InputBar(controller: _inputController, onSend: () => _send()),
        ],
      ),
      backgroundColor: scheme.surface,
    );
  }

  Widget _buildBody(BuildContext context, AssistantProvider provider) {
    if (provider.isLoadingHistory && provider.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.historyErrorMessage != null && provider.messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            provider.historyErrorMessage!,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium(
              color: AppColors.textSecondary(context),
            ),
          ),
        ),
      );
    }

    if (provider.messages.isEmpty) {
      return _EmptyState(onExampleTap: _send);
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: provider.messages.length,
      itemBuilder: (context, index) =>
          _MessageBubble(message: provider.messages[index]),
    );
  }
}

/// Boş durum: karşılama mesajı + örnek soru chip'leri — kullanıcı ne
/// sorabileceğini dokunarak keşfeder.
class _EmptyState extends StatelessWidget {
  final void Function(String question) onExampleTap;
  const _EmptyState({required this.onExampleTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.smart_toy_outlined,
              size: 48,
              color: AppColors.primary(context),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'ArasSaha Asistanına Sor',
              style: AppTextStyles.headingMedium(color: scheme.onSurface),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'İş emirleri, ekipman riski, stok ve İSG bildirimleri hakkında doğal dilde soru sorabilirsin.',
              style: AppTextStyles.bodyMedium(
                color: AppColors.textSecondary(context),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              alignment: WrapAlignment.center,
              children: [
                for (final question in _exampleQuestions)
                  ActionChip(
                    label: Text(question),
                    onPressed: () => onExampleTap(question),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Mesaj baloncuğu: kullanıcı sağda (accent), asistan solda (nötr/gri).
class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.isUser;
    final bubbleColor = isUser
        ? AppColors.accent(context)
        : scheme.surfaceContainerLowest;
    final textColor = isUser
        ? accessibleOnColor(AppColors.accent(context))
        : scheme.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(AppRadius.card),
            topRight: const Radius.circular(AppRadius.card),
            bottomLeft: Radius.circular(isUser ? AppRadius.card : 4),
            bottomRight: Radius.circular(isUser ? 4 : AppRadius.card),
          ),
        ),
        child: Text(
          message.message,
          style: AppTextStyles.bodyMedium(color: textColor),
        ),
      ),
    );
  }
}

/// "Yazıyor..." göstergesi — asistan yanıtı beklenirken sol tarafta,
/// [_MessageBubble] ile AYNI nötr baloncuk stiliyle gösterilir.
class _TypingIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(
          left: AppSpacing.md,
          bottom: AppSpacing.sm,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.textSecondary(context),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'yazıyor…',
              style: AppTextStyles.caption(
                color: AppColors.textSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Alt kısımda sabit (sticky), baş parmak erişimine uygun metin giriş alanı +
/// gönder butonu (thumb-zone kuralı — bkz. mobile-design skill).
class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  const _InputBar({required this.controller, required this.onSend});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          children: [
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: InputDecoration(
                    hintText: 'Bir soru sor…',
                    filled: true,
                    fillColor: scheme.surfaceContainerLowest,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm + 2,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // B2 (dokunma alanı): 48x48 minimum dokunma alanı — bkz.
            // widgets/app_button.dart'taki AYNI kural.
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              child: IconButton.filled(
                onPressed: onSend,
                icon: const Icon(Icons.send_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primary(context),
                  foregroundColor: accessibleOnColor(
                    AppColors.primary(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
