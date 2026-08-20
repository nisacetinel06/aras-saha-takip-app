import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

/// İki Faktörlü Doğrulama (2FA) KURULUM akışının state'i — bkz.
/// screens/settings/two_factor_setup_screen.dart. Login akışının 2. adımı
/// (pending_token doğrulama) BURADA DEĞİL, AuthProvider'dadır (bkz. o
/// dosyadaki verifyTwoFactor) — bu provider yalnızca GİRİŞ YAPMIŞ bir
/// yöneticinin kendi 2FA'sını etkinleştirme/devre dışı bırakma akışını yönetir.
class TwoFactorProvider extends ChangeNotifier {
  final ApiService _apiService;

  TwoFactorProvider({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  bool _isSettingUp = false;
  String? _setupErrorMessage;
  String? _otpauthUri;
  List<String> _backupCodes = [];

  bool _isConfirming = false;
  String? _confirmErrorMessage;

  bool _isDisabling = false;
  String? _disableErrorMessage;

  bool get isSettingUp => _isSettingUp;
  String? get setupErrorMessage => _setupErrorMessage;
  String? get otpauthUri => _otpauthUri;
  List<String> get backupCodes => _backupCodes;

  bool get isConfirming => _isConfirming;
  String? get confirmErrorMessage => _confirmErrorMessage;

  bool get isDisabling => _isDisabling;
  String? get disableErrorMessage => _disableErrorMessage;

  Future<bool> setup() async {
    _isSettingUp = true;
    _setupErrorMessage = null;
    notifyListeners();

    try {
      final result = await _apiService.setupTwoFactor();
      _otpauthUri = result.otpauthUri;
      _backupCodes = result.backupCodes;
      return true;
    } catch (e) {
      _setupErrorMessage = e.toString();
      return false;
    } finally {
      _isSettingUp = false;
      notifyListeners();
    }
  }

  Future<bool> confirm(String code) async {
    _isConfirming = true;
    _confirmErrorMessage = null;
    notifyListeners();

    try {
      await _apiService.confirmTwoFactor(code);
      return true;
    } catch (e) {
      _confirmErrorMessage = e.toString();
      return false;
    } finally {
      _isConfirming = false;
      notifyListeners();
    }
  }

  Future<bool> disable(String password) async {
    _isDisabling = true;
    _disableErrorMessage = null;
    notifyListeners();

    try {
      await _apiService.disableTwoFactor(password);
      return true;
    } catch (e) {
      _disableErrorMessage = e.toString();
      return false;
    } finally {
      _isDisabling = false;
      notifyListeners();
    }
  }

  /// Kurulum akışı iptal edilir/ekran kapatılırsa QR/yedek kod state'ini
  /// temizler — bir sonraki `setup()` çağrısı her zaman SIFIRDAN başlar.
  void reset() {
    _otpauthUri = null;
    _backupCodes = [];
    _setupErrorMessage = null;
    _confirmErrorMessage = null;
    notifyListeners();
  }
}
