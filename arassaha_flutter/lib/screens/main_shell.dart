import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:showcaseview/showcaseview.dart';
import '../models/app_user.dart';
import '../models/work_order.dart';
import '../providers/auth_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/user_provider.dart';
import '../providers/work_order_list_provider.dart';
import '../services/local_notification_service.dart';
import '../services/onboarding_prefs_service.dart';
import '../services/push_notification_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_logo.dart';
import '../widgets/app_navigation_drawer.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/offline_banner.dart';
import '../widgets/onboarding/coach_mark_style.dart';
import '../widgets/onboarding/home_tour_controller.dart';
import '../widgets/user_avatar.dart';
import 'assistant/assistant_chat_screen.dart';
import 'home/home_screen.dart';
import 'messages/manager_messages_screen.dart';
import 'messages/sent_messages_screen.dart';
import 'profile/profile_screen.dart';
import 'work_order_list_screen.dart';

/// Uygulamanın kalıcı kabuğu: Ana Sayfa / İş Emirleri / ArasAI / Profil
/// arasında alt navigasyon çubuğuyla geçiş sağlar. Ortak app bar burada
/// tanımlıdır; sekme içerikleri kendi Scaffold/AppBar'ını taşımaz.
///
/// Ana Sayfa revizyonu (radikal sadeleştirme): alt navigasyon eskiden 5
/// sekmeydi (Ana Sayfa/İş Emirleri/Harita/Dashboard/Profil) — Harita ve
/// Dashboard artık KALICI birer sekme değil, Ana Sayfa'nın "öne çıkanlar"
/// kartlarından ya da hamburger menü panelinden ([AppNavigationDrawer])
/// normal birer sayfa olarak push ediliyor (bkz. home/home_screen.dart,
/// home/module_entries.dart). Panel, yalnızca Ana Sayfa sekmesindeyken
/// `endDrawer` olarak takılıdır ve AppBar'daki menü ikonuyla (yine yalnızca
/// bu sekmede görünür) açılır — eskiden Ana Sayfa'nın en altındaki "Tüm
/// Modüller" butonu + ayrı bir arama ekranıydı (AllModulesScreen), o ekran
/// artık yok; modül listesi tek kaynağı (`buildModuleEntries`) doğrudan
/// paneli besliyor.
///
/// ArasAI (Modül 16) kalıcı bir sekmeye taşındı — eskiden
/// [ArasAiFloatingButton] adlı sürüklenebilir bir yuvarlak buton her sekmede
/// AYRI bir katman olarak duruyordu; artık zaten her an bir dokunuşla
/// erişilebilir bir sekme olduğu için o ikinci giriş noktası KALDIRILDI
/// (widgets/arasai_floating_button.dart silindi) — aynı özelliğe iki farklı
/// erişim yolu tutmak, "radikal sadeleştirme" ilkesiyle çelişirdi.
///
/// Zil ve tema butonları [NotificationBellButton]/[ThemeToggleButton]
/// (bkz. widgets/app_top_bar.dart) üzerinden gelir — [AppTopBar] kullanan
/// diğer TÜM ekranlarla birebir aynı, tek bir kaynaktan yönetilen bileşen.
///
/// Kullanıcı adı/rolü BİLEREK burada gösterilmez — bu üst çubuk her sekmede
/// (Ana Sayfa, Profil dahil) aynı anda görünür kaldığı için, kullanıcı adı/
/// rolünü burada göstermek, HomeScreen'in karşılama bölümündeki veya
/// ProfileScreen'deki [RoleBadge] ile AYNI bilgiyi ekranda İKİ KEZ (örn.
/// "Yönetici" hem üst çubukta hem karşılama kartında) tekrar ettiriyordu.
/// Artık kullanıcı adı/rolü YALNIZCA HomeScreen'in karşılama bölümünde ve
/// ProfileScreen'de, tek bir yerde gösteriliyor.
///
/// "Çıkış Yap" artık burada DEĞİL, Profil sekmesinde (Modül 8) — tek bir
/// yerde tutarlı olsun diye (bkz. profile_screen.dart).
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

