import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';
import 'providers/dashboard_provider.dart';
import 'providers/device_provider.dart';
import 'providers/equipment_provider.dart';
import 'providers/map_provider.dart';
import 'providers/risk_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/work_order_list_provider.dart';
import 'screens/main_shell.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // Kayıtlı tema tercihi yüklenene kadar native splash ekranda kalsın —
  // aksi halde bir anlık varsayılan (açık) tema "flash"ı görülebilir.
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  final themeProvider = ThemeProvider();
  await themeProvider.load();

  runApp(ArasSahaApp(themeProvider: themeProvider));
}

class ArasSahaApp extends StatefulWidget {
  final ThemeProvider themeProvider;
  const ArasSahaApp({super.key, required this.themeProvider});

  @override
  State<ArasSahaApp> createState() => _ArasSahaAppState();
}

class _ArasSahaAppState extends State<ArasSahaApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => FlutterNativeSplash.remove());
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WorkOrderListProvider()),
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
        ChangeNotifierProvider(create: (_) => MapProvider()),
        ChangeNotifierProvider(create: (_) => DeviceProvider()),
        ChangeNotifierProvider(create: (_) => EquipmentProvider()),
        ChangeNotifierProvider(create: (_) => RiskProvider()),
        ChangeNotifierProvider.value(value: widget.themeProvider),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'ArasSaha',
            debugShowCheckedModeBanner: false,
            themeMode: themeProvider.mode,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            home: const MainShell(),
          );
        },
      ),
    );
  }
}
