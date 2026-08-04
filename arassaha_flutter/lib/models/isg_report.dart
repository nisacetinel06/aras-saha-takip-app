import 'package:flutter/material.dart';
import 'work_order.dart' show AssignedUser;

/// İSG bildirim kategorisi. Backend'deki isg_reports.category ile birebir eşleşir.
enum IsgCategory {
  ekipmanArizasi,
  tehlikeliDurum,
  isKazasiRiski,
  diger;

  static IsgCategory fromJson(String value) {
    switch (value) {
      case 'ekipman_arizasi':
        return IsgCategory.ekipmanArizasi;
      case 'tehlikeli_durum':
        return IsgCategory.tehlikeliDurum;
      case 'is_kazasi_riski':
        return IsgCategory.isKazasiRiski;
      case 'diger':
        return IsgCategory.diger;
      default:
        return IsgCategory.diger;
    }
  }

  String toJson() {
    switch (this) {
      case IsgCategory.ekipmanArizasi:
        return 'ekipman_arizasi';
      case IsgCategory.tehlikeliDurum:
        return 'tehlikeli_durum';
      case IsgCategory.isKazasiRiski:
        return 'is_kazasi_riski';
      case IsgCategory.diger:
        return 'diger';
    }
  }

  String get label {
    switch (this) {
      case IsgCategory.ekipmanArizasi:
        return 'Ekipman Arızası';
      case IsgCategory.tehlikeliDurum:
        return 'Tehlikeli Durum';
      case IsgCategory.isKazasiRiski:
        return 'İş Kazası Riski';
      case IsgCategory.diger:
        return 'Diğer';
    }
  }

  IconData get icon {
    switch (this) {
      case IsgCategory.ekipmanArizasi:
        return Icons.build_outlined;
      case IsgCategory.tehlikeliDurum:
        return Icons.warning_amber_rounded;
      case IsgCategory.isKazasiRiski:
        return Icons.personal_injury_outlined;
      case IsgCategory.diger:
        return Icons.category_outlined;
    }
  }
}

/// İSG bildirim durumu. Backend'deki isg_reports.status ile birebir eşleşir.
enum IsgStatus {
  bekliyor,
  incelendi,
  cozuldu;

  static IsgStatus fromJson(String value) {
    return IsgStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => IsgStatus.bekliyor,
    );
  }

  String toJson() => name;

  String get label {
    switch (this) {
      case IsgStatus.bekliyor:
        return 'Bekliyor';
      case IsgStatus.incelendi:
        return 'İncelendi';
      case IsgStatus.cozuldu:
        return 'Çözüldü';
    }
  }

  // Lineer akış: bekliyor -> incelendi -> cozuldu (Modül 1'deki
  // WorkOrderStatus.nextStatus ile aynı desen — bkz. work_order.dart).
  IsgStatus? get nextStatus {
    switch (this) {
      case IsgStatus.bekliyor:
        return IsgStatus.incelendi;
      case IsgStatus.incelendi:
        return IsgStatus.cozuldu;
      case IsgStatus.cozuldu:
        return null;
    }
  }
}

/// İSG (İş Sağlığı ve Güvenliği) Bildirimi (Modül 5) — tek bir bildirim kaydı.
///
/// Bu modülde fotoğraf VE konum diğer modüllerden farklı olarak baştan
/// itibaren gerçektir: `photoPath` backend diskine gerçekten yazılmış bir
/// dosyaya işaret eder (work_order_photos ile aynı desen), `lat`/`lng` ise
/// cihazın gerçek GPS'inden (geolocator) okunmuş değerlerdir — sahte/varsayılan
/// koordinat asla gönderilmez.
class IsgReport {
  final int id;
  final AssignedUser? reportedBy;
  final String description;
  final IsgCategory category;
  final String? photoPath;
  final String? locationName;
  final double lat;
  final double lng;
  final IsgStatus status;
  final String? reviewerNote;
  final DateTime createdAt;
  final DateTime? reviewedAt;

  IsgReport({
    required this.id,
    required this.reportedBy,
    required this.description,
    required this.category,
    required this.photoPath,
    required this.locationName,
    required this.lat,
    required this.lng,
    required this.status,
    required this.reviewerNote,
    required this.createdAt,
    required this.reviewedAt,
  });

  factory IsgReport.fromJson(Map<String, dynamic> json) {
    return IsgReport(
      id: json['id'] as int,
      reportedBy: json['reported_by'] != null
          ? AssignedUser.fromJson(json['reported_by'] as Map<String, dynamic>)
          : null,
      description: json['description'] as String? ?? '',
      category: IsgCategory.fromJson(json['category'] as String),
      photoPath: json['photo_path'] as String?,
      locationName: json['location_name'] as String?,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      status: IsgStatus.fromJson(json['status'] as String),
      reviewerNote: json['reviewer_note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'] as String)
          : null,
    );
  }
}
