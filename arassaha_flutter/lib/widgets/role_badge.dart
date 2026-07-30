import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Kullanıcı rolünü gösteren küçük renkli rozet (Profil ekranı, Ana Sayfa
/// karşılaması, Kullanıcı Yönetimi listesi). İş emri durum/öncelik
/// rozetleriyle (bkz. status_badge.dart) KARIŞTIRILMAMASI için ayrı bir renk
/// paleti kullanır — bkz. app_colors.dart roleColor.
class RoleBadge extends StatelessWidget {
  final String role;
  final String label;

  const RoleBadge({super.key, required this.role, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = roleColor(context, role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}
