import 'package:flutter/material.dart';
import 'work_order.dart' show AssignedUser;

/// Öneri/şikayet kategorisi. Backend'deki feedback_items.category ile
/// birebir eşleşir — models/isg_report.dart IsgCategory ile AYNI desen.
enum FeedbackCategory {
  oneri,
  sikayet,
  diger;

  static FeedbackCategory fromJson(String value) {
    return FeedbackCategory.values.firstWhere(
      (e) => e.name == value,
      orElse: () => FeedbackCategory.diger,
    );
  }

  String toJson() => name;

  String get label {
    switch (this) {
      case FeedbackCategory.oneri:
        return 'Öneri';
      case FeedbackCategory.sikayet:
        return 'Şikayet';
      case FeedbackCategory.diger:
        return 'Diğer';
    }
  }

  IconData get icon {
    switch (this) {
      case FeedbackCategory.oneri:
        return Icons.lightbulb_outline;
      case FeedbackCategory.sikayet:
        return Icons.report_problem_outlined;
      case FeedbackCategory.diger:
        return Icons.category_outlined;
    }
  }
}

/// Öneri/şikayet durumu. Backend'deki feedback_items.status ile birebir
/// eşleşir — models/isg_report.dart IsgStatus ile AYNI desen, yalnızca son
/// aşamanın adı farklı ('cozuldu' değil 'kapatildi').
enum FeedbackStatus {
  bekliyor,
  incelendi,
  kapatildi;

  static FeedbackStatus fromJson(String value) {
    return FeedbackStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => FeedbackStatus.bekliyor,
    );
  }

  String toJson() => name;

  String get label {
    switch (this) {
      case FeedbackStatus.bekliyor:
        return 'Bekliyor';
      case FeedbackStatus.incelendi:
        return 'İncelendi';
      case FeedbackStatus.kapatildi:
        return 'Kapatıldı';
    }
  }

  // Lineer akış: bekliyor -> incelendi -> kapatildi — IsgStatus.nextStatus
  // ile AYNI desen (bkz. models/isg_report.dart).
  FeedbackStatus? get nextStatus {
    switch (this) {
      case FeedbackStatus.bekliyor:
        return FeedbackStatus.incelendi;
      case FeedbackStatus.incelendi:
        return FeedbackStatus.kapatildi;
      case FeedbackStatus.kapatildi:
        return null;
    }
  }
}

/// Öneri / Şikayet Kutusu (Modül 17) — tek bir bildirim kaydı.
///
/// Anonim Gönderim dengesi (bkz. routes/feedback.js dosya başı notu):
/// backend, is_anonymous=true olan kayıtlarda gerçek göndereni veritabanında
/// saklamaya devam eder ama response'ta HERKESTEN (yöneticiden dahi) gizler
/// — bu yüzden [submittedBy], anonim bir bildirimde HER ZAMAN null gelir;
/// Flutter tarafı bunu asla "Bilinmiyor" değil, bilinçli olarak "Anonim
/// Kullanıcı" olarak göstermelidir (bkz. feedback_list_screen.dart).
class FeedbackItem {
  final int id;
  final AssignedUser? submittedBy;
  final FeedbackCategory category;
  final String description;
  final String? photoPath;
  final bool isAnonymous;
  final FeedbackStatus status;
  final String? reviewerNote;
  final AssignedUser? reviewedBy;
  final DateTime createdAt;
  final DateTime? reviewedAt;

  FeedbackItem({
    required this.id,
    required this.submittedBy,
    required this.category,
    required this.description,
    required this.photoPath,
    required this.isAnonymous,
    required this.status,
    required this.reviewerNote,
    required this.reviewedBy,
    required this.createdAt,
    required this.reviewedAt,
  });

  factory FeedbackItem.fromJson(Map<String, dynamic> json) {
    return FeedbackItem(
      id: json['id'] as int,
      submittedBy: json['submitted_by'] != null
          ? AssignedUser.fromJson(json['submitted_by'] as Map<String, dynamic>)
          : null,
      category: FeedbackCategory.fromJson(json['category'] as String),
      description: json['description'] as String? ?? '',
      photoPath: json['photo_path'] as String?,
      isAnonymous: json['is_anonymous'] as bool? ?? false,
      status: FeedbackStatus.fromJson(json['status'] as String),
      reviewerNote: json['reviewer_note'] as String?,
      reviewedBy: json['reviewed_by'] != null
          ? AssignedUser.fromJson(json['reviewed_by'] as Map<String, dynamic>)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'] as String)
          : null,
    );
  }
}
