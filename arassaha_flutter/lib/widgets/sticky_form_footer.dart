import 'package:flutter/material.dart';
import '../theme/app_spacing.dart';

/// Formlardaki birincil "Kaydet/Gönder/Oluştur" butonunu, `ListView` içine
/// gömülü (kullanıcı formu ne kadar aşağı kaydırırsa kaydırsın kaybolan)
/// olmaktan çıkarıp `Scaffold.bottomNavigationBar` alanında SABİT (sticky)
/// tutar — baş parmak bölgesi (thumb zone) ergonomisi: birincil aksiyon her
/// zaman ekranın altında, tek elle erişilebilir konumda kalmalı.
///
/// `SafeArea(top: false)` ile cihazın alt gezinme çubuğuyla (gesture bar)
/// çakışması önlenir; üstteki ince kenarlık, buton alanını kaydırılabilir
/// içerikten görsel olarak ayırır.
class StickyFormFooter extends StatelessWidget {
  final Widget child;
  const StickyFormFooter({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 4,
          ),
          child: child,
        ),
      ),
    );
  }
}
