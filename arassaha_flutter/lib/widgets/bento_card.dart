import 'package:flutter/material.dart';

/// Yeni tasarım dilindeki "bento" kart görünümü: yumuşak, katmanlı gölge +
/// 12px köşe yuvarlaklığı. Standart `Card` yerine bunu kullanmak, tasarımdaki
/// `box-shadow: 0 4px 6px -1px rgba(0,0,0,.1), 0 2px 4px -1px rgba(0,0,0,.06)`
/// tarifine daha yakın bir görünüm sağlar.
class BentoCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const BentoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Not: Container'ı ClipRRect ile sarmıyoruz — bu, dışa taşan gölgeyi de
    // keserdi. Köşe yuvarlaklığının içerik taşırmasını önlemek InkWell'in
    // kendi borderRadius'una bırakılıyor.
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: isDark ? 0.5 : 0.3)),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 2)),
                BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 6, offset: const Offset(0, 4)),
              ],
      ),
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : Material(
              type: MaterialType.transparency,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Padding(padding: padding, child: child),
              ),
            ),
    );
  }
}
