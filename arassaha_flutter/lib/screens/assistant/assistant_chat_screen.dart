import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/chat_message.dart';
import '../../models/work_order.dart';
import '../../providers/assistant_provider.dart';
import '../../providers/map_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/empty_state.dart';
import '../admin/analytics_screen.dart';
import '../admin/user_management_list_screen.dart';
import '../dashboard_screen.dart';
import '../devices/device_list_screen.dart';
import '../equipment/equipment_home_screen.dart';
import '../equipment/qr_scanner_screen.dart';
import '../equipment/suspicious_meters_screen.dart';
import '../isg/isg_report_list_screen.dart';
import '../maintenance/maintenance_recommendations_screen.dart';
import '../map/map_screen.dart';
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
///
/// Marka/Ana Sayfa revizyonu: MainShell alt navigasyonu artık 4 sekme
/// (0 Ana Sayfa, 1 İş Emirleri, 2 ArasAI, 3 Profil) — Harita/Dashboard
/// sekmeden çıkarıldığı için `tabIndex` bu ikisini KAPSAMAZ, ilgili
/// hedeflerde ayrıca sayfa push edilir (bkz. _handleNavigation).
typedef AssistantTabNavigator =
    void Function(int tabIndex, {WorkOrderStatus? statusFilter});

const _exampleQuestions = [
  'Kaç açık arıza var?',
  'Acil iş emirlerini listele',
  'En riskli ekipmanlar?',
  'Kritik stoktakiler?',
  'Beni iş emirlerine götür',
];

/// ArasAI / Sohbet Arayüzü (Modül 16). Tüm roller erişebilir — asistan her
/// kullanıcının SADECE kendi RBAC kapsamındaki veriyi döner (bkz.
/// services/assistantQueries.js), bu yüzden ekranın kendisinde ayrıca bir rol
/// kısıtlaması yok.
///
/// Ana Sayfa revizyonu: bu ekran artık MainShell'in KALICI bir sekmesi
/// (index 2) — eskiden olduğu gibi ayrı bir sayfa olarak push EDİLMEZ, bu
/// yüzden kendi Scaffold/AppBar'ı yoktur (diğer sekmelerle — WorkOrderListScreen
/// vb. — AYNI desen); başlık ve ArasAI rozeti MainShell'in ortak app bar'ından
/// gelir (bkz. main_shell.dart).
class AssistantChatScreen extends StatefulWidget {
  /// MainShell'in sekme geçiş callback'i (bkz. main_shell.dart
  /// _navigateToTab) — asistan "beni iş emirlerine/profile götür" derse bu
  /// ÇAĞRILIR. Harita/Dashboard artık sekme olmadığı için o hedeflerde
  /// doğrudan sayfa push edilir (bkz. _handleNavigation).
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
    // Navigator'ı VE ScaffoldMessenger'ı ÖNCE yakala: sendMessage'ın await'i
    // sırasında bu widget pop edilmiş/dispose olmuş olsa bile (kullanıcı
    // geri gidip başka bir ekrana geçtiyse) elimizdeki referanslar geçerli
    // kalır.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    _scrollToBottom();

    final navigation = await provider.sendMessage(text);
    if (!mounted) return;
    _scrollToBottom();

    // Sohbet İÇİ kalıcı işaret (bkz. _MessageBubble — kırmızı "Gönderilemedi,
    // tekrar dene") TEK BAŞINA yeterli değil: kullanıcı o an ekranın alt
    // kısmına bakmıyor olabilir. SnackBar, ANLIK bir bildirimle hatayı
    // KESİNLİKLE fark etmesini garanti eder — ikisi BİRLİKTE PROMPT madde
    // 2'deki "iki katmanlı" garanti.
    if (provider.sendErrorMessage != null) {
      _showSendErrorSnackBar(messenger, provider.sendErrorMessage!);
    }

