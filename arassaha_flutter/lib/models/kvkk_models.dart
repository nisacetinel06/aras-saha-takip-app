/// KVKK Uyum Modülü — bkz. routes/kvkk.js. GET /api/kvkk/my-data-summary
/// yanıtı: kullanıcının kendi verisinin SAYISAL özeti ("sistemde benim
/// hakkımda ne var?") — tüm iş emri/İSG detaylarını değil, yalnızca sayıları
/// taşır (bkz. my_data_screen.dart).
class KvkkDataSummary {
  final String profileName;
  final String profileSicilNo;
  final String? profilePhone;
  final String? profileEmail;
  final bool hasPhoto;
  final int submittedIsgReportsCount;
  final int assignedWorkOrdersCount;
  final int uploadedPhotosCount;

  KvkkDataSummary({
    required this.profileName,
    required this.profileSicilNo,
    this.profilePhone,
    this.profileEmail,
    required this.hasPhoto,
    required this.submittedIsgReportsCount,
    required this.assignedWorkOrdersCount,
    required this.uploadedPhotosCount,
  });

  factory KvkkDataSummary.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'] as Map<String, dynamic>;
    return KvkkDataSummary(
      profileName: profile['name'] as String? ?? '',
      profileSicilNo: profile['sicil_no'] as String? ?? '',
      profilePhone: profile['phone'] as String?,
      profileEmail: profile['email'] as String?,
      hasPhoto: profile['has_photo'] as bool? ?? false,
      submittedIsgReportsCount:
          json['submitted_isg_reports_count'] as int? ?? 0,
      assignedWorkOrdersCount: json['assigned_work_orders_count'] as int? ?? 0,
      uploadedPhotosCount: json['uploaded_photos_count'] as int? ?? 0,
    );
  }
}

/// data_deletion_requests.request_type — bkz. routes/kvkk.js VALID_REQUEST_TYPES.
///
/// KAVRAMSAL AYRIM (bkz. routes/kvkk.js dosya başı): [profilFotografiSil]
/// yalnızca profil fotoğrafını temizler; [tumKisiselVerileriSil] kimlik
/// bilgilerini (ad/telefon/e-posta/fotoğraf) ANONİMLEŞTİRİR ve hesabı
/// pasifleştirir — ama iş emri/İSG bildirimi KAYITLARININ KENDİSİNİ SİLMEZ,
/// bunlar denetim amaçlı saklanması gerekebilecek operasyonel kayıtlardır.
enum KvkkRequestType {
  profilFotografiSil,
  tumKisiselVerileriSil;

  String toJson() {
    switch (this) {
      case KvkkRequestType.profilFotografiSil:
        return 'profil_fotografi_sil';
      case KvkkRequestType.tumKisiselVerileriSil:
        return 'tum_kisisel_verilerimi_sil';
    }
  }

  static KvkkRequestType fromJson(String value) {
    switch (value) {
      case 'tum_kisisel_verilerimi_sil':
        return KvkkRequestType.tumKisiselVerileriSil;
      case 'profil_fotografi_sil':
      default:
        return KvkkRequestType.profilFotografiSil;
    }
  }

  String get label {
    switch (this) {
      case KvkkRequestType.profilFotografiSil:
        return 'Sadece profil fotoğrafımı sil';
      case KvkkRequestType.tumKisiselVerileriSil:
        return 'Tüm kişisel verilerimi sil (hesabım kalıcı olarak anonimleştirilir)';
    }
  }
}

enum KvkkRequestStatus {
  beklemede,
  onaylandi,
  reddedildi,
  tamamlandi;

  static KvkkRequestStatus fromJson(String value) {
    switch (value) {
      case 'onaylandi':
        return KvkkRequestStatus.onaylandi;
      case 'reddedildi':
        return KvkkRequestStatus.reddedildi;
      case 'tamamlandi':
        return KvkkRequestStatus.tamamlandi;
      case 'beklemede':
      default:
        return KvkkRequestStatus.beklemede;
    }
  }

  String get label {
    switch (this) {
      case KvkkRequestStatus.beklemede:
        return 'Beklemede';
      case KvkkRequestStatus.onaylandi:
        return 'Onaylandı';
      case KvkkRequestStatus.reddedildi:
        return 'Reddedildi';
      case KvkkRequestStatus.tamamlandi:
        return 'Tamamlandı';
    }
  }
}

/// GET /api/kvkk/deletion-requests yalnızca yönetici yanıtındaki gömülü
/// talep sahibi özeti — bkz. routes/kvkk.js GET /deletion-requests.
class KvkkRequestUser {
  final int id;
  final String name;
  final String sicilNo;

  KvkkRequestUser({
    required this.id,
    required this.name,
    required this.sicilNo,
  });

  factory KvkkRequestUser.fromJson(Map<String, dynamic> json) {
    return KvkkRequestUser(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      sicilNo: json['sicil_no'] as String? ?? '',
    );
  }
}

/// data_deletion_requests satırı — hem kullanıcının kendi talebi (POST yanıtı)
/// hem yöneticinin gördüğü zenginleştirilmiş liste satırı (GET yanıtı, `user`/
/// `reviewedBy` dolu) için AYNI model kullanılır.
class KvkkDeletionRequest {
  final int id;
  final int userId;
  final KvkkRequestType requestType;
  final String? reason;
  final KvkkRequestStatus status;
  final String? reviewerNote;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final DateTime? completedAt;
  final KvkkRequestUser? user;
  final String? reviewedByName;

  KvkkDeletionRequest({
    required this.id,
    required this.userId,
    required this.requestType,
    this.reason,
    required this.status,
    this.reviewerNote,
    required this.createdAt,
    this.reviewedAt,
    this.completedAt,
    this.user,
    this.reviewedByName,
  });

  factory KvkkDeletionRequest.fromJson(Map<String, dynamic> json) {
    final reviewedBy = json['reviewed_by'] as Map<String, dynamic>?;
    return KvkkDeletionRequest(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      requestType: KvkkRequestType.fromJson(json['request_type'] as String),
      reason: json['reason'] as String?,
      status: KvkkRequestStatus.fromJson(json['status'] as String),
      reviewerNote: json['reviewer_note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'] as String)
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      user: json['user'] != null
          ? KvkkRequestUser.fromJson(json['user'] as Map<String, dynamic>)
          : null,
      reviewedByName: reviewedBy != null ? reviewedBy['name'] as String? : null,
    );
  }
}
