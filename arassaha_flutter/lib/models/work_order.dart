import 'equipment.dart' show EquipmentType;

/// Kestirimci Bakım Planlama (Modül 12) — iş emrinin kökeni. Backend'deki
/// work_orders.source_type ile birebir eşleşir. `ariza`, Modül 12 öncesi
/// TÜM iş emirlerinin (ve normal "Yeni İş Emri Oluştur" akışının) varsayılan
/// değeridir; `onlecici_bakim`/`onleyici_bakim` yalnızca bir bakım önerisinden
/// "Önleyici İş Emri Oluştur" ile dönüştürülen kayıtlarda görülür.
enum WorkOrderSourceType {
  ariza,
  onleyiciBakim;

  static WorkOrderSourceType fromJson(String value) {
    return value == 'onleyici_bakim'
        ? WorkOrderSourceType.onleyiciBakim
        : WorkOrderSourceType.ariza;
  }
}

// İş emri statüsü. Backend'deki work_orders.status alanıyla birebir eşleşir.
enum WorkOrderStatus {
  acik,
  yolda,
  sahada,
  cozuldu;

  static WorkOrderStatus fromJson(String value) {
    return WorkOrderStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => WorkOrderStatus.acik,
    );
  }

  String toJson() => name;

  String get label {
    switch (this) {
      case WorkOrderStatus.acik:
        return 'Açık';
      case WorkOrderStatus.yolda:
        return 'Yolda';
      case WorkOrderStatus.sahada:
        return 'Sahada';
      case WorkOrderStatus.cozuldu:
        return 'Çözüldü';
    }
  }

  // Lineer akış: her statüden yalnızca bir sonraki adıma geçiş yapılabilir.
  WorkOrderStatus? get nextStatus {
    switch (this) {
      case WorkOrderStatus.acik:
        return WorkOrderStatus.yolda;
      case WorkOrderStatus.yolda:
        return WorkOrderStatus.sahada;
      case WorkOrderStatus.sahada:
        return WorkOrderStatus.cozuldu;
      case WorkOrderStatus.cozuldu:
        return null;
    }
  }
}

// İş emri önceliği. Backend'deki work_orders.priority alanıyla birebir eşleşir.
enum WorkOrderPriority {
  acil,
  normal,
  dusuk;

  static WorkOrderPriority fromJson(String value) {
    return WorkOrderPriority.values.firstWhere(
      (e) => e.name == value,
      orElse: () => WorkOrderPriority.normal,
    );
  }

  String toJson() => name;

  String get label {
    switch (this) {
      case WorkOrderPriority.acil:
        return 'Acil';
      case WorkOrderPriority.normal:
        return 'Normal';
      case WorkOrderPriority.dusuk:
        return 'Düşük';
    }
  }
}

// Bir iş emrine atanan gerçek kişi. Backend'deki `users` tablosundan gelir
// (bkz. ARCHITECTURE.md Bölüm 11.1) — hiçbir zaman sabit kodlanmış bir isim değildir.
class AssignedUser {
  final int id;
  final String name;
  final String role;

  /// Yalnızca yönetici için zenginleştirilmiş GET /api/users yanıtında
  /// dolu gelir (bkz. routes/users.js FULL_FIELDS) — Yöneticiden Çalışana
  /// Duyuru/Mesaj Sistemi'nin "Şu İldeki Herkes" kısayolu için (bkz.
  /// providers/manager_message_provider.dart). Diğer tüketicilerde (PICKER_FIELDS)
  /// her zaman null'dur.
  final String? il;

  AssignedUser({
    required this.id,
    required this.name,
    required this.role,
    this.il,
  });

