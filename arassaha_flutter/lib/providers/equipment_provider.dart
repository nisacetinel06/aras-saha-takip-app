import 'package:flutter/foundation.dart';
import '../models/equipment.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';

/// Ekipman / Envanter (QR Kod) modülünün (Modül 4) state'ini yönetir:
/// ekipman listesi, QR/manuel kod ile sorgulama, id ile detay ve geçmiş arıza
/// kaydı çekme; her akışın kendi loading/error state'i ayrı tutulur çünkü
/// bunlar farklı ekranlarda (liste, QR tarama, detay) bağımsız çalışır.
class EquipmentProvider extends ChangeNotifier {
  final ApiService _apiService;

  EquipmentProvider({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  List<Equipment> _equipmentList = [];
  bool _isListLoading = false;
  String? _listErrorMessage;
  EquipmentType? _typeFilter;
  EquipmentStatus? _statusFilter;
  String? _ilFilter;

  Equipment? _selectedEquipment;
  bool _isDetailLoading = false;
  String? _detailErrorMessage;

  List<EquipmentHistoryEntry> _history = [];
  bool _isHistoryLoading = false;
  String? _historyErrorMessage;

  bool _isQrLookupLoading = false;
  String? _qrLookupErrorMessage;

  // Ekipman Seçici (EquipmentPickerField — bkz. Yeni İş Emri Oluştur formu)
  // için AYRI bir state seti: Ekipman Listesi ekranının filtrelenmiş
  // `_equipmentList`'ini ARAMA sonuçlarıyla ezmemek için bilinçli olarak
  // ayrı tutulur — ikisi aynı anda, birbirinden bağımsız açık olabilir.
  List<Equipment> _searchResults = [];
  bool _isSearching = false;
  String? _searchErrorMessage;

  // Ayarlar ve Çevrimdışı Mod (Modül 17) — Okuma Önbelleği. bkz.
  // WorkOrderListProvider'daki AYNI desen ve gerekçe notu.
  bool _isFromCache = false;
  DateTime? _cachedAt;

  List<Equipment> get equipmentList => _equipmentList;
  bool get isListLoading => _isListLoading;
  String? get listErrorMessage => _listErrorMessage;
  EquipmentType? get typeFilter => _typeFilter;
  EquipmentStatus? get statusFilter => _statusFilter;
  String? get ilFilter => _ilFilter;
  bool get isFromCache => _isFromCache;
  DateTime? get cachedAt => _cachedAt;

  List<Equipment> get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  String? get searchErrorMessage => _searchErrorMessage;

  Equipment? get selectedEquipment => _selectedEquipment;
  bool get isDetailLoading => _isDetailLoading;
  String? get detailErrorMessage => _detailErrorMessage;

  List<EquipmentHistoryEntry> get history => _history;
  bool get isHistoryLoading => _isHistoryLoading;
  String? get historyErrorMessage => _historyErrorMessage;

  bool get isQrLookupLoading => _isQrLookupLoading;
  String? get qrLookupErrorMessage => _qrLookupErrorMessage;

  /// Okuma Önbelleği (Modül 17) anahtarı — aktif tip/statü/il filtrelerini
  /// İÇERİR, bkz. WorkOrderListProvider._cacheKey'deki AYNI gerekçe.
  String get _cacheKey =>
      'equipment_list:${_typeFilter?.name ?? '-'}:${_statusFilter?.apiValue ?? '-'}:${_ilFilter ?? '-'}';

  Future<void> fetchEquipmentList() async {
    _isListLoading = true;
    _listErrorMessage = null;
    notifyListeners();

    try {
      _equipmentList = await _apiService.getEquipmentList(
        typeFilter: _typeFilter?.name,
        statusFilter: _statusFilter?.apiValue,
        ilFilter: _ilFilter,
      );
      _isFromCache = false;
      _cachedAt = null;
      await CacheService.set(
        _cacheKey,
        _equipmentList.map((e) => e.toJson()).toList(),
      );
    } catch (e) {
      final cached = CacheService.get(_cacheKey);
      if (cached != null) {
        final rawList = cached.data as List<dynamic>;
        _equipmentList = rawList
            .map((json) => Equipment.fromJson(json as Map<String, dynamic>))
            .toList();
        _isFromCache = true;
        _cachedAt = cached.cachedAt;
      } else {
        _listErrorMessage = e.toString();
      }
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

  Future<void> setIlFilter(String? il) async {
    _ilFilter = il;
    await fetchEquipmentList();
  }

  /// Filtrelenmiş Liste Boş Durumu (bkz. widgets/empty_state.dart) — "Tüm
  /// Filtreleri Temizle" butonu bunu çağırır.
  Future<void> clearAllFilters() async {
    _typeFilter = null;
    _statusFilter = null;
    _ilFilter = null;
    await fetchEquipmentList();
  }

  /// EquipmentPickerField tarafından, kullanıcı yazmayı bıraktıktan ~400ms
  /// sonra (debounce widget içinde bir Timer ile yönetilir) çağrılır — bu
  /// metod yalnızca API çağrısını yapar, debounce mantığını taşımaz.
  Future<void> searchEquipment(String query) async {
    _isSearching = true;
    _searchErrorMessage = null;
    notifyListeners();

    try {
      _searchResults = await _apiService.getEquipmentList(search: query);
    } catch (e) {
      _searchErrorMessage = e.toString();
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  void clearSearch() {
    _searchResults = [];
    _isSearching = false;
    _searchErrorMessage = null;
    notifyListeners();
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
