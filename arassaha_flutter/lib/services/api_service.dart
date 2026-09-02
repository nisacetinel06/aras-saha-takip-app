import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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
import '../models/audit_log_entry.dart';
import '../models/feedback_item.dart';
import '../models/isg_report.dart';
import '../models/kvkk_models.dart';
import '../models/maintenance_recommendation.dart';
import '../models/managed_device.dart';
import '../models/manager_message.dart';
import '../models/material.dart';
import '../models/usage_analytics.dart';
import '../models/meter_anomaly.dart';
import '../models/my_performance.dart';
import '../models/report.dart';
import '../models/sos_alert.dart';
import '../models/work_order.dart';
import '../models/work_order_map_pin.dart';

/// Backend ile ilgili tüm hataları sarmalayan özel exception sınıfı.
///
/// `statusCode`, çağıran katmanın (bkz. utils/error_mapper.dart
/// mapExceptionToUserMessage) HTTP durum koduna göre kullanıcı dostu bir
/// mesaj seçebilmesi için taşınır — örn. 401 için "Oturumunuz sona ermiş",
/// 404 için "Aranan kayıt bulunamadı". Sunucudan hiç yanıt alınamayan
/// (bağlantı/DNS/zaman aşımı) durumlarda bu sınıf KULLANILMAZ — ham
/// SocketException/TimeoutException, tipini KORUYARAK doğrudan çağırana
/// yansır (bkz. bu dosyadaki her metodun artık bir "catch-all" bloğu
/// OLMAMASI notu), çünkü mapper bu iki durumu (sunucu hata verdi / sunucuya
/// hiç ulaşılamadı) FARKLI mesajlarla ayırt eder.
class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}

/// Access + Refresh Token Sistemi — bkz. utils/authToken.js (backend),
/// _authenticated/_refreshAccessToken (aşağıda). Bir istek 401 döner VE
/// sessiz yenileme (POST /api/auth/refresh) DE başarısız olursa (refresh_token
/// kendisi de süresi dolmuş/iptal edilmiş/hiç yoksa) fırlatılır — bu, "normal"
/// bir ApiException DEĞİLDİR: oturum GERÇEKTEN bitmiştir, kullanıcı yeniden
/// giriş yapmadan devam edemez. AuthProvider.handleSessionExpired() (bkz.
/// ApiService.onUnauthorized) bu noktaya HER ZAMAN bu exception'dan ÖNCE
/// tetiklenir; bu tip yalnızca çağıran tarafın (varsa) kendi hata mesajını
/// bastırıp sessizce Login ekranına geçişe izin vermesi için mevcuttur.
class SessionExpiredException implements Exception {
  final String message;
  SessionExpiredException([
    this.message = 'Oturum süresi doldu, lütfen tekrar giriş yapın.',
  ]);

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

  /// Access + Refresh Token Sistemi — bkz. routes/auth.js POST /refresh
  /// (backend). access_token kısa ömürlü (15 dk) olduğu için normal
  /// kullanımda sıkça süresi dolar; refresh_token (30 gün, sunucu tarafında
  /// izlenebilir/iptal edilebilir) bu durumda İSTEMCİ TARAFINDAN GÖRÜNMEDEN
  /// yeni bir access_token almak için kullanılır (bkz. _refreshAccessToken).
  static String? refreshToken;

  /// Sessiz bir yenileme (401 sonrası otomatik refresh) VEYA açık bir
  /// AuthProvider.login/verifyTwoFactor çağrısı YENİ bir token çifti
  /// ürettiğinde çağrılır — AuthProvider bunu SecureStorageService'e KALICI
  /// yazmaya bağlar. ApiService bilinçli olarak SecureStorageService'e
  /// DOĞRUDAN bağımlı değildir (servisler arası döngüsel bağımlılığı önlemek
  /// + tek sorumluluk ilkesi, bkz. onUnauthorized ile AYNI callback deseni).
  static Future<void> Function(String accessToken, String refreshToken)?
  onTokenRefreshed;

  /// Bir istek 401 döner VE sessiz yenileme DE başarısız olursa (refresh_token
  /// kendisi de süresi dolmuş/iptal edilmiş/hiç yoksa) çağrılır. AuthProvider
  /// bunu handleSessionExpired()'a bağlar; bu sayede oturum GERÇEKTEN bittiğinde
  /// kullanıcı otomatik olarak LoginScreen'e düşer — sessiz yenilemenin
  /// BAŞARILI olduğu (çok daha sık rastlanan) durumda bu HİÇ tetiklenmez,
  /// kullanıcı hiçbir kesinti fark etmez.
  static void Function()? onUnauthorized;

  // Aynı anda birden fazla istek 401 alırsa (örn. Ana Sayfa açılışında
  // paralel giden dashboard/bildirim/iş emri çağrıları), her biri KENDİ
  // refresh çağrısını AYRI AYRI tetiklemesin diye TEK bir devam eden refresh
  // Future'ı paylaşılır — aksi halde rotasyon kuralı (bkz. backend "her
  // refresh_token TEK KULLANIMLIKTIR") ikinci eşzamanlı çağrıyı GERÇEK bir
  // yeniden-kullanım saldırısıymış gibi (yanlışlıkla) reddederdi.
  static Future<bool>? _refreshInFlight;

  Map<String, String> _headers({bool json = false}) {
    return {
      if (json) 'Content-Type': 'application/json',
      if (authToken != null) 'Authorization': 'Bearer $authToken',
    };
  }

  /// POST /api/auth/refresh ile sessizce YENİ bir access+refresh token çifti
  /// alır, `authToken`/`refreshToken`'ı günceller. Başarılıysa true, mevcut
  /// refresh_token yoksa YA DA backend bunu reddederse (401 — süresi dolmuş,
  /// iptal edilmiş, ya da rotasyon yeniden-kullanım tespiti) false döner.
  Future<bool> _refreshAccessToken() {
    final currentRefreshToken = refreshToken;
    if (currentRefreshToken == null) {
      return Future.value(false);
    }

    _refreshInFlight ??= () async {
      try {
        final uri = Uri.parse('$baseUrl/auth/refresh');
        final response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refresh_token': currentRefreshToken}),
        );

        if (response.statusCode != 200) {
          return false;
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final newAccessToken = data['access_token'] as String;
        final newRefreshToken = data['refresh_token'] as String;
        authToken = newAccessToken;
        refreshToken = newRefreshToken;
        await onTokenRefreshed?.call(newAccessToken, newRefreshToken);
        return true;
      } catch (_) {
        return false;
      }
    }();

    return _refreshInFlight!.whenComplete(() => _refreshInFlight = null);
  }

