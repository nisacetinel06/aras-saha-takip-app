import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';
import 'providers/anomaly_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/dashboard_provider.dart';
import 'providers/device_provider.dart';
import 'providers/equipment_provider.dart';
import 'providers/isg_provider.dart';
import 'providers/maintenance_provider.dart';
import 'providers/map_provider.dart';
import 'providers/material_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/reports_provider.dart';
import 'providers/risk_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/user_provider.dart';
import 'providers/work_order_list_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/main_shell.dart';
import 'services/local_notification_service.dart';
import 'theme/app_theme.dart';
import 'widgets/app_logo.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // Kayıtlı tema tercihi yüklenene kadar native splash ekranda kalsın —
  // aksi halde bir anlık varsayılan (açık) tema "flash"ı görülebilir.
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  final themeProvider = ThemeProvider();
  await themeProvider.load();

  // Bildirim Sistemi (Modül 6): kanal/eklenti kurulumu uygulama açılışında
  // bir kez yapılır — MainShell her sekme değişiminde yeniden inşa edildiği
  // için bu adımın orada tekrarlanması gereksizdir.
  await LocalNotificationService.instance.initialize();

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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => FlutterNativeSplash.remove(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => WorkOrderListProvider()),
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
        ChangeNotifierProvider(create: (_) => MapProvider()),
        ChangeNotifierProvider(create: (_) => DeviceProvider()),
        ChangeNotifierProvider(create: (_) => EquipmentProvider()),
        ChangeNotifierProvider(create: (_) => RiskProvider()),
        ChangeNotifierProvider(create: (_) => AnomalyProvider()),
        ChangeNotifierProvider(create: (_) => IsgProvider()),
        ChangeNotifierProvider(create: (_) => MaintenanceProvider()),
        ChangeNotifierProvider(create: (_) => MaterialProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => ReportsProvider()),
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
            home: const AuthGate(),
            // C4 (yazı ölçekleme desteği): cihazın erişilebilirlik yazı
            // boyutu ayarını TAMAMEN yok saymak (textScaler'ı 1.0'a sabitlemek)
            // kötü bir erişilebilirlik pratiği — büyütülmüş yazıyı görmek
            // isteyen kullanıcı bunu göremez. Ama sınırsız büyütme de sabit
            // yükseklikli kartlarda/butonlarda taşmaya yol açar. Makul bir üst
            // sınır (1.3x) ile ikisi arasında denge kurulur.
            builder: (context, child) {
              final clampedScaler = MediaQuery.textScalerOf(
                context,
              ).clamp(maxScaleFactor: 1.3);
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: clampedScaler),
                child: child!,
              );
            },
          );
        },
      ),
    );
  }
}

/// Uygulama açılışında AuthProvider.tryAutoLogin() çalışırken kısa bir
/// yükleniyor ekranı gösterir; sonucuna göre MainShell'e ya da LoginScreen'e
/// geçer. AuthProvider'ın oturumu (örn. 401 sonrası) reaktif olarak
/// temizlemesi durumunda da bu widget yeniden derlenip otomatik olarak
/// LoginScreen'e döner — ayrıca bir Navigator çağrısına gerek yoktur.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _autoLoginAttempted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<AuthProvider>().tryAutoLogin();
      if (mounted) setState(() => _autoLoginAttempted = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (!_autoLoginAttempted && auth.isLoading) {
      return const _SplashView();
    }

    return auth.isAuthenticated ? const MainShell() : const LoginScreen();
  }
}

class _SplashView extends StatelessWidget {
  const _SplashView();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLogo(height: 56, padding: EdgeInsets.all(16)),
            const SizedBox(height: 24),
            CircularProgressIndicator(color: scheme.primary),
          ],
        ),
      ),
    );
  }
}
