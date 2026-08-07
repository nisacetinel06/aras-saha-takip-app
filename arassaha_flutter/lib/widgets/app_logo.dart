import 'package:flutter/material.dart';

/// ArasSaha logosu (assets/images/SAHA.png) opak/beyaz zeminli bir görsel
/// (şeffaflık yok) — bu yüzden doğrudan ekrana basılmaz, "yapıştırılmış" gibi
/// durmasın diye her zaman beyaz, yuvarlak köşeli bir rozet içine alınır. Bu
/// rozet hem açık hem koyu temada (koyu temada da beyaz kalır, logonun kendi
/// zeminiyle uyumlu olması için) tutarlı görünür.
class AppLogo extends StatelessWidget {
  final double height;
  final EdgeInsetsGeometry padding;

  const AppLogo({
    super.key,
    this.height = 28,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Image.asset(
        'assets/images/SAHA.png',
        height: height,
        fit: BoxFit.contain,
        // UI denetimi bulgusu: kaynak PNG 2000x2000 — bu boyuttan küçük bir
        // rozete (22-40dp) indirgerken Flutter'ın varsayılan filterQuality.low
        // (bilinear) ölçeklemesi bazı cihaz/DPI kombinasyonlarında hafif
        // bulanık/pikselli kenarlar üretebiliyor. high, mip-map benzeri daha
        // kaliteli bir küçültme kullanır — TEK gerçek raster ikon kaynağımız
        // bu widget olduğu için düzeltme burada merkezi.
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

/// ArasAI (AI Asistan — Modül 16) rozet logosu (assets/images/ArasAI_LOGO.png)
/// — [AppLogo] ile AYNI "opak zemin -> beyaz rozet içine al" deseni, yalnızca
/// sohbet ekranındaki avatar/app bar ikonu bağlamında kullanılır.
class ArasAiLogo extends StatelessWidget {
  final double size;
  const ArasAiLogo({super.key, this.size = 28});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.12),
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: Image.asset(
        'assets/images/ArasAI_LOGO.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
