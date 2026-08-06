import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/connectivity_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Ayarlar ve Çevrimdışı Mod (Modül 17) — global çevrimdışı bandı.
///
/// MainShell'in Scaffold body'sinin EN ÜSTÜNE (AppBar'ın hemen altına),
/// TÜM sekmelerin (Ana Sayfa, İş Emirleri, Harita, Dashboard, Profil)
/// ÜSTÜNDE tek bir yerden eklenir — her ekranın kendi Scaffold'ına ayrı
/// ayrı eklenmesine gerek kalmaz, "AppTopBar kullanan her ekrana da
/// eklensin" alternatifi burada BİLİNÇLİ olarak tercih edilmedi çünkü
/// MainShell zaten TÜM sekmeleri aynı Scaffold içinde barındırıyor (bkz.
/// main_shell.dart IndexedStack) — tek ekleme noktası aynı sonucu verir.
///
/// [ConnectivityProvider.isOnline] false olduğu sürece görünür kalır,
/// bağlantı geri geldiği an (notifyListeners tetiklendiğinde) otomatik
/// daralıp kaybolur — ayrı bir zamanlayıcı/gecikme gerekmez.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final isOnline = context.watch<ConnectivityProvider>().isOnline;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final warning = AppColors.warning(context);

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: isOnline
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              color: warning.withValues(alpha: isDark ? 0.22 : 0.16),
              child: Row(
                children: [
                  Icon(Icons.cloud_off_outlined, size: 16, color: warning),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Çevrimdışısınız — son senkronize edilen veriler gösteriliyor',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
