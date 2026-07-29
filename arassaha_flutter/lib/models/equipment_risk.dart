import 'equipment.dart';

/// Arıza Risk Tahmini (Modül 9) — risk seviyesi. Backend'deki
/// equipment_risk_scores.risk_level ile birebir eşleşir; eşikler:
/// 0-33 dusuk, 34-66 orta, 67-100 yuksek (bkz. arassaha-ml/app.py).
enum RiskLevel {
  dusuk,
  orta,
  yuksek;

  static RiskLevel fromJson(String value) {
    switch (value) {
      case 'dusuk':
        return RiskLevel.dusuk;
      case 'orta':
        return RiskLevel.orta;
      case 'yuksek':
        return RiskLevel.yuksek;
      default:
        return RiskLevel.dusuk;
    }
  }

  String get label {
    switch (this) {
      case RiskLevel.dusuk:
        return 'Düşük Risk';
      case RiskLevel.orta:
        return 'Orta Risk';
      case RiskLevel.yuksek:
        return 'Yüksek Risk';
    }
  }
}

/// GET /api/equipment/:id/risk yanıtı — tek bir ekipmanın en güncel risk skoru.
///
/// DÜRÜSTLÜK NOTU: Bu skor, ArasSaha'nın henüz gerçek bir arıza geçmişi
/// biriktirmemiş olması nedeniyle SENTETİK (kural tabanlı üretilmiş) bir veri
/// setiyle eğitilmiş bir modelden gelir (bkz. arassaha-ml/README.md). Model
/// eğitimi ve servis entegrasyonu gerçektir; yalnızca eğitim verisi sentetiktir.
class EquipmentRisk {
  final int equipmentId;
  final int riskScore;
  final RiskLevel riskLevel;
  final DateTime computedAt;

  EquipmentRisk({
    required this.equipmentId,
    required this.riskScore,
    required this.riskLevel,
    required this.computedAt,
  });

  factory EquipmentRisk.fromJson(Map<String, dynamic> json) {
    return EquipmentRisk(
      equipmentId: json['equipment_id'] as int,
      riskScore: json['risk_score'] as int,
      riskLevel: RiskLevel.fromJson(json['risk_level'] as String),
      computedAt: DateTime.parse(json['computed_at'] as String),
    );
  }
}

/// GET /api/dashboard/risky-equipment içindeki tek bir satır — Dashboard'un
/// "Riskli Ekipmanlar" bölümü için ekipman bilgisi + risk skorunu bir arada taşır.
class RiskyEquipmentSummary {
  final int id;
  final String qrCode;
  final EquipmentType equipmentType;
  final String locationName;
  final EquipmentStatus status;
  final int riskScore;
  final RiskLevel riskLevel;

  RiskyEquipmentSummary({
    required this.id,
    required this.qrCode,
    required this.equipmentType,
    required this.locationName,
    required this.status,
    required this.riskScore,
    required this.riskLevel,
  });

  factory RiskyEquipmentSummary.fromJson(Map<String, dynamic> json) {
    return RiskyEquipmentSummary(
      id: json['id'] as int,
      qrCode: json['qr_code'] as String,
      equipmentType: EquipmentType.fromJson(json['equipment_type'] as String),
      locationName: json['location_name'] as String? ?? '',
      status: EquipmentStatus.fromJson(json['status'] as String),
      riskScore: json['risk_score'] as int,
      riskLevel: RiskLevel.fromJson(json['risk_level'] as String),
    );
  }
}