/// Sekme sırası SABİTTİR (0 Ana Sayfa, 1 İş Emirleri, 2 ArasAI, 3 Mesajlar,
/// 4 Profil) — diğer ekranlardan sekme geçişi yapan TÜM kod (HomeScreen,
/// AssistantChatScreen, DashboardScreen) AYNI indeksleri varsayar. Mesajlar
/// (Modül — Yöneticiden Çalışana Duyuru Sistemi) Profil'in HEMEN ÖNÜNE
/// eklendi — HomeScreen'deki `onNavigate(3)` çağrıları bu değişiklikle
/// BİRLİKTE `onNavigate(4)`'e taşındı (bkz. home_screen.dart avatar tıklaması).
class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _titles = [
    'Ana Sayfa',
    'İş Emirleri',
    'ArasAI',
    'Mesajlar',
    'Profil',
  ];

  // dispose() içinde context.read(...) çağırmak güvensizdir: tüm widget
  // ağacı TEK SEFERDE (örn. runApp'in yeni bir kökle tekrar çağrılması)
  // sökülürse, bu widget'ın dispose()'u çalıştığı anda üstteki Provider'ın
  // hâlâ "aktif" olduğu garanti değildir ("Looking up a deactivated widget's
  // ancestor is unsafe" hatası). Referans, ağaç kesin olarak stabilken
  // (didChangeDependencies) önceden yakalanır.
  NotificationProvider? _notificationProvider;

  // Ana Sayfa Turu (bkz. sınıf dokümantasyonu — "Ana Sayfa Turu + Bağlamsal
  // İpuçları" tasarım kararı): 5 adımın hedef widget'ları HEM HomeScreen'in
  // gövdesinde (karşılama, Hızlı İşlemler, ArasAI) HEM DE bu kabuğun kendi
  // AppBar/BottomNav'ında (Tüm Modüller = hamburger menü, Profil sekmesi)
  // yaşıyor — bu yüzden 5 anahtarın TAMAMI burada, tek sahipte tanımlanır ve
  // ilk 3'ü HomeScreen'e constructor parametresiyle geçirilir.
  final GlobalKey _welcomeKey = GlobalKey();
  final GlobalKey _quickActionsKey = GlobalKey();
  final GlobalKey _arasAiKey = GlobalKey();
  final GlobalKey _allModulesKey = GlobalKey();
  final GlobalKey _profileTabKey = GlobalKey();

  late final ShowcaseView _showcaseView;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _notificationProvider = context.read<NotificationProvider>();
  }

  @override
  void initState() {
    super.initState();

    // showcaseview 5.x'te artık bir `ShowCaseWidget` sarmalayıcısına gerek
    // yok (o API v6.0.0'da kaldırılacak şekilde deprecated) — tek bir
    // `ShowcaseView.register()` çağrısı yeterli, overlay uygulamanın kök
    // Navigator'ının Overlay'ine otomatik eklenir. MainShell, kullanıcı
    // giriş yapmışken HER ZAMAN ekranda kalan kalıcı kabuk olduğu için
    // (sekmeler arası geçişte yeniden oluşturulmaz) kayıt için doğal yer
    // burası.
    _showcaseView = ShowcaseView.register(
      // Yalnızca görünür "İleri"/"Geç"/"Geri" butonları turu ilerletsin —
      // dimli zeminin (barrier) HERHANGİ bir yerine dokunma varsayılan
      // olarak da bir sonraki adıma geçirir (bkz. showcaseview
      // handleBarrierTap). Bu, kullanıcının kazara/dolaylı bir dokunuşla
      // (örn. ekranın herhangi bir yerine basarak) turu bilmeden
      // ilerletmesini engeller — PROMPT madde 5'teki "kullanıcı bir sonraki
      // adıma BİLEREK, ilgili butona basarak geçmeli" ilkesiyle tutarlı.
      disableBarrierInteraction: true,
      onFinish: _markHomeTourSeen,
      onDismiss: (_) => _markHomeTourSeen(),
    );
    HomeTourController.registerRestartHandler(_restartHomeTour);

    // Profil sekmesindeki avatarın (fotoğraf varsa) alt navigasyon
    // ikonunda da görünebilmesi için uygulama açılışında bir kez çekilir.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      context.read<UserProvider>().fetchMyProfile();

      // Bildirim Sistemi (Modül 6): MainShell yalnızca kimlik doğrulanmış
      // kullanıcının gördüğü kabuk olduğu için polling burada başlatılır —
      // login öncesi (LoginScreen) hiç çalışmaz. Kullanıcı çıkış yaptığında
      // (ya da 401 ile oturumu düşünce) AuthGate bu widget'ı unmount eder,
      // dispose() timer'ı otomatik durdurur — ayrı bir logout hook'una gerek yok.
      //
      // Ayarlar ekranındaki "Bildirimler" tercihi (Modül 17) kapalıysa
      // polling hiç başlatılmaz — kullanıcı Ayarlar'dan tekrar açarsa
      // SettingsScreen doğrudan NotificationProvider.startPolling()'i
      // çağırır (bkz. settings_screen.dart).
      await LocalNotificationService.instance.requestPermission();
      if (!mounted) return;

      // Push Bildirim (FCM) — AYNI çağrı noktası: MainShell yalnızca kimlik
      // doğrulanmış kullanıcının gördüğü kabuk olduğu için, burada çağırmak
      // "login sonrası" ile eşdeğerdir (hem interaktif login hem 2FA
      // doğrulama hem de tryAutoLogin sonrası TEK bir yerden kapsanır).
      // Bildirimler tercihi kapalı olsa bile FCM token'ı kaydedilir — bu
      // tercih yalnızca polling+yerel bildirimi kapatır, SOS gibi kritik
      // bildirimler için push HER ZAMAN etkin kalmalı.
      await PushNotificationService.instance.initialize();
      if (!mounted) return;

      final notificationsEnabled = context
          .read<SettingsProvider>()
          .notificationsEnabled;
      if (notificationsEnabled) {
        context.read<NotificationProvider>().startPolling();
      }

      // Bildirim izni istemi (varsa) kapandıktan SONRA turu başlat — aksi
      // halde OS izin dialog'u ile coach-mark overlay'i aynı anda ekranda
      // çakışabilir.
      _maybeStartHomeTour();
    });
  }

  @override
  void dispose() {
    HomeTourController.unregisterRestartHandler(_restartHomeTour);
    _showcaseView.unregister();
    _notificationProvider?.stopPolling();
    super.dispose();
  }

  Future<void> _maybeStartHomeTour() async {
    // Entegrasyon testi (bkz. integration_test/critical_flow_test.dart)
    // gerçek widget etkileşimiyle çalışır ve girişten HEMEN sonra "İş
    // Emirleri" sekmesine dokunur — turun tam ekranı kaplayan overlay'i bu
    // dokunuşu yutup testi kırardı. `IntegrationTestWidgetsFlutterBinding`
    // yalnızca entegrasyon testi altında kullanıldığı için, gerçek kullanıcı
    // deneyimini hiç ETKİLEMEDEN tur bu ortamda atlanır — `integration_test`
    // paketini burada import ETMEMEK için (o bir dev_dependency, uygulama
    // koduna sızdırılmamalı) runtime tipi string olarak karşılaştırılır.
    final bindingName = WidgetsBinding.instance.runtimeType.toString();
    if (bindingName == 'IntegrationTestWidgetsFlutterBinding') return;

    final hasSeen = await OnboardingPrefsService.hasSeenHomeTour();
    if (hasSeen || !mounted) return;
    _startHomeTour();
  }

  void _startHomeTour() {
    _showcaseView.startShowCase([
      _welcomeKey,
      _quickActionsKey,
      _arasAiKey,
      _allModulesKey,
      _profileTabKey,
    ]);
  }

  Future<void> _markHomeTourSeen() =>
      OnboardingPrefsService.setHasSeenHomeTour(true);

  /// Ayarlar ekranındaki (Modül 17) "Turu Tekrar Göster" butonundan
  /// [HomeTourController] aracılığıyla çağrılır: Ana Sayfa sekmesine döner
  /// ve turu baştan başlatır — ilk seferinde yanlışlıkla "Geç"e basan ya da
  /// turu tekrar hatırlamak isteyen kullanıcılar için bir kaçış kapısı.
  void _restartHomeTour() {
    setState(() => _index = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startHomeTour());
  }

  /// Hub'daki (Ana Sayfa) "öne çıkanlar" kartlarından ya da ArasAI'nin
  /// navigate_to_screen yanıtından çağrılır: ilgili sekmeye, isteğe bağlı bir
  /// statü filtresi önceden uygulanmış şekilde geçer. Sekmeler IndexedStack
  /// ile canlı tutulduğu için filtre, ilgili provider'a doğrudan burada
  /// uygulanır. Harita artık bir sekme OLMADIĞI için (bkz. sınıf
  /// dokümantasyonu) burada yalnızca İş Emirleri (index 1) filtresi kalır —
  /// Harita'ya statü filtresiyle gitmek isteyen çağıranlar (DashboardScreen,
  /// AssistantChatScreen) `MapProvider.fetchMapData` çağırdıktan sonra
  /// doğrudan `MapScreen`'i push eder.
  void _navigateToTab(int index, {WorkOrderStatus? statusFilter}) {
    if (statusFilter != null && index == 1) {
      context.read<WorkOrderListProvider>().setFilter(statusFilter);
    }
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final myProfile = context.watch<UserProvider>().myProfile;
    return _buildScaffold(context, myProfile);
  }

  Widget _buildScaffold(BuildContext context, AppUser? myProfile) {
    // Mesajlar sekmesi (Yöneticiden Çalışana Duyuru Sistemi) — rol bazlı
    // yönlendirme: teknisyen/dispeçer KENDİ aldığı mesajları (salt okunur,
    // bkz. ManagerMessagesScreen), yönetici KENDİ gönderdiklerini + "Yeni
    // Mesaj Gönder" FAB'ını (bkz. SentMessagesScreen) görür. `embedded: true`
    // her ikisinin de kendi AppTopBar'ını ÇİZMEMESİNİ sağlar — bu sekmenin
    // başlığı zaten aşağıdaki ortak AppBar'dan ("Mesajlar", bkz. _titles) gelir.
    final isYonetici = context.watch<AuthProvider>().isYonetici;
    final messagesTab = isYonetici
        ? const SentMessagesScreen(embedded: true)
        : const ManagerMessagesScreen(embedded: true);
    // Sekme ikonundaki kırmızı nokta (bkz. NavigationBar destinations aşağısı)
    // — NotificationProvider'ın AYNI 30 sn'lik polling'ine eklendi (bkz.
    // notification_provider.dart), ayrı bir istek/timer AÇILMADI. Yönetici
    // hiçbir mesajın alıcısı olamayacağı için bu sayı onda her zaman 0'dır.
    final unreadMessageCount = context
        .watch<NotificationProvider>()
        .unreadMessageCount;

    final tabs = <Widget>[
      HomeScreen(
        onNavigate: _navigateToTab,
        onboardingWelcomeKey: _welcomeKey,
        onboardingQuickActionsKey: _quickActionsKey,
        onboardingArasAiKey: _arasAiKey,
      ),
      const WorkOrderListScreen(),
      AssistantChatScreen(onNavigateToTab: _navigateToTab),
      messagesTab,
      const ProfileScreen(),
    ];
    // UI denetimi bulgusu: Ana Sayfa artık kendi karşılama bölümünde büyük,
    // belirgin bir SAHA logosu gösteriyor (bkz. home_screen.dart) — üst bar
    // AYRICA aynı logoyu gösterirse aynı ekranda iki kez tekrar eder. Bu
    // yüzden logo yalnızca Ana Sayfa OLMAYAN sekmelerde (İş Emirleri, ArasAI,
    // Profil) üst barda görünür. ArasAI sekmesinde ayrıca küçük bir ikinci
    // görsel (ArasAiLogo rozeti) YOK — yalnızca SAHA logosu + "ArasAI" metni
    // (bkz. UI denetimi C.1); ArasAiLogo yalnızca sohbet baloncuklarında kalır.
    final isHomeTab = _index == 0;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isHomeTab) ...[
              const AppLogo(
                height: 22,
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              const SizedBox(width: 10),
            ],
            Flexible(
              child: Text(_titles[_index], overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          // Hamburger menü (Modül erişimi — eskiden Ana Sayfa'nın en
          // altındaki "Tüm Modüller" butonuydu, bkz. module_entries.dart):
          // yalnızca Ana Sayfa sekmesinde görünür, çünkü [AppNavigationDrawer]
          // yalnızca isHomeTab true iken Scaffold'a `endDrawer` olarak takılı
          // (aşağıda). `Builder`, bu IconButton'ın kendi context'inin, henüz
          // inşa edilmekte olan bu Scaffold'un bir alt öğesi olmasını sağlar —
          // Scaffold.of(context) bu sayede DOĞRU (henüz oluşturulmakta olan)
          // Scaffold'u bulur.
          if (isHomeTab)
            Builder(
              builder: (context) => Showcase(
                key: _allModulesKey,
                // Yalnızca aksiyon butonları ilerletsin — bkz. üstteki
                // disableBarrierInteraction notu, AYNI gerekçe hedefin
                // kendisine dokunma için de geçerli.
                disableDefaultTargetGestures: true,
                title: 'Tüm Modüller',
                description:
                    'Ekipman sorgulama, İSG bildirimi ve diğer tüm '
                    'özelliklere buradan ulaşabilirsiniz.',
                tooltipBackgroundColor: CoachMarkStyle.background(context),
                textColor: CoachMarkStyle.foreground(context),
                tooltipBorderRadius: CoachMarkStyle.borderRadius,
                titleTextStyle: CoachMarkStyle.title(context),
                descTextStyle: CoachMarkStyle.description(context),
                tooltipActionConfig: CoachMarkStyle.actionConfig,
                tooltipActions: CoachMarkStyle.homeTourActions(
                  context,
                  isFirstStep: false,
                ),
                child: IconButton(
                  tooltip: 'Menü',
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                ),
              ),
            ),
          const NotificationBellButton(),
          const ThemeToggleButton(),
          const SizedBox(width: 4),
        ],
      ),
      endDrawer: isHomeTab
          ? AppNavigationDrawer(onNavigate: _navigateToTab)
          : null,
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: IndexedStack(index: _index, children: tabs),
          ),
        ],
      ),
      // Tasarım cilası: alt navigasyon çubuğu artık düz opak bir dolgu
      // yerine buzlu-cam (frosted glass) efektiyle çiziliyor — referans
      // alınan bir web navbar örneğindeki `backdrop-blur` + yarı saydam
      // zemin + üst kenarlık fikrinin Flutter karşılığı (bkz. kullanıcının
      // 21st.dev navbar isteği). `NavigationBar`'ın kendi arka planı/gölgesi
      // KAPATILIR (`backgroundColor: transparent`, `elevation: 0`) — aksi
      // halde bulanıklaştırma ARKASINDAKİ içerik değil, bu widget'ın KENDİ
      // opak zemini görünürdü.
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainer.withValues(alpha: 0.82),
              border: Border(
                top: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
            ),
            child: NavigationBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Ana Sayfa',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.assignment_outlined),
                  selectedIcon: Icon(Icons.assignment),
                  label: 'İş Emirleri',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.smart_toy_outlined),
                  selectedIcon: Icon(Icons.smart_toy),
                  label: 'ArasAI',
                ),
                NavigationDestination(
                  // Sayısal bir rozet yerine BİLİNÇLİ olarak küçük bir nokta —
                  // bu sekme "kaç mesaj var"ı değil, "okunmamış bir şey var mı"yı
                  // göstermek için yeterli (bkz. görev talimatı örnek kod).
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.chat_bubble_outline_rounded),
                      if (unreadMessageCount > 0)
                        Positioned(
                          top: -3,
                          right: -6,
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: AppColors.danger(context),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  selectedIcon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.chat_bubble_rounded),
                      if (unreadMessageCount > 0)
                        Positioned(
                          top: -3,
                          right: -6,
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: AppColors.danger(context),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  label: 'Mesajlar',
                ),
                NavigationDestination(
                  // Turun son adımı: unselected `icon` sarmalanır (bkz. Showcase'e
                  // BİLEREK yalnızca `icon`, `selectedIcon` DEĞİL — tur Ana
                  // Sayfa'dayken başlar, Profil sekmesi henüz SEÇİLİ değildir,
                  // dolayısıyla ekranda görünen budur; ikisini de sarmalamak aynı
                  // GlobalKey'in aynı anda iki yerde mount olmasına yol açardı).
                  icon: Builder(
                    builder: (context) => Showcase(
                      key: _profileTabKey,
                      disableDefaultTargetGestures: true,
                      title: 'Profil',
                      description:
                          'Buradan profilinizi görüntüleyebilir ve '
                          'ayarlarınızı yönetebilirsiniz.',
                      tooltipBackgroundColor: CoachMarkStyle.background(
                        context,
                      ),
                      textColor: CoachMarkStyle.foreground(context),
                      tooltipBorderRadius: CoachMarkStyle.borderRadius,
                      titleTextStyle: CoachMarkStyle.title(context),
                      descTextStyle: CoachMarkStyle.description(context),
                      tooltipActionConfig: CoachMarkStyle.actionConfig,
                      tooltipPosition: TooltipPosition.top,
                      tooltipActions: CoachMarkStyle.homeTourFinalStepActions(
                        context,
                      ),
                      child: myProfile != null
                          ? UserAvatar(
                              photoPath: myProfile.photoPath,
                              initials: myProfile.initials,
                              role: myProfile.role,
                              radius: 12,
                            )
                          : const Icon(Icons.person_outline),
                    ),
                  ),
                  selectedIcon: myProfile != null
                      ? UserAvatar(
                          photoPath: myProfile.photoPath,
                          initials: myProfile.initials,
                          role: myProfile.role,
                          radius: 12,
                        )
                      : const Icon(Icons.person),
                  label: 'Profil',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
