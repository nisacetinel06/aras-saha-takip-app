/// Kullanıcı Yönetimi işlem geçmişi (user_action_logs) — Cihaz Yönetimi
/// modülündeki DeviceActionLog ile AYNI desen: "kim ne zaman ne yaptı" kaydı.
class UserActionLog {
  final int id;
  final int targetUserId;
  final String actionType;
  final String performedBy;
  final DateTime createdAt;

  UserActionLog({
    required this.id,
    required this.targetUserId,
    required this.actionType,
    required this.performedBy,
    required this.createdAt,
  });

  factory UserActionLog.fromJson(Map<String, dynamic> json) {
    return UserActionLog(
      id: json['id'] as int,
      targetUserId: json['target_user_id'] as int,
      actionType: json['action_type'] as String,
      performedBy: json['performed_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Aksiyon kodunu ekranda gösterilecek Türkçe etikete çevirir.
  String get label {
    switch (actionType) {
      case 'olusturuldu':
        return 'Kullanıcı oluşturuldu';
      case 'guncellendi':
        return 'Bilgiler güncellendi';
      case 'pasiflestirildi':
        return 'Pasifleştirildi';
      case 'aktiflestirildi':
        return 'Aktifleştirildi';
      case 'sifre_sifirlandi':
        return 'Şifre sıfırlandı';
      case 'rol_degistirildi':
        return 'Rolü değiştirildi';
      default:
        return actionType;
    }
  }
}

/// Profil ve Kullanıcı Yönetimi (Modül 8) için tam kullanıcı modeli.
///
/// `work_order.dart` içindeki `AssignedUser` (id/name/role) hafif "kişi
/// seçici" ihtiyaçları (iş emri atama, İSG bildiren personel) için yeterlidir
/// ve değiştirilmedi; bu model ise Profil ekranı ve Kullanıcı Yönetimi
/// paneli için gereken tüm özlük bilgilerini (telefon, e-posta, fotoğraf,
/// aktif/pasif durumu) taşır. Backend'in GET /api/users/me, GET
/// /api/users/:id ve (yönetici için) GET /api/users yanıtlarıyla birebir
/// eşleşir — bkz. routes/users.js FULL_FIELDS.
class AppUser {
  final int id;
  final String name;
  final String role;
  final String sicilNo;
  final String? phone;
  final String? email;
  final String? photoPath;
  final bool isActive;
  final int? supervisorId;
  final List<UserActionLog> logs;

  AppUser({
    required this.id,
    required this.name,
    required this.role,
    required this.sicilNo,
    this.phone,
    this.email,
    this.photoPath,
    this.isActive = true,
    this.supervisorId,
    this.logs = const [],
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as int,
      name: json['name'] as String,
      role: json['role'] as String? ?? '',
      sicilNo: json['sicil_no'] as String? ?? '',
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      photoPath: json['photo_path'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      supervisorId: json['supervisor_id'] as int?,
      // `logs` yalnızca GET /api/users/:id yanıtında gömülüdür (bkz.
      // routes/users.js) — liste/me yanıtlarında yoktur, boş kalır.
      logs: json['logs'] != null
          ? (json['logs'] as List)
                .map((l) => UserActionLog.fromJson(l as Map<String, dynamic>))
                .toList()
          : const [],
    );
  }

  /// Fotoğraf yokken avatar'da gösterilecek baş harfler (örn. "Ahmet Yılmaz" -> "AY").
  String get initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  AppUser copyWith({
    String? name,
    String? role,
    String? phone,
    String? email,
    String? photoPath,
    bool? isActive,
  }) {
    return AppUser(
      id: id,
      name: name ?? this.name,
      role: role ?? this.role,
      sicilNo: sicilNo,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      photoPath: photoPath ?? this.photoPath,
      isActive: isActive ?? this.isActive,
      supervisorId: supervisorId,
      logs: logs,
    );
  }
}
