import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/work_order.dart' show AssignedUser;
import '../services/api_service.dart';
import '../utils/role_helper.dart' as role_helper;

/// Auth (Modül 7 — Kullanıcı Rolleri ve Yetkilendirme) durumunu yönetir:
/// giriş/çıkış, uygulama açılışında otomatik giriş denemesi ve rol bazlı
/// erişim kontrolü için kolay erişilebilir getter'lar.
class AuthProvider extends ChangeNotifier {
  static const _tokenKey = 'auth_token';

  final ApiService _api = ApiService();

  String? _token;
  AssignedUser? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  AuthProvider() {
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

  /// Kullanıcının rolünün Türkçe, ekranda gösterilebilir hâli — AppBar'daki
  /// rol rozeti, Ana Sayfa karşılaması ve Profil ekranı bunu kullanır.
  String get roleLabel => _currentUser != null ? role_helper.roleLabel(_currentUser!.role) : '';

  Future<bool> login(String sicilNo, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _api.login(sicilNo: sicilNo, password: password);
      _token = result.token;
      _currentUser = result.user;
      ApiService.authToken = _token;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, _token!);

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
      final prefs = await SharedPreferences.getInstance();
      final storedToken = prefs.getString(_tokenKey);

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

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);

    notifyListeners();
  }
}
