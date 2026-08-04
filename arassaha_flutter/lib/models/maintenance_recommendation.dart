import 'equipment.dart';
import 'equipment_risk.dart' show RiskLevel;

/// Kestirimci Bakım Planlama (Modül 12) — bir önerinin durumu. Backend'deki
/// maintenance_recommendations.status ile birebir eşleşir.
enum MaintenanceRecommendationStatus {
  onerildi,
  planlandi,
  tamamlandi,
  reddedildi;

  static MaintenanceRecommendationStatus fromJson(String value) {
    return MaintenanceRecommendationStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => MaintenanceRecommendationStatus.onerildi,
    );
  }

  String toJson() => name;

  String get label {
    switch (this) {
      case MaintenanceRecommendationStatus.onerildi:
        return 'Bekliyor';
      case MaintenanceRecommendationStatus.planlandi:
        return 'Planlandı';
      case MaintenanceRecommendationStatus.tamamlandi:
        return 'Tamamlandı';
      case MaintenanceRecommendationStatus.reddedildi:
        return 'Reddedildi';
    }
  }
}

/// Öneriye bağlı ekipmanın hafif özeti — GET /api/maintenance/recommendations
/// yanıtındaki gömülü `equipment` nesnesiyle birebir eşleşir (bkz.
/// routes/maintenance.js mapRecommendationRow).
class MaintenanceRecommendationEquipmentRef {
  final int id;
  final String qrCode;
  final EquipmentType equipmentType;
  final String locationName;
  final String il;
  final String ilce;
  final String mahalle;
  final double? lat;
  final double? lng;
  final EquipmentStatus status;

  MaintenanceRecommendationEquipmentRef({
    required this.id,
    required this.qrCode,
    required this.equipmentType,
    required this.locationName,
    required this.il,
    required this.ilce,
    required this.mahalle,
    required this.lat,
    required this.lng,
    required this.status,
  });

  factory MaintenanceRecommendationEquipmentRef.fromJson(
    Map<String, dynamic> json,
  ) {
    return MaintenanceRecommendationEquipmentRef(
      id: json['id'] as int,
      qrCode: json['qr_code'] as String? ?? '',
      equipmentType: EquipmentType.fromJson(
        json['equipment_type'] as String? ?? '',
      ),
      locationName: json['location_name'] as String? ?? '',
      il: json['il'] as String? ?? '',
      ilce: json['ilce'] as String? ?? '',
      mahalle: json['mahalle'] as String? ?? '',
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      status: EquipmentStatus.fromJson(json['status'] as String? ?? 'aktif'),
    );
  }
}

/// Kestirimci Bakım Planlama (Modül 12) — tek bir bakım önerisi.
///
/// ÖNEMLİ AYRIM: Bu öneriyi üreten bir ML modeli DEĞİLDİR — Modül 9'un
/// (RiskProvider/EquipmentRisk) ürettiği risk_score'un SABİT eşiklerle
/// (67/34) bir bakım önerisine çevrildiği bir iş kuralıdır (bkz.
/// arassaha-backend/routes/maintenance.js). `urgencyLevel` bu yüzden Modül
/// 9'un RiskLevel enum'ını yeniden kullanır — iki modül aynı üç değeri
/// (dusuk/orta/yuksek) ve dolayısıyla AYNI renk paletini paylaşır (bkz.
/// theme/app_colors.dart riskLevelColor).
class MaintenanceRecommendation {
  final int id;
  final int equipmentId;
  final int riskScoreAtCreation;
  final RiskLevel urgencyLevel;
  final DateTime recommendedDate;
  final String reason;
  final MaintenanceRecommendationStatus status;
  final int? relatedWorkOrderId;
  final DateTime createdAt;
  final MaintenanceRecommendationEquipmentRef equipment;

  MaintenanceRecommendation({
    required this.id,
    required this.equipmentId,
    required this.riskScoreAtCreation,
    required this.urgencyLevel,
    required this.recommendedDate,
    required this.reason,
    required this.status,
    required this.relatedWorkOrderId,
    required this.createdAt,
    required this.equipment,
  });

  factory MaintenanceRecommendation.fromJson(Map<String, dynamic> json) {
    return MaintenanceRecommendation(
      id: json['id'] as int,
      equipmentId: json['equipment_id'] as int,
      riskScoreAtCreation: json['risk_score_at_creation'] as int,
      urgencyLevel: RiskLevel.fromJson(json['urgency_level'] as String),
      // Backend yalnızca "YYYY-MM-DD" gönderir (bkz. routes/maintenance.js
      // addDaysIso) — DateTime.parse bunu gece yarısı yerel/UTC olarak çözer,
      // yalnızca tarih gösterimi için kullanıldığından saat kısmı önemsizdir.
      recommendedDate: DateTime.parse(json['recommended_date'] as String),
      reason: json['reason'] as String,
      status: MaintenanceRecommendationStatus.fromJson(
        json['status'] as String,
      ),
      relatedWorkOrderId: json['related_work_order_id'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
      equipment: MaintenanceRecommendationEquipmentRef.fromJson(
        json['equipment'] as Map<String, dynamic>,
      ),
    );
  }
}
