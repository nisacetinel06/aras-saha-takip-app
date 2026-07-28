import 'work_order.dart' show AssignedUser;

/// Cihaz kayıt durumu. Backend'deki managed_devices.enrollment_status ile
/// birebir eşleşir.
enum DeviceEnrollmentStatus {
  kayitli,
  beklemede,
  kayitDisi;

  static DeviceEnrollmentStatus fromJson(String value) {
    switch (value) {
      case 'kayitli':
        return DeviceEnrollmentStatus.kayitli;
      case 'beklemede':
        return DeviceEnrollmentStatus.beklemede;
      case 'kayit_disi':
        return DeviceEnrollmentStatus.kayitDisi;
      default:
        return DeviceEnrollmentStatus.kayitli;
    }
  }

  String get label {
    switch (this) {
      case DeviceEnrollmentStatus.kayitli:
        return 'Kayıtlı';
      case DeviceEnrollmentStatus.beklemede:
        return 'Beklemede';
      case DeviceEnrollmentStatus.kayitDisi:
        return 'Kayıt Dışı';
    }
  }
}

/// Uyumluluk durumu. Backend'deki managed_devices.compliance_status ile eşleşir.
enum DeviceComplianceStatus {
  uyumlu,
  uyumsuz;

  static DeviceComplianceStatus fromJson(String value) {
    return value == 'uyumsuz' ? DeviceComplianceStatus.uyumsuz : DeviceComplianceStatus.uyumlu;
  }

  String get label => this == DeviceComplianceStatus.uyumlu ? 'Uyumlu' : 'Uyumsuz';
}

/// Bir cihaz üzerinde yapılan simüle işlemin geçmiş kaydı (device_action_logs).
class DeviceActionLog {
  final int id;
  final int deviceId;
  final String actionType;
  final String performedBy;
  final DateTime createdAt;

  DeviceActionLog({
    required this.id,
    required this.deviceId,
    required this.actionType,
    required this.performedBy,
    required this.createdAt,
  });

  factory DeviceActionLog.fromJson(Map<String, dynamic> json) {
    return DeviceActionLog(
      id: json['id'] as int,
      deviceId: json['device_id'] as int,
      actionType: json['action_type'] as String,
      performedBy: json['performed_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Aksiyon kodunu ekranda gösterilecek Türkçe etikete çevirir.
  String get label {
    switch (actionType) {
      case 'kilitle':
        return 'Cihaz kilitlendi';
      case 'kilit_ac':
        return 'Kilit açıldı';
      case 'hesap_sil':
        return 'Hesap silindi';
      case 'senkron_zorla':
        return 'Senkronizasyon zorlandı';
      case 'politika_uygula':
        return 'Politika uygulandı';
      default:
        return actionType;
    }
  }
}

/// Cihaz Yönetimi (MDM simülasyonu) modülündeki tek bir yönetilen cihaz.
/// Bkz. DESIGN_SYSTEM.md — bu modelin arkasındaki backend GERÇEK bir cihaza
/// komut göndermez, yalnızca kendi veritabanındaki durumu simüle eder.
class ManagedDevice {
  final int id;
  final String deviceName;
  final AssignedUser? assignedUser;
  final String deviceModel;
  final String osVersion;
  final String appVersion;
  final DeviceEnrollmentStatus enrollmentStatus;
  final DeviceComplianceStatus complianceStatus;
  final DateTime? lastSyncAt;
  final int batteryLevel;
  final bool isLocked;
  final DateTime createdAt;
  final List<DeviceActionLog> logs;

  ManagedDevice({
    required this.id,
    required this.deviceName,
    required this.assignedUser,
    required this.deviceModel,
    required this.osVersion,
    required this.appVersion,
    required this.enrollmentStatus,
    required this.complianceStatus,
    required this.lastSyncAt,
    required this.batteryLevel,
    required this.isLocked,
    required this.createdAt,
    this.logs = const [],
  });

  factory ManagedDevice.fromJson(Map<String, dynamic> json) {
    return ManagedDevice(
      id: json['id'] as int,
      deviceName: json['device_name'] as String,
      assignedUser: json['assigned_user'] != null
          ? AssignedUser.fromJson(json['assigned_user'] as Map<String, dynamic>)
          : null,
      deviceModel: json['device_model'] as String? ?? '',
      osVersion: json['os_version'] as String? ?? '',
      appVersion: json['app_version'] as String? ?? '',
      enrollmentStatus: DeviceEnrollmentStatus.fromJson(json['enrollment_status'] as String),
      complianceStatus: DeviceComplianceStatus.fromJson(json['compliance_status'] as String),
      lastSyncAt: json['last_sync_at'] != null ? DateTime.parse(json['last_sync_at'] as String) : null,
      batteryLevel: json['battery_level'] as int? ?? 0,
      isLocked: json['is_locked'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      logs: json['logs'] != null
          ? (json['logs'] as List).map((l) => DeviceActionLog.fromJson(l as Map<String, dynamic>)).toList()
          : const [],
    );
  }
}
