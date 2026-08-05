import 'equipment.dart' show EquipmentType;
import 'equipment_risk.dart' show RiskLevel;
import 'material.dart' show MaterialCategory, MaterialUnit;

/// Raporlar / Analitik Sayfası (Modül 14).
///
/// Bu dosyadaki tüm modeller salt-okunur (yalnızca fromJson) — Modül 9/11'in
/// zaten ürettiği verinin farklı kırılımları/özetleri olduğu için burada
/// yazma/mutasyon işlemi yok.

/// GET /api/reports/regional-risk-summary — bir ilin risk yoğunluk haritası
/// bubble'ı için gereken her şey (merkez koordinat + ekipman sayısı + ort. risk).
class RegionalRiskSummary {
  final String il;
  final double centerLat;
  final double centerLng;
  final int equipmentCount;
  /// null: bu ilde hiç ekipman/risk skoru yok ("veri yok" durumu) — Flutter
  /// tarafı bunu gri/boş bir bubble olarak gösterir (bkz. reports_screen.dart).
  final double? avgRiskScore;
  final int highRiskCount;

  RegionalRiskSummary({
    required this.il,
    required this.centerLat,
    required this.centerLng,
    required this.equipmentCount,
    required this.avgRiskScore,
    required this.highRiskCount,
  });

  /// avg_risk_score'u, backend'deki equipment_risk_scores.risk_level ile AYNI
  /// eşiklerle (0-33 düşük, 34-66 orta, 67-100 yüksek — bkz.
  /// models/equipment_risk.dart) bir [RiskLevel]'e çevirir. Veri yoksa null.
  RiskLevel? get riskLevel {
    final score = avgRiskScore;
    if (score == null) return null;
    if (score <= 33) return RiskLevel.dusuk;
    if (score <= 66) return RiskLevel.orta;
    return RiskLevel.yuksek;
  }

  factory RegionalRiskSummary.fromJson(Map<String, dynamic> json) {
    return RegionalRiskSummary(
      il: json['il'] as String,
      centerLat: (json['center_lat'] as num).toDouble(),
      centerLng: (json['center_lng'] as num).toDouble(),
      equipmentCount: json['equipment_count'] as int,
      avgRiskScore: (json['avg_risk_score'] as num?)?.toDouble(),
      highRiskCount: json['high_risk_count'] as int,
    );
  }
}

/// GET /api/reports/fault-by-region — bir satır.
class RegionFaultCount {
  final String il;
  final int faultCount;

  RegionFaultCount({required this.il, required this.faultCount});

  factory RegionFaultCount.fromJson(Map<String, dynamic> json) {
    return RegionFaultCount(
      il: json['il'] as String,
      faultCount: json['fault_count'] as int,
    );
  }
}

/// GET /api/reports/fault-by-equipment-type — bir satır.
class EquipmentTypeFaultCount {
  final EquipmentType equipmentType;
  final int faultCount;

  EquipmentTypeFaultCount({
    required this.equipmentType,
    required this.faultCount,
  });

  factory EquipmentTypeFaultCount.fromJson(Map<String, dynamic> json) {
    return EquipmentTypeFaultCount(
      equipmentType: EquipmentType.fromJson(json['equipment_type'] as String),
      faultCount: json['fault_count'] as int,
    );
  }
}

const _trendMonthLabels = [
  'Oca',
  'Şub',
  'Mar',
  'Nis',
  'May',
  'Haz',
  'Tem',
  'Ağu',
  'Eyl',
  'Eki',
  'Kas',
  'Ara',
];

/// GET /api/reports/fault-trend — bir ay.
class MonthlyFaultCount {
  /// "YYYY-MM" formatında (bkz. backend strftime('%Y-%m', ...)).
  final String yearMonth;
  final int faultCount;

  MonthlyFaultCount({required this.yearMonth, required this.faultCount});

  /// Çizgi grafiğin X ekseni için kısa Türkçe ay etiketi (örn. "Tem").
  String get shortLabel {
    final month = int.tryParse(yearMonth.split('-').last) ?? 1;
    return _trendMonthLabels[(month - 1).clamp(0, 11)];
  }

  factory MonthlyFaultCount.fromJson(Map<String, dynamic> json) {
    return MonthlyFaultCount(
      yearMonth: json['year_month'] as String,
      faultCount: json['fault_count'] as int,
    );
  }
}

/// GET /api/reports/anomaly-by-region — bir satır.
class RegionAnomalySummary {
  final String il;
  final int totalMeters;
  final int suspiciousCount;
  /// 0.0-1.0 arası oran (örn. 0.5 = %50).
  final double suspiciousRatio;

  RegionAnomalySummary({
    required this.il,
    required this.totalMeters,
    required this.suspiciousCount,
    required this.suspiciousRatio,
  });

  factory RegionAnomalySummary.fromJson(Map<String, dynamic> json) {
    return RegionAnomalySummary(
      il: json['il'] as String,
      totalMeters: json['total_meters'] as int,
      suspiciousCount: json['suspicious_count'] as int,
      suspiciousRatio: (json['suspicious_ratio'] as num).toDouble(),
    );
  }
}

/// GET /api/reports/material-usage-top — bir satır.
class TopMaterialUsage {
  final int id;
  final String name;
  final MaterialUnit unit;
  final MaterialCategory category;
  final double totalUsed;

  TopMaterialUsage({
    required this.id,
    required this.name,
    required this.unit,
    required this.category,
    required this.totalUsed,
  });

  factory TopMaterialUsage.fromJson(Map<String, dynamic> json) {
    return TopMaterialUsage(
      id: json['id'] as int,
      name: json['name'] as String,
      unit: MaterialUnit.fromJson(json['unit'] as String),
      category: MaterialCategory.fromJson(json['category'] as String),
      totalUsed: (json['total_used'] as num).toDouble(),
    );
  }
}
