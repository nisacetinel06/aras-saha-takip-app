import 'package:flutter/material.dart';
import 'equipment.dart' show EquipmentType;

/// Stok miktarları REAL (double) tutulur ("metre"/"kg" gibi kesirli birimler
/// için) ama çoğu değer aslında tam sayı ("22 adet") — bu yüzden ".0" son
/// ekini yalnızca gerçekten kesirliyse gösterir (örn. "22" ama "22.5 metre").
String formatMaterialQuantity(double value) {
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
}

/// Malzeme kategorisi. Backend'deki materials.category ile birebir eşleşir.
enum MaterialCategory {
  kablo,
  sigorta,
  izolator,
  konnektor,
  diger;

  static MaterialCategory fromJson(String value) {
    return MaterialCategory.values.firstWhere(
      (e) => e.name == value,
      orElse: () => MaterialCategory.diger,
    );
  }

  String toJson() => name;

  String get label {
    switch (this) {
      case MaterialCategory.kablo:
        return 'Kablo';
      case MaterialCategory.sigorta:
        return 'Sigorta';
      case MaterialCategory.izolator:
        return 'İzolatör';
      case MaterialCategory.konnektor:
        return 'Konnektör';
      case MaterialCategory.diger:
        return 'Diğer';
    }
  }

  IconData get icon {
    switch (this) {
      case MaterialCategory.kablo:
        return Icons.cable;
      case MaterialCategory.sigorta:
        return Icons.electric_bolt;
      case MaterialCategory.izolator:
        return Icons.bolt;
      case MaterialCategory.konnektor:
        return Icons.settings_input_component;
      case MaterialCategory.diger:
        return Icons.inventory_2_outlined;
    }
  }
}

/// Ölçü birimi. Backend'deki materials.unit ile birebir eşleşir.
enum MaterialUnit {
  adet,
  metre,
  kg;

  static MaterialUnit fromJson(String value) {
    return MaterialUnit.values.firstWhere(
      (e) => e.name == value,
      orElse: () => MaterialUnit.adet,
    );
  }

  String toJson() => name;

  String get label => name;
}

/// Malzeme / Yedek Parça Stok Takibi (Modül 13) — tek bir malzeme tipi.
///
/// `compatibleEquipmentTypes`: bu malzemenin TİPİK olarak hangi ekipman
/// tipleriyle kullanıldığı — bir kısıt/zorunluluk DEĞİL, yalnızca
/// [MaterialPickerField]'ın arama sonuçlarını akıllı sıralaması için bir
/// ipucu (bkz. widgets/material_picker_field.dart).
class MaterialItem {
  final int id;
  final String name;
  final MaterialCategory category;
  final MaterialUnit unit;
  final double stockQuantity;
  final double minStockThreshold;
  final List<EquipmentType> compatibleEquipmentTypes;
  final double? unitCost;
  final DateTime createdAt;

  MaterialItem({
    required this.id,
    required this.name,
    required this.category,
    required this.unit,
    required this.stockQuantity,
    required this.minStockThreshold,
    required this.compatibleEquipmentTypes,
    required this.unitCost,
    required this.createdAt,
  });

  bool get isLowStock => stockQuantity <= minStockThreshold;

