import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import '../models/app_notification.dart';
import '../models/app_user.dart';
import '../models/dashboard_summary.dart';
import '../models/description_classification.dart';
import '../models/equipment.dart';
import '../models/equipment_risk.dart';
import '../models/isg_report.dart';
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
  // GEÇİCİ: Modül 6 (Bildirim Sistemi) yerel test için Railway yerine yerel
  // backend'e yönlendirildi — Railway'de henüz bu modülün kodu yok. Test
  // bitince yukarıdaki Railway URL'sine geri alınmalı.
  static const String host = 'http://localhost:3000';
  static const String baseUrl = '$host/api';

  /// `work_order_photos.photo_path` backend'den `/uploads/...` şeklinde göreli
  /// bir yol olarak gelir; ekranda göstermek için sunucu host'uyla birleştirilir.
  static String photoUrl(String photoPath) => '$host$photoPath';

  // --- Auth (Modül 7) — merkezi token yönetimi ---
  //
  // ApiService her çağrıldığında yeni bir örnek olarak kullanılabildiği için
  // (bkz. her provider'ın kendi `ApiService()` alanı) token'ı burada, sınıf
  // düzeyinde (static) bir alanda tutuyoruz. AuthProvider login/logout/
  // tryAutoLogin sırasında bu alanı günceller; böylece TÜM istekler (hangi
  // provider'dan gelirse gelsin) aynı token'ı otomatik taşır — her metodun
  // kendi başına token okumasına gerek kalmaz.
  static String? authToken;

  /// Herhangi bir istek 401 (oturum geçersiz/süresi dolmuş) dönerse çağrılır.
  /// AuthProvider bunu kendi oturum temizleme mantığına bağlar; bu sayede
  /// token süresi dolduğunda kullanıcı otomatik olarak LoginScreen'e düşer.
  static void Function()? onUnauthorized;

  Map<String, String> _headers({bool json = false}) {
    return {
      if (json) 'Content-Type': 'application/json',
      if (authToken != null) 'Authorization': 'Bearer $authToken',
    };
  }

  /// Auth header'ı otomatik ekleyen ve 401 durumunda global oturum
  /// temizleme callback'ini tetikleyen ortak GET/POST/PATCH yardımcıları.
  /// Tüm iş modülü metodları (workorders, equipment, isg, devices, dashboard,
  /// risk) bunlar üzerinden çağrı yapar — Authorization header'ını tekrar
  /// tekrar elle eklemek gerekmez.
  Future<http.Response> _get(Uri uri) async {
    final response = await http.get(uri, headers: _headers());
    _reportIfUnauthorized(response);
    return response;
  }

  Future<http.Response> _post(Uri uri, {Object? body}) async {
    final response = await http.post(uri, headers: _headers(json: body != null), body: body);
    _reportIfUnauthorized(response);
    return response;
  }

  Future<http.Response> _patch(Uri uri, {Object? body}) async {
    final response = await http.patch(uri, headers: _headers(json: body != null), body: body);
    _reportIfUnauthorized(response);
    return response;
  }

  void _reportIfUnauthorized(http.Response response) {
    if (response.statusCode == 401) {
      onUnauthorized?.call();
    }
  }

  /// POST /api/auth/login
  /// Sicil no + şifre yanlışsa backend 401 döner — bu, "oturum süresi doldu"
  /// anlamına gelmediği (henüz bir oturum bile yok) için `onUnauthorized`
  /// callback'i BİLEREK tetiklenmez; hata doğrudan LoginScreen'e mesaj
  /// olarak döner.
  Future<({String token, AssignedUser user})> login({
    required String sicilNo,
    required String password,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/auth/login');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'sicil_no': sicilNo, 'password': password}),
      );

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Sicil no veya şifre hatalı.'));
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (
        token: data['token'] as String,
        user: AssignedUser.fromJson(data['user'] as Map<String, dynamic>),
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// GET /api/auth/me — verilen token'ın hâlâ geçerli olup olmadığını ve
  /// kullanıcının güncel bilgisini kontrol eder (uygulama açılışında
  /// otomatik giriş için kullanılır). Bilinçli olarak `authToken` static
  /// alanını DEĞİL, parametre olarak verilen token'ı kullanır — çünkü
  /// tryAutoLogin bu çağrı başarılı olmadan `authToken`'ı kalıcı kabul etmez.
  Future<AssignedUser> getMe(String token) async {
    try {
      final uri = Uri.parse('$baseUrl/auth/me');
      final response = await http.get(uri, headers: {'Authorization': 'Bearer $token'});

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Oturum geçersiz.'));
      }

      return AssignedUser.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  Future<List<WorkOrder>> getWorkOrders({String? statusFilter}) async {
    try {
      final uri = Uri.parse('$baseUrl/workorders').replace(
        queryParameters: statusFilter != null ? {'status': statusFilter} : null,
      );
      final response = await _get(uri);

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
      final response = await _get(uri);

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
      final response = await _get(uri);

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
      final response = await _patch(uri, body: jsonEncode({'status': newStatus}));

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

  /// PATCH /api/workorders/:id/assign — yalnızca dispeçer/yönetici. Var olan
  /// bir iş emrinin atanan kişisini değiştirir (bkz. WorkOrderDetailScreen
  /// "Atanan Kişiyi Değiştir").
  Future<WorkOrder> assignWorkOrder(int id, int assignedUserId) async {
    try {
      final uri = Uri.parse('$baseUrl/workorders/$id/assign');
      final response = await _patch(uri, body: jsonEncode({'assigned_user_id': assignedUserId}));

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'İş emri ataması değiştirilemedi.'));
      }

      return WorkOrder.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// POST /api/workorders — yeni iş emri oluşturur (yalnızca dispeçer/yönetici,
  /// backend requireRole ile korur). `equipmentId` opsiyoneldir.
  Future<WorkOrder> createWorkOrder({
    required String title,
    required String description,
    required WorkOrderPriority priority,
    required String locationName,
    required double lat,
    required double lng,
    required int assignedUserId,
    int? equipmentId,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/workorders');
      final response = await _post(
        uri,
        body: jsonEncode({
          'title': title,
          'description': description,
          'priority': priority.toJson(),
          'location_name': locationName,
          'lat': lat,
          'lng': lng,
          'assigned_user_id': assignedUserId,
          'equipment_id': equipmentId,
        }),
      );

      if (response.statusCode != 201) {
        throw ApiException(_extractError(response, 'İş emri oluşturulamadı.'));
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
      final bytes = await imageFile.readAsBytes();
      final detectedMime = lookupMimeType(imageFile.path, headerBytes: bytes);
      final mimeType = (detectedMime != null && detectedMime.startsWith('image/'))
          ? detectedMime
          : 'image/jpeg';
      final filename = imageFile.path.split(Platform.pathSeparator).last;

      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(_headers())
        ..files.add(http.MultipartFile.fromBytes(
          'photo',
          bytes,
          filename: filename,
          contentType: MediaType.parse(mimeType),
        ));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      _reportIfUnauthorized(response);

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
  /// `activeOnly: true` verilirse yalnızca aktif kullanıcılar döner — iş emri
  /// atama/yeniden atama dropdown'larının pasif bir teknisyeni HİÇ göstermemesi
  /// için (bkz. CreateWorkOrderScreen, WorkOrderDetailScreen reassignment).
  Future<List<AssignedUser>> getUsers({String? roleFilter, bool activeOnly = false}) async {
    try {
      final uri = Uri.parse('$baseUrl/users').replace(
        queryParameters: {
          if (roleFilter != null) 'role': roleFilter,
          if (activeOnly) 'active': 'true',
        },
      );
      final response = await _get(uri);

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

  // --- Profil ve Kullanıcı Yönetimi — Modül 8 ---
  // GET /api/users, çağıran yöneticiyse backend zaten zenginleştirilmiş
  // (telefon/e-posta/fotoğraf dahil) yanıt döner (bkz. routes/users.js);
  // getAllUsersFull bu zengin yanıtı AppUser'a çözer. getUsers (yukarıda),
  // hafif "kişi seçici" ihtiyaçları (iş emri atama, İSG bildiren personel)
  // için değişmeden kalır.

  /// GET /api/users/me — giriş yapmış kullanıcının kendi tam profili.
  Future<AppUser> getMyProfile() async {
    try {
      final uri = Uri.parse('$baseUrl/users/me');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Profil bilgisi alınamadı.'));
      }

      return AppUser.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// Kullanıcı Yönetimi paneli (yalnızca yönetici) — tüm kullanıcıları tam
  /// alan setiyle getirir.
  Future<List<AppUser>> getAllUsersFull({String? roleFilter}) async {
    try {
      final uri = Uri.parse('$baseUrl/users').replace(
        queryParameters: roleFilter != null ? {'role': roleFilter} : null,
      );
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Kullanıcılar alınamadı.'));
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => AppUser.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// GET /api/users/:id — yalnızca yönetici, tek kullanıcı detayı.
  Future<AppUser> getUserDetail(int id) async {
    try {
      final uri = Uri.parse('$baseUrl/users/$id');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Kullanıcı detayı alınamadı.'));
      }

      return AppUser.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// POST /api/users — yeni kullanıcı oluşturur (yalnızca yönetici).
  /// `supervisorId` verilirse (yeni teknisyeni doğrudan bir dispeçere
  /// bağlamak için), backend bunun GERÇEKTEN bir dispeçere ait olduğunu
  /// doğrular — bkz. ARCHITECTURE.md Modül 8 (dispeçer atama/değiştirme).
  Future<AppUser> createUser({
    required String name,
    required String sicilNo,
    required String password,
    required String role,
    String? phone,
    String? email,
    int? supervisorId,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/users');
      final response = await _post(
        uri,
        body: jsonEncode({
          'name': name,
          'sicil_no': sicilNo,
          'password': password,
          'role': role,
          if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
          if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
          'supervisor_id': ?supervisorId,
        }),
      );

      if (response.statusCode != 201) {
        throw ApiException(_extractError(response, 'Kullanıcı oluşturulamadı.'));
      }

      return AppUser.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// PATCH /api/users/:id — yalnızca yönetici. Yalnızca verilen alanlar güncellenir.
  ///
  /// NOT: is_active bu metottan YÖNETİLMEZ — aktifleştirme/pasifleştirme
  /// yalnızca `reactivateUser`/`deactivateUser` üzerinden, loglanarak yapılır.
  ///
  /// `updateSupervisor: true` verilirse `supervisor_id` alanı body'ye dahil
  /// edilir — `supervisorId` bir değerse ATAMA/DEĞİŞTİRME, `null` ise
  /// teknisyenin dispeçer bağını SİLME anlamına gelir. `updateSupervisor:
  /// false` (varsayılan) iken bu alan hiç gönderilmez, backend dokunmaz —
  /// bu ayrım gerekli çünkü "null gönder" (bağı kaldır) ile "hiç gönderme"
  /// (dokunma) backend için FARKLI anlamlara gelir.
  Future<AppUser> updateUser(
    int id, {
    String? name,
    String? phone,
    String? email,
    String? role,
    bool updateSupervisor = false,
    int? supervisorId,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/users/$id');
      final response = await _patch(
        uri,
        body: jsonEncode({
          'name': ?name,
          'phone': ?phone,
          'email': ?email,
          'role': ?role,
          if (updateSupervisor) 'supervisor_id': supervisorId,
        }),
      );

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Kullanıcı güncellenemedi.'));
      }

      return AppUser.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// POST /api/users/:id/photo — yalnızca yönetici, gerçek multipart/form-data
  /// yüklemesi (work_orders/:id/photos ile aynı desen).
  Future<AppUser> uploadUserPhoto(int id, File imageFile) async {
    try {
      final uri = Uri.parse('$baseUrl/users/$id/photo');

      final bytes = await imageFile.readAsBytes();
      final detectedMime = lookupMimeType(imageFile.path, headerBytes: bytes);
      final mimeType = (detectedMime != null && detectedMime.startsWith('image/'))
          ? detectedMime
          : 'image/jpeg';
      final filename = imageFile.path.split(Platform.pathSeparator).last;

      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(_headers())
        ..files.add(http.MultipartFile.fromBytes(
          'photo',
          bytes,
          filename: filename,
          contentType: MediaType.parse(mimeType),
        ));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      _reportIfUnauthorized(response);

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Profil fotoğrafı yüklenemedi.'));
      }

      return AppUser.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// DELETE /api/users/:id — yalnızca yönetici. Gerçek silme değil, soft
  /// delete (is_active=0) — bkz. routes/users.js. Backend, yöneticinin KENDİ
  /// hesabını pasifleştirmesini 400 ile engeller.
  Future<AppUser> deactivateUser(int id) async {
    try {
      final uri = Uri.parse('$baseUrl/users/$id');
      final response = await http.delete(uri, headers: _headers());
      _reportIfUnauthorized(response);

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Kullanıcı pasif hale getirilemedi.'));
      }

      return AppUser.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// PATCH /api/users/:id/reactivate — yalnızca yönetici. deactivateUser'ın tersi.
  Future<AppUser> reactivateUser(int id) async {
    try {
      final uri = Uri.parse('$baseUrl/users/$id/reactivate');
      final response = await _patch(uri);

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Kullanıcı aktif hale getirilemedi.'));
      }

      return AppUser.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// PATCH /api/users/:id/reset-password — yalnızca yönetici. Teknisyen/
  /// dispeçer kendi şifresini değiştiremediği için (profil salt-okunur),
  /// şifresini unutan bir kullanıcının şifresi buradan yönetici tarafından
  /// sıfırlanır.
  Future<void> resetUserPassword(int id, String newPassword) async {
    try {
      final uri = Uri.parse('$baseUrl/users/$id/reset-password');
      final response = await _patch(uri, body: jsonEncode({'password': newPassword}));

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Şifre sıfırlanamadı.'));
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// Profil fotoğrafı URL'i — `photo_path` backend'den `/uploads/...` şeklinde
  /// göreli bir yol olarak gelir; sunucu host'uyla birleştirilir (bkz. photoUrl).
  static String? profilePhotoUrl(String? photoPath) => photoPath != null ? photoUrl(photoPath) : null;

  /// Dashboard (Modül 2) için özet istatistikleri getirir.
  Future<DashboardSummary> getDashboardSummary() async {
    try {
      final uri = Uri.parse('$baseUrl/dashboard/summary');
      final response = await _get(uri);

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
      final response = await _get(uri);

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
      final response = await _get(uri);

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
      final response = await _get(uri);

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
      final response = await _post(uri, body: body != null ? jsonEncode(body) : null);

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

  // --- Ekipman / Envanter (QR Kod) — Modül 4 ---
  // Bu verinin veritabanı şeması (install_date, last_maintenance_date vb.)
  // bilinçli olarak ileride eklenecek Arıza Risk Tahmini (ML) modülünün
  // girdisi olacak şekilde tasarlandı, bkz. lib/models/equipment.dart.

  /// Ekipman listesi. `typeFilter`/`statusFilter` verilirse backend'e
  /// ?type=.../&status=... query parametresi olarak gider.
  Future<List<Equipment>> getEquipmentList({String? typeFilter, String? statusFilter}) async {
    try {
      final uri = Uri.parse('$baseUrl/equipment').replace(
        queryParameters: {
          if (typeFilter != null) 'type': typeFilter,
          if (statusFilter != null) 'status': statusFilter,
        },
      );
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Ekipmanlar alınamadı.'));
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Equipment.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// QR kod (ya da manuel girilen kod) ile ekipman sorgular — ana sorgulama
  /// yöntemi. Eşleşme yoksa backend 404 + "Bu QR koda ait ekipman
  /// bulunamadı." mesajı döner; bu mesaj olduğu gibi ApiException'a taşınır.
  Future<Equipment> getEquipmentByQr(String qrCode) async {
    try {
      final uri = Uri.parse('$baseUrl/equipment/qr/${Uri.encodeComponent(qrCode)}');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Bu QR koda ait ekipman bulunamadı.'));
      }

      return Equipment.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// Harita/liste üzerinden gelindiğinde id ile ekipman detayı getirir.
  Future<Equipment> getEquipmentDetail(int id) async {
    try {
      final uri = Uri.parse('$baseUrl/equipment/$id');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Ekipman detayı alınamadı.'));
      }

      return Equipment.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// Bu ekipmana bağlı geçmiş iş emirlerini (arıza kayıtlarını) getirir.
  Future<List<EquipmentHistoryEntry>> getEquipmentHistory(int id) async {
    try {
      final uri = Uri.parse('$baseUrl/equipment/$id/history');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Ekipman geçmişi alınamadı.'));
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => EquipmentHistoryEntry.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  // --- Arıza Risk Tahmini — Modül 9 ---
  // DÜRÜSTLÜK NOTU: Bu skorları üreten model, ArasSaha'nın henüz gerçek bir
  // arıza geçmişi biriktirmemiş olması nedeniyle SENTETİK (kural tabanlı
  // üretilmiş) bir veri setiyle eğitildi. Bkz. arassaha-ml/README.md.

  /// Bir ekipmanın en güncel risk skorunu getirir (yoksa backend anlık
  /// hesaplayıp kaydeder — bkz. routes/risk.js).
  Future<EquipmentRisk> getEquipmentRisk(int equipmentId) async {
    try {
      final uri = Uri.parse('$baseUrl/equipment/$equipmentId/risk');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Risk skoru alınamadı.'));
      }

      return EquipmentRisk.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// Dashboard'un "Riskli Ekipmanlar" bölümü için risk skoruna göre azalan
  /// sırayla ilk `limit` ekipmanı getirir.
  Future<List<RiskyEquipmentSummary>> getRiskyEquipment({int limit = 5}) async {
    try {
      final uri = Uri.parse('$baseUrl/dashboard/risky-equipment').replace(
        queryParameters: {'limit': '$limit'},
      );
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Riskli ekipman listesi alınamadı.'));
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => RiskyEquipmentSummary.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  // --- İSG (İş Sağlığı ve Güvenliği) Bildirimi — Modül 5 ---
  // submitIsgReport gerçek bir fotoğraf dosyasını multipart/form-data ile
  // yükler (work_orders/:id/photos ile aynı yaklaşım); lat/lng, çağıran
  // tarafından (bkz. IsgProvider) cihazın gerçek GPS'inden okunmuş olarak gelir.

  Future<List<IsgReport>> getIsgReports({String? statusFilter}) async {
    try {
      final uri = Uri.parse('$baseUrl/isg-reports').replace(
        queryParameters: statusFilter != null ? {'status': statusFilter} : null,
      );
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'İSG bildirimleri alınamadı.'));
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => IsgReport.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  Future<IsgReport> getIsgReportDetail(int id) async {
    try {
      final uri = Uri.parse('$baseUrl/isg-reports/$id');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'İSG bildirimi detayı alınamadı.'));
      }

      return IsgReport.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// Yeni bir İSG bildirimi gönderir. Fotoğraf dosyası gerçekten backend'e
  /// yüklenir (multipart/form-data); `lat`/`lng` cihazın gerçek GPS
  /// konumundan (geolocator) okunmuş olmalıdır — bu metod bunu zorunlu kılar
  /// ama gerçekliğini doğrulayamaz, o sorumluluk çağıran tarafındadır.
  ///
  /// NOT: "bildiren kişi" burada GÖNDERİLMEZ — backend bunu Authorization
  /// header'ındaki token'dan (req.user.id) otomatik doldurur (bkz. routes/isg.js).
  /// Zaten giriş yapmış kullanıcı bildirimi yaptığı için tekrar isim seçtirmeye
  /// gerek yoktur (Modül 6 ile birlikte kaldırıldı, bkz. isg_report_form_screen.dart).
  Future<IsgReport> submitIsgReport({
    required String description,
    required IsgCategory category,
    required double lat,
    required double lng,
    String? locationName,
    required File photo,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/isg-reports');

      final bytes = await photo.readAsBytes();
      final detectedMime = lookupMimeType(photo.path, headerBytes: bytes);
      final mimeType = (detectedMime == 'image/jpeg' || detectedMime == 'image/png')
          ? detectedMime!
          : 'image/jpeg';
      final filename = photo.path.split(Platform.pathSeparator).last;

      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(_headers())
        ..fields['description'] = description
        ..fields['category'] = category.toJson()
        ..fields['lat'] = '$lat'
        ..fields['lng'] = '$lng'
        ..files.add(http.MultipartFile.fromBytes(
          'photo',
          bytes,
          filename: filename,
          contentType: MediaType.parse(mimeType),
        ));

      if (locationName != null && locationName.trim().isNotEmpty) {
        request.fields['location_name'] = locationName.trim();
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      _reportIfUnauthorized(response);

      if (response.statusCode != 201) {
        throw ApiException(_extractError(response, 'İSG bildirimi gönderilemedi.'));
      }

      return IsgReport.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  Future<IsgReport> updateIsgReportStatus(int id, IsgStatus newStatus, {String? reviewerNote}) async {
    try {
      final uri = Uri.parse('$baseUrl/isg-reports/$id/status');
      final response = await _patch(
        uri,
        body: jsonEncode({
          'status': newStatus.toJson(),
          if (reviewerNote != null && reviewerNote.trim().isNotEmpty) 'reviewer_note': reviewerNote.trim(),
        }),
      );

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'İSG bildirimi durumu güncellenemedi.'));
      }

      return IsgReport.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  // --- Bildirim Sistemi — Modül 6 ---
  // Gerçek bir push (FCM) altyapısı YOK: bu metodlar NotificationProvider
  // tarafından hem periyodik yoklama (unread-count, her 30 sn) hem de
  // Bildirimler ekranının tam listesi için kullanılır (bkz. ARCHITECTURE.md).

  Future<List<AppNotification>> getNotifications({bool unreadOnly = false}) async {
    try {
      final uri = Uri.parse('$baseUrl/notifications').replace(
        queryParameters: unreadOnly ? {'unread_only': 'true'} : null,
      );
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Bildirimler alınamadı.'));
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => AppNotification.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// Polling için hafif bir çağrı — tam listeyi çekmez, yalnızca sayıyı döner.
  Future<int> getUnreadNotificationCount() async {
    try {
      final uri = Uri.parse('$baseUrl/notifications/unread-count');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Okunmamış bildirim sayısı alınamadı.'));
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['count'] as int;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  Future<AppNotification> markNotificationRead(int id) async {
    try {
      final uri = Uri.parse('$baseUrl/notifications/$id/read');
      final response = await _patch(uri);

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Bildirim okundu olarak işaretlenemedi.'));
      }

      return AppNotification.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  Future<void> markAllNotificationsRead() async {
    try {
      final uri = Uri.parse('$baseUrl/notifications/mark-all-read');
      final response = await _patch(uri);

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Bildirimler okundu olarak işaretlenemedi.'));
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  // --- Arıza Açıklaması Otomatik Sınıflandırma — Modül 10 ---
  // Bu, Node üzerinden Python (TF-IDF + LogisticRegression) ML servisine giden
  // bir PROXY çağrısıdır — Modül 9'daki risk skoru çağrılarıyla aynı desen.

  /// "Yeni İş Emri Oluştur" formundaki açıklama metninden arıza tipi/öncelik
  /// önerisi ister (bkz. CreateWorkOrderScreen debounce mantığı). ML servisi
  /// kapalıysa ya da metin çok kısaysa/güven düşükse backend zaten
  /// `suggested_type: null` döner — bu durumda çağıran taraf öneri kutusunu
  /// hiç göstermemelidir (bkz. DescriptionClassification.hasSuggestion).
  Future<DescriptionClassification> classifyDescription(String description) async {
    try {
      final uri = Uri.parse('$baseUrl/ml/classify-description');
      final response = await _post(uri, body: jsonEncode({'description': description}));

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Açıklama sınıflandırılamadı.'));
      }

      return DescriptionClassification.fromJson(jsonDecode(response.body));
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
