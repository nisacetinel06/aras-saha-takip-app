import 'package:flutter/material.dart';

/// İlgili kaydın türü. Backend'deki notifications.related_type alanıyla
/// birebir eşleşir — Bildirimler ekranında ikon seçimi ve tıklanınca hangi
/// detay ekranına gidileceği bu türe göre belirlenir.
enum NotificationRelatedType {
  workOrder,
  isgReport,
  equipment;

  static NotificationRelatedType fromJson(String value) {
    switch (value) {
      case 'work_order':
        return NotificationRelatedType.workOrder;
      case 'isg_report':
        return NotificationRelatedType.isgReport;
      case 'equipment':
        return NotificationRelatedType.equipment;
      default:
        return NotificationRelatedType.workOrder;
    }
  }

  IconData get icon {
    switch (this) {
      case NotificationRelatedType.workOrder:
        return Icons.assignment_outlined;
      case NotificationRelatedType.isgReport:
        return Icons.shield_outlined;
      case NotificationRelatedType.equipment:
        return Icons.inventory_2_outlined;
    }
  }
}

/// Bildirim Sistemi (Modül 6) — tek bir bildirim kaydı.
///
/// Bu veri gerçek bir push (FCM vb.) altyapısından DEĞİL, backend'in
/// `notifications` tablosundan gelir; Flutter tarafı bunu periyodik olarak
/// (bkz. NotificationProvider.startPolling) yoklar. Bkz. ARCHITECTURE.md.
class AppNotification {
  final int id;
  final String message;
  final NotificationRelatedType relatedType;
  final int relatedId;
  final bool isRead;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.message,
    required this.relatedType,
    required this.relatedId,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as int,
      message: json['message'] as String,
      relatedType: NotificationRelatedType.fromJson(json['related_type'] as String),
      relatedId: json['related_id'] as int,
      isRead: json['is_read'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      message: message,
      relatedType: relatedType,
      relatedId: relatedId,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }
}