  factory MaterialItem.fromJson(Map<String, dynamic> json) {
    return MaterialItem(
      id: json['id'] as int,
      name: json['name'] as String,
      category: MaterialCategory.fromJson(json['category'] as String),
      unit: MaterialUnit.fromJson(json['unit'] as String),
      stockQuantity: (json['stock_quantity'] as num).toDouble(),
      minStockThreshold: (json['min_stock_threshold'] as num).toDouble(),
      compatibleEquipmentTypes:
          (json['compatible_equipment_types'] as List<dynamic>? ?? [])
              .map((t) => EquipmentType.fromJson(t as String))
              .toList(),
      unitCost: (json['unit_cost'] as num?)?.toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// GET /api/materials/:id yanıtındaki `usage_history` — bu malzemenin hangi
/// iş emrinde, ne zaman, kim tarafından ne kadar kullanıldığı.
class MaterialUsageHistoryEntry {
  final int id;
  final int workOrderId;
  final String workOrderTitle;
  final double quantityUsed;
  final int recordedById;
  final String recordedByName;
  final DateTime createdAt;

  MaterialUsageHistoryEntry({
    required this.id,
    required this.workOrderId,
    required this.workOrderTitle,
    required this.quantityUsed,
    required this.recordedById,
    required this.recordedByName,
    required this.createdAt,
  });

  factory MaterialUsageHistoryEntry.fromJson(Map<String, dynamic> json) {
    return MaterialUsageHistoryEntry(
      id: json['id'] as int,
      workOrderId: json['work_order_id'] as int,
      workOrderTitle: json['work_order_title'] as String,
      quantityUsed: (json['quantity_used'] as num).toDouble(),
      recordedById: json['recorded_by_id'] as int,
      recordedByName: json['recorded_by_name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// Stok hareketi türü. Backend'deki material_stock_movements.movement_type ile
/// birebir eşleşir. 'iade', saf bir 'kullanim' (stok azaltmaz) ya da saf bir
/// 'ikmal' (gerçek bir depo girişi değil) OLMADIĞI için üçüncü, ayrı bir tür
/// olarak tutulur — hatalı girilmiş bir kullanım kaydının geri alınmasını
/// temsil eder (bkz. routes/materials.js DELETE /workorders/:id/materials/:usageId).
enum MaterialMovementType {
  kullanim,
  ikmal,
  iade;

  static MaterialMovementType fromJson(String value) {
    return MaterialMovementType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => MaterialMovementType.kullanim,
    );
  }
}

/// GET /api/materials/:id yanıtındaki `stock_movements` — Cihaz Yönetimi/
/// Kullanıcı Yönetimi'ndeki "işlem geçmişi" ile AYNI desen.
class MaterialStockMovement {
  final int id;
  final MaterialMovementType movementType;
  final double quantity;
  final int? relatedWorkOrderId;
  final String performedByName;
  final DateTime createdAt;

  MaterialStockMovement({
    required this.id,
    required this.movementType,
    required this.quantity,
    required this.relatedWorkOrderId,
    required this.performedByName,
    required this.createdAt,
  });

  factory MaterialStockMovement.fromJson(Map<String, dynamic> json) {
    return MaterialStockMovement(
      id: json['id'] as int,
      movementType: MaterialMovementType.fromJson(
        json['movement_type'] as String,
      ),
      quantity: (json['quantity'] as num).toDouble(),
      relatedWorkOrderId: json['related_work_order_id'] as int?,
      performedByName: json['performed_by_name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// GET /api/materials/:id yanıtı — MaterialItem + kullanım geçmişi + stok hareketi geçmişi.
class MaterialDetail {
  final MaterialItem material;
  final List<MaterialUsageHistoryEntry> usageHistory;
  final List<MaterialStockMovement> stockMovements;

  MaterialDetail({
    required this.material,
    required this.usageHistory,
    required this.stockMovements,
  });

  factory MaterialDetail.fromJson(Map<String, dynamic> json) {
    return MaterialDetail(
      material: MaterialItem.fromJson(json),
      usageHistory: (json['usage_history'] as List<dynamic>? ?? [])
          .map(
            (e) =>
                MaterialUsageHistoryEntry.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      stockMovements: (json['stock_movements'] as List<dynamic>? ?? [])
          .map((e) => MaterialStockMovement.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Bir iş emrinde kullanılan tek bir malzeme kaydı. GET
/// /api/workorders/:id/materials listesinde VE POST'un başarı yanıtında
/// AYNI şekilde gömülü `material`/`recorded_by` nesneleriyle gelir.
class WorkOrderMaterialUsage {
  final int id;
  final int workOrderId;
  final double quantityUsed;
  final DateTime createdAt;
  final int materialId;
  final String materialName;
  final MaterialUnit materialUnit;
  final int recordedById;
  final String recordedByName;

  WorkOrderMaterialUsage({
    required this.id,
    required this.workOrderId,
    required this.quantityUsed,
    required this.createdAt,
    required this.materialId,
    required this.materialName,
    required this.materialUnit,
    required this.recordedById,
    required this.recordedByName,
  });

  factory WorkOrderMaterialUsage.fromJson(Map<String, dynamic> json) {
    final material = json['material'] as Map<String, dynamic>;
    final recordedBy = json['recorded_by'] as Map<String, dynamic>;
    return WorkOrderMaterialUsage(
      id: json['id'] as int,
      workOrderId: json['work_order_id'] as int,
      quantityUsed: (json['quantity_used'] as num).toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
      materialId: material['id'] as int,
      materialName: material['name'] as String,
      materialUnit: MaterialUnit.fromJson(material['unit'] as String),
      recordedById: recordedBy['id'] as int,
      recordedByName: recordedBy['name'] as String,
    );
  }
}
