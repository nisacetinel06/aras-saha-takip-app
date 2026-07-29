import 'package:flutter/material.dart';
import 'work_order.dart' show WorkOrderStatus, WorkOrderPriority;

/// Ekipman türü. Backend'deki equipment.equipment_type ile birebir eşleşir.
enum EquipmentType {
  trafo,
  direk,
  kesici,
  sayac;

  static EquipmentType fromJson(String value) {
    return EquipmentType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => EquipmentType.trafo,
    );
  }

  String get label {
    switch (this) {
      case EquipmentType.trafo:
        return 'Trafo';
      case EquipmentType.direk:
        return 'Direk';
      case EquipmentType.kesici:
        return 'Kesici';
      case EquipmentType.sayac:
        return 'Sayaç';
    }
  }

  IconData get icon {
    switch (this) {
      case EquipmentType.trafo:
        return Icons.electrical_services;
      case EquipmentType.direk:
        return Icons.cell_tower;
      case EquipmentType.kesici:
        return Icons.power_settings_new;
      case EquipmentType.sayac:
        return Icons.speed;
    }
  }
}

/// Ekipman durumu. Backend'deki equipment.status ile birebir eşleşir.
enum EquipmentStatus {
  aktif,
  bakimda,
  devreDisi;

  static EquipmentStatus fromJson(String value) {
    switch (value) {
      case 'aktif':
        return EquipmentStatus.aktif;
      case 'bakimda':
        return EquipmentStatus.bakimda;
      case 'devre_disi':
        return EquipmentStatus.devreDisi;
      default:
        return EquipmentStatus.aktif;
    }
  }

  String get label {
    switch (this) {
      case EquipmentStatus.aktif:
        return 'Aktif';
      case EquipmentStatus.bakimda:
        return 'Bakımda';
      case EquipmentStatus.devreDisi:
        return 'Devre Dışı';
    }
  }

  /// Backend'in beklediği değer (`devreDisi` -> `devre_disi`); diğerleri `name` ile aynı.
  String get apiValue => this == EquipmentStatus.devreDisi ? 'devre_disi' : name;
}

/// Bir ekipmana bağlı geçmiş iş emri (arıza) kaydı — GET
/// /api/equipment/:id/history endpointi'nin döndürdüğü hafif alan seti.
/// Modül 1'in tam WorkOrder modelini taşımaz; kayda tıklanınca
/// WorkOrderDetailScreen kendi detayını backend'den ayrıca çeker.
class EquipmentHistoryEntry {
  final int id;
  final String title;
  final WorkOrderStatus status;
  final WorkOrderPriority priority;
  final DateTime createdAt;
  final DateTime updatedAt;

  EquipmentHistoryEntry({
    required this.id,
    required this.title,
    required this.status,
    required this.priority,
    required this.createdAt,
    required this.updatedAt,
  });

  factory EquipmentHistoryEntry.fromJson(Map<String, dynamic> json) {
    return EquipmentHistoryEntry(
      id: json['id'] as int,
      title: json['title'] as String,
      status: WorkOrderStatus.fromJson(json['status'] as String),
      priority: WorkOrderPriority.fromJson(json['priority'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

/// Ekipman / Envanter (Modül 4) — sahadaki tek bir ekipman kaydı (trafo,
/// direk, kesici, sayaç).
///
/// ÖNEMLİ (ML notu): `installDate`, `lastMaintenanceDate` ve bu ekipmana bağlı
/// geçmiş iş emri SAYISI (equipment/:id/history'nin uzunluğu), ileride
/// eklenecek Arıza Risk Tahmini modülünün girdi/feature'ları olacaktır
/// ("ekipman yaşı", "son bakımdan bu yana geçen süre", "geçmiş arıza sıklığı"
/// gibi özellikler buradan türetilir). Bu yüzden bu alanlar bugün yalnızca
/// envanter görüntülemek için kullanılıyor olsa da şemadan çıkarılmamalıdır.
class Equipment {
  final int id;
  final String qrCode;
  final EquipmentType equipmentType;
  final String locationName;
  final double lat;
  final double lng;
  final DateTime? installDate;
  final DateTime? lastMaintenanceDate;
  final String manufacturer;
  final String? capacityInfo;
  final EquipmentStatus status;
  final DateTime createdAt;

  Equipment({
    required this.id,
    required this.qrCode,
    required this.equipmentType,
    required this.locationName,
    required this.lat,
    required this.lng,
    required this.installDate,
    required this.lastMaintenanceDate,
    required this.manufacturer,
    required this.capacityInfo,
    required this.status,
    required this.createdAt,
  });

  factory Equipment.fromJson(Map<String, dynamic> json) {
    return Equipment(
      id: json['id'] as int,
      qrCode: json['qr_code'] as String,
      equipmentType: EquipmentType.fromJson(json['equipment_type'] as String),
      locationName: json['location_name'] as String? ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
      installDate: json['install_date'] != null ? DateTime.parse(json['install_date'] as String) : null,
      lastMaintenanceDate:
          json['last_maintenance_date'] != null ? DateTime.parse(json['last_maintenance_date'] as String) : null,
      manufacturer: json['manufacturer'] as String? ?? '',
      capacityInfo: json['capacity_info'] as String?,
      status: EquipmentStatus.fromJson(json['status'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
