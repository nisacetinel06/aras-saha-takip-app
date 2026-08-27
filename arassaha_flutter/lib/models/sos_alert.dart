/// Acil Durum / SOS Bildirimi Modülü.
///
/// Sahada çalışan bir teknisyenin TEK dokunuşla mevcut konumunu ve bir acil
/// durum bildirimini dispeçer/yöneticilere göndermesi içindir. Backend'deki
/// `sos_alerts` tablosuyla birebir eşleşir (bkz. database.js, routes/sosAlerts.js).
library;

enum SosAlertStatus {
  aktif,
  onaylandi,
  kapatildi;

  static SosAlertStatus fromJson(String value) {
    switch (value) {
      case 'onaylandi':
        return SosAlertStatus.onaylandi;
      case 'kapatildi':
        return SosAlertStatus.kapatildi;
      default:
        return SosAlertStatus.aktif;
    }
  }
}

/// GET /api/sos-alerts yanıtındaki tek bir satır — teknisyen SADECE KENDİ
/// bildirimlerini, dispeçer/yönetici TÜM bildirimleri görür (bkz.
/// routes/sosAlerts.js GET /). `reporterName`/`reporterPhone`, backend'in
/// JOIN ile eklediği, dar bir güvenlik istisnasıdır (bkz. routes/sosAlerts.js
/// LIST_FIELDS notu) — "ilgili teknisyeni doğrudan aramak" ihtiyacı için;
/// teknisyen bu alanları yalnızca KENDİ adı/telefonu olarak görür.
class SosAlert {
  final int id;
  final double lat;
  final double lng;
  final String? note;
  final SosAlertStatus status;
  final DateTime createdAt;
  final int triggeredByUserId;
  final String reporterName;
  final String? reporterPhone;
  final DateTime? acknowledgedAt;
  final String? closedNote;
  final DateTime? closedAt;

  SosAlert({
    required this.id,
    required this.lat,
    required this.lng,
    this.note,
    required this.status,
    required this.createdAt,
    required this.triggeredByUserId,
    required this.reporterName,
    this.reporterPhone,
    this.acknowledgedAt,
    this.closedNote,
    this.closedAt,
  });

  bool get isActive => status == SosAlertStatus.aktif;

  factory SosAlert.fromJson(Map<String, dynamic> json) {
    return SosAlert(
      id: json['id'] as int,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      note: json['note'] as String?,
      status: SosAlertStatus.fromJson(json['status'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      triggeredByUserId: json['triggered_by_user_id'] as int,
      reporterName: json['triggered_by_name'] as String? ?? 'Bilinmiyor',
      reporterPhone: json['triggered_by_phone'] as String?,
      acknowledgedAt: json['acknowledged_at'] != null
          ? DateTime.parse(json['acknowledged_at'] as String)
          : null,
      closedNote: json['closed_note'] as String?,
      closedAt: json['closed_at'] != null
          ? DateTime.parse(json['closed_at'] as String)
          : null,
    );
  }

  SosAlert copyWith({
    SosAlertStatus? status,
    DateTime? acknowledgedAt,
    String? closedNote,
    DateTime? closedAt,
    String? note,
  }) {
    return SosAlert(
      id: id,
      lat: lat,
      lng: lng,
      note: note ?? this.note,
      status: status ?? this.status,
      createdAt: createdAt,
      triggeredByUserId: triggeredByUserId,
      reporterName: reporterName,
      reporterPhone: reporterPhone,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
      closedNote: closedNote ?? this.closedNote,
      closedAt: closedAt ?? this.closedAt,
    );
  }
}

/// GET /api/users/me/supervisor yanıtı — "Yöneticimi Ara" butonunun aradığı
/// numarayı taşır. `phone` null olabilir (dispeçer/yönetici telefonunu hiç
/// girmemişse) — bu durumda çağıran taraf sabit Acil Durum Hattı'na düşer
/// (bkz. utils/emergency_contact.dart).
class SupervisorContact {
  final int id;
  final String name;
  final String? phone;

  SupervisorContact({required this.id, required this.name, this.phone});

  factory SupervisorContact.fromJson(Map<String, dynamic> json) {
    return SupervisorContact(
      id: json['id'] as int,
      name: json['name'] as String,
      phone: json['phone'] as String?,
    );
  }
}
