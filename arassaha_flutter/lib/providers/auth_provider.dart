import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/work_order.dart' show AssignedUser;
import '../services/api_service.dart';
import '../services/push_notification_service.dart';
import '../services/secure_storage_service.dart';
import '../utils/error_mapper.dart';
import '../utils/role_helper.dart' as role_helper;

/// Auth (Modül 7 — Kullanıcı Rolleri ve Yetkilendirme) durumunu yönetir:
/// giriş/çıkış, uygulama açılışında otomatik giriş denemesi ve rol bazlı
/// erişim kontrolü için kolay erişilebilir getter'lar.
class AuthProvider extends ChangeNotifier {
  // ESKİ (artık yalnızca tek seferlik MIGRATION için okunuyor, bkz.
  // tryAutoLogin) — token bu anahtarla SharedPreferences'ta düz metin
  // olarak tutuluyordu. Yeni token'lar ARTIK burada DEĞİL, _secureStorage'da
  // saklanır (bkz. services/secure_storage_service.dart üstündeki NEDEN
  // notu). Bu sabit SİLİNMEMELİ — mevcut kurulu uygulamalardaki
  // kullanıcıların migration'ı bu anahtara bağlı.
  static const _legacyTokenKey = 'auth_token';

  final ApiService _api;
  final SecureStorageService _secureStorage;

  String? _token;
  AssignedUser? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  // "Şifremi Değiştir" — bkz. changePassword. Login akışının _isLoading/
  // _errorMessage'ından BİLİNÇLİ olarak AYRI alanlar: aksi halde bu ekranda
  // bir hata, farklı bir ekranda (örn. arka planda tekrar tetiklenen bir
  // login denemesi) yanlışlıkla gösterilebilirdi.
  bool _isChangingPassword = false;
  String? _changePasswordErrorMessage;
  bool _changePasswordErrorIsCurrentPasswordWrong = false;

  // "Şifremi Unuttum" (Giriş ekranı) — bkz. requestPasswordReset. Login/
  // değiştir akışlarının kendi _isLoading/_errorMessage'ından BİLİNÇLİ olarak
  // AYRI alanlar (changePassword'deki AYNI gerekçe): bu istek Giriş ekranından,
  // henüz kimlik doğrulaması TAMAMLANMAMIŞKEN yapılır.
  bool _isRequestingPasswordReset = false;
  String? _passwordResetRequestError;

  // İki Faktörlü Doğrulama (2FA) — bkz. routes/twoFactor.js. `login()`
  // 2FA etkin bir yönetici için TAM token çifti yerine bu kısa ömürlü (5 dk)
  // ara token'ı döndürdüğünde burada saklanır; giriş `verifyTwoFactor()`
  // BAŞARILI olana kadar TAMAMLANMAZ (isAuthenticated hâlâ false kalır).
  String? _pendingTwoFactorToken;

  AuthProvider({ApiService? apiService, SecureStorageService? secureStorage})
    : _api = apiService ?? ApiService(),
      _secureStorage = secureStorage ?? SecureStorageService() {
    // Herhangi bir istek 401 dönerse VE sessiz yenileme (bkz.
    // ApiService._refreshAccessToken) DE başarısız olursa (refresh_token
    // kendisi de süresi dolmuş/iptal edilmiş) oturumu burada temizleriz —
    // AuthGate bunu dinleyip kullanıcıyı otomatik olarak LoginScreen'e
    // düşürür (bkz. main.dart). Sessiz yenileme BAŞARILI olduğu (çok daha
    // sık rastlanan) durumda bu HİÇ tetiklenmez.
    ApiService.onUnauthorized = handleSessionExpired;
    // 401 sonrası sessiz bir yenileme (VEYA tryAutoLogin sırasında açık bir
    // yenileme) YENİ bir token çifti ürettiğinde, bunu KALICI depolamaya
    // (SecureStorageService) yazmak için çağrılır — aksi halde uygulama bir
    // sonraki açılışta hâlâ ESKİ (artık rotasyonla iptal edilmiş) refresh
    // token'ı kullanmaya çalışırdı.
    ApiService.onTokenRefreshed = _persistRefreshedTokens;
  }

