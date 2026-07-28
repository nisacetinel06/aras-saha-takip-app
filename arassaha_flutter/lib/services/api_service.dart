import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import '../models/dashboard_summary.dart';
import '../models/managed_device.dart';
import '../models/work_order.dart';
import '../models/work_order_map_pin.dart';

/// Backend ile ilgili tüm hataları sarmalayan özel exception sınıfı.
class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

class ApiService {
  // Backend Railway'de canlı: https://arassaha-backend-production.up.railway.app
  // Lokal test için gerekirse aşağıdakilerle değiştir:
  // - Android emulator:      http://10.0.2.2:3000/api
  // - Gerçek cihaz + USB kablo: http://localhost:3000/api (+ adb reverse tcp:3000 tcp:3000)
  // - Gerçek cihaz + aynı WiFi ağı: http://<bilgisayarın-yerel-IP'si>:3000/api
  static const String host = 'https://arassaha-backend-production.up.railway.app';
  static const String baseUrl = '$host/api';

  /// `work_order_photos.photo_path` backend'den `/uploads/...` şeklinde göreli
  /// bir yol olarak gelir; ekranda göstermek için sunucu host'uyla birleştirilir.
  static String photoUrl(String photoPath) => '$host$photoPath';

  Future<List<WorkOrder>> getWorkOrders({String? statusFilter}) async {
    try {
      final uri = Uri.parse('$baseUrl/workorders').replace(
        queryParameters: statusFilter != null ? {'status': statusFilter} : null,
      );
      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'İş emirleri alınamadı.'));
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => WorkOrder.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// Harita ekranı (Modül 3) için hafif iş emri verisi getirir.
  Future<List<WorkOrderMapPin>> getMapData({String? statusFilter}) async {
    try {
      final uri = Uri.parse('$baseUrl/workorders/map').replace(
        queryParameters: statusFilter != null ? {'status': statusFilter} : null,
      );
      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Harita verileri alınamadı.'));
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => WorkOrderMapPin.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  Future<WorkOrder> getWorkOrderDetail(int id) async {
    try {
      final uri = Uri.parse('$baseUrl/workorders/$id');
      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'İş emri detayı alınamadı.'));
      }

      return WorkOrder.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  Future<WorkOrder> updateStatus(int id, String newStatus) async {
    try {
      final uri = Uri.parse('$baseUrl/workorders/$id/status');
      final response = await http.patch(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': newStatus}),
      );

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Durum güncellenemedi.'));
      }

      return WorkOrder.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// Fotoğrafı gerçek bir multipart/form-data isteğiyle backend'e yükler.
  /// Backend dosyayı diskine yazar (uploads/) ve kalıcı bir URL döner; bu sayede
  /// başka bir cihazdan bağlanan kullanıcı (örn. saha amiri) fotoğrafı görebilir.
  Future<WorkOrderPhoto> addPhoto(int id, File imageFile) async {
    try {
      final uri = Uri.parse('$baseUrl/workorders/$id/photos');

      // Bazı cihazlarda (kamera/galeri kaynağına göre) dosya yolu tanınabilir bir
      // uzantı taşımayabilir; bu durumda `MultipartFile.fromPath` content-type'ı
      // "application/octet-stream" olarak gönderir ve backend'in "yalnızca resim"
      // kontrolü isteği reddeder. Bunu önlemek için içerik (byte) bazlı mime tespiti
      // yapıp content-type'ı açıkça belirtiyoruz, bulunamazsa image/jpeg'e düşüyoruz.
      final bytes = await imageFile.readAsBytes();
      final detectedMime = lookupMimeType(imageFile.path, headerBytes: bytes);
      final mimeType = (detectedMime != null && detectedMime.startsWith('image/'))
          ? detectedMime
          : 'image/jpeg';
      final filename = imageFile.path.split(Platform.pathSeparator).last;

      final request = http.MultipartRequest('POST', uri)
        ..files.add(http.MultipartFile.fromBytes(
          'photo',
          bytes,
          filename: filename,
          contentType: MediaType.parse(mimeType),
        ));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 201) {
        throw ApiException(_extractError(response, 'Fotoğraf eklenemedi.'));
      }

      return WorkOrderPhoto.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// "Kişiler" listesi hiçbir yerde sabit kodlanmaz; her zaman bu endpoint
  /// üzerinden gerçek `users` tablosundan çekilir (bkz. ARCHITECTURE.md Bölüm 11.1).
  Future<List<AssignedUser>> getUsers({String? roleFilter}) async {
    try {
      final uri = Uri.parse('$baseUrl/users').replace(
        queryParameters: roleFilter != null ? {'role': roleFilter} : null,
      );
      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Kişiler alınamadı.'));
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => AssignedUser.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// Dashboard (Modül 2) için özet istatistikleri getirir.
  Future<DashboardSummary> getDashboardSummary() async {
    try {
      final uri = Uri.parse('$baseUrl/dashboard/summary');
      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Dashboard özeti alınamadı.'));
      }

      return DashboardSummary.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  // --- Cihaz Yönetimi — bkz. DESIGN_SYSTEM.md ---
  // lock/unlock/wipe: backend'in kendi veritabanındaki durumu değiştirir,
  // gerçek bir cihaza UZAKTAN komut göndermez (bunun için Google Android
  // Management API gibi bir MDM altyapısı gerekir).
  // forceSyncDevice: tersi yönde çalışır — bu cihazın GERÇEK telemetrisini
  // (DeviceTelemetryService) backend'e gönderip kalıcı olarak kaydettirir.

  Future<List<ManagedDevice>> getDevices() async {
    try {
      final uri = Uri.parse('$baseUrl/devices');
      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Cihazlar alınamadı.'));
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => ManagedDevice.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  Future<ManagedDevice> getDeviceDetail(int id) async {
    try {
      final uri = Uri.parse('$baseUrl/devices/$id');
      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Cihaz detayı alınamadı.'));
      }

      return ManagedDevice.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  Future<List<DeviceActionLog>> getDeviceLogs(int id) async {
    try {
      final uri = Uri.parse('$baseUrl/devices/$id/logs');
      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'İşlem geçmişi alınamadı.'));
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => DeviceActionLog.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  Future<ManagedDevice> _performDeviceAction(
    int id,
    String actionSlug,
    String fallbackError, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/devices/$id/actions/$actionSlug');
      final response = await http.post(
        uri,
        headers: body != null ? {'Content-Type': 'application/json'} : null,
        body: body != null ? jsonEncode(body) : null,
      );

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, fallbackError));
      }

      return ManagedDevice.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// Cihazı veritabanında kilitli olarak işaretler. (Gerçek bir cihaza uzaktan
  /// komut gitmez — bkz. DESIGN_SYSTEM.md "Cihaz Yönetimi Modülü" notu.)
  Future<ManagedDevice> lockDevice(int id) => _performDeviceAction(id, 'lock', 'Cihaz kilitlenemedi.');

  /// Cihazın kilidini veritabanında kaldırır.
  Future<ManagedDevice> unlockDevice(int id) => _performDeviceAction(id, 'unlock', 'Kilit kaldırılamadı.');

  /// Cihazı veritabanında "kayıt dışı" (hesap silinmiş) yapar.
  Future<ManagedDevice> wipeDevice(int id) => _performDeviceAction(id, 'wipe', 'Hesap silinemedi.');

  /// Senkronizasyonu zorlar. `batteryLevel`/`deviceModel`/`osVersion` verilirse
  /// (yani bu uygulama gerçekten bir fiziksel cihazda çalışıyorsa,
  /// DeviceTelemetryService ile okunmuşsa) backend bu GERÇEK değerleri kalıcı
  /// olarak kaydeder; verilmezse yalnızca senkron zamanı güncellenir.
  Future<ManagedDevice> forceSyncDevice(
    int id, {
    int? batteryLevel,
    String? deviceModel,
    String? osVersion,
  }) =>
      _performDeviceAction(
        id,
        'force-sync',
        'Senkronizasyon zorlanamadı.',
        body: {
          'battery_level': ?batteryLevel,
          'device_model': ?deviceModel,
          'os_version': ?osVersion,
        },
      );

  String _extractError(http.Response response, String fallback) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['error'] != null) {
        return body['error'] as String;
      }
    } catch (_) {
      // Yanıt JSON değilse fallback mesajı kullanılır.
    }
    return fallback;
  }
}
