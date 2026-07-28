import 'package:flutter/material.dart';

/// Henüz backend'i/gerçek verisi olmayan modüller (Bildirimler, Ayarlar vb.)
/// için dürüst bir "yakında" ekranı. Sahte veri veya çalışmıyormuş gibi
/// duran bir liste göstermek yerine, özelliğin henüz mevcut olmadığını
/// açıkça belirtir (bkz. ARCHITECTURE.md Temel Kalite İlkesi).
class PlaceholderScreen extends StatelessWidget {
  final IconData icon;
  final String message;

  const PlaceholderScreen({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: scheme.outline),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
