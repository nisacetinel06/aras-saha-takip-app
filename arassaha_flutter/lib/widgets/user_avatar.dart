import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';

/// Uygulamadaki TÜM kullanıcı avatarları (Ana Sayfa karşılaması, alt
/// navigasyondaki Profil sekmesi ikonu, Profil ekranı, Kullanıcı Yönetimi
/// listesi/formu) bu ortak bileşenden türer. Fotoğrafı varsa gerçekten
/// backend'den (NetworkImage) gösterir; yoksa rol rengiyle tonlanmış bir
/// "harf avatarı" (örn. "AY") gösterir — bkz. app_colors.dart roleColor.
class UserAvatar extends StatelessWidget {
  final String? photoPath;
  final String initials;
  final String role;
  final double radius;

  const UserAvatar({
    super.key,
    required this.photoPath,
    required this.initials,
    required this.role,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    final color = roleColor(context, role);
    final photoUrl = ApiService.profilePhotoUrl(photoPath);

    if (photoUrl != null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: color.withValues(alpha: 0.15),
        backgroundImage: NetworkImage(photoUrl),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.7,
        ),
      ),
    );
  }
}
