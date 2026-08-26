import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/notification_provider.dart';
import '../providers/theme_provider.dart';
import '../screens/notifications/notifications_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// TÜM ekranların ortak üst barı. Önceden her ekran kendi `AppBar`'ını,
/// kendi dark/light toggle `IconButton`'ını elle (kopyala-yapıştır ile)
/// yazıyordu — 11 dosyada birebir aynı kod tekrarlanmıştı ve üç dosyada
/// (CreateWorkOrderScreen, NotificationsScreen, UserEditScreen) bu toggle
/// unutulmuştu. Bildirim zili de MainShell'in üst çubuğunda VE (bir ara)
/// Ana Sayfa'nın karşılama satırında ayrı ayrı çizilip aynı ekranda iki kez
/// görünüyordu. Kök neden, tek bir kaynaktan yönetilen bir header bileşeni
/// olmamasıydı — artık HER ekran (MainShell hariç; o kendi sekme başlığını/
/// logosunu taşıdığı için ayrı ama AYNI [NotificationBellButton] ve
/// [ThemeToggleButton] alt bileşenlerini kullanır) bu tek `AppTopBar`'ı kullanır.
///
/// `showBackButton`, `showNotificationBell`, `showThemeToggle` bayraklarıyla
/// hangi ekranda neyin görüneceği kontrol edilir (örn. Login ekranı bu
/// bileşeni hiç kullanmaz — kendi tam ekran tasarımını korur).
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showBackButton;
  final bool showNotificationBell;
  final bool showThemeToggle;

  /// Ekrana özel ek aksiyonlar (örn. bir liste ekranındaki filtre ikonu) —
  /// zil ve tema butonlarından ÖNCE gösterilir, böylece zil/tema her zaman
  /// en sağda, tutarlı bir konumda kalır.
  final List<Widget>? extraActions;

  const AppTopBar({
    super.key,
    required this.title,
    this.showBackButton = true,
    this.showNotificationBell = true,
    this.showThemeToggle = true,
    this.extraActions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title, overflow: TextOverflow.ellipsis),
      automaticallyImplyLeading: showBackButton,
      actions: [
        ...?extraActions,
        if (showNotificationBell) const NotificationBellButton(),
        if (showThemeToggle) const ThemeToggleButton(),
        const SizedBox(width: AppSpacing.xs),
      ],
    );
  }
}

/// Bildirim zili — okunmamış sayıyı [NotificationProvider]'dan GERÇEK zamanlı
/// okur, dokununca [NotificationsScreen]'e gider. Uygulamada zili çizen TEK
/// yer burasıdır; [AppTopBar] kullanan her ekran ve [MainShell] birebir bu
/// widget'ı paylaşır — bir daha iki farklı "zil" koduna asla gerek yok.
class NotificationBellButton extends StatelessWidget {
  const NotificationBellButton({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unreadCount = context.watch<NotificationProvider>().unreadCount;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: 'Bildirimler',
          icon: const Icon(Icons.notifications_outlined),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const NotificationsScreen()),
          ),
        ),
        Positioned(
          top: 6,
          right: 6,
          child: IgnorePointer(
            // Rozet, okunmamış sayı değiştiğinde (artış veya
            // markAllAsRead ile sıfırlanma) küçük bir "pop" (ölçek)
            // animasyonuyla belirir/kaybolur — AnimatedSwitcher'ın
            // `ValueKey(unreadCount)`'a bağlı olması, her farklı sayı
            // değerinde yeni bir widget/animasyon tetikler.
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: unreadCount > 0
                  ? Container(
                      key: ValueKey(unreadCount),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.danger(context),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(color: scheme.surface, width: 1.5),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        unreadCount > 9 ? '9+' : '$unreadCount',
                        style: TextStyle(
                          color: accessibleOnColor(AppColors.danger(context)),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('empty')),
            ),
          ),
        ),
      ],
    );
  }
}

/// Aydınlık/karanlık mod geçiş butonu — [AppTopBar] kullanan her ekran ve
/// [MainShell] birebir bu widget'ı paylaşır.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return IconButton(
      tooltip: themeProvider.isDark ? 'Aydınlık moda geç' : 'Karanlık moda geç',
      icon: Icon(
        themeProvider.isDark
            ? Icons.light_mode_outlined
            : Icons.dark_mode_outlined,
      ),
      onPressed: themeProvider.toggle,
    );
  }
}