  String? get token => _token;
  AssignedUser? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _token != null && _currentUser != null;

  bool get isChangingPassword => _isChangingPassword;
  String? get changePasswordErrorMessage => _changePasswordErrorMessage;

  bool get isRequestingPasswordReset => _isRequestingPasswordReset;
  String? get passwordResetRequestError => _passwordResetRequestError;

  /// true ise hata backend'in 401 (mevcut şifre hatalı) yanıtından geliyor
  /// demektir — çağıran ekran (ChangePasswordScreen) bu durumda hatayı genel
  /// bir SnackBar yerine "Mevcut Şifre" alanının ALTINDA göstermelidir
  /// (bkz. PROMPT madde 3).
  bool get changePasswordErrorIsCurrentPasswordWrong =>
      _changePasswordErrorIsCurrentPasswordWrong;

  /// `login()` 2FA gerektiren bir yanıt döndürdüyse true olur —
  /// LoginScreen bunu görünce TwoFactorVerifyScreen'e yönlendirir.
  bool get requiresTwoFactor => _pendingTwoFactorToken != null;

  bool get isTeknisyen => _currentUser?.role == 'teknisyen';
  bool get isDispecer => _currentUser?.role == 'dispecer';
  bool get isYonetici => _currentUser?.role == 'yonetici';

  /// İş emri oluşturma/atama yetkisi — dispeçer ve yönetici.
  bool get canCreateWorkOrders => isDispecer || isYonetici;

  /// İş emri durum güncelleme yetkisi — yalnızca teknisyen ve dispeçer.
  /// Yönetici sahada çalışmadığı için durumu bizzat değiştiremez, yalnızca
  /// takip eder (bkz. WorkOrderDetailScreen "Durum Güncelle" bölümü ve
  /// backend PATCH /api/workorders/:id/status — requireRole ile aynı kural).
  bool get canUpdateWorkOrderStatus => isTeknisyen || isDispecer;

  /// Kullanıcının rolünün Türkçe, ekranda gösterilebilir hâli — AppBar'daki
  /// rol rozeti, Ana Sayfa karşılaması ve Profil ekranı bunu kullanır.
  String get roleLabel =>
      _currentUser != null ? role_helper.roleLabel(_currentUser!.role) : '';

