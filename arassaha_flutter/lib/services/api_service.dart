import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import '../models/app_notification.dart';
import '../models/app_user.dart';
import '../models/chat_message.dart';
import '../models/dashboard_summary.dart';
import '../models/description_classification.dart';
import '../models/equipment.dart';
import '../models/equipment_risk.dart';
import '../models/isg_report.dart';
import '../models/kvkk_models.dart';
import '../models/maintenance_recommendation.dart';
import '../models/managed_device.dart';
import '../models/material.dart';
import '../models/usage_analytics.dart';
import '../models/meter_anomaly.dart';
import '../models/report.dart';
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
  // Lokal test için geçici olarak değiştirmek istersen (yerelde test bitince
  // MUTLAKA Railway URL'sine geri al, aksi halde bilgisayar kapalıyken veya
  // farklı bir ağdayken uygulama sunucuya ulaşamaz):
  // - Android emulator:      http://10.0.2.2:3000
  // - Gerçek cihaz + USB kablo: http://localhost:3000 (+ adb reverse tcp:3000 tcp:3000)
  // - Gerçek cihaz + aynı WiFi ağı: http://<bilgisayarın-yerel-IP'si>:3000
  // E2E entegrasyon testi (integration_test/) LOKAL bir backend'e karşı
  // çalışmak zorunda (gerçek Railway prod verisine yazmamak için) — bu yüzden
  // `API_HOST` derleme-zamanı ortam değişkeniyle override edilebilir hale
  // getirildi. VARSAYILAN DEĞER HER ZAMAN Railway'dir; override yalnızca
  // `flutter test integration_test/... --dart-define=API_HOST=...` gibi
  // AÇIKÇA belirtildiğinde devreye girer — normal `flutter run`/release build
  // davranışı DEĞİŞMEZ, uygulama her zaman Railway'e bağlanmaya devam eder.
  static const String host = String.fromEnvironment(
    'API_HOST',
    defaultValue: 'https://arassaha-backend-production.up.railway.app',
  );
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
    final response = await http.post(
      uri,
      headers: _headers(json: body != null),
      body: body,
    );
    _reportIfUnauthorized(response);
    return response;
  }

  Future<http.Response> _patch(Uri uri, {Object? body}) async {
    final response = await http.patch(
      uri,
      headers: _headers(json: body != null),
      body: body,
    );
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
        throw ApiException(
          _extractError(response, 'Sicil no veya şifre hatalı.'),
        );
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
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

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

  /// [sort]/[q]/[limit]/[offset] opsiyoneldir (bkz. routes/workOrders.js GET
  /// / dokümantasyonu) — "Tamamlanan İş Emirlerim" bölümü (Ana Sayfa,
  /// teknisyen) dışındaki hiçbir çağıran bunları göndermez, bu yüzden
  /// davranışları eskisiyle birebir aynı kalır.
  Future<List<WorkOrder>> getWorkOrders({
    String? statusFilter,
    String? sort,
    String? q,
    int? limit,
    int? offset,
  }) async {
    try {
      final queryParameters = <String, String>{
        if (statusFilter != null) 'status': statusFilter,
        if (sort != null) 'sort': sort,
        if (q != null && q.isNotEmpty) 'q': q,
        if (limit != null) 'limit': '$limit',
        if (offset != null) 'offset': '$offset',
      };
      final uri = Uri.parse(
        '$baseUrl/workorders',
      ).replace(queryParameters: queryParameters.isEmpty ? null : queryParameters);
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
        throw ApiException(
          _extractError(response, 'Harita verileri alınamadı.'),
        );
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
        throw ApiException(
          _extractError(response, 'İş emri detayı alınamadı.'),
        );
      }

      return WorkOrder.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// [clientActionId] yalnızca çevrimdışı yazma kuyruğundan senkronize
  /// edilen istekler tarafından gönderilir (bkz. offline_queue_service.dart)
  /// — backend'in idempotency kontrolü bu alan doluysa devreye girer, aynı
  /// işlemin ağ hatası nedeniyle iki kez gönderilmesi durumunda durumun
  /// veritabanında iki kez uygulanmasını önler.
  Future<WorkOrder> updateStatus(
    int id,
    String newStatus, {
    String? clientActionId,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/workorders/$id/status');
      final response = await _patch(
        uri,
        body: jsonEncode({
          'status': newStatus,
          if (clientActionId != null) 'client_action_id': clientActionId,
        }),
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

  /// PATCH /api/workorders/:id/assign — yalnızca dispeçer/yönetici. Var olan
  /// bir iş emrinin atanan kişisini değiştirir (bkz. WorkOrderDetailScreen
  /// "Atanan Kişiyi Değiştir").
  Future<WorkOrder> assignWorkOrder(int id, int assignedUserId) async {
    try {
      final uri = Uri.parse('$baseUrl/workorders/$id/assign');
      final response = await _patch(
        uri,
        body: jsonEncode({'assigned_user_id': assignedUserId}),
      );

      if (response.statusCode != 200) {
        throw ApiException(
          _extractError(response, 'İş emri ataması değiştirilemedi.'),
        );
      }

      return WorkOrder.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// POST /api/workorders — yeni iş emri oluşturur (yalnızca dispeçer/yönetici,
  /// backend requireRole ile korur).
  ///
  /// KONUM TUTARLILIĞI: `equipmentId` artık ZORUNLUDUR ve konum bilgisi
  /// (location_name/lat/lng) burada HİÇ gönderilmez — backend bunu her zaman
  /// equipment kaydından türetir (bkz. routes/workOrders.js POST /). Bu,
  /// istemci tarafında yanlışlıkla/kasıtlı gönderilebilecek tutarsız bir
  /// konumun veritabanına asla yazılamayacağını garanti eder.
  Future<WorkOrder> createWorkOrder({
    required String title,
    required String description,
    required WorkOrderPriority priority,
    required int assignedUserId,
    required int equipmentId,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/workorders');
      final response = await _post(
        uri,
        body: jsonEncode({
          'title': title,
          'description': description,
          'priority': priority.toJson(),
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
      final mimeType =
          (detectedMime != null && detectedMime.startsWith('image/'))
          ? detectedMime
          : 'image/jpeg';
      final filename = imageFile.path.split(Platform.pathSeparator).last;

      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(_headers())
        ..files.add(
          http.MultipartFile.fromBytes(
            'photo',
            bytes,
            filename: filename,
            contentType: MediaType.parse(mimeType),
          ),
        );

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
  Future<List<AssignedUser>> getUsers({
    String? roleFilter,
    bool activeOnly = false,
  }) async {
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
        throw ApiException(
          _extractError(response, 'Profil bilgisi alınamadı.'),
        );
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
        throw ApiException(
          _extractError(response, 'Kullanıcı detayı alınamadı.'),
        );
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
        throw ApiException(
          _extractError(response, 'Kullanıcı oluşturulamadı.'),
        );
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
        throw ApiException(
          _extractError(response, 'Kullanıcı güncellenemedi.'),
        );
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
      final mimeType =
          (detectedMime != null && detectedMime.startsWith('image/'))
          ? detectedMime
          : 'image/jpeg';
      final filename = imageFile.path.split(Platform.pathSeparator).last;

      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(_headers())
        ..files.add(
          http.MultipartFile.fromBytes(
            'photo',
            bytes,
            filename: filename,
            contentType: MediaType.parse(mimeType),
          ),
        );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      _reportIfUnauthorized(response);

      if (response.statusCode != 200) {
        throw ApiException(
          _extractError(response, 'Profil fotoğrafı yüklenemedi.'),
        );
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
        throw ApiException(
          _extractError(response, 'Kullanıcı pasif hale getirilemedi.'),
        );
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
        throw ApiException(
          _extractError(response, 'Kullanıcı aktif hale getirilemedi.'),
        );
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
      final response = await _patch(
        uri,
        body: jsonEncode({'password': newPassword}),
      );

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
  static String? profilePhotoUrl(String? photoPath) =>
      photoPath != null ? photoUrl(photoPath) : null;

  /// Dashboard (Modül 2) için özet istatistikleri getirir.
  Future<DashboardSummary> getDashboardSummary() async {
    try {
      final uri = Uri.parse('$baseUrl/dashboard/summary');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          _extractError(response, 'Dashboard özeti alınamadı.'),
        );
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
      final response = await _post(
        uri,
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
  Future<ManagedDevice> lockDevice(int id) =>
      _performDeviceAction(id, 'lock', 'Cihaz kilitlenemedi.');

  /// Cihazın kilidini veritabanında kaldırır.
  Future<ManagedDevice> unlockDevice(int id) =>
      _performDeviceAction(id, 'unlock', 'Kilit kaldırılamadı.');

  /// Cihazı veritabanında "kayıt dışı" (hesap silinmiş) yapar.
  Future<ManagedDevice> wipeDevice(int id) =>
      _performDeviceAction(id, 'wipe', 'Hesap silinemedi.');

  /// Senkronizasyonu zorlar. `batteryLevel`/`deviceModel`/`osVersion` verilirse
  /// (yani bu uygulama gerçekten bir fiziksel cihazda çalışıyorsa,
  /// DeviceTelemetryService ile okunmuşsa) backend bu GERÇEK değerleri kalıcı
  /// olarak kaydeder; verilmezse yalnızca senkron zamanı güncellenir.
  Future<ManagedDevice> forceSyncDevice(
    int id, {
    int? batteryLevel,
    String? deviceModel,
    String? osVersion,
  }) => _performDeviceAction(
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

  /// Ekipman listesi. `typeFilter`/`statusFilter`/`ilFilter` verilirse
  /// backend'e ?type=.../&status=.../&il=... query parametresi olarak gider.
  /// `search` verilirse (EquipmentPickerField — bkz. create_work_order_screen.dart)
  /// backend qr_code/il/ilce/mahalle üzerinde arama yapıp sonucu sınırlı
  /// sayıda (en fazla 20) kayıtla döner.
  Future<List<Equipment>> getEquipmentList({
    String? typeFilter,
    String? statusFilter,
    String? ilFilter,
    String? search,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/equipment').replace(
        queryParameters: {
          if (typeFilter != null) 'type': typeFilter,
          if (statusFilter != null) 'status': statusFilter,
          if (ilFilter != null) 'il': ilFilter,
          if (search != null && search.trim().isNotEmpty)
            'search': search.trim(),
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
      final uri = Uri.parse(
        '$baseUrl/equipment/qr/${Uri.encodeComponent(qrCode)}',
      );
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          _extractError(response, 'Bu QR koda ait ekipman bulunamadı.'),
        );
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
        throw ApiException(
          _extractError(response, 'Ekipman detayı alınamadı.'),
        );
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
        throw ApiException(
          _extractError(response, 'Ekipman geçmişi alınamadı.'),
        );
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
      final uri = Uri.parse(
        '$baseUrl/dashboard/risky-equipment',
      ).replace(queryParameters: {'limit': '$limit'});
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          _extractError(response, 'Riskli ekipman listesi alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => RiskyEquipmentSummary.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  // --- Kayıp-Kaçak / Anormal Tüketim Tespiti — Modül 11 ---
  // DÜRÜSTLÜK NOTU: Bu skorları üreten IsolationForest modeli, ArasSaha'nın
  // henüz gerçek bir AMI/akıllı sayaç okuma sistemi olmaması nedeniyle
  // SENTETİK bir tüketim geçmişiyle eğitildi. Bkz. arassaha-ml/README.md.

  /// GET /api/meters/suspicious — anomaly_score'a göre azalan sırayla tüm
  /// şüpheli sayaçlar (yalnızca is_suspicious=1 olanlar).
  Future<List<SuspiciousMeterSummary>> getSuspiciousMeters() async {
    try {
      final uri = Uri.parse('$baseUrl/meters/suspicious');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          _extractError(response, 'Şüpheli sayaç listesi alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => SuspiciousMeterSummary.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// Bir sayacın en güncel anomali skorunu getirir (yoksa backend anlık
  /// hesaplayıp kaydeder — bkz. routes/anomaly.js).
  Future<MeterAnomaly> getEquipmentAnomaly(int equipmentId) async {
    try {
      final uri = Uri.parse('$baseUrl/equipment/$equipmentId/anomaly');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Anomali skoru alınamadı.'));
      }

      return MeterAnomaly.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// Bir sayacın son 12 aylık ham tüketim geçmişini getirir (Ekipman
  /// Detayı'ndaki fl_chart grafiği için).
  Future<List<MeterConsumptionEntry>> getEquipmentConsumption(
    int equipmentId,
  ) async {
    try {
      final uri = Uri.parse('$baseUrl/equipment/$equipmentId/consumption');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          _extractError(response, 'Tüketim geçmişi alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => MeterConsumptionEntry.fromJson(json)).toList();
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
        throw ApiException(
          _extractError(response, 'İSG bildirimleri alınamadı.'),
        );
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
        throw ApiException(
          _extractError(response, 'İSG bildirimi detayı alınamadı.'),
        );
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
      final mimeType =
          (detectedMime == 'image/jpeg' || detectedMime == 'image/png')
          ? detectedMime!
          : 'image/jpeg';
      final filename = photo.path.split(Platform.pathSeparator).last;

      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(_headers())
        ..fields['description'] = description
        ..fields['category'] = category.toJson()
        ..fields['lat'] = '$lat'
        ..fields['lng'] = '$lng'
        ..files.add(
          http.MultipartFile.fromBytes(
            'photo',
            bytes,
            filename: filename,
            contentType: MediaType.parse(mimeType),
          ),
        );

      if (locationName != null && locationName.trim().isNotEmpty) {
        request.fields['location_name'] = locationName.trim();
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      _reportIfUnauthorized(response);

      if (response.statusCode != 201) {
        throw ApiException(
          _extractError(response, 'İSG bildirimi gönderilemedi.'),
        );
      }

      return IsgReport.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  Future<IsgReport> updateIsgReportStatus(
    int id,
    IsgStatus newStatus, {
    String? reviewerNote,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/isg-reports/$id/status');
      final response = await _patch(
        uri,
        body: jsonEncode({
          'status': newStatus.toJson(),
          if (reviewerNote != null && reviewerNote.trim().isNotEmpty)
            'reviewer_note': reviewerNote.trim(),
        }),
      );

      if (response.statusCode != 200) {
        throw ApiException(
          _extractError(response, 'İSG bildirimi durumu güncellenemedi.'),
        );
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

  Future<List<AppNotification>> getNotifications({
    bool unreadOnly = false,
  }) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/notifications',
      ).replace(queryParameters: unreadOnly ? {'unread_only': 'true'} : null);
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
        throw ApiException(
          _extractError(response, 'Okunmamış bildirim sayısı alınamadı.'),
        );
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
        throw ApiException(
          _extractError(response, 'Bildirim okundu olarak işaretlenemedi.'),
        );
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
        throw ApiException(
          _extractError(response, 'Bildirimler okundu olarak işaretlenemedi.'),
        );
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
  Future<DescriptionClassification> classifyDescription(
    String description,
  ) async {
    try {
      final uri = Uri.parse('$baseUrl/ml/classify-description');
      final response = await _post(
        uri,
        body: jsonEncode({'description': description}),
      );

      if (response.statusCode != 200) {
        throw ApiException(
          _extractError(response, 'Açıklama sınıflandırılamadı.'),
        );
      }

      return DescriptionClassification.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  // --- Kestirimci Bakım Planlama — Modül 12 ---
  // AYRIM: Bu modül bir ML modeli İÇERMEZ. Modül 9'un ürettiği risk_score,
  // backend'de (routes/maintenance.js) SABİT eşiklerle bir bakım önerisine
  // çevrilir — burası yalnızca o iş kuralının sonucunu okuyan/tetikleyen bir
  // HTTP istemcisidir (Modül 9'daki risk skoru çağrılarıyla aynı desen).

  /// POST /api/maintenance/refresh-recommendations — yalnızca yönetici.
  /// Modül 9'un güncel risk skorlarını okuyup önerileri yeniden hesaplar.
  /// ÇOĞALTMA YOK: aynı ekipman için zaten bekleyen bir öneri varsa backend
  /// yeni bir satır AÇMAZ, yalnızca günceller (bkz. routes/maintenance.js).
  Future<({int created, int updated, int skipped})>
  refreshMaintenanceRecommendations() async {
    try {
      final uri = Uri.parse('$baseUrl/maintenance/refresh-recommendations');
      final response = await _post(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          _extractError(response, 'Bakım önerileri yeniden hesaplanamadı.'),
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (
        created: data['created'] as int,
        updated: data['updated'] as int,
        skipped: data['skipped'] as int,
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// GET /api/maintenance/recommendations?status=&urgency= — giriş yapmış herkes.
  Future<List<MaintenanceRecommendation>> getMaintenanceRecommendations({
    String? statusFilter,
    String? urgencyFilter,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/maintenance/recommendations').replace(
        queryParameters: {
          if (statusFilter != null) 'status': statusFilter,
          if (urgencyFilter != null) 'urgency': urgencyFilter,
        },
      );
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          _extractError(response, 'Bakım önerileri alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data
          .map((json) => MaintenanceRecommendation.fromJson(json))
          .toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// POST /api/maintenance/recommendations/:id/create-work-order — dispeçer/
  /// yönetici. Öneriyi gerçek bir iş emrine dönüştürür (source_type=
  /// 'onleyici_bakim'); `priority` verilmezse backend urgency_level'dan türetir.
  Future<WorkOrder> createWorkOrderFromRecommendation(
    int recommendationId, {
    int? assignedUserId,
    String? priority,
  }) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/maintenance/recommendations/$recommendationId/create-work-order',
      );
      final response = await _post(
        uri,
        body: jsonEncode({
          if (assignedUserId != null) 'assigned_user_id': assignedUserId,
          if (priority != null) 'priority': priority,
        }),
      );

      if (response.statusCode != 201) {
        throw ApiException(
          _extractError(response, 'Önleyici iş emri oluşturulamadı.'),
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return WorkOrder.fromJson(data['work_order'] as Map<String, dynamic>);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// PATCH /api/maintenance/recommendations/:id/dismiss — dispeçer/yönetici.
  Future<MaintenanceRecommendation> dismissMaintenanceRecommendation(
    int recommendationId,
  ) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/maintenance/recommendations/$recommendationId/dismiss',
      );
      final response = await _patch(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          _extractError(response, 'Bakım önerisi reddedilemedi.'),
        );
      }

      return MaintenanceRecommendation.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  // --- Malzeme / Yedek Parça Stok Takibi — Modül 13 ---
  // Görüntüleme (GET) giriş yapmış HERKESE açık; malzeme kullanımı kaydetme
  // (recordMaterialUsage) de teknisyen DAHİL herkese açık — sahada malzemeyi
  // kullanan kişi odur. Silme/restock/yeni malzeme ekleme backend'de
  // requireRole ile korunur (bkz. routes/materials.js dosya başı RBAC özeti).

  /// GET /api/materials?category=&low_stock=true&search=...
  Future<List<MaterialItem>> getMaterials({
    String? category,
    bool lowStockOnly = false,
    String? search,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/materials').replace(
        queryParameters: {
          if (category != null) 'category': category,
          if (lowStockOnly) 'low_stock': 'true',
          if (search != null && search.trim().isNotEmpty)
            'search': search.trim(),
        },
      );
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Malzemeler alınamadı.'));
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => MaterialItem.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// GET /api/materials/:id — detay + kullanım/stok hareketi geçmişi.
  Future<MaterialDetail> getMaterialDetail(int id) async {
    try {
      final uri = Uri.parse('$baseUrl/materials/$id');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          _extractError(response, 'Malzeme detayı alınamadı.'),
        );
      }

      return MaterialDetail.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// POST /api/materials — yalnızca yönetici. Yeni bir malzeme TİPİ tanımlar.
  Future<MaterialItem> createMaterial({
    required String name,
    required MaterialCategory category,
    required MaterialUnit unit,
    required double stockQuantity,
    required double minStockThreshold,
    required List<EquipmentType> compatibleEquipmentTypes,
    double? unitCost,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/materials');
      final response = await _post(
        uri,
        body: jsonEncode({
          'name': name,
          'category': category.toJson(),
          'unit': unit.toJson(),
          'stock_quantity': stockQuantity,
          'min_stock_threshold': minStockThreshold,
          'compatible_equipment_types': compatibleEquipmentTypes
              .map((t) => t.name)
              .toList(),
          if (unitCost != null) 'unit_cost': unitCost,
        }),
      );

      if (response.statusCode != 201) {
        throw ApiException(_extractError(response, 'Malzeme oluşturulamadı.'));
      }

      return MaterialItem.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// POST /api/materials/:id/restock — yalnızca yönetici. Stok girişi/ikmali.
  Future<MaterialItem> restockMaterial(int id, double quantityAdded) async {
    try {
      final uri = Uri.parse('$baseUrl/materials/$id/restock');
      final response = await _post(
        uri,
        body: jsonEncode({'quantity_added': quantityAdded}),
      );

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Stok ikmali yapılamadı.'));
      }

      return MaterialItem.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// GET /api/workorders/:id/materials — bir iş emrinde kullanılan malzemeler.
  Future<List<WorkOrderMaterialUsage>> getWorkOrderMaterials(
    int workOrderId,
  ) async {
    try {
      final uri = Uri.parse('$baseUrl/workorders/$workOrderId/materials');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          _extractError(response, 'Kullanılan malzemeler alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => WorkOrderMaterialUsage.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// POST /api/workorders/:id/materials — giriş yapmış HERKES (teknisyen
  /// dahil). Stok yetersizse backend 400 + net bir hata mesajı döner (bkz.
  /// routes/materials.js) — bu mesaj olduğu gibi ApiException'a taşınır.
  Future<WorkOrderMaterialUsage> recordMaterialUsage(
    int workOrderId,
    int materialId,
    double quantityUsed,
  ) async {
    try {
      final uri = Uri.parse('$baseUrl/workorders/$workOrderId/materials');
      final response = await _post(
        uri,
        body: jsonEncode({
          'material_id': materialId,
          'quantity_used': quantityUsed,
        }),
      );

      if (response.statusCode != 201) {
        throw ApiException(
          _extractError(response, 'Malzeme kullanımı kaydedilemedi.'),
        );
      }

      return WorkOrderMaterialUsage.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// DELETE /api/workorders/:id/materials/:usageId — dispeçer/yönetici.
  /// Kaydı siler VE düşülen stoğu geri ekler (bkz. routes/materials.js).
  Future<void> removeMaterialUsage(int workOrderId, int usageId) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/workorders/$workOrderId/materials/$usageId',
      );
      final response = await http.delete(uri, headers: _headers());
      _reportIfUnauthorized(response);

      if (response.statusCode != 200) {
        throw ApiException(
          _extractError(response, 'Malzeme kullanım kaydı silinemedi.'),
        );
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// GET /api/dashboard/low-stock-materials — Dashboard "Kritik Stoktaki
  /// Malzemeler" widget'ı için.
  Future<List<MaterialItem>> getLowStockMaterials({int limit = 5}) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/dashboard/low-stock-materials',
      ).replace(queryParameters: {'limit': '$limit'});
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          _extractError(response, 'Kritik stoktaki malzemeler alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => MaterialItem.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  // --- Basit Kullanım Analitiği — UX standardizasyonu turu bölüm E ---
  // Bu, AnalyticsService tarafından "fire and forget" olarak çağrılır (bkz.
  // services/analytics_service.dart) — bu yüzden diğer metodlardan farklı
  // olarak burada ApiException fırlatılmaz/statusCode kontrol edilmez; hata
  // olursa çağıran taraf zaten sessizce yutuyor.

  /// POST /api/analytics/log
  Future<void> logAnalyticsEvent({
    required String eventType,
    required String screenName,
    String? elementName,
  }) async {
    final uri = Uri.parse('$baseUrl/analytics/log');
    await _post(
      uri,
      body: jsonEncode({
        'event_type': eventType,
        'screen_name': screenName,
        if (elementName != null) 'element_name': elementName,
      }),
    );
  }

  /// GET /api/analytics/summary — yalnızca yönetici.
  Future<UsageAnalyticsSummary> getAnalyticsSummary() async {
    try {
      final uri = Uri.parse('$baseUrl/analytics/summary');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          _extractError(response, 'Kullanım analitiği alınamadı.'),
        );
      }

      return UsageAnalyticsSummary.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  // --- Raporlar / Analitik Sayfası (Modül 14) — yalnızca yönetici. Backend
  // her endpoint'te requireRole('yonetici') uyguluyor (bkz. routes/reports.js);
  // burada ayrıca bir rol kontrolü YOK, 403 gelirse ApiException olarak diğer
  // tüm metodlarla AYNI şekilde fırlatılır.

  /// GET /api/reports/regional-risk-summary
  Future<List<RegionalRiskSummary>> getRegionalRiskSummary() async {
    try {
      final uri = Uri.parse('$baseUrl/reports/regional-risk-summary');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          _extractError(response, 'Bölgesel risk özeti alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => RegionalRiskSummary.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// GET /api/reports/fault-by-region
  Future<List<RegionFaultCount>> getFaultByRegion() async {
    try {
      final uri = Uri.parse('$baseUrl/reports/fault-by-region');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          _extractError(response, 'Bölgeye göre arıza dağılımı alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => RegionFaultCount.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// GET /api/reports/fault-by-equipment-type
  Future<List<EquipmentTypeFaultCount>> getFaultByEquipmentType() async {
    try {
      final uri = Uri.parse('$baseUrl/reports/fault-by-equipment-type');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          _extractError(
            response,
            'Ekipman tipine göre arıza dağılımı alınamadı.',
          ),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data
          .map((json) => EquipmentTypeFaultCount.fromJson(json))
          .toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// GET /api/reports/fault-trend?months=
  Future<List<MonthlyFaultCount>> getFaultTrend({int months = 6}) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/reports/fault-trend',
      ).replace(queryParameters: {'months': '$months'});
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          _extractError(response, 'Aylık arıza trendi alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => MonthlyFaultCount.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// GET /api/reports/anomaly-by-region
  Future<List<RegionAnomalySummary>> getAnomalyByRegion() async {
    try {
      final uri = Uri.parse('$baseUrl/reports/anomaly-by-region');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          _extractError(response, 'Bölgeye göre anomali dağılımı alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => RegionAnomalySummary.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// GET /api/reports/material-usage-top?limit=
  Future<List<TopMaterialUsage>> getTopMaterialUsage({int limit = 10}) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/reports/material-usage-top',
      ).replace(queryParameters: {'limit': '$limit'});
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          _extractError(response, 'En çok kullanılan malzemeler alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => TopMaterialUsage.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  // AI Asistan / Sohbet Arayüzü (Modül 16).

  /// GET /api/assistant/history — kullanıcının son 50 mesajı, kronolojik sırada.
  Future<List<ChatMessage>> getAssistantHistory() async {
    try {
      final uri = Uri.parse('$baseUrl/assistant/history');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          _extractError(response, 'Sohbet geçmişi alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => ChatMessage.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// POST /api/assistant/query — kullanıcı mesajını gönderir, asistanın
  /// (Gemini API + güvenli sorgu fonksiyonları ile üretilmiş) yanıtını,
  /// varsa bir uygulama-içi yönlendirme talebiyle ([AssistantReply.
  /// navigateScreen]) birlikte döner (bkz. routes/assistant.js
  /// navigate_to_screen özel durumu). Backend 200 ile döner (Gemini'ye
  /// ulaşılamasa bile zarif bir hata mesajı `reply` içinde gelir), bu
  /// yüzden burada ayrı bir "asistan hatası" dalı yok, yalnızca ağ/sunucu
  /// hatası ele alınır.
  Future<AssistantReply> sendAssistantMessage(String message) async {
    try {
      final uri = Uri.parse('$baseUrl/assistant/query');
      final response = await _post(uri, body: jsonEncode({'message': message}));

      if (response.statusCode != 200) {
        throw ApiException(
          _extractError(response, 'Asistan yanıtı alınamadı.'),
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return AssistantReply.fromJson(data);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  // --- KVKK Uyum Modülü ---
  // GET /my-data-summary + POST /deletion-requests giriş yapmış HERKESE açık
  // (kendi verisi/kendi talebi); GET (liste) + approve/reject yalnızca
  // yönetici — bkz. routes/kvkk.js dosya başındaki RBAC tablosu.

  /// GET /api/kvkk/aydinlatma-metni — sabit taslak metni backend'den okur.
  /// [isDraft]/[draftWarning] UI'da HER ZAMAN gösterilmeli — hukuk/KVKK uyum
  /// birimi onayına kadar bu metin resmi değildir (bkz. routes/kvkk.js).
  Future<({String title, bool isDraft, String draftWarning, String content})>
  getKvkkAydinlatmaMetni() async {
    try {
      final uri = Uri.parse('$baseUrl/kvkk/aydinlatma-metni');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          _extractError(response, 'Aydınlatma metni alınamadı.'),
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (
        title: data['title'] as String,
        isDraft: data['is_draft'] as bool? ?? true,
        draftWarning: data['draft_warning'] as String? ?? '',
        content: data['content'] as String,
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// GET /api/kvkk/my-data-summary — giriş yapmış kullanıcının kendi
  /// verisinin sayısal özeti.
  Future<KvkkDataSummary> getMyDataSummary() async {
    try {
      final uri = Uri.parse('$baseUrl/kvkk/my-data-summary');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          _extractError(response, 'Kişisel veri özeti alınamadı.'),
        );
      }

      return KvkkDataSummary.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// POST /api/kvkk/deletion-requests — yalnızca KENDİ adına talep açar
  /// (user_id istemciden gönderilmez, backend token'dan doldurur).
  Future<void> submitDeletionRequest({
    required KvkkRequestType requestType,
    String? reason,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/kvkk/deletion-requests');
      final response = await _post(
        uri,
        body: jsonEncode({
          'request_type': requestType.toJson(),
          if (reason != null && reason.trim().isNotEmpty)
            'reason': reason.trim(),
        }),
      );

      if (response.statusCode != 201) {
        throw ApiException(
          _extractError(response, 'Silme talebi oluşturulamadı.'),
        );
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// GET /api/kvkk/deletion-requests — yalnızca yönetici.
  Future<List<KvkkDeletionRequest>> getAllDeletionRequests() async {
    try {
      final uri = Uri.parse('$baseUrl/kvkk/deletion-requests');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          _extractError(response, 'Silme talepleri alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => KvkkDeletionRequest.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// PATCH /api/kvkk/deletion-requests/:id/approve — yalnızca yönetici.
  /// Talebi onaylar VE anonimleştirmeyi (backend'de senkron/tek transaction
  /// içinde) tetikler — bkz. routes/kvkk.js "En Kritik Kısım" notu.
  Future<void> approveDeletionRequest(int id) async {
    try {
      final uri = Uri.parse('$baseUrl/kvkk/deletion-requests/$id/approve');
      final response = await _patch(uri, body: jsonEncode({}));

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Talep onaylanamadı.'));
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Sunucuya bağlanılamadı: $e');
    }
  }

  /// PATCH /api/kvkk/deletion-requests/:id/reject — yalnızca yönetici.
  /// [reviewerNote] (red gerekçesi) backend'de ZORUNLUDUR.
  Future<void> rejectDeletionRequest(int id, String reviewerNote) async {
    try {
      final uri = Uri.parse('$baseUrl/kvkk/deletion-requests/$id/reject');
      final response = await _patch(
        uri,
        body: jsonEncode({'reviewer_note': reviewerNote.trim()}),
      );

      if (response.statusCode != 200) {
        throw ApiException(_extractError(response, 'Talep reddedilemedi.'));
      }
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
