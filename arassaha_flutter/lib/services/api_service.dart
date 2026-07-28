import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import '../models/dashboard_summary.dart';
import '../models/work_order.dart';

/// Backend ile ilgili tüm hataları sarmalayan özel exception sınıfı.
class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

class ApiService {
  // Test ortamına göre bu satırı değiştir:
  // - Android emulator:      http://10.0.2.2:3000/api
  //   (emulator'ın kendi bilgisayarını gördüğü özel adres)
  // - Gerçek cihaz + USB kablo: http://localhost:3000/api
  //   (önce bilgisayarda "adb reverse tcp:3000 tcp:3000" çalıştırılmalı;
  //   bu, tabletin localhost isteğini bilgisayarın 3000 portuna yönlendirir)
  // - Gerçek cihaz + aynı WiFi ağı: http://<bilgisayarın-yerel-IP'si>:3000/api
  //   (örn. http://192.168.1.23:3000/api, ipconfig ile bulunur)
  static const String host = 'http://localhost:3000';
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
