import 'package:flutter/material.dart';
import '../screens/sos/sos_confirm_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Acil Durum (SOS) Modülü — ortak, tek dokunuşlu tetikleyici bileşen.
///
/// Ana Sayfa'nın en üstünde (kaydırmaya gerek kalmadan görünür) kullanılır;
/// ileride başka ekranlara da eklenebilsin diye bağımsız/ortak bir bileşen
/// olarak tasarlandı — herhangi bir yerden `const SosButton()` ile kullanılır,
/// dokunulunca [SosConfirmScreen]'i (3 saniyelik onay katmanı) açar; GERÇEK
/// bir bildirim BURADA gönderilmez.
///
/// B2 (dokunma alanı): 72dp yükseklik — touch-psychology.md'nin "Critical
/// Actions: 56-64px" kuralının da üzerinde, bilinçli olarak: bu buton eldivenli
/// / kazara dokunma toleransı gereken bir SAHA aracı, standart bir aksiyon
/// butonu değil.
class SosButton extends StatelessWidget {
  const SosButton({super.key});

  @override
  Widget build(BuildContext context) {
    final danger = AppColors.danger(context);
    final onDanger = accessibleOnColor(danger);

    return SizedBox(
      width: double.infinity,
      child: Material(
        color: danger,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const SosConfirmScreen(),
              fullscreenDialog: true,
            ),
          ),
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + 4,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.sos_rounded, color: onDanger, size: 32),
                const SizedBox(width: AppSpacing.sm + 4),
                Text(
                  'ACİL DURUM (SOS)',
                  style: TextStyle(
                    color: onDanger,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
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