  /// [false] dönmesi iki farklı anlama gelebilir: GERÇEK bir hata
  /// ([errorMessage] dolar) YA DA 2FA doğrulaması gerekiyor ([requiresTwoFactor]
  /// true olur, hata YOKTUR) — çağıran taraf (LoginScreen) HER İKİSİNİ de
  /// ayrı ayrı kontrol etmelidir.
  Future<bool> login(String sicilNo, String password) async {
    _isLoading = true;
    _errorMessage = null;
    _pendingTwoFactorToken = null;
    notifyListeners();

    try {
      final result = await _api.login(sicilNo: sicilNo, password: password);

      if (result.requiresTwoFactor) {
        _pendingTwoFactorToken = result.pendingToken;
        return false;
      }

      _token = result.accessToken;
      _currentUser = result.user;
      ApiService.authToken = result.accessToken;
      ApiService.refreshToken = result.refreshToken;

      await _secureStorage.saveToken(result.accessToken!);
      await _secureStorage.saveRefreshToken(result.refreshToken!);

      return true;
    } catch (e) {
      _errorMessage = mapExceptionToUserMessage(e);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Login akışının 2. adımı — [code] authenticator'daki TOTP kodu ya da
  /// bir yedek kod olabilir (bkz. ApiService.verifyTwoFactor). Başarılıysa
  /// [isAuthenticated] true olur (normal login sonrasıyla AYNI durum).
  Future<bool> verifyTwoFactor(String code) async {
    final pendingToken = _pendingTwoFactorToken;
    if (pendingToken == null) return false;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _api.verifyTwoFactor(
        pendingToken: pendingToken,
        code: code,
      );
      _token = result.accessToken;
      _currentUser = result.user;
      ApiService.authToken = result.accessToken;
      ApiService.refreshToken = result.refreshToken;

      await _secureStorage.saveToken(result.accessToken);
      await _secureStorage.saveRefreshToken(result.refreshToken);
      _pendingTwoFactorToken = null;

      return true;
    } catch (e) {
      _errorMessage = mapExceptionToUserMessage(e);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Kullanıcı 2FA doğrulama ekranından geri dönerse (authenticator'a
  /// erişimi yok, vazgeçti vb.) bekleyen ara token'ı temizler.
  void cancelTwoFactor() {
    _pendingTwoFactorToken = null;
    _errorMessage = null;
    notifyListeners();
  }

  /// "Şifremi Değiştir" — bkz. ApiService.changePassword, routes/auth.js
  /// POST /change-password. Admin'in [resetUserPassword] akışından (Kullanıcı
  /// Yönetimi) BİLİNÇLİ olarak AYRI: bu, kullanıcının KENDİ isteğiyle, kendi
  /// bildiği mevcut şifreyle yaptığı bir değişikliktir.
  ///
  /// BİLİNÇLİ OLARAK burada [handleSessionExpired] ÇAĞRILMAZ: backend başarılı
  /// bir değişiklikte bu kullanıcının TÜM refresh_token'larını (bu cihaz
  /// DAHİL) zaten sunucu tarafında iptal etti, ama yerel oturumu BURADA hemen
  /// temizlersek AuthGate ekranı ANINDA (kullanıcı "Şifreniz değiştirildi"
  /// onayını görmeden) LoginScreen'e düşürebilir — ChangePasswordScreen bu
  /// widget ağacının bir parçası olduğu için o an yarım kalmış/tuhaf bir geçiş
  /// yaşanır. Bunun yerine ekran ÖNCE onay mesajını gösterir, kullanıcı
  /// kapattıktan SONRA ayrıca [handleSessionExpired]'ı çağırır (bkz.
  /// screens/settings/change_password_screen.dart) — sıralama tamamen
  /// çağıran tarafın (UI) kontrolünde kalır.
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    _isChangingPassword = true;
    _changePasswordErrorMessage = null;
    _changePasswordErrorIsCurrentPasswordWrong = false;
    notifyListeners();

    try {
      await _api.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      return true;
    } catch (e) {
      // Bu endpoint'in TÜM hata mesajları (bkz. routes/auth.js POST
      // /change-password) zaten kullanıcıya gösterilebilir, Türkçe metinler
      // — genel mapExceptionToUserMessage'ın "HER 401 = oturum süresi doldu"
      // varsayımı burada YANLIŞ olurdu (bu 401 "mevcut şifre hatalı"
      // anlamına gelir, bkz. ApiService.changePassword dokümantasyonu). Bu
      // yüzden bir ApiException için backend'in kendi mesajı AYNEN
      // kullanılır; ağ hatası gibi ApiException OLMAYAN durumlarda genel
      // mapper geçerli kalır.
      _changePasswordErrorIsCurrentPasswordWrong =
          e is ApiException && e.statusCode == 401;
      _changePasswordErrorMessage = e is ApiException
          ? e.message
          : mapExceptionToUserMessage(e);
      return false;
    } finally {
      _isChangingPassword = false;
      notifyListeners();
    }
  }

  /// "Şifremi Unuttum" — bkz. ApiService.requestPasswordReset, routes/auth.js
  /// POST /forgot-password. Giriş ekranından, kimlik doğrulaması OLMADAN
  /// çağrılır. Dönen [String] her zaman backend'in genel (sicil_no'nun kayıtlı
  /// olup olmadığını gizleyen) onay mesajıdır — çağıran ekran bunu doğrudan
  /// gösterebilir. Hata YALNIZCA ağ/sunucu sorunu (rate limit, 500 vb.)
  /// durumunda [passwordResetRequestError]'a yazılır.
  Future<String?> requestPasswordReset(String sicilNo) async {
    _isRequestingPasswordReset = true;
    _passwordResetRequestError = null;
    notifyListeners();

    try {
      return await _api.requestPasswordReset(sicilNo);
    } catch (e) {
      _passwordResetRequestError = mapExceptionToUserMessage(e);
      return null;
    } finally {
      _isRequestingPasswordReset = false;
      notifyListeners();
    }
  }

  /// GERÇEK bir sunucu taraflı oturum sonlandırma — yalnızca yerel depolamayı
  /// temizlemek YETERSİZDİR (bkz. "Güvenli Token Saklama" görevi): çalınmış
  /// bir refresh_token, yerel temizlik yapılsa bile başka bir cihazdan hâlâ
  /// kullanılabilirdi. Bu yüzden önce backend'e POST /api/auth/logout ile
  /// refresh_token'ı İPTAL ETTİRİR (bkz. ApiService.logout, routes/auth.js),
  /// ANCAK BUNDAN SONRA yerel oturumu temizler.
  Future<void> logout() async {
    // Push Bildirim (FCM) — backend'deki kayıtlı token, oturum (VE dolayısıyla
    // Authorization header'ı) hâlâ geçerliyken temizlenir; handleSessionExpired
    // sonrası authToken null olduğu için bu istek artık kimliksiz kalırdı.
    // PushNotificationService.clearRegisteredToken kendi hatasını zaten
    // sessizce yutar (bkz. o metod) — çıkış akışını asla engellemez.
    await PushNotificationService.instance.clearRegisteredToken();

    final storedRefreshToken = await _secureStorage.getRefreshToken();
    if (storedRefreshToken != null) {
      // ApiService.logout ağ hatasını zaten sessizce yutar (bkz. oradaki
      // dokümantasyon notu) — çıkış akışı bu yüzden asla kullanıcıyı
      // kilitlemez, ama backend'e iptal isteği GERÇEKTEN gönderilmiş olur.
      await _api.logout(storedRefreshToken);
    }
    await handleSessionExpired();
  }

  /// Uygulama açılışında çağrılır: cihazda kayıtlı bir access token varsa
  /// GET /api/auth/me ile geçerliliğini kontrol eder. Access token süresi
  /// dolmuşsa (bkz. Access + Refresh Token Sistemi, 15 dk) ama kayıtlı bir
  /// refresh_token HÂLÂ geçerliyse, kullanıcıya HİÇ fark ettirmeden bir
  /// yenileme denenir — yalnızca refresh_token da geçersiz/süresi
  /// dolmuşsa/hiç yoksa oturum gerçekten temizlenir ve kullanıcı
  /// LoginScreen'e yönlendirilir (AuthGate isAuthenticated'a bakar).
  Future<void> tryAutoLogin() async {
    _isLoading = true;
    notifyListeners();

    try {
      String? storedToken = await _secureStorage.getToken();
      final storedRefreshToken = await _secureStorage.getRefreshToken();

      // MIGRATION (KRİTİK — bu güvenlik iyileştirmesinden ÖNCE yayınlanmış
      // sürümlerde token SharedPreferences'ta düz metin olarak duruyordu).
      // Güvenli depolamada token yoksa, eski konumda kalmış bir token olup
      // olmadığına bakılır — varsa var olan kullanıcı habersizce "çıkış
      // yapılmış" gibi GÖSTERİLMEMESİ için önce güvenli depolamaya taşınır,
      // sonra eski (güvensiz) kopya SİLİNİR. Bu blok yalnızca BİR KEZ
      // çalışır: taşıma sonrası _legacyTokenKey bir daha hiç yazılmaz, bu
      // yüzden bir sonraki açılışta `legacyToken` zaten null olur ve bu dal
      // atlanır. (Bu MIGRATION döneminden kalma token'lar için hiçbir
      // refresh_token YOKTUR — bu, süresi dolduklarında normal şekilde
      // yeniden girişe düşecekleri anlamına gelir, bu BEKLENEN bir davranıştır.)
      if (storedToken == null) {
        final prefs = await SharedPreferences.getInstance();
        final legacyToken = prefs.getString(_legacyTokenKey);
        if (legacyToken != null) {
          await _secureStorage.saveToken(legacyToken);
          await prefs.remove(_legacyTokenKey);
          storedToken = legacyToken;
        }
      }

      if (storedToken == null) {
        return;
      }

      ApiService.authToken = storedToken;
      ApiService.refreshToken = storedRefreshToken;

      AssignedUser user;
      try {
        user = await _api.getMe(storedToken);
      } on ApiException {
        // Access token GERÇEKTEN süresi dolmuş/geçersiz olabilir — GERÇEKTEN
        // oturumu bitirmeden önce, hâlâ geçerli olabilecek bir refresh_token
        // varsa sessizce bir yenileme denenir (bkz. sınıf başı dokümantasyonu).
        if (storedRefreshToken == null) {
          rethrow;
        }
        final refreshed = await _api.refresh(storedRefreshToken);
        await _persistRefreshedTokens(
          refreshed.accessToken,
          refreshed.refreshToken,
        );
        storedToken = refreshed.accessToken;
        user = await _api.getMe(storedToken);
      }

      _token = storedToken;
      _currentUser = user;
      ApiService.authToken = storedToken;
    } catch (_) {
      await handleSessionExpired();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sessiz bir yenileme (401 sonrası otomatik VEYA tryAutoLogin sırasında
  /// açık) YENİ bir token çifti ürettiğinde çağrılır — ApiService.authToken/
  /// refreshToken static alanları ZATEN güncel (bkz. ApiService.onTokenRefreshed
  /// çağrı noktası); burada asıl iş, bu YENİ çiftin KALICI depolamaya
  /// (SecureStorageService) da yazılmasıdır — aksi halde uygulama bir sonraki
  /// açılışta hâlâ ESKİ (rotasyonla artık iptal edilmiş) refresh_token'ı
  /// kullanmaya çalışırdı.
  Future<void> _persistRefreshedTokens(
    String accessToken,
    String refreshToken,
  ) async {
    _token = accessToken;
    ApiService.authToken = accessToken;
    ApiService.refreshToken = refreshToken;

    await _secureStorage.saveToken(accessToken);
    await _secureStorage.saveRefreshToken(refreshToken);

    notifyListeners();
  }

  /// GERÇEK bir oturum sonlandırma anı: ya `logout()` (kullanıcı bilerek
  /// çıkış yaptı) ya da bir isteğin 401 dönüp sessiz yenilemenin DE
  /// başarısız olduğu an (bkz. ApiService.onUnauthorized — refresh_token'ın
  /// kendisi de süresi dolmuş/iptal edilmiş) çağrılır. Her iki durumda da
  /// AuthGate bunu (isAuthenticated=false) dinleyip kullanıcıyı otomatik
  /// olarak LoginScreen'e düşürür (bkz. main.dart) — bu, "SessionExpiredException
  /// + global oturum-bitti mekanizması" gereksiniminin uygulama tarafıdır.
  Future<void> handleSessionExpired() async {
    _token = null;
    _currentUser = null;
    ApiService.authToken = null;
    ApiService.refreshToken = null;

    await _secureStorage.clearAll();
    // Migration henüz hiç çalışmadan (örn. kullanıcı hiç açmadan) çıkış
    // yapılan bir senaryoda bile eski anahtarın artık kalıntı olarak
    // durmaması için burada da temizlenir.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyTokenKey);

    notifyListeners();
  }
}