  factory AssignedUser.fromJson(Map<String, dynamic> json) {
    return AssignedUser(
      id: json['id'] as int,
      name: json['name'] as String,
      role: json['role'] as String? ?? '',
      il: json['il'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'role': role};
}

class WorkOrderPhoto {
  final int id;
  final int workOrderId;
  final String photoPath;
  final DateTime createdAt;

  WorkOrderPhoto({
    required this.id,
    required this.workOrderId,
    required this.photoPath,
    required this.createdAt,
  });

  factory WorkOrderPhoto.fromJson(Map<String, dynamic> json) {
    return WorkOrderPhoto(
      id: json['id'] as int,
      workOrderId: json['work_order_id'] as int,
      photoPath: json['photo_path'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class WorkOrder {
  final int id;
  final String title;
  final String description;
  final WorkOrderStatus status;
  final WorkOrderPriority priority;
  final String locationName;
  final double lat;
  final double lng;
  final AssignedUser? assignedUser;
  // SEC-03 Kısım B — "bu işi bana kim verdi" şeffaflığı. Bu özellik
  // eklenmeden ÖNCE oluşturulmuş kayıtlarda backend bunu null döner (bkz.
  // routes/workOrders.js mapWorkOrderRow) — HER ZAMAN null-safe ele alınmalı,
  // asla "veri eksik" hatası olarak GÖSTERİLMEMELİ (bkz. work_order_detail_screen.dart).
  final AssignedUser? assignedByUser;
  final String equipmentRef;
  // Modül 4 (Ekipman) ile gerçek bağlantı: bu iş emri bir ekipmana bağlıysa
  // equipment.id'ye giden değer — Ekipman Detay ekranına gitmek için kullanılır.
  final int? equipmentId;
  // Bağlı ekipmanın tipi (JOIN ile gelir, bkz. routes/workOrders.js
  // SELECT_WORK_ORDER_WITH_USER) — iş emri detayında yalnızca QR kodu değil,
  // ekipman tipini de göstermek için (Modül 4 <-> Modül 1 iki yönlü bağlantı).
  final EquipmentType? equipmentType;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<WorkOrderPhoto> photos;
  // Kestirimci Bakım Planlama (Modül 12) — bkz. WorkOrderSourceType. Backend
  // eski (Modül 12 öncesi) kayıtları geriye dönük 'ariza' ile doldurduğu için
  // (bkz. database.js migrasyonu) bu alan HER ZAMAN doludur, null değildir.
  final WorkOrderSourceType sourceType;
  final int? sourceRecommendationId;

  WorkOrder({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    required this.locationName,
    required this.lat,
    required this.lng,
    required this.assignedUser,
    this.assignedByUser,
    required this.equipmentRef,
    this.equipmentId,
    this.equipmentType,
    required this.createdAt,
    required this.updatedAt,
    this.photos = const [],
    this.sourceType = WorkOrderSourceType.ariza,
    this.sourceRecommendationId,
  });

  factory WorkOrder.fromJson(Map<String, dynamic> json) {
    return WorkOrder(
      id: json['id'] as int,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      status: WorkOrderStatus.fromJson(json['status'] as String),
      priority: WorkOrderPriority.fromJson(json['priority'] as String),
      locationName: json['location_name'] as String? ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
      assignedUser: json['assigned_user'] != null
          ? AssignedUser.fromJson(json['assigned_user'] as Map<String, dynamic>)
          : null,
      assignedByUser: json['assigned_by_user'] != null
          ? AssignedUser.fromJson(json['assigned_by_user'] as Map<String, dynamic>)
          : null,
      equipmentRef: json['equipment_ref'] as String? ?? '',
      equipmentId: json['equipment_id'] as int?,
      equipmentType: json['equipment_type'] != null
          ? EquipmentType.fromJson(json['equipment_type'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      photos: json['photos'] != null
          ? (json['photos'] as List)
                .map((p) => WorkOrderPhoto.fromJson(p as Map<String, dynamic>))
                .toList()
          : const [],
      sourceType: WorkOrderSourceType.fromJson(
        json['source_type'] as String? ?? 'ariza',
      ),
      sourceRecommendationId: json['source_recommendation_id'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'status': status.toJson(),
      'priority': priority.toJson(),
      'location_name': locationName,
      'lat': lat,
      'lng': lng,
      'assigned_user': assignedUser?.toJson(),
      'assigned_by_user': assignedByUser?.toJson(),
      'equipment_ref': equipmentRef,
      'equipment_id': equipmentId,
      'equipment_type': equipmentType?.name,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      // Modül 17 (Okuma Önbelleği) — Kestirimci Bakım Planlama (Modül 12)
      // filtresinin (WorkOrderListProvider.onlyPreventiveMaintenance)
      // önbellekten yüklenen listelerde de doğru çalışması için source_type
      // AYRICA serileştirilir; yoksa fromJson bunu varsayılan 'ariza' kabul
      // ederdi (bkz. fromJson'daki `?? 'ariza'`).
      'source_type': sourceType == WorkOrderSourceType.onleyiciBakim
          ? 'onleyici_bakim'
          : 'ariza',
      'source_recommendation_id': sourceRecommendationId,
    };
  }

  WorkOrder copyWith({WorkOrderStatus? status, List<WorkOrderPhoto>? photos}) {
    return WorkOrder(
      id: id,
      title: title,
      description: description,
      status: status ?? this.status,
      priority: priority,
      locationName: locationName,
      lat: lat,
      lng: lng,
      assignedUser: assignedUser,
      assignedByUser: assignedByUser,
      equipmentRef: equipmentRef,
      equipmentId: equipmentId,
      equipmentType: equipmentType,
      createdAt: createdAt,
      updatedAt: updatedAt,
      photos: photos ?? this.photos,
      sourceType: sourceType,
      sourceRecommendationId: sourceRecommendationId,
    );
  }
}
