import 'package:flutter/foundation.dart';
import '../models/work_order.dart';
import '../services/api_service.dart';
import '../utils/error_mapper.dart';

/// "Tamamlanan İş Emirlerim" bölümü (Ana Sayfa, teknisyen rolü) — bkz.
/// home/completed_work_orders_section.dart ve
/// work_orders/completed_work_orders_screen.dart. WorkOrderListProvider'dan
/// BİLİNÇLİ olarak ayrı: o, statü filtresi dışındaki TÜM listeyi tek seferde
/// çekip aramayı istemci tarafında uygular (bkz. work_order_list_provider.dart)
/// — bir teknisyenin YILLAR içinde biriken tamamlanmış iş emri sayısı büyük
/// olabileceğinden burada arama/sıralama backend'e sorgu parametresi olarak
/// gönderilir ve liste sayfalanır (bkz. routes/workOrders.js GET /
/// dokümantasyonu). Diğer TÜM ekranlarla aynı Provider mimarisini izler
/// (main.dart'ta tek bir global örnek) — Ana Sayfa'daki önizleme (ilk
/// [previewLimit] kayıt) ile "Tümünü Gör" tam liste ekranı AYNI örneği ve
/// AYNI biriken [items] listesini paylaşır; Ana Sayfa yalnızca bu listenin
/// başındaki birkaç kaydı gösterir, tam ekran ise `loadMore()` ile listeyi
/// büyütür.
class CompletedWorkOrdersProvider extends ChangeNotifier {
  final ApiService _apiService;

  CompletedWorkOrdersProvider({ApiService? apiService})
    : _apiService = apiService ?? ApiService();

  static const int pageSize = 15;
  static const int previewLimit = 10;

  List<WorkOrder> _items = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _errorMessage;
  // İLK yüklemenin hatasından ([errorMessage]) BİLİNÇLİ olarak ayrı: bir
  // sayfalama (loadMore) hatası, Ana Sayfa'daki önizlemenin zaten başarıyla
  // gösterdiği ilk sayfayı bir hata ekranına ÇEVİRMEMELİ — yalnızca tam liste
  // ekranındaki "daha fazla yükle" satırında görünür.
  String? _loadMoreErrorMessage;
  bool _sortDescending = true;
  String _searchQuery = '';
  bool _hasMore = true;
  int _offset = 0;

  List<WorkOrder> get items => _items;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get errorMessage => _errorMessage;
  String? get loadMoreErrorMessage => _loadMoreErrorMessage;
  bool get sortDescending => _sortDescending;
  String get searchQuery => _searchQuery;
  bool get hasMore => _hasMore;

  Future<void> loadInitial() async {
    _isLoading = true;
    _errorMessage = null;
    _loadMoreErrorMessage = null;
    _offset = 0;
    _hasMore = true;
    notifyListeners();

    try {
      final results = await _fetchPage(offset: 0);
      _items = results;
      _offset = results.length;
      _hasMore = results.length == pageSize;
    } catch (e) {
      _errorMessage = mapExceptionToUserMessage(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Tam liste ekranındaki sonsuz kaydırma bunu çağırır. Zaten yükleniyorsa
  /// veya bilinen tüm kayıtlar zaten çekilmişse (`hasMore == false`) hiçbir
  /// şey yapmaz — kaydırma sırasında aynı sayfanın yanlışlıkla birden fazla
  /// kez istenmesini (çift istek/çift kayıt) önler.
  Future<void> loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    _loadMoreErrorMessage = null;
    notifyListeners();

    try {
      final results = await _fetchPage(offset: _offset);
      _items = [..._items, ...results];
      _offset += results.length;
      _hasMore = results.length == pageSize;
    } catch (e) {
      // Sayfalama hatası mevcut listeyi BOZMAZ — yalnızca bir sonraki
      // kaydırmada tekrar denenir (bkz. completed_work_orders_screen.dart
      // alt bilgi satırındaki "Tekrar Dene").
      _loadMoreErrorMessage = mapExceptionToUserMessage(e);
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  void setSortDescending(bool value) {
    if (_sortDescending == value) return;
    _sortDescending = value;
    loadInitial();
  }

  void setSearchQuery(String value) {
    if (_searchQuery == value) return;
    _searchQuery = value;
    loadInitial();
  }

  Future<List<WorkOrder>> _fetchPage({required int offset}) {
    return _apiService.getWorkOrders(
      statusFilter: WorkOrderStatus.cozuldu.toJson(),
      sort: _sortDescending ? 'desc' : 'asc',
      q: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
      limit: pageSize,
      offset: offset,
    );
  }
}
