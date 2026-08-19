import 'package:flutter/foundation.dart';
import '../models/audit_log_entry.dart';
import '../services/api_service.dart';

/// Denetim Logu Paneli (bkz. screens/admin/audit_log_screen.dart) state'i:
/// filtreler (kategori/tarih aralığı) + sayfalanmış kayıt listesi.
/// CompletedWorkOrdersProvider'daki (bkz. o dosya) "ilk yükleme / daha
/// fazla yükle" deseniyle AYNI — ama offset'ten "sonuç sayısı == sayfa
/// boyutu mu" diye tahmin etmek yerine backend'in kendi `page`/`has_more`
/// alanlarına güvenir (bkz. routes/auditLog.js), bu daha kesin bir sinyaldir.
class AuditLogProvider extends ChangeNotifier {
  final ApiService _apiService;

  AuditLogProvider({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  List<AuditLogEntry> _entries = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _errorMessage;
  // İLK yüklemenin hatasından BİLİNÇLİ olarak ayrı — CompletedWorkOrdersProvider
  // ile AYNI gerekçe: bir "daha fazla yükle" hatası, zaten başarıyla
  // gösterilen ilk sayfayı bir hata ekranına ÇEVİRMEMELİ.
  String? _loadMoreErrorMessage;
  bool _hasMore = false;
  int _totalCount = 0;
  int _currentPage = 1;

  AuditLogCategory? _categoryFilter;
  DateTime? _fromDateFilter;
  DateTime? _toDateFilter;

  List<AuditLogEntry> get entries => _entries;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get errorMessage => _errorMessage;
  String? get loadMoreErrorMessage => _loadMoreErrorMessage;
  bool get hasMore => _hasMore;
  int get totalCount => _totalCount;

  AuditLogCategory? get categoryFilter => _categoryFilter;
  DateTime? get fromDateFilter => _fromDateFilter;
  DateTime? get toDateFilter => _toDateFilter;
  bool get hasActiveFilters =>
      _categoryFilter != null || _fromDateFilter != null || _toDateFilter != null;

  Future<void> fetchInitial() async {
    _isLoading = true;
    _errorMessage = null;
    _loadMoreErrorMessage = null;
    notifyListeners();

    try {
      final result = await _fetchPage(1);
      _entries = result.entries;
      _totalCount = result.totalCount;
      _hasMore = result.hasMore;
      _currentPage = result.page;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// "Daha Fazla Yükle" butonu/sonsuz kaydırma bunu çağırır. Zaten
  /// yükleniyorsa veya bilinen tüm kayıtlar zaten çekilmişse (`hasMore ==
  /// false`) hiçbir şey yapmaz — aynı sayfanın yanlışlıkla iki kez
  /// istenmesini (çift istek/çift kayıt) önler.
  Future<void> loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    _loadMoreErrorMessage = null;
    notifyListeners();

    try {
      final result = await _fetchPage(_currentPage + 1);
      _entries = [..._entries, ...result.entries];
      _totalCount = result.totalCount;
      _hasMore = result.hasMore;
      _currentPage = result.page;
    } catch (e) {
      _loadMoreErrorMessage = e.toString();
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  void setCategory(AuditLogCategory? category) {
    if (_categoryFilter == category) return;
    _categoryFilter = category;
    fetchInitial();
  }

  /// `from`/`to` ikisi de null verilirse tarih filtresi tamamen kaldırılır.
  void setDateRange(DateTime? from, DateTime? to) {
    _fromDateFilter = from;
    _toDateFilter = to;
    fetchInitial();
  }

  /// EmptyState'teki (bkz. widgets/empty_state.dart) "Tüm Filtreleri
  /// Temizle" butonu bunu çağırır — tutarlılık için diğer filtrelenmiş
  /// listelerdeki (Stok/Ekipman/Bakım Önerileri) AYNI desen.
  void clearAllFilters() {
    _categoryFilter = null;
    _fromDateFilter = null;
    _toDateFilter = null;
    fetchInitial();
  }

  Future<AuditLogPage> _fetchPage(int page) {
    return _apiService.getAuditLog(
      category: _categoryFilter,
      fromDate: _fromDateFilter,
      toDate: _toDateFilter,
      page: page,
    );
  }
}