    if (navigation != null) {
      _handleNavigation(navigator, navigation.screen, navigation.status);
    }
  }

  /// Bir baloncuğun altındaki "Gönderilemedi, tekrar dene" işaretine
  /// dokununca çağrılır — [AssistantProvider.retryMessage] SADECE o tek
  /// mesajı, sohbetin tamamını yeniden yüklemeden tekrar gönderir.
  void _retry(int messageId) async {
    final provider = context.read<AssistantProvider>();
    final messenger = ScaffoldMessenger.of(context);

    await provider.retryMessage(messageId);
    if (!mounted) return;
    _scrollToBottom();

    if (provider.sendErrorMessage != null) {
      _showSendErrorSnackBar(messenger, provider.sendErrorMessage!);
    }
  }

  void _showSendErrorSnackBar(
    ScaffoldMessengerState messenger,
    String message,
  ) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Asistanın navigate_to_screen yanıtını gerçek bir ekran geçişine çevirir.
  /// Bu ekran artık MainShell'in KALICI bir sekmesi olduğu için (pushed bir
  /// sayfa DEĞİL), önceden burada olan "önce sohbeti kapat" (navigator.pop())
  /// adımı KALDIRILDI — kapatılacak bir pushed route yok, kapatmaya çalışmak
  /// yanlışlıkla MainShell'in kendisini kapatırdı. Sekme hedefleri doğrudan
  /// `onNavigateToTab` ile değiştirilir; Harita/Dashboard artık sekme olmadığı
  /// için o iki hedef normal bir sayfa push'u ile açılır.
  void _handleNavigation(
    NavigatorState navigator,
    String screen,
    String? status,
  ) {
    switch (screen) {
      case 'ana_sayfa':
        widget.onNavigateToTab?.call(0);
        return;
      case 'is_emirleri':
        widget.onNavigateToTab?.call(
          1,
          statusFilter: status != null
              ? WorkOrderStatus.fromJson(status)
              : null,
        );
        return;
      case 'harita':
        if (status != null) {
          navigator.context.read<MapProvider>().fetchMapData(
            statusFilter: status,
          );
        }
        navigator.push(MaterialPageRoute(builder: (_) => const MapScreen()));
        return;
      case 'dashboard':
        final onNavigateToTab = widget.onNavigateToTab;
        if (onNavigateToTab == null) return;
        navigator.push(
          MaterialPageRoute(
            builder: (_) => DashboardScreen(onNavigate: onNavigateToTab),
          ),
        );
        return;
      case 'profil':
        widget.onNavigateToTab?.call(3);
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
        navigator.push(
          MaterialPageRoute(builder: (_) => const ReportsScreen()),
        );
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

    // Provider her notifyListeners()'da (yeni mesaj/typing/history) burası
    // yeniden çizilir — her seferinde en alta kaydırmak, kullanıcı yeni bir
    // mesaj gördüğü anda otomatik scroll standart sohbet UX'idir.
    _scrollToBottom();

    // Artık kendi Scaffold/AppBar'ı YOK (bkz. sınıf dokümantasyonu) —
    // WorkOrderListScreen/MapScreen ile AYNI desen: MainShell'in ortak
    // Scaffold'ının body'sine doğrudan bir Column döner.
    // Gönderme hatası artık İKİ yerde gösteriliyor — baloncuğun kendisinde
    // (kalıcı, bkz. _MessageBubble) ve bir SnackBar'da (anlık, bkz. _send/
    // _retry) — burada AYRICA üçüncü, ad-hoc bir metin şeridi YOK; aynı
    // sinyali üçüncü kez tekrarlamak gürültü olurdu ve İş Emri Listesi/
    // Ekipman Listesi'nde de böyle kalıcı bir "son hata" şeridi yok.
    return Column(
      children: [
        Expanded(child: _buildBody(context, provider)),
        if (provider.isTyping) _TypingIndicator(),
        _InputBar(controller: _inputController, onSend: () => _send()),
      ],
    );
  }

  Widget _buildBody(BuildContext context, AssistantProvider provider) {
    if (provider.isLoadingHistory && provider.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // İş Emri Listesi/Ekipman Listesi ile AYNI bileşen ve "Tekrar Dene"
    // davranışı (bkz. PROMPT madde 1) — kullanıcı hangi ekranda olursa
    // olsun aynı görsel dili görsün. `historyErrorMessage` zaten
    // AssistantProvider.fetchHistory()'de mapExceptionToUserMessage(e) ile
    // üretildi (bkz. providers/assistant_provider.dart) — burada AYRICA
    // çevrilmez, olduğu gibi subtitle'a geçirilir.
    if (provider.historyErrorMessage != null && provider.messages.isEmpty) {
      return EmptyState(
        icon: Icons.chat_bubble_outline,
        title: 'Sohbet geçmişi yüklenemedi',
        subtitle: provider.historyErrorMessage!,
        onPrimaryAction: () => provider.fetchHistory(),
        primaryActionLabel: 'Tekrar Dene',
      );
    }

    if (provider.messages.isEmpty) {
      return _EmptyState(onExampleTap: _send);
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: provider.messages.length,
      itemBuilder: (context, index) {
        final message = provider.messages[index];
        return _MessageBubble(
          message: message,
          onRetry: () => _retry(message.id),
        );
      },
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
            const ArasAiLogo(size: 56),
            const SizedBox(height: AppSpacing.md),
            Text(
              "ArasAI'ya Sor",
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

/// Mesaj baloncuğu: kullanıcı sağda (birincil mavi), asistan solda
/// (nötr/gri) + küçük bir ArasAI rozeti ile.
///
/// [ChatMessageStatus] yalnızca KULLANICI baloncukları için anlamlıdır
/// (asistan mesajları `fromJson`'dan zaten `gonderildi` ile gelir, bkz.
/// models/chat_message.dart) — `gonderiliyor` sırasında balonun altında
/// küçük bir "Gönderiliyor…" spinner'ı, `basarisiz` durumunda ise kırmızı
/// bir uyarı + dokunulabilir "Gönderilemedi, tekrar dene" satırı gösterir
/// (bkz. PROMPT madde 2 — sohbet uygulamalarındaki standart desen).
class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback onRetry;
  const _MessageBubble({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.isUser;
    // Marka revizyonu: kullanıcı baloncuğu artık "accent" (turuncu) değil,
    // birincil marka rengi (mavi) — genel arayüzde tek bir aksiyon/vurgu
    // rengi kuralı sohbet baloncukları için de geçerli.
    final bubbleColor = isUser
        ? AppColors.primary(context)
        : scheme.surfaceContainerLowest;
    final textColor = isUser
        ? accessibleOnColor(AppColors.primary(context))
        : scheme.onSurface;

    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * (isUser ? 0.78 : 0.68),
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
    );

    if (isUser) {
      if (message.status == ChatMessageStatus.gonderildi) {
        return Align(alignment: Alignment.centerRight, child: bubble);
      }
      return Align(
        alignment: Alignment.centerRight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            bubble,
            Padding(
              padding: const EdgeInsets.only(
                right: AppSpacing.xs,
                bottom: AppSpacing.xs,
              ),
              child: message.status == ChatMessageStatus.gonderiliyor
                  ? const _SendingIndicator()
                  : _SendFailedIndicator(onRetry: onRetry),
            ),
          ],
        ),
      );
    }

    // Asistan mesajlarının yanında küçük bir ArasAI rozeti — kullanıcı
    // baloncuğunda avatar YOK (zaten sağda, "ben" olduğu bariz).
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          const ArasAiLogo(size: 24),
          const SizedBox(width: AppSpacing.xs),
          Flexible(child: bubble),
        ],
      ),
    );
  }
}

/// `gonderiliyor` durumundaki bir kullanıcı baloncuğunun altında — kısa
/// süreliğine görünür, dokunulamaz (yalnızca bilgilendirici).
class _SendingIndicator extends StatelessWidget {
  const _SendingIndicator();

  @override
  Widget build(BuildContext context) {
    final color = AppColors.textSecondary(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
        ),
        const SizedBox(width: 4),
        Text('Gönderiliyor…', style: AppTextStyles.caption(color: color)),
      ],
    );
  }
}

/// `basarisiz` durumundaki bir kullanıcı baloncuğunun altında — kırmızı
/// uyarı ikonu + dokunulabilir "Gönderilemedi, tekrar dene" metni.
/// Dokununca YALNIZCA bu tek mesajı yeniden gönderir (bkz.
/// AssistantProvider.retryMessage) — sohbetin tamamı yeniden yüklenmez.
class _SendFailedIndicator extends StatelessWidget {
  final VoidCallback onRetry;
  const _SendFailedIndicator({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.danger(context);
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.chip),
      onTap: onRetry,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              'Gönderilemedi, tekrar dene',
              style: AppTextStyles.caption(
                color: color,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
          ],
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
