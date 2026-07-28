import 'package:flutter/material.dart';
import '../theme/app_spacing.dart';

enum AppButtonVariant { primary, secondary, text }

/// Uygulamadaki TÜM butonlar için tek ortak bileşen. Metin her zaman
/// `Flexible` + `TextOverflow.ellipsis` ile sarmalanır — buton ne kadar dar
/// olursa olsun taşma (RenderFlex overflow) oluşmaz. Bkz. DESIGN_SYSTEM.md A.4.
class AppButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final AppButtonVariant variant;
  final VoidCallback? onPressed;
  final bool isLoading;

  /// Yıkıcı/riskli aksiyonlar (örn. "Hesabı Sil") için varsayılan primary/
  /// secondary rengini geçersiz kılar (örn. `colorScheme.error`). Belirtilmezse
  /// tema rengi kullanılır.
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

    final leading = isLoading
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: variant == AppButtonVariant.primary ? scheme.onPrimary : (color ?? scheme.primary),
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
        return ConstrainedBox(
          constraints: constraints,
          child: ElevatedButton(
            style: color != null ? ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white) : null,
            onPressed: effectiveOnPressed,
            child: content,
          ),
        );
      case AppButtonVariant.secondary:
        return ConstrainedBox(
          constraints: constraints,
          child: OutlinedButton(
            style: color != null
                ? OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color!, width: 1.5))
                : null,
            onPressed: effectiveOnPressed,
            child: content,
          ),
        );
      case AppButtonVariant.text:
        return ConstrainedBox(
          constraints: constraints,
          child: TextButton(
            style: color != null ? TextButton.styleFrom(foregroundColor: color) : null,
            onPressed: effectiveOnPressed,
            child: content,
          ),
        );
    }
  }
}
