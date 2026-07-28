import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/work_order.dart';
import '../providers/map_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/work_order_list_provider.dart';
import '../widgets/app_logo.dart';
import 'dashboard_screen.dart';
import 'home/home_screen.dart';
import 'map/map_screen.dart';
import 'work_order_list_screen.dart';

/// Uygulamanın kalıcı kabuğu: Ana Sayfa / İş Emirleri / Harita / Dashboard
/// arasında alt navigasyon çubuğuyla geçiş sağlar. Ortak app bar (ekran
/// başlığı + dark/light toggle) burada tanımlıdır; sekme içerikleri kendi
/// Scaffold/AppBar'ını taşımaz. Bkz. DESIGN_SYSTEM.md Bölüm B.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _titles = ['Ana Sayfa', 'İş Emirleri', 'Harita', 'Dashboard'];

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

    final tabs = <Widget>[
      HomeScreen(onNavigate: _navigateToTab),
      const WorkOrderListScreen(),
      const MapScreen(),
      DashboardScreen(onNavigate: _navigateToTab),
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
        actions: [
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
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Ana Sayfa',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment),
            label: 'İş Emirleri',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Harita',
          ),
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
        ],
      ),
    );
  }
}
