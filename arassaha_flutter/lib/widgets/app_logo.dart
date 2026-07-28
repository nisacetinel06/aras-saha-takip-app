import 'package:flutter/material.dart';

/// Aras EDAŞ logosu (assets/images/aras_logo.jpg) opak/beyaz zeminli bir
/// görsel (şeffaflık yok) — bu yüzden doğrudan ekrana basılmaz, "yapıştırılmış"
/// gibi durmasın diye her zaman beyaz, yuvarlak köşeli bir rozet içine alınır.
/// Bu rozet hem açık hem koyu temada (koyu temada da beyaz kalır, logonun
/// kendi zeminiyle uyumlu olması için) tutarlı görünür.
class AppLogo extends StatelessWidget {
  final double height;
  final EdgeInsetsGeometry padding;

  const AppLogo({super.key, this.height = 28, this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6)});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Image.asset('assets/images/aras_logo.jpg', height: height, fit: BoxFit.contain),
    );
  }
}
