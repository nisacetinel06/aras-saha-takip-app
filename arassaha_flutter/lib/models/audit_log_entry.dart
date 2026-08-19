import 'package:flutter/material.dart';

/// GET /api/audit-log'un `category` alanı — backend'deki services/
/// auditLogAggregator.js VALID_CATEGORIES ile birebir eşleşir.
enum AuditLogCategory {
  giris,
  kullaniciYonetimi,
  cihazYonetimi,
  stok,
  kvkk,
  dosyaTemizleme;

  String toJson() {
    switch (this) {
      case AuditLogCategory.giris:
        return 'giris';
      case AuditLogCategory.kullaniciYonetimi:
        return 'kullanici_yonetimi';
      case AuditLogCategory.cihazYonetimi:
        return 'cihaz_yonetimi';
      case AuditLogCategory.stok:
        return 'stok';
      case AuditLogCategory.kvkk:
        return 'kvkk';
      case AuditLogCategory.dosyaTemizleme:
        return 'dosya_temizleme';
    }
  }

  static AuditLogCategory? fromJson(String? value) {
    switch (value) {
      case 'giris':
        return AuditLogCategory.giris;
      case 'kullanici_yonetimi':
        return AuditLogCategory.kullaniciYonetimi;
      case 'cihaz_yonetimi':
        return AuditLogCategory.cihazYonetimi;
      case 'stok':
        return AuditLogCategory.stok;
      case 'kvkk':
        return AuditLogCategory.kvkk;
      case 'dosya_temizleme':
        return AuditLogCategory.dosyaTemizleme;
      default:
        return null;
    }
  }

  String get label {
    switch (this) {
      case AuditLogCategory.giris:
        return 'Giriş';
      case AuditLogCategory.kullaniciYonetimi:
        return 'Kullanıcı Yönetimi';
      case AuditLogCategory.cihazYonetimi:
        return 'Cihaz Yönetimi';
      case AuditLogCategory.stok:
        return 'Stok';
      case AuditLogCategory.kvkk:
        return 'KVKK';
      case AuditLogCategory.dosyaTemizleme:
        return 'Dosya Temizleme';
    }
  }

  IconData get icon {
    switch (this) {
      case AuditLogCategory.giris:
        return Icons.lock_outline;
      case AuditLogCategory.kullaniciYonetimi:
        return Icons.person_outline;
      case AuditLogCategory.cihazYonetimi:
        return Icons.phonelink_lock_outlined;
      case AuditLogCategory.stok:
        return Icons.inventory_2_outlined;
      case AuditLogCategory.kvkk:
        return Icons.privacy_tip_outlined;
      case AuditLogCategory.dosyaTemizleme:
        return Icons.auto_delete_outlined;
    }
  }
}

/// Denetim Logu Paneli (bkz. screens/admin/audit_log_screen.dart) — 6 farklı
/// kaynak tablonun (backend'de services/auditLogAggregator.js tarafından)
/// ortak bir şekle normalize edilmiş TEK bir kaydı.
class AuditLogEntry {
  final DateTime timestamp;
  final int? actorId;
  final String actorName;
  // `category` backend'in TANIDIĞI bir değerse dolu; boş/yeni bir kategori
  // gelirse (ileride eklenebilecek bir kaynak) null kalır — UI bu durumda
  // genel/nötr bir ikon ve `categoryRaw` metnini gösterir, ÇÖKMEZ.
  final AuditLogCategory? category;
  final String categoryRaw;
  final String actionType;
  final String description;

  AuditLogEntry({
    required this.timestamp,
    this.actorId,
    required this.actorName,
    required this.category,
    required this.categoryRaw,
    required this.actionType,
    required this.description,
  });

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) {
    final categoryRaw = json['category'] as String? ?? '';
    return AuditLogEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
      actorId: json['actor_id'] as int?,
      actorName: json['actor_name'] as String? ?? 'Bilinmiyor',
      category: AuditLogCategory.fromJson(categoryRaw),
      categoryRaw: categoryRaw,
      actionType: json['action_type'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }

  /// Güvenlik açısından dikkat çekici bir olay mı — bkz. audit_log_screen.dart
  /// sol kenar vurgusu (yönetici sayfayı hızlıca tararken şüpheli girişleri
  /// fark edebilsin, bkz. görev talimatı). Şu an yalnızca başarısız giriş
  /// denemesi bu vurguyu tetikler.
  bool get isSecurityAlert => actionType == 'giris_basarisiz';
}

/// GET /api/audit-log'un TAM yanıtı — sayfalama bilgisiyle birlikte.
class AuditLogPage {
  final List<AuditLogEntry> entries;
  final int totalCount;
  final int page;
  final bool hasMore;

  AuditLogPage({
    required this.entries,
    required this.totalCount,
    required this.page,
    required this.hasMore,
  });

  factory AuditLogPage.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'] as List<dynamic>? ?? [];
    return AuditLogPage(
      entries: rawEntries
          .map((e) => AuditLogEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalCount: json['total_count'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      hasMore: json['has_more'] as bool? ?? false,
    );
  }
}
