import 'equipment.dart';

/// Kayıp-Kaçak / Anormal Tüketim Tespiti (Modül 11) — GET
/// /api/equipment/:id/anomaly yanıtı: tek bir sayacın en güncel anomali skoru.
///
/// DÜRÜSTLÜK NOTU: Bu skoru üreten IsolationForest modeli, ArasSaha'nın
/// henüz gerçek bir AMI/akıllı sayaç okuma sistemi olmaması nedeniyle
/// SENTETİK (kural tabanlı üretilmiş) bir tüketim geçmişiyle eğitildi (bkz.
/// arassaha-ml/README.md). Model eğitimi ve servis entegrasyonu gerçektir;
/// yalnızca eğitim verisi sentetiktir.
class MeterAnomaly {
  final int equipmentId;
  final int anomalyScore;
  final bool isSuspicious;
  final String? detectedReason;
  final DateTime computedAt;

  MeterAnomaly({
    required this.equipmentId,
    required this.anomalyScore,
    required this.isSuspicious,
    required this.detectedReason,
    required this.computedAt,
  });

  factory MeterAnomaly.fromJson(Map<String, dynamic> json) {
    return MeterAnomaly(
      equipmentId: json['equipment_id'] as int,
      anomalyScore: json['anomaly_score'] as int,
      isSuspicious: (json['is_suspicious'] as num) == 1 || json['is_suspicious'] == true,
      detectedReason: json['detected_reason'] as String?,
      computedAt: DateTime.parse(json['computed_at'] as String),
    );
  }
}

/// GET /api/meters/suspicious içindeki tek bir satır — Şüpheli Sayaçlar
/// listesi için ekipman bilgisi + anomali skoru + kural tabanlı gerekçeyi bir
/// arada taşır. RiskyEquipmentSummary (Modül 9) ile AYNI amaçlı ama farklı
/// bir yapı: burada `detectedReason`, kullanıcıya somut bir gerekçe sunduğu
/// için modülün en değerli alanıdır.
class SuspiciousMeterSummary {
  final int id;
  final String qrCode;
  final EquipmentType equipmentType;
  final String locationName;
  final EquipmentStatus status;
  final int anomalyScore;
  final bool isSuspicious;
  final String? detectedReason;

  SuspiciousMeterSummary({
    required this.id,
    required this.qrCode,
    required this.equipmentType,
    required this.locationName,
    required this.status,
    required this.anomalyScore,
    required this.isSuspicious,
    required this.detectedReason,
  });

  factory SuspiciousMeterSummary.fromJson(Map<String, dynamic> json) {
    return SuspiciousMeterSummary(
      id: json['id'] as int,
      qrCode: json['qr_code'] as String,
      equipmentType: EquipmentType.fromJson(json['equipment_type'] as String),
      locationName: json['location_name'] as String? ?? '',
      status: EquipmentStatus.fromJson(json['status'] as String),
      anomalyScore: json['anomaly_score'] as int,
      isSuspicious: (json['is_suspicious'] as num) == 1 || json['is_suspicious'] == true,
      detectedReason: json['detected_reason'] as String?,
    );
  }
}

/// GET /api/equipment/:id/consumption içindeki tek bir ay — Ekipman
/// Detayı'ndaki tüketim grafiği (fl_chart) için ham veri noktası.
class MeterConsumptionEntry {
  final String yearMonth;
  final double consumptionKwh;

  MeterConsumptionEntry({required this.yearMonth, required this.consumptionKwh});

  factory MeterConsumptionEntry.fromJson(Map<String, dynamic> json) {
    return MeterConsumptionEntry(
      yearMonth: json['year_month'] as String,
      consumptionKwh: (json['consumption_kwh'] as num).toDouble(),
    );
  }
}
