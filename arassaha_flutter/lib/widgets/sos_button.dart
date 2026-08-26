import 'package:flutter/material.dart';
import '../screens/sos/sos_confirm_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_card.dart';

/// Acil Durum (SOS) Modülü — ortak, tek dokunuşlu tetikleyici bileşen.
///
/// Ana Sayfa'nın en ALTINDA, "Çabuk Erişim"den sonra, kendi başına duran bir
/// şerit olarak kullanılır (bkz. home_screen.dart) — ileride başka ekranlara
/// da eklenebilsin diye bağımsız/ortak bir bileşen olarak tasarlandı,
/// herhangi bir yerden `const SosButton()` ile kullanılır, dokunulunca
/// [SosConfirmScreen]'i (3 saniyelik onay katmanı) açar; GERÇEK bir bildirim
/// BURADA gönderilmez.
///
/// Görsel dil: dolu/opak kırmızı blok DEĞİL, açık kırmızı zemin + ince
/// kırmızı kenarlık + kırmızı tonda ikon/metin — [AppCard]'ın zaten var olan
/// `backgroundTint` mekanizması (bkz. app_card.dart, home_screen.dart
/// _SosAlertsAccessCard'daki AYNI desen) yeniden kullanılır, yeni bir stil
/// icat edilmez. B2 (dokunma alanı): asgari 56dp yükseklik — bu buton
/// eldivenli/kazara dokunma toleransı gereken bir SAHA aracı, standart bir
/// aksiyon butonu değil.
class SosButton extends StatelessWidget {
  const SosButton({super.key});

  @override
  Widget build(BuildContext context) {
    final danger = AppColors.danger(context);

    return AppCard(
      backgroundTint: danger,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 4,
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const SosConfirmScreen(),
          fullscreenDialog: true,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sos_rounded, color: danger, size: 26),
            const SizedBox(width: AppSpacing.sm + 4),
            Text(
              'ACİL DURUM (SOS)',
              style: TextStyle(
                color: danger,
                fontWeight: FontWeight.w800,
                fontSize: 16,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// AppTopBar'ın `extraActions` yuvasında kullanılan KÜÇÜK ikon varyantı —
/// bkz. PROMPT madde 4: "en sık kullanılan 2-3 ekranda erişilebilir" kapsam
/// kararı gereği İş Emri Detayı ve Harita ekranlarının üst bar'ına eklenir.
/// Davranış BİREBİR [SosButton] ile AYNI (aynı [SosConfirmScreen]'i açar) —
/// yalnızca boyutu farklı.
class SosAppBarAction extends StatelessWidget {
  const SosAppBarAction({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Acil Durum (SOS)',
      icon: Icon(Icons.sos_rounded, color: AppColors.danger(context)),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const SosConfirmScreen(),
          fullscreenDialog: true,
        ),
      ),
    );
  }
}
