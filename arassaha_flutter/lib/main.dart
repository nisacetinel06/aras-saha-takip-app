import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/dashboard_provider.dart';
import 'providers/map_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/work_order_list_provider.dart';
import 'screens/dashboard_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const ArasSahaApp());
}

class ArasSahaApp extends StatelessWidget {
  const ArasSahaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WorkOrderListProvider()),
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
        ChangeNotifierProvider(create: (_) => MapProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'ArasSaha',
            debugShowCheckedModeBanner: false,
            themeMode: themeProvider.mode,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            home: const DashboardScreen(),
          );
        },
      ),
    );
  }
}
