import 'package:flutter/foundation.dart';
import '../models/work_order.dart';
import '../models/work_order_map_pin.dart';
import '../services/api_service.dart';

/// Harita ekranının state'ini yönetir: pin verisini çekme, yükleniyor/hata
/// durumları ve statü filtresi. Veri seti küçük olduğu (≈15 kayıt) için statü
/// filtresi backend'e tekrar istek atmadan, istemci tarafında uygulanır —
/// yalnızca ilk yüklemede backend'e ?status= parametresi gönderilebilir
/// (örn. Dashboard'dan "acik" filtresiyle doğrudan haritaya yönlendirmek için).
class MapProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  List<WorkOrderMapPin> _allPins = [];
  bool _isLoading = false;
  String? _errorMessage;
  WorkOrderStatus? _statusFilter;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  WorkOrderStatus? get statusFilter => _statusFilter;

  List<WorkOrderMapPin> get mapMarkers {
    if (_statusFilter == null) return _allPins;
    return _allPins.where((pin) => pin.status == _statusFilter).toList();
  }

  Future<void> fetchMapData({String? statusFilter}) async {
    if (statusFilter != null) {
      _statusFilter = WorkOrderStatus.fromJson(statusFilter);
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _allPins = await _apiService.getMapData();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setStatusFilter(WorkOrderStatus? status) {
    _statusFilter = status;
    notifyListeners();
  }
}
