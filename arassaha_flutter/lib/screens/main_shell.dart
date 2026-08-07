import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_user.dart';
import '../models/work_order.dart';
import '../providers/notification_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/user_provider.dart';
import '../providers/work_order_list_provider.dart';
import '../services/local_notification_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/offline_banner.dart';
import '../widgets/user_avatar.dart';
import 'assistant/assistant_chat_screen.dart';
import 'home/home_screen.dart';
import 'profile/profile_screen.dart';
import 'work_order_list_screen.dart';

/// Uygulamanın kalıcı kabuğu: Ana Sayfa / İş Emirleri / ArasAI / Profil
/// arasında alt navigasyon çubuğuyla geçiş sağlar. Ortak app bar burada
/// tanımlıdır; sekme içerikleri kendi Scaffold/AppBar'ını taşımaz.
///
/// Ana Sayfa revizyonu (radikal sadeleştirme): alt navigasyon eskiden 5
/// sekmeydi (Ana Sayfa/İş Emirleri/Harita/Dashboard/Profil) — Harita ve
/// Dashboard artık KALICI birer sekme değil, Ana Sayfa'nın "öne çıkanlar"
/// kartlarından ya da "Tüm Modüller" ekranından normal birer sayfa olarak
/// push ediliyor (bkz. home/home_screen.dart, home/all_modules_screen.dart).
/// Bunun yerine ArasAI (Modül 16) kalıcı bir sekmeye taşındı — eskiden
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

/// Sekme sırası SABİTTİR (0 Ana Sayfa, 1 İş Emirleri, 2 ArasAI, 3 Profil) —
/// diğer ekranlardan sekme geçişi yapan TÜM kod (HomeScreen,
/// AssistantChatScreen, DashboardScreen) AYNI indeksleri varsayar.
class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _titles = ['Ana Sayfa', 'İş Emirleri', 'ArasAI', 'Profil'];

  @override
  void initState() {
    super.initState();
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
      final notificationsEnabled = context
          .read<SettingsProvider>()
          .notificationsEnabled;
      if (notificationsEnabled) {
        context.read<NotificationProvider>().startPolling();
      }
    });
  }

  @override
  void dispose() {
    context.read<NotificationProvider>().stopPolling();
    super.dispose();
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
    final tabs = <Widget>[
      HomeScreen(onNavigate: _navigateToTab),
      const WorkOrderListScreen(),
      AssistantChatScreen(onNavigateToTab: _navigateToTab),
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
        actions: const [
          NotificationBellButton(),
          ThemeToggleButton(),
          SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: IndexedStack(index: _index, children: tabs),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
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
            icon: myProfile != null
                ? UserAvatar(
                    photoPath: myProfile.photoPath,
                    initials: myProfile.initials,
                    role: myProfile.role,
                    radius: 12,
                  )
                : const Icon(Icons.person_outline),
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
    );
  }
}
