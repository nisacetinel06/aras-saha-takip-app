import 'work_order.dart';

/// Harita ekranı için hafif iş emri verisi. GET /api/workorders/map
/// endpoint'inin döndürdüğü alanlarla birebir eşleşir; WorkOrder'daki diğer
/// zorunlu alanları (description, assigned_user, photos vb.) taşımaz.
class WorkOrderMapPin {
  final int id;
  final String title;
  final WorkOrderStatus status;
  final WorkOrderPriority priority;
  final double lat;
  final double lng;
  // Modül 4 (Ekipman) ile bağlantı: pin bir ekipmana bağlıysa harita bilgi
  // balonunda "Ekipman Detayını Gör" bağlantısı gösterilebilsin diye taşınır.
  final int? equipmentId;

  WorkOrderMapPin({
    required this.id,
    required this.title,
    required this.status,
    required this.priority,
    required this.lat,
    required this.lng,
    this.equipmentId,
  });

  factory WorkOrderMapPin.fromJson(Map<String, dynamic> json) {
    return WorkOrderMapPin(
      id: json['id'] as int,
      title: json['title'] as String,
      status: WorkOrderStatus.fromJson(json['status'] as String),
      priority: WorkOrderPriority.fromJson(json['priority'] as String),
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      equipmentId: json['equipment_id'] as int?,
    );
  }
}
