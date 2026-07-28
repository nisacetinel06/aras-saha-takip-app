import 'package:flutter/foundation.dart';
import '../models/work_order.dart';
import '../services/api_service.dart';

/// İş emri listesi ekranının state'ini yönetir: veri çekme, statü filtresi
/// (backend'e sorgu olarak gider), serbest metin araması (çekilmiş liste
/// üzerinde istemci tarafında uygulanır) ve hata durumu.
class WorkOrderListProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  List<WorkOrder> _workOrders = [];
  bool _isLoading = false;
  String? _errorMessage;
  WorkOrderStatus? _filterStatus;
  String _searchQuery = '';

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  WorkOrderStatus? get filterStatus => _filterStatus;
  String get searchQuery => _searchQuery;

  List<WorkOrder> get workOrders {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _workOrders;

    return _workOrders.where((wo) {
      return wo.title.toLowerCase().contains(query) ||
          wo.locationName.toLowerCase().contains(query) ||
          wo.description.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> loadWorkOrders() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _workOrders = await _apiService.getWorkOrders(
        statusFilter: _filterStatus?.toJson(),
      );
    } catch (e) {
      _errorMessage = e.toString();
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
}
