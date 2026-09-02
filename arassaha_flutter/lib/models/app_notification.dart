import 'package:flutter/material.dart';

/// İlgili kaydın türü. Backend'deki notifications.related_type alanıyla
/// birebir eşleşir — Bildirimler ekranında ikon seçimi ve tıklanınca hangi
/// detay ekranına gidileceği bu türe göre belirlenir.
enum NotificationRelatedType {
  workOrder,
  isgReport,
  equipment,
  managerMessage,
  sosAlert,
  passwordResetRequest;

  static NotificationRelatedType fromJson(String value) {
    switch (value) {
      case 'work_order':
        return NotificationRelatedType.workOrder;
      case 'isg_report':
        return NotificationRelatedType.isgReport;
      case 'equipment':
        return NotificationRelatedType.equipment;
      case 'manager_message':
        return NotificationRelatedType.managerMessage;
      case 'sos_alert':
        return NotificationRelatedType.sosAlert;
      case 'password_reset_request':
        return NotificationRelatedType.passwordResetRequest;
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
      case NotificationRelatedType.managerMessage:
        return Icons.mail_outline;
      case NotificationRelatedType.sosAlert:
        return Icons.sos_outlined;
      case NotificationRelatedType.passwordResetRequest:
        return Icons.lock_reset_outlined;
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
      relatedType: NotificationRelatedType.fromJson(
        json['related_type'] as String,
      ),
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

  static const _relatedTypeApiValues = {
    NotificationRelatedType.workOrder: 'work_order',
    NotificationRelatedType.isgReport: 'isg_report',
    NotificationRelatedType.equipment: 'equipment',
    NotificationRelatedType.managerMessage: 'manager_message',
    NotificationRelatedType.sosAlert: 'sos_alert',
    NotificationRelatedType.passwordResetRequest: 'password_reset_request',
  };

  /// Ayarlar ve Çevrimdışı Mod (Modül 17) — Okuma Önbelleği için: NotificationProvider
  /// bir liste çektiğinde bu şekli `CacheService.set` ile saklar, bağlantı
  /// koptuğunda `fromJson` ile AYNI şekli geri okuyup listeyi yeniden kurar.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'message': message,
      'related_type': _relatedTypeApiValues[relatedType],
      'related_id': relatedId,
      'is_read': isRead,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
