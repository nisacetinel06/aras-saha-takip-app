import 'package:flutter/foundation.dart';
import '../models/work_order.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';

/// İş emri listesi ekranının state'ini yönetir: veri çekme, statü filtresi
/// (backend'e sorgu olarak gider), serbest metin araması (çekilmiş liste
/// üzerinde istemci tarafında uygulanır) ve hata durumu.
class WorkOrderListProvider extends ChangeNotifier {
  final ApiService _apiService;

  WorkOrderListProvider({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  List<WorkOrder> _workOrders = [];
  bool _isLoading = false;
  String? _errorMessage;
  WorkOrderStatus? _filterStatus;
  String _searchQuery = '';
  // Kestirimci Bakım Planlama (Modül 12) — kaynak ayrımı filtresi. Backend'in
  // GET /api/workorders'ı source_type sorgu parametresi desteklemediği için
  // (bkz. routes/workOrders.js), _searchQuery ile AYNI şekilde istemci
  // tarafında, zaten çekilmiş liste üzerinde uygulanır.
  bool _onlyPreventiveMaintenance = false;

  // Ayarlar ve Çevrimdışı Mod (Modül 17) — Okuma Önbelleği (Read-Through
  // Cache). `_isFromCache`/`_cachedAt` yalnızca EN SON çekme İSTEĞİ BAŞARISIZ
  // olup önbellekten dönüldüğünde dolar; başarılı bir canlı çekmede ikisi de
  // sıfırlanır. Ekran bu ikisiyle "Son güncelleme: 12 dakika önce
  // (çevrimdışı)" notunu gösterir (bkz. work_order_list_screen.dart).
  bool _isFromCache = false;
  DateTime? _cachedAt;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  WorkOrderStatus? get filterStatus => _filterStatus;
  String get searchQuery => _searchQuery;
  bool get onlyPreventiveMaintenance => _onlyPreventiveMaintenance;
  bool get isFromCache => _isFromCache;
  DateTime? get cachedAt => _cachedAt;

  List<WorkOrder> get workOrders {
    final query = _searchQuery.trim().toLowerCase();

    return _workOrders.where((wo) {
      if (_onlyPreventiveMaintenance &&
          wo.sourceType != WorkOrderSourceType.onleyiciBakim) {
        return false;
      }
      if (query.isEmpty) return true;
      return wo.title.toLowerCase().contains(query) ||
          wo.locationName.toLowerCase().contains(query) ||
          wo.description.toLowerCase().contains(query);
    }).toList();
  }

  /// Okuma Önbelleği (Modül 17): önbellek anahtarı, aktif statü filtresini
  /// İÇERİR — "Açık" filtresiyle çekilmiş bir liste, "Tümü" filtresi için
  /// yanlışlıkla önbellek isabeti (cache hit) OLUŞTURMAZ.
  String get _cacheKey => 'work_orders:${_filterStatus?.toJson() ?? 'all'}';

  Future<void> loadWorkOrders() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _workOrders = await _apiService.getWorkOrders(
        statusFilter: _filterStatus?.toJson(),
      );
      _isFromCache = false;
      _cachedAt = null;
      await CacheService.set(
        _cacheKey,
        _workOrders.map((w) => w.toJson()).toList(),
      );
    } catch (e) {
      final cached = CacheService.get(_cacheKey);
      if (cached != null) {
        final rawList = cached.data as List<dynamic>;
        _workOrders = rawList
            .map((json) => WorkOrder.fromJson(json as Map<String, dynamic>))
            .toList();
        _isFromCache = true;
        _cachedAt = cached.cachedAt;
      } else {
        _errorMessage = e.toString();
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setFilter(WorkOrderStatus? status) async {
    _filterStatus = status;
    await loadWorkOrders();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setOnlyPreventiveMaintenance(bool value) {
    _onlyPreventiveMaintenance = value;
    notifyListeners();
  }

  /// Filtrelenmiş Liste Boş Durumu (bkz. widgets/empty_state.dart) — "Tüm
  /// Filtreleri Temizle" butonu bunu çağırır. Statü sunucuya giden bir
  /// parametre olduğu için tek bir [loadWorkOrders] çağrısıyla hem statü
  /// filtresi sıfırlanır hem de arama/önleyici bakım (istemci tarafı)
  /// filtreleri temizlenmiş listeye anında yansır.
  Future<void> clearAllFilters() async {
    _searchQuery = '';
    _onlyPreventiveMaintenance = false;
    _filterStatus = null;
    await loadWorkOrders();
  }
}
