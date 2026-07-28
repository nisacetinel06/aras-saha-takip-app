import 'package:flutter/material.dart';
import '../models/work_order.dart';
import 'map/map_screen.dart';
import 'placeholder_screen.dart';
import 'work_order_list_screen.dart';

/// Görevler / Harita / Duyurular / Ayarlar arasında alt navigasyon çubuğuyla
/// geçiş sağlayan ortak kabuk. Ortak app bar + bottom nav burada tanımlıdır;
/// sekme içerikleri kendi Scaffold/AppBar'ını taşımaz.
class MainShell extends StatefulWidget {
  /// Dashboard'dan belirli bir statü filtresiyle Görevler sekmesine açılmak
  /// istendiğinde verilir.
  final WorkOrderStatus? initialStatusFilter;

  /// Dashboard'dan doğrudan Harita sekmesine, belirli bir statü filtresi
  /// önceden uygulanmış şekilde açılmak istendiğinde verilir (örn. "Açık
  /// Arızalar" kartındaki harita ikonu -> Harita sekmesi + 'acik' filtresi).
  final WorkOrderStatus? initialMapStatusFilter;

  const MainShell({super.key, this.initialStatusFilter, this.initialMapStatusFilter});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _index = widget.initialMapStatusFilter != null ? 1 : 0;

  static const _titles = ['ArasSaha', 'Harita', 'Duyurular', 'Ayarlar'];

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      WorkOrderListScreen(initialStatusFilter: widget.initialStatusFilter),
      MapScreen(initialStatusFilter: widget.initialMapStatusFilter),
      const PlaceholderScreen(
        icon: Icons.notifications_outlined,
        message: 'Bildirimler modülü yakında eklenecek.',
      ),
      const PlaceholderScreen(
        icon: Icons.settings_outlined,
        message: 'Ayarlar modülü yakında eklenecek.',
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Text(_titles[_index]),
      ),
      drawer: _ShellDrawer(onDashboardTap: () => Navigator.of(context).pop()),
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment),
            label: 'Görevler',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Harita',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: 'Duyurular',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Ayarlar',
          ),
        ],
      ),
    );
  }
}

class _ShellDrawer extends StatelessWidget {
  final VoidCallback onDashboardTap;
  const _ShellDrawer({required this.onDashboardTap});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text('ArasSaha', style: Theme.of(context).textTheme.headlineMedium),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.dashboard_outlined),
              title: const Text('Panele Dön'),
              onTap: () {
                Navigator.of(context).pop(); // sürgü menüyü kapat
                onDashboardTap();
              },
            ),
          ],
        ),
      ),
    );
  }
}