  /// TÜM auth gerektiren isteklerin GEÇTİĞİ merkezi nokta: [sendRequest] ilk
  /// denemede 401 dönerse, KULLANICIYA GÖRÜNMEDEN sessizce bir refresh
  /// dener ve BAŞARILIYSA isteği YENİ access_token ile TEKRAR gönderir. Bu
  /// ikinci deneme de 401 dönerse (ya da refresh'in kendisi başarısız
  /// olduysa) oturum GERÇEKTEN bitmiştir: `onUnauthorized` tetiklenir ve
  /// `SessionExpiredException` fırlatılır.
  Future<http.Response> _authenticated(
    Future<http.Response> Function() sendRequest,
  ) async {
    var response = await sendRequest();

    if (response.statusCode == 401) {
      final refreshed = await _refreshAccessToken();
      if (refreshed) {
        response = await sendRequest();
      }

      if (response.statusCode == 401) {
        onUnauthorized?.call();
        throw SessionExpiredException();
      }
    }

    return response;
  }

  /// Auth header'ı otomatik ekleyen, 401 durumunda sessiz yenileme + tekrar
  /// deneme uygulayan ortak GET/POST/PATCH/DELETE yardımcıları. Tüm iş
  /// modülü metodları (workorders, equipment, isg, devices, dashboard, risk)
  /// bunlar üzerinden çağrı yapar — Authorization header'ını VEYA 401/refresh
  /// mantığını tekrar tekrar elle eklemek gerekmez.
  Future<http.Response> _get(Uri uri) =>
      _authenticated(() => http.get(uri, headers: _headers()));

  Future<http.Response> _post(Uri uri, {Object? body}) => _authenticated(
    () => http.post(
      uri,
      headers: _headers(json: body != null),
      body: body,
    ),
  );

  Future<http.Response> _patch(Uri uri, {Object? body}) => _authenticated(
    () => http.patch(
      uri,
      headers: _headers(json: body != null),
      body: body,
    ),
  );

  Future<http.Response> _delete(Uri uri) =>
      _authenticated(() => http.delete(uri, headers: _headers()));

  /// Multipart (dosya yükleme) istekleri _get/_post/_patch'in düz http
  /// çağrılarına benzemez — bir `MultipartRequest` yalnızca BİR KEZ
  /// gönderilebilir. Bu yüzden [buildRequest] bir FABRİKA fonksiyonudur:
  /// olası bir 401->refresh->tekrar deneme döngüsünde HER denemede TAZE bir
  /// istek nesnesi üretir (dosya baytları zaten belleğe okunmuş olduğundan
  /// bu, diskten tekrar okuma GEREKTİRMEZ — bkz. addPhoto/uploadUserPhoto/
  /// submitIsgReport).
  Future<http.Response> _sendMultipart(
    http.MultipartRequest Function() buildRequest,
  ) {
    return _authenticated(() async {
      final streamedResponse = await buildRequest().send();
      return http.Response.fromStream(streamedResponse);
    });
  }

