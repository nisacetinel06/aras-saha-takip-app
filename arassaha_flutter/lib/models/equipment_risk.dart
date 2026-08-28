import 'equipment.dart';

/// Arıza Risk Tahmini (Modül 9) — risk seviyesi. Backend'deki
/// equipment_risk_scores.risk_level ile birebir eşleşir; eşikler:
/// 0-33 dusuk, 34-66 orta, 67-100 yuksek (bkz. arassaha-ml/app.py).
///
/// TEST-19: `belirsiz` — modelin predict_proba'sının en yüksek sınıfa
/// verdiği olasılık düşük güven eşiğinin (bkz. arassaha-ml/app.py
/// RISK_UNCERTAIN_THRESHOLD) altında kaldığında backend bu değeri döner.
/// Modül 10'daki (NLP/metin sınıflandırma) "düşük güvende öneri gösterme"
/// disipliniyle AYNI ilke: kesin bir yuksek/orta/dusuk etiketi, model
/// gerçekte kararsızken YANLIŞ bir kesinlik hissi verirdi. UI tarafı
/// (equipment_list_screen.dart _RiskBadge, equipment_detail_screen.dart,
/// dashboard_screen.dart _RiskyEquipmentSection) bu durumda renkli/sayısal
/// rozeti DEĞİL, nötr bir "belirsiz" göstergesi render eder.
enum RiskLevel {
  dusuk,
  orta,
  yuksek,
  belirsiz;

  static RiskLevel fromJson(String value) {
    switch (value) {
      case 'dusuk':
        return RiskLevel.dusuk;
      case 'orta':
        return RiskLevel.orta;
      case 'yuksek':
        return RiskLevel.yuksek;
      case 'belirsiz':
        return RiskLevel.belirsiz;
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
      case RiskLevel.belirsiz:
        return 'Belirsiz';
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

/// TEST-19: Gerçek Geri Bildirim Döngüsü — GET /api/ml/risk-model-performance
/// yanıtı. arassaha-ml/models/model_metadata.json'daki SENTETİK test seti
/// metrikleriNDEN FARKLI olarak, bu skorlar backend'in risk_prediction_outcomes
/// tablosunda GERÇEKTEN biriken tahmin/sonuç çiftlerinden hesaplanır — "model
/// gerçek hayatta ne kadar isabetli" sorusuna dürüst bir cevaptır (bkz.
/// routes/risk.js dosya başı yorumu).
class RiskModelPerformanceBucket {
  final int total;
  final int? faulted;
  final int? notFaulted;
  final double? ratePercent;

  RiskModelPerformanceBucket({
    required this.total,
    this.faulted,
    this.notFaulted,
    this.ratePercent,
  });
}

class RiskModelPerformance {
  final int totalPredictions;
  final int resolvedPredictions;
  final int pendingPredictions;
  final bool hasEnoughData;
  final int minRequiredForReliableSummary;
  final RiskModelPerformanceBucket highRisk;
  final RiskModelPerformanceBucket mediumRisk;
  final RiskModelPerformanceBucket lowRisk;

  RiskModelPerformance({
    required this.totalPredictions,
    required this.resolvedPredictions,
    required this.pendingPredictions,
    required this.hasEnoughData,
    required this.minRequiredForReliableSummary,
    required this.highRisk,
    required this.mediumRisk,
    required this.lowRisk,
  });

  factory RiskModelPerformance.fromJson(Map<String, dynamic> json) {
    final high = json['high_risk'] as Map<String, dynamic>;
    final medium = json['medium_risk'] as Map<String, dynamic>;
    final low = json['low_risk'] as Map<String, dynamic>;

    return RiskModelPerformance(
      totalPredictions: json['total_predictions'] as int,
      resolvedPredictions: json['resolved_predictions'] as int,
      pendingPredictions: json['pending_predictions'] as int,
      hasEnoughData: json['has_enough_data'] as bool,
      minRequiredForReliableSummary:
          json['min_required_for_reliable_summary'] as int,
      highRisk: RiskModelPerformanceBucket(
        total: high['total'] as int,
        faulted: high['faulted'] as int?,
        ratePercent: (high['fault_rate_percent'] as num?)?.toDouble(),
      ),
      mediumRisk: RiskModelPerformanceBucket(
        total: medium['total'] as int,
        faulted: medium['faulted'] as int?,
        ratePercent: (medium['fault_rate_percent'] as num?)?.toDouble(),
      ),
      lowRisk: RiskModelPerformanceBucket(
        total: low['total'] as int,
        notFaulted: low['not_faulted'] as int?,
        ratePercent: (low['no_fault_rate_percent'] as num?)?.toDouble(),
      ),
    );
  }
}
