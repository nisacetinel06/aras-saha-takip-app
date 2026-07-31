import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/work_order.dart';
import '../providers/auth_provider.dart';
import '../providers/map_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/user_provider.dart';
import '../providers/work_order_list_provider.dart';
import '../services/local_notification_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_logo.dart';
import '../widgets/user_avatar.dart';
import 'dashboard_screen.dart';
import 'home/home_screen.dart';
import 'map/map_screen.dart';
import 'notifications/notifications_screen.dart';
import 'profile/profile_screen.dart';
import 'work_order_list_screen.dart';

/// Uygulamanın kalıcı kabuğu: Ana Sayfa / İş Emirleri / Harita / Dashboard /
/// Profil arasında alt navigasyon çubuğuyla geçiş sağlar. Ortak app bar
/// (ekran başlığı + dark/light toggle) burada tanımlıdır; sekme içerikleri
/// kendi Scaffold/AppBar'ını taşımaz. Bkz. DESIGN_SYSTEM.md Bölüm B.
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

  static const _titles = ['Ana Sayfa', 'İş Emirleri', 'Harita', 'Dashboard', 'Profil'];

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
      await LocalNotificationService.instance.requestPermission();
      if (mounted) context.read<NotificationProvider>().startPolling();
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
        context.read<MapProvider>().fetchMapData(statusFilter: statusFilter.toJson());
      }
    }
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final auth = context.watch<AuthProvider>();
    final myProfile = context.watch<UserProvider>().myProfile;
    final unreadCount = context.watch<NotificationProvider>().unreadCount;
    final scheme = Theme.of(context).colorScheme;

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
            const AppLogo(height: 22, padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
            const SizedBox(width: 10),
            Flexible(child: Text(_titles[_index], overflow: TextOverflow.ellipsis)),
          ],
        ),
        // Hangi rolle (ve kim olarak) giriş yaptığını her zaman hatırlatan
        // küçük bir alt şerit — kullanıcı "paneli unutuyorum" dediği için
        // eklendi (Modül 7). Tüm sekmelerde ortak olduğu için burada,
        // MainShell'in ortak AppBar'ında duruyor.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${auth.currentUser?.name ?? ''} · ${auth.roleLabel}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        actions: [
          // Bildirim Sistemi (Modül 6) — Ana Sayfa'daki "Bildirimler" modül
          // kartıyla aynı ekrana gider; buradaki rozet okunmamış sayıyı her
          // sekmeden erişilebilir şekilde gösterir (bkz. NotificationProvider).
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: 'Bildirimler',
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                ),
              ),
              if (unreadCount > 0)
                Positioned(
                  top: 6,
                  right: 6,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      decoration: BoxDecoration(
                        color: AppColors.danger(context),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(color: scheme.surface, width: 1.5),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        unreadCount > 9 ? '9+' : '$unreadCount',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: themeProvider.isDark ? 'Aydınlık moda geç' : 'Karanlık moda geç',
            icon: Icon(themeProvider.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: themeProvider.toggle,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(index: _index, children: tabs),
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
                ? UserAvatar(photoPath: myProfile.photoPath, initials: myProfile.initials, role: myProfile.role, radius: 12)
                : const Icon(Icons.person_outline),
            selectedIcon: myProfile != null
                ? UserAvatar(photoPath: myProfile.photoPath, initials: myProfile.initials, role: myProfile.role, radius: 12)
                : const Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}