  /// POST /api/auth/login
  /// Sicil no + şifre yanlışsa backend 401 döner — bu, "oturum süresi doldu"
  /// anlamına gelmediği (henüz bir oturum bile yok) için `onUnauthorized`
  /// callback'i BİLEREK tetiklenmez; hata doğrudan LoginScreen'e mesaj
  /// olarak döner.
  /// İki Faktörlü Doğrulama (2FA) — bkz. routes/twoFactor.js. Şifre
  /// DOĞRUYSA bile, 2FA etkin bir yönetici için backend TAM token çifti
  /// yerine `requires_2fa: true` + kısa ömürlü bir `pending_token` döner
  /// (bkz. routes/auth.js login akışı). Bu yüzden bu metodun dönüş tipi HER
  /// İKİ sonucu da (tam giriş VEYA 2FA'nın gerektiği) tek bir kayıt (record)
  /// içinde temsil eder — `accessToken`/`refreshToken`/`user` yalnızca 2FA
  /// gerekmiyorsa dolu, `pendingToken` yalnızca 2FA gerekiyorsa doludur.
  ///
  /// Access + Refresh Token Sistemi — bkz. routes/auth.js (backend): başarılı
  /// girişte artık TEK bir `token` DEĞİL, kısa ömürlü (15 dk) `access_token`
  /// + uzun ömürlü ama sunucu tarafında iptal edilebilir (30 gün)
  /// `refresh_token` çifti döner.
  Future<
    ({
      String? accessToken,
      String? refreshToken,
      AssignedUser? user,
      bool requiresTwoFactor,
      String? pendingToken,
    })
  >
  login({required String sicilNo, required String password}) async {
    try {
      final uri = Uri.parse('$baseUrl/auth/login');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'sicil_no': sicilNo, 'password': password}),
      );

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Sicil no veya şifre hatalı.'),
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['requires_2fa'] == true) {
        return (
          accessToken: null,
          refreshToken: null,
          user: null,
          requiresTwoFactor: true,
          pendingToken: data['pending_token'] as String,
        );
      }

      return (
        accessToken: data['access_token'] as String,
        refreshToken: data['refresh_token'] as String,
        user: AssignedUser.fromJson(data['user'] as Map<String, dynamic>),
        requiresTwoFactor: false,
        pendingToken: null,
      );
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  /// POST /api/auth/2fa/verify — login akışının 2. adımı. [pendingToken],
  /// `login()`'ın `requiresTwoFactor: true` döndüğü çağrıdan gelir. [code]
  /// authenticator uygulamasındaki 6 haneli TOTP kodu YA DA (authenticator'a
  /// erişim yoksa) kurulumda alınan 8 haneli yedek kodlardan biri olabilir —
  /// backend AYNI alanda ikisini de kabul eder.
  Future<({String accessToken, String refreshToken, AssignedUser user})>
  verifyTwoFactor({required String pendingToken, required String code}) async {
    try {
      final uri = Uri.parse('$baseUrl/auth/2fa/verify');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'pending_token': pendingToken, 'code': code}),
      );

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Kod doğrulanamadı.'),
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (
        accessToken: data['access_token'] as String,
        refreshToken: data['refresh_token'] as String,
        user: AssignedUser.fromJson(data['user'] as Map<String, dynamic>),
      );
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  /// POST /api/auth/2fa/setup — yalnızca yönetici, giriş yapmış (tam) oturum
  /// gerektirir. Yeni bir TOTP secret + 8 yedek kod üretir; backend BUNU
  /// HENÜZ ETKİNLEŞTİRMEZ (bkz. routes/twoFactor.js) — POST /confirm ile
  /// doğrulanması gerekir. [backupCodes] SADECE bu çağrıda düz metin olarak
  /// gelir, bir daha asla geri dönmez.
  Future<({String otpauthUri, List<String> backupCodes})>
  setupTwoFactor() async {
    try {
      final uri = Uri.parse('$baseUrl/auth/2fa/setup');
      final response = await _post(uri, body: jsonEncode({}));

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, '2FA kurulumu başlatılamadı.'),
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (
        otpauthUri: data['otpauth_uri'] as String,
        backupCodes: (data['backup_codes'] as List).cast<String>(),
      );
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  /// POST /api/auth/2fa/confirm — authenticator'dan okunan İLK kodu
  /// doğrular; başarılıysa 2FA gerçekten etkinleşir.
  Future<void> confirmTwoFactor(String code) async {
    try {
      final uri = Uri.parse('$baseUrl/auth/2fa/confirm');
      final response = await _post(uri, body: jsonEncode({'code': code}));

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Kod doğrulanamadı.'),
        );
      }
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  /// POST /api/auth/2fa/disable — GÜVENLİK: backend mevcut şifrenin tekrar
  /// gönderilmesini zorunlu kılar (bkz. routes/twoFactor.js) — yalnızca
  /// geçerli bir JWT ile 2FA kapatılamaz.
  Future<void> disableTwoFactor(String password) async {
    try {
      final uri = Uri.parse('$baseUrl/auth/2fa/disable');
      final response = await _post(
        uri,
        body: jsonEncode({'password': password}),
      );

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, '2FA devre dışı bırakılamadı.'),
        );
      }
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Oturum geçersiz.'),
        );
      }

      return AssignedUser.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  /// POST /api/auth/refresh — süresi dolmuş bir access_token'ı, HÂLÂ geçerli
  /// bir refresh_token karşılığında yeniler. `_refreshAccessToken` (401
  /// sonrası SESSİZ/otomatik yenileme için) BUNU DOĞRUDAN ÇAĞIRMAZ — kendi
  /// `authToken`/`refreshToken` static alanlarını güncellemesi ve eşzamanlı
  /// çağrıları TEK bir istekte birleştirmesi gerektiği için ayrı bir dahili
  /// implementasyonu var. Bu genel metod, AuthProvider'ın (örn. uygulama
  /// açılışında, tryAutoLogin sırasında) GEREKTİĞİNDE AÇIKÇA bir yenileme
  /// tetikleyebilmesi için mevcuttur.
  Future<({String accessToken, String refreshToken})> refresh(
    String refreshTokenValue,
  ) async {
    try {
      final uri = Uri.parse('$baseUrl/auth/refresh');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshTokenValue}),
      );

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Oturum yenilenemedi.'),
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (
        accessToken: data['access_token'] as String,
        refreshToken: data['refresh_token'] as String,
      );
    } on ApiException {
      rethrow;
    }
  }

  /// POST /api/auth/logout — refresh_token'ı SUNUCU TARAFINDA iptal eder
  /// (bkz. routes/auth.js POST /logout). Yalnızca YEREL depolamayı temizlemek
  /// YETERSİZDİR: çalınmış bir refresh_token, yerel temizlik yapılsa bile
  /// başka bir cihazdan hâlâ kullanılabilirdi — bu çağrı GERÇEK bir sunucu
  /// taraflı oturum sonlandırmadır. Backend bu endpoint'i İDEMPOTENT ve HER
  /// ZAMAN 200 dönecek şekilde tasarladığı için (bkz. routes/auth.js "çıkış
  /// işlemi asla başarısız GÖRÜNMEMELİDİR" notu), burada network hatası
  /// dışında bir başarısızlık BEKLENMEZ; yine de logout akışının asla
  /// kullanıcıyı kilitlememesi için hata sessizce yutulur (çağıran taraf
  /// zaten ardından yerel depolamayı temizleyecektir).
  Future<void> logout(String refreshTokenValue) async {
    try {
      final uri = Uri.parse('$baseUrl/auth/logout');
      await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshTokenValue}),
      );
    } catch (_) {
      // bkz. yukarıdaki dokümantasyon notu — logout ASLA çağıran tarafı
      // yerel oturum temizliğini yapmaktan alıkoymamalı.
    }
  }

  /// POST /api/auth/change-password — giriş yapmış kullanıcı KENDİ şifresini
  /// değiştirir. Admin'in [resetUserPassword]'ünden (PATCH /users/:id/reset-password)
  /// BİLİNÇLİ olarak AYRI bir metot/endpoint — o bir KURTARMA akışıdır
  /// (mevcut şifre istenmez), bu ise kullanıcının kendi bildiği mevcut
  /// şifreyle yaptığı bir değişikliktir (bkz. routes/auth.js dosya başı
  /// dokümantasyonu). Mevcut şifre hatalıysa backend 401 döner.
  ///
  /// BİLİNÇLİ OLARAK [_post] (ve dolayısıyla [_authenticated]) DEĞİL, ham
  /// `http.post` kullanılır — `login()`'daki AYNI gerekçe: bu endpoint'in
  /// 401'i "mevcut şifre hatalı" anlamına gelir, "oturumun süresi doldu"
  /// DEĞİL. `_authenticated` üzerinden gitseydi, yanlış mevcut şifre girmiş
  /// bir kullanıcı için 401 → sessiz refresh (BAŞARILI olur, çünkü access
  /// token aslında geçerlidir) → istek TEKRAR gönderilir → yine 401 (şifre
  /// hâlâ yanlış) → `onUnauthorized` tetiklenir → kullanıcı yanlışlıkla
  /// TÜM UYGULAMADAN atılırdı. Ham çağrı bu yanlış tetiklemeyi önler; token
  /// yine de `_headers(json: true)` ile elle eklenir (kullanıcı zaten giriş
  /// yapmış olmalı).
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/change-password');
    final response = await http.post(
      uri,
      headers: _headers(json: true),
      body: jsonEncode({
        'current_password': currentPassword,
        'new_password': newPassword,
      }),
    );

    if (response.statusCode != 200) {
      throw ApiException(
        response.statusCode,
        _extractError(response, 'Şifre değiştirilemedi.'),
      );
    }
  }

  /// Push Bildirim (FCM) — bkz. routes/auth.js POST /register-fcm-token,
  /// services/push_notification_service.dart. [token] `null` verilirse
  /// (çıkış yaparken, bkz. AuthProvider.logout) backend'deki kayıtlı token
  /// temizlenir — çıkış yapılmış bir cihaza artık bildirim gitmemesi için.
  Future<void> registerFcmToken(String? token) async {
    final uri = Uri.parse('$baseUrl/auth/register-fcm-token');
    final response = await _post(uri, body: jsonEncode({'fcm_token': token}));

    if (response.statusCode != 200) {
      throw ApiException(
        response.statusCode,
        _extractError(response, 'Bildirim token\'ı kaydedilemedi.'),
      );
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
      final uri = Uri.parse('$baseUrl/workorders').replace(
        queryParameters: queryParameters.isEmpty ? null : queryParameters,
      );
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'İş emirleri alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => WorkOrder.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
          response.statusCode,
          _extractError(response, 'Harita verileri alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => WorkOrderMapPin.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  Future<WorkOrder> getWorkOrderDetail(int id) async {
    try {
      final uri = Uri.parse('$baseUrl/workorders/$id');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'İş emri detayı alınamadı.'),
        );
      }

      return WorkOrder.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Durum güncellenemedi.'),
        );
      }

      return WorkOrder.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
          response.statusCode,
          _extractError(response, 'İş emri ataması değiştirilemedi.'),
        );
      }

      return WorkOrder.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
        throw ApiException(
          response.statusCode,
          _extractError(response, 'İş emri oluşturulamadı.'),
        );
      }

      return WorkOrder.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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

      final response = await _sendMultipart(() {
        return http.MultipartRequest('POST', uri)
          ..headers.addAll(_headers())
          ..files.add(
            http.MultipartFile.fromBytes(
              'photo',
              bytes,
              filename: filename,
              contentType: MediaType.parse(mimeType),
            ),
          );
      });

      if (response.statusCode != 201) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Fotoğraf eklenemedi.'),
        );
      }

      return WorkOrderPhoto.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
    String? ilFilter,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/users').replace(
        queryParameters: {
          if (roleFilter != null) 'role': roleFilter,
          if (activeOnly) 'active': 'true',
          if (ilFilter != null) 'il': ilFilter,
        },
      );
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Kişiler alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => AssignedUser.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
          response.statusCode,
          _extractError(response, 'Profil bilgisi alınamadı.'),
        );
      }

      return AppUser.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Kullanıcılar alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => AppUser.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  /// GET /api/users/:id — yalnızca yönetici, tek kullanıcı detayı.
  Future<AppUser> getUserDetail(int id) async {
    try {
      final uri = Uri.parse('$baseUrl/users/$id');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Kullanıcı detayı alınamadı.'),
        );
      }

      return AppUser.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
    String? il,
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
          if (il != null && il.trim().isNotEmpty) 'il': il.trim(),
          'supervisor_id': ?supervisorId,
        }),
      );

      if (response.statusCode != 201) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Kullanıcı oluşturulamadı.'),
        );
      }

      return AppUser.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
    String? il,
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
          'il': ?il,
          'role': ?role,
          if (updateSupervisor) 'supervisor_id': supervisorId,
        }),
      );

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Kullanıcı güncellenemedi.'),
        );
      }

      return AppUser.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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

      final response = await _sendMultipart(() {
        return http.MultipartRequest('POST', uri)
          ..headers.addAll(_headers())
          ..files.add(
            http.MultipartFile.fromBytes(
              'photo',
              bytes,
              filename: filename,
              contentType: MediaType.parse(mimeType),
            ),
          );
      });

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Profil fotoğrafı yüklenemedi.'),
        );
      }

      return AppUser.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  /// DELETE /api/users/:id — yalnızca yönetici. Gerçek silme değil, soft
  /// delete (is_active=0) — bkz. routes/users.js. Backend, yöneticinin KENDİ
  /// hesabını pasifleştirmesini 400 ile engeller.
  Future<AppUser> deactivateUser(int id) async {
    try {
      final uri = Uri.parse('$baseUrl/users/$id');
      final response = await _delete(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Kullanıcı pasif hale getirilemedi.'),
        );
      }

      return AppUser.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  /// PATCH /api/users/:id/reactivate — yalnızca yönetici. deactivateUser'ın tersi.
  Future<AppUser> reactivateUser(int id) async {
    try {
      final uri = Uri.parse('$baseUrl/users/$id/reactivate');
      final response = await _patch(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Kullanıcı aktif hale getirilemedi.'),
        );
      }

      return AppUser.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  /// PATCH /api/users/:id/reset-password — yalnızca yönetici. Bir kullanıcı
  /// KENDİ mevcut şifresini biliyorsa [changePassword]'ü kullanır; bu metot
  /// yalnızca şifresini TAMAMEN UNUTMUŞ (mevcut şifreyi bilemeyen) bir
  /// kullanıcı için yöneticinin uyguladığı KURTARMA akışıdır — ikisi
  /// KARIŞTIRILMAMALI (bkz. routes/auth.js dosya başı dokümantasyonu).
  Future<void> resetUserPassword(int id, String newPassword) async {
    try {
      final uri = Uri.parse('$baseUrl/users/$id/reset-password');
      final response = await _patch(
        uri,
        body: jsonEncode({'password': newPassword}),
      );

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Şifre sıfırlanamadı.'),
        );
      }
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
          response.statusCode,
          _extractError(response, 'Dashboard özeti alınamadı.'),
        );
      }

      return DashboardSummary.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  /// Performansım (Modül 16) için giriş yapmış kullanıcının kendi özet
  /// istatistiklerini getirir — getDashboardSummary ile AYNI desen, tek fark
  /// backend'in bu sorguyu her zaman req.user.id'ye sabitlemesi.
  Future<MyPerformanceSummary> getMyPerformance() async {
    try {
      final uri = Uri.parse('$baseUrl/dashboard/my-performance');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Performans özeti alınamadı.'),
        );
      }

      return MyPerformanceSummary.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      rethrow;
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
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Cihazlar alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => ManagedDevice.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  Future<ManagedDevice> getDeviceDetail(int id) async {
    try {
      final uri = Uri.parse('$baseUrl/devices/$id');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Cihaz detayı alınamadı.'),
        );
      }

      return ManagedDevice.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  Future<List<DeviceActionLog>> getDeviceLogs(int id) async {
    try {
      final uri = Uri.parse('$baseUrl/devices/$id/logs');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'İşlem geçmişi alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => DeviceActionLog.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
        throw ApiException(
          response.statusCode,
          _extractError(response, fallbackError),
        );
      }

      return ManagedDevice.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
    // QR Kod Üretimi modülü — 'false' (henüz basılmamış) veya 'true' (en az
    // bir kez basılmış). Diğer filtrelerle (type/il) AND ile birleşir, bkz.
    // backend routes/equipment.js GET / dosya başı notu.
    bool? qrPrintedFilter,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/equipment').replace(
        queryParameters: {
          if (typeFilter != null) 'type': typeFilter,
          if (statusFilter != null) 'status': statusFilter,
          if (ilFilter != null) 'il': ilFilter,
          if (search != null && search.trim().isNotEmpty)
            'search': search.trim(),
          if (qrPrintedFilter != null) 'qr_printed': qrPrintedFilter.toString(),
        },
      );
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Ekipmanlar alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Equipment.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  /// QR Kod Üretimi modülü — seçilen ekipmanların `qr_printed_at` alanını şu
  /// anki zamana günceller (yalnızca yönetici). PDF paylaşım/yazdırma
  /// diyaloğu başarıyla kapandıktan SONRA çağrılır (bkz.
  /// providers/qr_generation_provider.dart markAsPrinted).
  Future<List<Equipment>> markEquipmentQrPrinted(
    List<int> equipmentIds,
  ) async {
    try {
      final uri = Uri.parse('$baseUrl/equipment/mark-qr-printed');
      final response = await _patch(
        uri,
        body: jsonEncode({'equipment_ids': equipmentIds}),
      );

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'QR basıldı işaretlemesi yapılamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Equipment.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      rethrow;
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
          response.statusCode,
          _extractError(response, 'Bu QR koda ait ekipman bulunamadı.'),
        );
      }

      return Equipment.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  /// Harita/liste üzerinden gelindiğinde id ile ekipman detayı getirir.
  Future<Equipment> getEquipmentDetail(int id) async {
    try {
      final uri = Uri.parse('$baseUrl/equipment/$id');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Ekipman detayı alınamadı.'),
        );
      }

      return Equipment.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  /// Bu ekipmana bağlı geçmiş iş emirlerini (arıza kayıtlarını) getirir.
  Future<List<EquipmentHistoryEntry>> getEquipmentHistory(int id) async {
    try {
      final uri = Uri.parse('$baseUrl/equipment/$id/history');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Ekipman geçmişi alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => EquipmentHistoryEntry.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Risk skoru alınamadı.'),
        );
      }

      return EquipmentRisk.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
          response.statusCode,
          _extractError(response, 'Riskli ekipman listesi alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => RiskyEquipmentSummary.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  /// TEST-19: GET /api/ml/risk-model-performance (yalnızca yönetici) —
  /// risk_prediction_outcomes'ta GERÇEKTEN biriken tahmin/sonuç çiftlerinden
  /// hesaplanan, sentetik test seti metriklerinden BAĞIMSIZ dürüst bir özet.
  Future<RiskModelPerformance> getRiskModelPerformance() async {
    try {
      final uri = Uri.parse('$baseUrl/ml/risk-model-performance');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Risk modeli performans özeti alınamadı.'),
        );
      }

      return RiskModelPerformance.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      rethrow;
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
          response.statusCode,
          _extractError(response, 'Şüpheli sayaç listesi alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => SuspiciousMeterSummary.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  /// Bir sayacın en güncel anomali skorunu getirir (yoksa backend anlık
  /// hesaplayıp kaydeder — bkz. routes/anomaly.js).
  Future<MeterAnomaly> getEquipmentAnomaly(int equipmentId) async {
    try {
      final uri = Uri.parse('$baseUrl/equipment/$equipmentId/anomaly');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Anomali skoru alınamadı.'),
        );
      }

      return MeterAnomaly.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
          response.statusCode,
          _extractError(response, 'Tüketim geçmişi alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => MeterConsumptionEntry.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
          response.statusCode,
          _extractError(response, 'İSG bildirimleri alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => IsgReport.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  Future<IsgReport> getIsgReportDetail(int id) async {
    try {
      final uri = Uri.parse('$baseUrl/isg-reports/$id');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'İSG bildirimi detayı alınamadı.'),
        );
      }

      return IsgReport.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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

      final response = await _sendMultipart(() {
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

        return request;
      });

      if (response.statusCode != 201) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'İSG bildirimi gönderilemedi.'),
        );
      }

      return IsgReport.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
          response.statusCode,
          _extractError(response, 'İSG bildirimi durumu güncellenemedi.'),
        );
      }

      return IsgReport.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  /// TEST-20: Gerçek Saha Fotoğraflarından Geri Bildirim Döngüsü — yönetici/
  /// dispeçer bir İSG bildirimini incelerken fotoğrafta GERÇEKTE hasar olup
  /// olmadığını işaretler (bkz. routes/isg.js PATCH /:id/verify-damage).
  Future<IsgReport> verifyIsgReportDamage(int id, bool actualDamage) async {
    try {
      final uri = Uri.parse('$baseUrl/isg-reports/$id/verify-damage');
      final response = await _patch(
        uri,
        body: jsonEncode({'actual_damage': actualDamage}),
      );

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Hasar doğrulaması kaydedilemedi.'),
        );
      }

      return IsgReport.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      rethrow;
    }
  }

  /// TEST-20: GET /api/ml/damage-model-performance (yalnızca yönetici).
  Future<DamageModelPerformance> getDamageModelPerformance() async {
    try {
      final uri = Uri.parse('$baseUrl/ml/damage-model-performance');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Hasar tespiti model performans özeti alınamadı.'),
        );
      }

      return DamageModelPerformance.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      rethrow;
    }
  }

  // --- Öneri / Şikayet Kutusu — Modül 17 ---
  // İSG bildirimi (yukarısı) ile AYNI desen; tek fark, fotoğrafın OPSİYONEL
  // olması (submitFeedback her koşulda multipart/form-data gönderir — dosya
  // yoksa `files` boş kalır, backend'in multer'ı fotoğrafsız da metin
  // alanlarını doğru ayrıştırır, bkz. routes/feedback.js).

  Future<List<FeedbackItem>> getFeedbackItems({String? statusFilter}) async {
    try {
      final uri = Uri.parse('$baseUrl/feedback').replace(
        queryParameters: statusFilter != null ? {'status': statusFilter} : null,
      );
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Öneri/şikayet bildirimleri alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => FeedbackItem.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      rethrow;
    }
  }

  Future<FeedbackItem> getFeedbackItemDetail(int id) async {
    try {
      final uri = Uri.parse('$baseUrl/feedback/$id');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Bildirim detayı alınamadı.'),
        );
      }

      return FeedbackItem.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      rethrow;
    }
  }

  /// Yeni bir öneri/şikayet gönderir. "Bildiren kişi" burada GÖNDERİLMEZ —
  /// backend bunu giriş yapmış kullanıcının token'ından otomatik doldurur
  /// (bkz. submitIsgReport'taki AYNI not). `photo` null olabilir — İSG'nin
  /// aksine fotoğraf zorunlu değil.
  Future<FeedbackItem> submitFeedback({
    required String description,
    required FeedbackCategory category,
    required bool isAnonymous,
    File? photo,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/feedback');

      Uint8List? bytes;
      String? mimeType;
      String? filename;
      if (photo != null) {
        bytes = await photo.readAsBytes();
        final detectedMime = lookupMimeType(photo.path, headerBytes: bytes);
        mimeType = (detectedMime == 'image/jpeg' || detectedMime == 'image/png')
            ? detectedMime!
            : 'image/jpeg';
        filename = photo.path.split(Platform.pathSeparator).last;
      }

      final response = await _sendMultipart(() {
        final request = http.MultipartRequest('POST', uri)
          ..headers.addAll(_headers())
          ..fields['description'] = description
          ..fields['category'] = category.toJson()
          ..fields['is_anonymous'] = isAnonymous.toString();

        if (bytes != null) {
          request.files.add(
            http.MultipartFile.fromBytes(
              'photo',
              bytes,
              filename: filename,
              contentType: MediaType.parse(mimeType!),
            ),
          );
        }

        return request;
      });

      if (response.statusCode != 201) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Bildirim gönderilemedi.'),
        );
      }

      return FeedbackItem.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      rethrow;
    }
  }

  Future<FeedbackItem> updateFeedbackStatus(
    int id,
    FeedbackStatus newStatus, {
    String? reviewerNote,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/feedback/$id/status');
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
          response.statusCode,
          _extractError(response, 'Bildirim durumu güncellenemedi.'),
        );
      }

      return FeedbackItem.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      rethrow;
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
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Bildirimler alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => AppNotification.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  /// Polling için hafif bir çağrı — tam listeyi çekmez, yalnızca sayıyı döner.
  Future<int> getUnreadNotificationCount() async {
    try {
      final uri = Uri.parse('$baseUrl/notifications/unread-count');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Okunmamış bildirim sayısı alınamadı.'),
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['count'] as int;
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  Future<AppNotification> markNotificationRead(int id) async {
    try {
      final uri = Uri.parse('$baseUrl/notifications/$id/read');
      final response = await _patch(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Bildirim okundu olarak işaretlenemedi.'),
        );
      }

      return AppNotification.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  Future<void> markAllNotificationsRead() async {
    try {
      final uri = Uri.parse('$baseUrl/notifications/mark-all-read');
      final response = await _patch(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Bildirimler okundu olarak işaretlenemedi.'),
        );
      }
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  // --- Yöneticiden Çalışana Duyuru/Mesaj Sistemi ---
  // TEK YÖNLÜ yayın: yalnızca yönetici mesaj oluşturur, çalışan SADECE okur.
  // Bkz. routes/managerMessages.js — sohbet/AI Asistan (chat_message.dart)
  // metotlarıyla KARIŞTIRILMAMALI, bu TAMAMEN ayrı, tek yönlü bir modeldir.

  /// GET /api/manager-messages — giriş yapmış herkes, KENDİSİNİN ALICI
  /// OLDUĞU mesajları listeler (yönetici de kendi aldıklarını görür).
  Future<List<ManagerMessage>> getManagerMessages() async {
    try {
      final uri = Uri.parse('$baseUrl/manager-messages');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Mesajlar alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => ManagerMessage.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      rethrow;
    }
  }

  /// GET /api/manager-messages/unread-count — alt navigasyondaki "Mesajlar"
  /// sekmesinin kırmızı nokta rozeti için hafif bir çağrı (bkz.
  /// getUnreadNotificationCount ile AYNI desen, NotificationProvider polling'i
  /// tarafından çağrılır). Yönetici için backend her zaman 0 döner (bkz.
  /// routes/managerMessages.js — TEK YÖNLÜ model, yönetici hiçbir mesajın
  /// alıcısı olamaz).
  Future<int> getUnreadManagerMessageCount() async {
    try {
      final uri = Uri.parse('$baseUrl/manager-messages/unread-count');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Okunmamış mesaj sayısı alınamadı.'),
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['count'] as int;
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      rethrow;
    }
  }

  /// PATCH /api/manager-messages/:id/read — mesajın alıcısı kendi okundu
  /// zamanını işaretler. Bu kullanıcı bu mesajın alıcısı DEĞİLSE backend 404
  /// döner (bkz. routes/managerMessages.js — SEC-02 tarzı sahiplik kontrolü).
  Future<void> markManagerMessageRead(int id) async {
    try {
      final uri = Uri.parse('$baseUrl/manager-messages/$id/read');
      final response = await _patch(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Mesaj okundu olarak işaretlenemedi.'),
        );
      }
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      rethrow;
    }
  }

  /// POST /api/manager-messages — SADECE yönetici. `title` opsiyoneldir.
  Future<void> sendManagerMessage({
    String? title,
    required String content,
    required List<int> recipientUserIds,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/manager-messages');
      final response = await _post(
        uri,
        body: jsonEncode({
          if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
          'content': content.trim(),
          'recipient_user_ids': recipientUserIds,
        }),
      );

      if (response.statusCode != 201) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Mesaj gönderilemedi.'),
        );
      }
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      rethrow;
    }
  }

  /// GET /api/manager-messages/sent — SADECE yönetici, kendi gönderdiği
  /// mesajları okundu/toplam alıcı sayısıyla listeler.
  Future<List<SentManagerMessage>> getSentManagerMessages() async {
    try {
      final uri = Uri.parse('$baseUrl/manager-messages/sent');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Gönderilen mesajlar alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => SentManagerMessage.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      rethrow;
    }
  }

  /// GET /api/manager-messages/:id/read-status — SADECE o mesajı gönderen
  /// yönetici (başka bir yönetici ya da alıcı çağırırsa backend 403/404 döner).
  Future<MessageReadStatus> getManagerMessageReadStatus(int id) async {
    try {
      final uri = Uri.parse('$baseUrl/manager-messages/$id/read-status');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Okundu bilgisi alınamadı.'),
        );
      }

      return MessageReadStatus.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      rethrow;
    }
  }

  // --- Acil Durum / SOS Bildirimi Modülü ---
  // bkz. routes/sosAlerts.js. POST BİLİNÇLİ olarak minimal — yalnızca lat/lng
  // gönderir, backend tarafı da hiçbir ekstra doğrulama/adım eklemez (hız
  // önceliği).

  /// POST /api/sos-alerts — giriş yapmış HERKES. Yalnızca konum gönderir.
  Future<int> createSosAlert({required double lat, required double lng}) async {
    try {
      final uri = Uri.parse('$baseUrl/sos-alerts');
      final response = await _post(
        uri,
        body: jsonEncode({'lat': lat, 'lng': lng}),
      );

      if (response.statusCode != 201) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Acil durum bildirimi gönderilemedi.'),
        );
      }

      final data = jsonDecode(response.body);
      return data['id'] as int;
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      rethrow;
    }
  }

  /// PATCH /api/sos-alerts/:id/note — SADECE bildirimi oluşturan kullanıcı,
  /// sonradan opsiyonel bir not ekler.
  Future<void> addSosAlertNote(int id, String note) async {
    try {
      final uri = Uri.parse('$baseUrl/sos-alerts/$id/note');
      final response = await _patch(uri, body: jsonEncode({'note': note}));

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Not eklenemedi.'),
        );
      }
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      rethrow;
    }
  }

  /// GET /api/sos-alerts — giriş yapmış herkes çağırabilir, ama görünürlük
  /// backend'de role göre ayrılır: teknisyen SADECE KENDİ gönderdiği
  /// bildirimleri (bkz. screens/sos/my_sos_alerts_screen.dart), dispeçer/
  /// yönetici TÜM bildirimleri (aktif + geçmiş) en yeniden en eskiye alır.
  Future<List<SosAlert>> getSosAlerts() async {
    try {
      final uri = Uri.parse('$baseUrl/sos-alerts');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'SOS bildirimleri listelenemedi.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => SosAlert.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      rethrow;
    }
  }

  /// PATCH /api/sos-alerts/:id/acknowledge — SADECE dispeçer/yönetici.
  Future<void> acknowledgeSosAlert(int id) async {
    try {
      final uri = Uri.parse('$baseUrl/sos-alerts/$id/acknowledge');
      final response = await _patch(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Bildirim onaylanamadı.'),
        );
      }
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      rethrow;
    }
  }

  /// PATCH /api/sos-alerts/:id/close — SADECE dispeçer/yönetici.
  Future<void> closeSosAlert(int id, {String? closedNote}) async {
    try {
      final uri = Uri.parse('$baseUrl/sos-alerts/$id/close');
      final response = await _patch(
        uri,
        body: jsonEncode({if (closedNote != null) 'closed_note': closedNote}),
      );

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Bildirim kapatılamadı.'),
        );
      }
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      rethrow;
    }
  }

  /// GET /api/users/me/supervisor — "Yöneticimi Ara" butonu için, giriş
  /// yapmış kullanıcının KENDİ bağlı olduğu dispeçer/yöneticinin ad+telefonu.
  /// Bağlı bir yönetici yoksa backend 404 döner — bu durumda çağıran taraf
  /// (bkz. screens/sos/sos_sent_screen.dart) sabit Acil Durum Hattı'na düşer.
  Future<SupervisorContact?> getMySupervisorContact() async {
    try {
      final uri = Uri.parse('$baseUrl/users/me/supervisor');
      final response = await _get(uri);

      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Yönetici bilgisi alınamadı.'),
        );
      }

      return SupervisorContact.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      rethrow;
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
          response.statusCode,
          _extractError(response, 'Açıklama sınıflandırılamadı.'),
        );
      }

      return DescriptionClassification.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
          response.statusCode,
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
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
          response.statusCode,
          _extractError(response, 'Bakım önerileri alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data
          .map((json) => MaintenanceRecommendation.fromJson(json))
          .toList();
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
          response.statusCode,
          _extractError(response, 'Önleyici iş emri oluşturulamadı.'),
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return WorkOrder.fromJson(data['work_order'] as Map<String, dynamic>);
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
          response.statusCode,
          _extractError(response, 'Bakım önerisi reddedilemedi.'),
        );
      }

      return MaintenanceRecommendation.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Malzemeler alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => MaterialItem.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  /// GET /api/materials/:id — detay + kullanım/stok hareketi geçmişi.
  Future<MaterialDetail> getMaterialDetail(int id) async {
    try {
      final uri = Uri.parse('$baseUrl/materials/$id');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Malzeme detayı alınamadı.'),
        );
      }

      return MaterialDetail.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Malzeme oluşturulamadı.'),
        );
      }

      return MaterialItem.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Stok ikmali yapılamadı.'),
        );
      }

      return MaterialItem.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
          response.statusCode,
          _extractError(response, 'Kullanılan malzemeler alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => WorkOrderMaterialUsage.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  /// POST /api/workorders/:id/materials — giriş yapmış HERKES (teknisyen
  /// dahil). Stok yetersizse backend 400 + net bir hata mesajı döner (bkz.
  /// routes/materials.js) — bu mesaj olduğu gibi ApiException'a taşınır.
  ///
  /// [warning] yalnızca kayıt "atanmamış iş emri" olarak işaretlendiyse
  /// dolu gelir (bkz. routes/materials.js `is_off_assignment`) — BLOKLAYICI
  /// bir hata DEĞİLDİR, işlem zaten başarıyla tamamlanmıştır; yalnızca
  /// bilgilendirme amaçlıdır (bkz. MaterialProvider.lastRecordWarning).
  Future<({WorkOrderMaterialUsage usage, String? warning})> recordMaterialUsage(
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
          response.statusCode,
          _extractError(response, 'Malzeme kullanımı kaydedilemedi.'),
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (
        usage: WorkOrderMaterialUsage.fromJson(data),
        warning: data['warning'] as String?,
      );
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  /// DELETE /api/workorders/:id/materials/:usageId — dispeçer/yönetici.
  /// Kaydı siler VE düşülen stoğu geri ekler (bkz. routes/materials.js).
  Future<void> removeMaterialUsage(int workOrderId, int usageId) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/workorders/$workOrderId/materials/$usageId',
      );
      final response = await _delete(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Malzeme kullanım kaydı silinemedi.'),
        );
      }
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
          response.statusCode,
          _extractError(response, 'Kritik stoktaki malzemeler alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => MaterialItem.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
          response.statusCode,
          _extractError(response, 'Kullanım analitiği alınamadı.'),
        );
      }

      return UsageAnalyticsSummary.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
          response.statusCode,
          _extractError(response, 'Bölgesel risk özeti alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => RegionalRiskSummary.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  /// GET /api/reports/fault-by-region
  Future<List<RegionFaultCount>> getFaultByRegion() async {
    try {
      final uri = Uri.parse('$baseUrl/reports/fault-by-region');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Bölgeye göre arıza dağılımı alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => RegionFaultCount.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  /// GET /api/reports/fault-by-equipment-type
  Future<List<EquipmentTypeFaultCount>> getFaultByEquipmentType() async {
    try {
      final uri = Uri.parse('$baseUrl/reports/fault-by-equipment-type');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
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
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
          response.statusCode,
          _extractError(response, 'Aylık arıza trendi alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => MonthlyFaultCount.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  /// GET /api/reports/anomaly-by-region
  Future<List<RegionAnomalySummary>> getAnomalyByRegion() async {
    try {
      final uri = Uri.parse('$baseUrl/reports/anomaly-by-region');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Bölgeye göre anomali dağılımı alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => RegionAnomalySummary.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
          response.statusCode,
          _extractError(response, 'En çok kullanılan malzemeler alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => TopMaterialUsage.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
          response.statusCode,
          _extractError(response, 'Sohbet geçmişi alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => ChatMessage.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
          response.statusCode,
          _extractError(response, 'Asistan yanıtı alınamadı.'),
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return AssistantReply.fromJson(data);
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
          response.statusCode,
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
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
          response.statusCode,
          _extractError(response, 'Kişisel veri özeti alınamadı.'),
        );
      }

      return KvkkDataSummary.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
          response.statusCode,
          _extractError(response, 'Silme talebi oluşturulamadı.'),
        );
      }
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  /// GET /api/kvkk/deletion-requests — yalnızca yönetici.
  Future<List<KvkkDeletionRequest>> getAllDeletionRequests() async {
    try {
      final uri = Uri.parse('$baseUrl/kvkk/deletion-requests');
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Silme talepleri alınamadı.'),
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => KvkkDeletionRequest.fromJson(json)).toList();
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Talep onaylanamadı.'),
        );
      }
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Talep reddedilemedi.'),
        );
      }
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
    }
  }

  // --- Denetim Logu (Audit Log) — yalnızca yönetici ---
  // GET /api/audit-log?category=&actor_id=&from=&to=&page=&limit= — bkz.
  // routes/auditLog.js + services/auditLogAggregator.js. Sistemdeki tüm
  // state-changing işlemlerin (login denemeleri, kullanıcı/cihaz yönetimi,
  // stok hareketleri, KVKK talepleri, otomatik dosya temizliği) TEK, birleşik
  // bir görünümü.
  Future<AuditLogPage> getAuditLog({
    AuditLogCategory? category,
    int? actorId,
    DateTime? fromDate,
    DateTime? toDate,
    int page = 1,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/audit-log').replace(
        queryParameters: {
          if (category != null) 'category': category.toJson(),
          if (actorId != null) 'actor_id': '$actorId',
          if (fromDate != null) 'from': fromDate.toUtc().toIso8601String(),
          if (toDate != null) 'to': toDate.toUtc().toIso8601String(),
          'page': '$page',
        },
      );
      final response = await _get(uri);

      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          _extractError(response, 'Denetim logu alınamadı.'),
        );
      }

      return AuditLogPage.fromJson(jsonDecode(response.body));
    } on ApiException {
      rethrow;
    } on SessionExpiredException {
      // Sessiz yenileme (bkz. _authenticated/_refreshAccessToken) BİLE
      // başarısız oldu — oturum GERÇEKTEN bitti. onUnauthorized callback'i
      // (AuthProvider.handleSessionExpired) bu noktaya gelinmeden ÖNCE zaten
      // tetiklenmiş olur; burada yalnızca bu özel tipi OLDUĞU GİBİ yukarı
      // taşıyoruz — rethrow olmasaydı bu `on` bloğu istisnayı "yakalanmış"
      // sayıp yutar, çağıran taraf oturumun bittiğini asla öğrenemezdi.
      rethrow;
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
