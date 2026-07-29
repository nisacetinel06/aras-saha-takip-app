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

  AssignedUser({required this.id, required this.name, required this.role});

  factory AssignedUser.fromJson(Map<String, dynamic> json) {
    return AssignedUser(
      id: json['id'] as int,
      name: json['name'] as String,
      role: json['role'] as String? ?? '',
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
  final String equipmentRef;
  // Modül 4 (Ekipman) ile gerçek bağlantı: bu iş emri bir ekipmana bağlıysa
  // equipment.id'ye giden değer — Ekipman Detay ekranına gitmek için kullanılır.
  final int? equipmentId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<WorkOrderPhoto> photos;

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
    required this.equipmentRef,
    this.equipmentId,
    required this.createdAt,
    required this.updatedAt,
    this.photos = const [],
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
      equipmentRef: json['equipment_ref'] as String? ?? '',
      equipmentId: json['equipment_id'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      photos: json['photos'] != null
          ? (json['photos'] as List)
              .map((p) => WorkOrderPhoto.fromJson(p as Map<String, dynamic>))
              .toList()
          : const [],
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
      'equipment_ref': equipmentRef,
      'equipment_id': equipmentId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
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
      equipmentRef: equipmentRef,
      equipmentId: equipmentId,
      createdAt: createdAt,
      updatedAt: updatedAt,
      photos: photos ?? this.photos,
    );
  }
}
