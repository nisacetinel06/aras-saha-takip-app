import 'package:flutter/material.dart';
import '../theme/app_spacing.dart';

/// Uygulamadaki TÜM kartlar (iş emri kartı, dashboard özet kartı, ekipman
/// kartı, harita bilgi balonu vb.) bu ortak bileşenden türer — aynı gölge,
/// aynı radius, aynı iç padding. Bkz. DESIGN_SYSTEM.md A.5.
///
/// `statusStripeColor` verilirse kartın sol kenarında 4px'lik renkli bir
/// "durum şeridi" çizilir — uygulamanın imza görsel öğesi (bkz. A.6). Durum
/// taşımayan kartlarda (örn. Ana Sayfa modül ızgarası) bu parametre boş bırakılır.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? statusStripeColor;

  /// Kartın zeminini varsayılan `surfaceContainerLowest` yerine bu renkle
  /// (düşük alpha'da) boyar — örn. Ana Sayfa modül kartlarında her modülün
  /// kendi rengiyle hafifçe tonlanması için.
  final Color? backgroundTint;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
    this.statusStripeColor,
    this.backgroundTint,
  });

  Widget _buildContent(BuildContext context) {
    return onTap == null
        ? Padding(padding: padding, child: child)
        : Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              child: Padding(padding: padding, child: child),
            ),
          );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Durum şeridi yoksa içerik doğrudan Padding/InkWell'dir — ekstra bir Row
    // sarmalayıcı eklemiyoruz. Şerit varsa Row'u `IntrinsicHeight` içine
    // alıyoruz: aksi halde (örn. ListView gibi yükseklik sınırı olmayan bir
    // bağlamda) `CrossAxisAlignment.stretch`, alt katmana "sonsuz yükseklik"
    // kısıtı geçirip layout hatasına yol açıyordu.
    final body = statusStripeColor == null
        ? _buildContent(context)
        : IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: statusStripeColor),
                Expanded(child: _buildContent(context)),
              ],
            ),
          );

    // Container'ı ClipRRect ile sarmıyoruz — bu, dışa taşan gölgeyi de
    // keserdi. Köşe yuvarlaklığının içerik taşırmasını önlemek InkWell'in
    // kendi borderRadius'una bırakılıyor.
    return Container(
      decoration: BoxDecoration(
        color:
            backgroundTint?.withValues(alpha: isDark ? 0.28 : 0.22) ??
            scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color:
              backgroundTint?.withValues(alpha: isDark ? 0.55 : 0.45) ??
              scheme.outlineVariant.withValues(alpha: isDark ? 0.5 : 0.3),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 6,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      clipBehavior: Clip.antiAlias,
      child: body,
    );
  }
}
