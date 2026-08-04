import 'dart:io';
import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// Cihaz Yönetimi modülündeki "Zorla Senkronize Et" aksiyonu için, UYGULAMANIN
/// O AN ÇALIŞTIĞI fiziksel cihazdan GERÇEK pil/model/OS bilgisini okur.
///
/// Not: Şu an filoda yönetilen 12 kayıttan yalnızca biri gerçekten elimizdeki
/// fiziksel cihaza (tablet) karşılık gelir — diğerleri sahte personel
/// kayıtlarıdır. "Zorla Senkronize Et" hangi kayıt için tetiklenirse
/// tetiklensin, bu uygulamayı çalıştıran cihazın gerçek telemetrisini
/// gönderir; gerçek bir MDM filosunda bu veri, her cihazın kendi üzerinde
/// çalışan kendi ajanından (kendi ArasSaha kurulumundan) gelirdi.
class DeviceTelemetry {
  final int batteryLevel;
  final String deviceModel;
  final String osVersion;

  DeviceTelemetry({
    required this.batteryLevel,
    required this.deviceModel,
    required this.osVersion,
  });
}

class DeviceTelemetryService {
  final Battery _battery = Battery();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  Future<DeviceTelemetry> readCurrentDevice() async {
    final batteryLevel = await _battery.batteryLevel;

    String model = 'Bilinmeyen cihaz';
    String osVersion = 'Bilinmeyen sürüm';

    if (Platform.isAndroid) {
      final info = await _deviceInfo.androidInfo;
      model = '${info.manufacturer} ${info.model}'.trim();
      osVersion = 'Android ${info.version.release}';
    } else if (Platform.isIOS) {
      final info = await _deviceInfo.iosInfo;
      model = info.utsname.machine;
      osVersion = '${info.systemName} ${info.systemVersion}';
    }

    return DeviceTelemetry(
      batteryLevel: batteryLevel,
      deviceModel: model,
      osVersion: osVersion,
    );
  }
}
