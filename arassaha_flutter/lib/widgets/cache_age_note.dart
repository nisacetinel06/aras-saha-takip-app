import 'package:flutter/material.dart';
import '../services/cache_service.dart';
import '../theme/app_spacing.dart';

/// Ayarlar ve Çevrimdışı Mod (Modül 17) — Okuma Önbelleği. Bir liste ekranı
/// canlı çekmenin BAŞARISIZ olup önbellekten döndüğü durumda (bkz. ilgili
/// provider'daki `isFromCache`/`cachedAt`) bu notu listenin ÜSTÜNDE gösterir:
/// "Son güncelleme: 12 dakika önce (çevrimdışı)". [MainShell]'deki global
/// [OfflineBanner]'dan FARKLI bir amacı var — banner "bağlantı yok" der,
/// bu not "gördüğün liste NE KADAR eski" der; ikisi birbirini tekrarlamaz,
/// aynı ekranda ikisi de görünebilir.
class CacheAgeNote extends StatelessWidget {
  final DateTime cachedAt;
  const CacheAgeNote({super.key, required this.cachedAt});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(Icons.history, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Son güncelleme: ${formatCacheAge(cachedAt)} (çevrimdışı)',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
