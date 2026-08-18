import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/work_order.dart' show AssignedUser;
import '../services/api_service.dart';
import '../services/secure_storage_service.dart';
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

  AuthProvider({ApiService? apiService, SecureStorageService? secureStorage})
    : _api = apiService ?? ApiService(),
      _secureStorage = secureStorage ?? SecureStorageService() {
    // Herhangi bir istek 401 dönerse (token süresi doldu/geçersiz), oturumu
    // burada temizleriz — AuthGate bunu dinleyip kullanıcıyı otomatik olarak
    // LoginScreen'e düşürür (bkz. main.dart).
    ApiService.onUnauthorized = _clearSession;
  }

  String? get token => _token;
  AssignedUser? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _token != null && _currentUser != null;

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

  Future<bool> login(String sicilNo, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _api.login(sicilNo: sicilNo, password: password);
      _token = result.token;
      _currentUser = result.user;
      ApiService.authToken = _token;

      await _secureStorage.saveToken(_token!);

      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _clearSession();
  }

  /// Uygulama açılışında çağrılır: cihazda kayıtlı bir token varsa
  /// GET /api/auth/me ile geçerliliğini kontrol eder. Token geçersizse
  /// (süresi dolmuş, kullanıcı silinmiş vb.) sessizce temizlenir ve
  /// kullanıcı LoginScreen'e yönlendirilir (AuthGate isAuthenticated'a bakar).
  Future<void> tryAutoLogin() async {
    _isLoading = true;
    notifyListeners();

    try {
      String? storedToken = await _secureStorage.getToken();

      // MIGRATION (KRİTİK — bu güvenlik iyileştirmesinden ÖNCE yayınlanmış
      // sürümlerde token SharedPreferences'ta düz metin olarak duruyordu).
      // Güvenli depolamada token yoksa, eski konumda kalmış bir token olup
      // olmadığına bakılır — varsa var olan kullanıcı habersizce "çıkış
      // yapılmış" gibi GÖSTERİLMEMESİ için önce güvenli depolamaya taşınır,
      // sonra eski (güvensiz) kopya SİLİNİR. Bu blok yalnızca BİR KEZ
      // çalışır: taşıma sonrası _legacyTokenKey bir daha hiç yazılmaz, bu
      // yüzden bir sonraki açılışta `legacyToken` zaten null olur ve bu dal
      // atlanır.
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

      final user = await _api.getMe(storedToken);
      _token = storedToken;
      _currentUser = user;
      ApiService.authToken = storedToken;
    } catch (_) {
      await _clearSession();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _clearSession() async {
    _token = null;
    _currentUser = null;
    ApiService.authToken = null;

    await _secureStorage.clearAll();
    // Migration henüz hiç çalışmadan (örn. kullanıcı hiç açmadan) çıkış
    // yapılan bir senaryoda bile eski anahtarın artık kalıntı olarak
    // durmaması için burada da temizlenir.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyTokenKey);

    notifyListeners();
  }
}
