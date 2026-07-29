import 'package:flutter/foundation.dart';
import '../models/equipment.dart';
import '../services/api_service.dart';

/// Ekipman / Envanter (QR Kod) modülünün (Modül 4) state'ini yönetir:
/// ekipman listesi, QR/manuel kod ile sorgulama, id ile detay ve geçmiş arıza
/// kaydı çekme; her akışın kendi loading/error state'i ayrı tutulur çünkü
/// bunlar farklı ekranlarda (liste, QR tarama, detay) bağımsız çalışır.
class EquipmentProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  List<Equipment> _equipmentList = [];
  bool _isListLoading = false;
  String? _listErrorMessage;
  EquipmentType? _typeFilter;
  EquipmentStatus? _statusFilter;

  Equipment? _selectedEquipment;
  bool _isDetailLoading = false;
  String? _detailErrorMessage;

  List<EquipmentHistoryEntry> _history = [];
  bool _isHistoryLoading = false;
  String? _historyErrorMessage;

  bool _isQrLookupLoading = false;
  String? _qrLookupErrorMessage;

  List<Equipment> get equipmentList => _equipmentList;
  bool get isListLoading => _isListLoading;
  String? get listErrorMessage => _listErrorMessage;
  EquipmentType? get typeFilter => _typeFilter;
  EquipmentStatus? get statusFilter => _statusFilter;

  Equipment? get selectedEquipment => _selectedEquipment;
  bool get isDetailLoading => _isDetailLoading;
  String? get detailErrorMessage => _detailErrorMessage;

  List<EquipmentHistoryEntry> get history => _history;
  bool get isHistoryLoading => _isHistoryLoading;
  String? get historyErrorMessage => _historyErrorMessage;

  bool get isQrLookupLoading => _isQrLookupLoading;
  String? get qrLookupErrorMessage => _qrLookupErrorMessage;

  Future<void> fetchEquipmentList() async {
    _isListLoading = true;
    _listErrorMessage = null;
    notifyListeners();

    try {
      _equipmentList = await _apiService.getEquipmentList(
        typeFilter: _typeFilter?.name,
        statusFilter: _statusFilter?.apiValue,
      );
    } catch (e) {
      _listErrorMessage = e.toString();
    } finally {
      _isListLoading = false;
      notifyListeners();
    }
  }

  Future<void> setTypeFilter(EquipmentType? type) async {
    _typeFilter = type;
    await fetchEquipmentList();
  }

  Future<void> setStatusFilter(EquipmentStatus? status) async {
    _statusFilter = status;
    await fetchEquipmentList();
  }

  /// QR tarama ya da manuel kod girişi sonrası çağrılır. Başarılıysa
  /// bulunan `Equipment` döner (çağıran taraf bununla detay ekranına gider);
  /// 404 dahil her hata durumunda null döner ve mesaj `qrLookupErrorMessage`
  /// üzerinden okunabilir — böylece QR tarama ekranı kamerayı kapatmadan
  /// üstte kısa süreli bir uyarı gösterip taramaya devam edebilir.
  Future<Equipment?> fetchEquipmentByQr(String code) async {
    _isQrLookupLoading = true;
    _qrLookupErrorMessage = null;
    notifyListeners();

    try {
      final equipment = await _apiService.getEquipmentByQr(code);
      return equipment;
    } catch (e) {
      _qrLookupErrorMessage = e.toString();
      return null;
    } finally {
      _isQrLookupLoading = false;
      notifyListeners();
    }
  }

  void clearQrLookupError() {
    _qrLookupErrorMessage = null;
    notifyListeners();
  }

  Future<void> fetchEquipmentDetail(int id) async {
    _isDetailLoading = true;
    _detailErrorMessage = null;
    notifyListeners();

    try {
      _selectedEquipment = await _apiService.getEquipmentDetail(id);
    } catch (e) {
      _detailErrorMessage = e.toString();
    } finally {
      _isDetailLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchEquipmentHistory(int id) async {
    _isHistoryLoading = true;
    _historyErrorMessage = null;
    notifyListeners();

    try {
      _history = await _apiService.getEquipmentHistory(id);
    } catch (e) {
      _historyErrorMessage = e.toString();
    } finally {
      _isHistoryLoading = false;
      notifyListeners();
    }
  }
}
