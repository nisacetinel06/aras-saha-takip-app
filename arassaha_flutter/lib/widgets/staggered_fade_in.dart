import 'package:flutter/material.dart';

/// Kademeli (staggered) liste giriş animasyonu — bir liste ilk render
/// edildiğinde her satırın hafifçe kayarak/belirerek girmesini sağlar (bkz.
/// notifications_screen.dart, sos/sos_alerts_screen.dart). Yeni bir paket
/// (örn. flutter_animate) eklemek yerine, Flutter'ın kendi `TweenAnimationBuilder`'ı
/// kullanılır — her satırın SÜRESİ [index]'e göre değiştirilir: tüm satırlar
/// aynı anda başlar ama sonrakiler daha geç biter, bu da gerçek bir gecikme
/// (delay) mekanizması olmadan kademeli bir his verir. `index`, 10'dan sonra
/// sabitlenir — çok uzun listelerde kuyruk süresi sınırsız uzamasın diye.
///
/// Yalnızca opaklık + `Transform.translate` (transform) değiştirir — layout'u
/// ETKİLEMEZ, GPU-ucuz repaint/composite (bkz. mobile-design skill
/// "transform/opacity" ilkesi). `MediaQuery.disableAnimations` açıksa
/// (erişilebilirlik tercihi) animasyon tamamen atlanır, [child] doğrudan
/// döner.
///
/// ÖNEMLİ: çağıran taraf her satıra kararlı bir `key` (örn.
/// `ValueKey(item.id)`) VERMELİDİR — aksi halde listenin kısmi bir state
/// güncellemesinde (örn. tek bir bildirim okundu işaretlenince
/// `notifyListeners()` TÜM listeyi yeniden inşa eder) her satır yeniden
/// oluşturulup animasyon her seferinde baştan oynar.
class StaggeredFadeIn extends StatelessWidget {
  final int index;
  final Widget child;

  const StaggeredFadeIn({super.key, required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;

    final cappedIndex = index > 10 ? 10 : index;
    final duration = Duration(milliseconds: 220 + cappedIndex * 35);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOut,
      builder: (context, value, childWidget) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 12),
            child: childWidget,
          ),
        );
      },
      child: child,
    );
  }
}
