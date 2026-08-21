import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/app_user.dart';
import '../services/api_service.dart';
import '../utils/error_mapper.dart';

/// Profil ve Kullanıcı Yönetimi (Modül 8) ekranlarının state'ini yönetir:
/// kendi profilim, (yönetici için) kullanıcı listesi/detayı, kullanıcı
/// oluşturma/güncelleme/fotoğraf yükleme/pasifleştirme.
class UserProvider extends ChangeNotifier {
  final ApiService _apiService;

  UserProvider({ApiService? apiService})
    : _apiService = apiService ?? ApiService();

  AppUser? _myProfile;
  bool _isLoadingProfile = false;
  String? _profileErrorMessage;

  List<AppUser> _users = [];
  bool _isLoadingUsers = false;
  String? _usersErrorMessage;

  AppUser? _selectedUser;
  bool _isLoadingDetail = false;
  String? _detailErrorMessage;

  bool _isSaving = false;
  String? _saveErrorMessage;

  AppUser? get myProfile => _myProfile;
  bool get isLoadingProfile => _isLoadingProfile;
  String? get profileErrorMessage => _profileErrorMessage;

  List<AppUser> get users => _users;
  bool get isLoadingUsers => _isLoadingUsers;
  String? get usersErrorMessage => _usersErrorMessage;

  AppUser? get selectedUser => _selectedUser;
  bool get isLoadingDetail => _isLoadingDetail;
  String? get detailErrorMessage => _detailErrorMessage;

  bool get isSaving => _isSaving;
  String? get saveErrorMessage => _saveErrorMessage;

  Future<void> fetchMyProfile() async {
    _isLoadingProfile = true;
    _profileErrorMessage = null;
    notifyListeners();

    try {
      _myProfile = await _apiService.getMyProfile();
    } catch (e) {
      _profileErrorMessage = mapExceptionToUserMessage(e);
    } finally {
      _isLoadingProfile = false;
      notifyListeners();
    }
  }

  Future<void> fetchAllUsers({String? roleFilter}) async {
    _isLoadingUsers = true;
    _usersErrorMessage = null;
    notifyListeners();

    try {
      _users = await _apiService.getAllUsersFull(roleFilter: roleFilter);
    } catch (e) {
      _usersErrorMessage = mapExceptionToUserMessage(e);
    } finally {
      _isLoadingUsers = false;
      notifyListeners();
    }
  }

  Future<void> fetchUserDetail(int id) async {
    _isLoadingDetail = true;
    _detailErrorMessage = null;
    _selectedUser = null;
    notifyListeners();

    try {
      _selectedUser = await _apiService.getUserDetail(id);
    } catch (e) {
      _detailErrorMessage = mapExceptionToUserMessage(e);
    } finally {
      _isLoadingDetail = false;
      notifyListeners();
    }
  }

  Future<bool> createUser({
    required String name,
    required String sicilNo,
    required String password,
    required String role,
    String? phone,
    String? email,
    int? supervisorId,
  }) async {
    _isSaving = true;
    _saveErrorMessage = null;
    notifyListeners();

    try {
      // Oluşturulan kullanıcı _selectedUser'a atanır — çağıran taraf (örn.
      // UserEditScreen), yeni kullanıcının id'sini fotoğraf yüklemek için
      // buradan okur (bkz. updateUser ile aynı desen).
      _selectedUser = await _apiService.createUser(
        name: name,
        sicilNo: sicilNo,
        password: password,
        role: role,
        phone: phone,
        email: email,
        supervisorId: supervisorId,
      );
      return true;
    } catch (e) {
      _saveErrorMessage = mapExceptionToUserMessage(e);
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  /// `updateSupervisor: true` verilirse dispeçer bağı da güncellenir
  /// (bkz. ApiService.updateUser — atama/değiştirme/silme aynı alan
  /// üzerinden yönetilir, `supervisorId: null` bağı kaldırır).
  Future<bool> updateUser(
    int id, {
    String? name,
    String? phone,
    String? email,
    String? role,
    bool updateSupervisor = false,
    int? supervisorId,
  }) async {
    _isSaving = true;
    _saveErrorMessage = null;
    notifyListeners();

    try {
      _selectedUser = await _apiService.updateUser(
        id,
        name: name,
        phone: phone,
        email: email,
        role: role,
        updateSupervisor: updateSupervisor,
        supervisorId: supervisorId,
      );
      return true;
    } catch (e) {
      _saveErrorMessage = mapExceptionToUserMessage(e);
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<bool> uploadUserPhoto(int id, File imageFile) async {
    _isSaving = true;
    _saveErrorMessage = null;
    notifyListeners();

    try {
      _selectedUser = await _apiService.uploadUserPhoto(id, imageFile);
      return true;
    } catch (e) {
      _saveErrorMessage = mapExceptionToUserMessage(e);
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<bool> deactivateUser(int id) async {
    _isSaving = true;
    _saveErrorMessage = null;
    notifyListeners();

    try {
      final updated = await _apiService.deactivateUser(id);
      _replaceInList(updated);
      return true;
    } catch (e) {
      _saveErrorMessage = mapExceptionToUserMessage(e);
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<bool> reactivateUser(int id) async {
    _isSaving = true;
    _saveErrorMessage = null;
    notifyListeners();

    try {
      final updated = await _apiService.reactivateUser(id);
      _replaceInList(updated);
      return true;
    } catch (e) {
      _saveErrorMessage = mapExceptionToUserMessage(e);
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  /// Yönetici tarafından şifre sıfırlama — teknisyen/dispeçer kendi şifresini
  /// değiştiremediği için (profil salt-okunur), şifresini unutan bir
  /// kullanıcı için bu akış kullanılır.
  Future<bool> resetPassword(int id, String newPassword) async {
    _isSaving = true;
    _saveErrorMessage = null;
    notifyListeners();

    try {
      await _apiService.resetUserPassword(id, newPassword);
      return true;
    } catch (e) {
      _saveErrorMessage = mapExceptionToUserMessage(e);
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  void _replaceInList(AppUser updated) {
    final index = _users.indexWhere((u) => u.id == updated.id);
    if (index != -1) _users[index] = updated;
  }
}
