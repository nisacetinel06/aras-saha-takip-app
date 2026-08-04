import 'package:flutter/material.dart';
import '../services/analytics_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Renk kuralı (bkz. DESIGN_SYSTEM.md / app_colors.dart):
/// - `primary`: birincil/asıl aksiyon ("Kaydet", "Gönder", "Giriş Yap" gibi
///   kullanıcıyı asıl harekete geçiren buton) — HER ZAMAN primary (mavi), dolu.
///   FAB kendi accent (turuncu) rengini korur (bkz. app_theme.dart
///   floatingActionButtonTheme) — bu bilinçli bir ayrım, FAB'ın ekranda ayrı
///   bir vurgu olarak öne çıkması isteniyor.
/// - `secondary`: ikincil/nötr/iptal aksiyonu — primary (mavi), outline.
/// - `text`: en düşük vurgulu aksiyon — primary (mavi), zeminsiz.
/// - `destructive`: yıkıcı/geri alınamaz aksiyon ("Hesabı Sil", "Çıkış Yap",
///   "Pasifleştir") — danger (kırmızı), outline. Durum renkleri (success/
///   warning/danger) BAŞKA HİÇBİR yerde genel bir buton rengi olarak
///   kullanılmaz — yalnızca bu varyant ve rozetler/durum şeritlerinde.
enum AppButtonVariant { primary, secondary, text, destructive }

/// Uygulamadaki TÜM butonlar için tek ortak bileşen. Metin her zaman
/// `Flexible` + `TextOverflow.ellipsis` ile sarmalanır — buton ne kadar dar
/// olursa olsun taşma (RenderFlex overflow) oluşmaz. Bkz. DESIGN_SYSTEM.md A.4.
class AppButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final AppButtonVariant variant;
  final VoidCallback? onPressed;
  final bool isLoading;

  /// Yalnızca istisnai bir durum için varsayılan varyant rengini geçersiz
  /// kılar. Yıkıcı aksiyonlar için bunu KULLANMA — `AppButtonVariant.destructive`
  /// zaten doğru (danger) rengi otomatik uygular.
  final Color? color;

  const AppButton({
    super.key,
    required this.label,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.onPressed,
    this.isLoading = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveOnPressed = isLoading ? null : onPressed;

    Color loadingColor() {
      // D1 kontrast bulgusu: koyu temada scheme.primary (#5B9BE0) sabit
      // Colors.white ile yalnızca 2.91:1 kontrast veriyordu (WCAG AA eşiği
      // 4.5:1) — accessibleOnColor doğru rengi (ihtiyaç halinde koyu) hesaplar.
      if (variant == AppButtonVariant.primary)
        return accessibleOnColor(color ?? scheme.primary);
      if (color != null) return color!;
      return variant == AppButtonVariant.destructive
          ? scheme.error
          : scheme.primary;
    }

    final leading = isLoading
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: loadingColor(),
            ),
          )
        : (icon != null ? Icon(icon, size: 18) : null);

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leading != null) ...[leading, const SizedBox(width: AppSpacing.sm)],
        Flexible(
          child: Text(label, overflow: TextOverflow.ellipsis, maxLines: 1),
        ),
      ],
    );

    final constraints = const BoxConstraints(minHeight: 48);

    switch (variant) {
      case AppButtonVariant.primary:
        // Birincil aksiyon HER ZAMAN primary (mavi), dolu — ambient temanın
        // ElevatedButton varsayılanı zaten scheme.primary'dir, ama burada
        // açıkça belirtiliyor ki `color` geçersiz kılması net şekilde çalışsın.
        //
        // E3 (kullanım analitiği): TÜM primary butonlar burada MERKEZİ olarak
        // loglanır — her ekranda tek tek AnalyticsService.logButtonTap
        // çağırmaya gerek yok. Ekranın adı, en son o ekranın initState'inde
        // çağırdığı logScreenView'dan gelir (bkz. AnalyticsService.currentScreen).
        final loggedOnPressed = effectiveOnPressed == null
            ? null
            : () {
                AnalyticsService.logButtonTap(
                  AnalyticsService.currentScreen,
                  label,
                );
                effectiveOnPressed();
              };
        return ConstrainedBox(
          constraints: constraints,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: color ?? scheme.primary,
              // bkz. loadingColor() üstündeki D1 notu — aynı sebeple sabit
              // beyaz yerine hesaplanmış kontrastlı renk kullanılıyor.
              foregroundColor: accessibleOnColor(color ?? scheme.primary),
            ),
            onPressed: loggedOnPressed,
            child: content,
          ),
        );
      case AppButtonVariant.secondary:
        return ConstrainedBox(
          constraints: constraints,
          child: OutlinedButton(
            style: color != null
                ? OutlinedButton.styleFrom(
                    foregroundColor: color,
                    side: BorderSide(color: color!, width: 1.5),
                  )
                : null,
            onPressed: effectiveOnPressed,
            child: content,
          ),
        );
      case AppButtonVariant.text:
        return ConstrainedBox(
          constraints: constraints,
          child: TextButton(
            style: color != null
                ? TextButton.styleFrom(foregroundColor: color)
                : null,
            onPressed: effectiveOnPressed,
            child: content,
          ),
        );
      case AppButtonVariant.destructive:
        final destructiveColor = color ?? scheme.error;
        return ConstrainedBox(
          constraints: constraints,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: destructiveColor,
              side: BorderSide(color: destructiveColor, width: 1.5),
            ),
            onPressed: effectiveOnPressed,
            child: content,
          ),
        );
    }
  }
}
