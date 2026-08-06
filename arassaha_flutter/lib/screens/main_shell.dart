import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_user.dart';
import '../models/work_order.dart';
import '../providers/map_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/user_provider.dart';
import '../providers/work_order_list_provider.dart';
import '../services/local_notification_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/arasai_floating_button.dart';
import '../widgets/offline_banner.dart';
import '../widgets/user_avatar.dart';
import 'dashboard_screen.dart';
import 'home/home_screen.dart';
import 'map/map_screen.dart';
import 'profile/profile_screen.dart';
import 'work_order_list_screen.dart';

/// Uygulamanın kalıcı kabuğu: Ana Sayfa / İş Emirleri / Harita / Dashboard /
/// Profil arasında alt navigasyon çubuğuyla geçiş sağlar. Ortak app bar
/// burada tanımlıdır; sekme içerikleri kendi Scaffold/AppBar'ını taşımaz.
/// Bkz. DESIGN_SYSTEM.md Bölüm B.
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

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _titles = [
    'Ana Sayfa',
    'İş Emirleri',
    'Harita',
    'Dashboard',
    'Profil',
  ];

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

  /// Hub'daki modül kartlarından ya da Dashboard'daki özet kartlardan
  /// çağrılır: ilgili sekmeye, isteğe bağlı bir statü filtresi önceden
  /// uygulanmış şekilde geçer. Sekmeler IndexedStack ile canlı tutulduğu için
  /// filtre, ilgili provider'a doğrudan burada uygulanır.
  void _navigateToTab(int index, {WorkOrderStatus? statusFilter}) {
    if (statusFilter != null) {
      if (index == 1) {
        context.read<WorkOrderListProvider>().setFilter(statusFilter);
      } else if (index == 2) {
        context.read<MapProvider>().fetchMapData(
          statusFilter: statusFilter.toJson(),
        );
      }
    }
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final myProfile = context.watch<UserProvider>().myProfile;

    return Stack(
      children: [
        _buildScaffold(context, myProfile),
        // ArasAI (Modül 16) — her sekmede erişilebilir, sürüklenebilir
        // yuvarlak asistan başlatıcısı. Scaffold'ın ÜSTÜNDE, ayrı bir
        // katmanda durur; hiçbir sekmenin kendi layout'unu etkilemez.
        ArasAiFloatingButton(onNavigateToTab: _navigateToTab),
      ],
    );
  }

  Widget _buildScaffold(BuildContext context, AppUser? myProfile) {
    final tabs = <Widget>[
      HomeScreen(onNavigate: _navigateToTab),
      const WorkOrderListScreen(),
      const MapScreen(),
      DashboardScreen(onNavigate: _navigateToTab),
      const ProfileScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLogo(
              height: 22,
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            const SizedBox(width: 10),
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
          Expanded(child: IndexedStack(index: _index, children: tabs)),
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
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Harita',
          ),
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
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
