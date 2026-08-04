import 'package:flutter/foundation.dart';
import '../models/maintenance_recommendation.dart';
import '../models/work_order.dart';
import '../services/api_service.dart';

/// Kestirimci Bakım Planlama (Modül 12) ekranlarının state'ini yönetir.
///
/// AYRIM: Bu provider bir ML sonucu göstermez — Modül 9'un risk skorundan
/// backend'de (routes/maintenance.js) kural tabanlı olarak türetilmiş bakım
/// önerilerini listeler ve bunları gerçek iş emirlerine dönüştürme/reddetme
/// aksiyonlarını tetikler.
class MaintenanceProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  List<MaintenanceRecommendation> _recommendations = [];
  bool _isLoading = false;
  String? _errorMessage;

  // fetchRecommendations'a en son verilen filtreler — bir mutasyon (iş emri
  // oluşturma/reddetme) sonrası listeyi AYNI filtrelerle yeniden çekmek için
  // saklanır; aksi halde örn. "Bekleyen" filtresi açıkken bir öneri
  // 'planlandi'ya geçtiğinde listeden düşmesi gerekirken ekranda kalırdı.
  String? _lastStatusFilter;
  String? _lastUrgencyFilter;

  bool _isRefreshingRules = false;
  String? _refreshRulesError;

  final Set<int> _mutatingRecommendationIds = {};
  String? _mutationErrorMessage;

  List<MaintenanceRecommendation> get recommendations => _recommendations;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  bool get isRefreshingRules => _isRefreshingRules;
  String? get refreshRulesError => _refreshRulesError;

  String? get mutationErrorMessage => _mutationErrorMessage;
  bool isMutating(int recommendationId) =>
      _mutatingRecommendationIds.contains(recommendationId);

  /// Belirli bir ekipman için bekleyen (henüz bir iş emrine dönüştürülmemiş)
  /// öneri varsa döner — Ekipman Detayı'ndaki bağlam içi karta bakar.
  MaintenanceRecommendation? recommendationForEquipment(int equipmentId) {
    for (final r in _recommendations) {
      if (r.equipmentId == equipmentId &&
          r.status == MaintenanceRecommendationStatus.onerildi) {
        return r;
      }
    }
    return null;
  }

  Future<void> fetchRecommendations({
    String? statusFilter,
    String? urgencyFilter,
  }) async {
    _lastStatusFilter = statusFilter;
    _lastUrgencyFilter = urgencyFilter;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _recommendations = await _apiService.getMaintenanceRecommendations(
        statusFilter: statusFilter,
        urgencyFilter: urgencyFilter,
      );
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// POST /api/maintenance/refresh-recommendations — yalnızca yönetici.
  /// Modül 9'un güncel risk skorlarını kural tabanlı önerilere çevirir/
  /// günceller, sonra listeyi en son kullanılan filtrelerle yeniden çeker.
  /// Sonucu (created/updated/skipped) döner ki ekran bunu bir SnackBar ile
  /// gösterip çoğaltma korumasının çalıştığını (updated>0, created=0 ikinci
  /// çağrıda) kullanıcıya da görünür kılabilsin.
  Future<({int created, int updated, int skipped})?>
  refreshRecommendationRules() async {
    _isRefreshingRules = true;
    _refreshRulesError = null;
    notifyListeners();

    try {
      final result = await _apiService.refreshMaintenanceRecommendations();
      await fetchRecommendations(
        statusFilter: _lastStatusFilter,
        urgencyFilter: _lastUrgencyFilter,
      );
      return result;
    } catch (e) {
      _refreshRulesError = e.toString();
      return null;
    } finally {
      _isRefreshingRules = false;
      notifyListeners();
    }
  }

  /// Öneriyi gerçek bir iş emrine dönüştürür (dispeçer/yönetici). Başarılı
  /// olursa listeyi en son filtrelerle yeniden çeker — böylece örn. "Bekleyen"
  /// filtresi açıkken bu öneri 'planlandi'ya geçip listeden kaybolur.
  Future<WorkOrder?> createWorkOrderFromRecommendation(
    int recommendationId, {
    required int assignedUserId,
    String? priority,
  }) async {
    _mutatingRecommendationIds.add(recommendationId);
    _mutationErrorMessage = null;
    notifyListeners();

    try {
      final workOrder = await _apiService.createWorkOrderFromRecommendation(
        recommendationId,
        assignedUserId: assignedUserId,
        priority: priority,
      );
      await fetchRecommendations(
        statusFilter: _lastStatusFilter,
        urgencyFilter: _lastUrgencyFilter,
      );
      return workOrder;
    } catch (e) {
      _mutationErrorMessage = e.toString();
      return null;
    } finally {
      _mutatingRecommendationIds.remove(recommendationId);
      notifyListeners();
    }
  }

  /// Öneriyi reddeder (dispeçer/yönetici). createWorkOrderFromRecommendation
  /// ile AYNI sebeple (bkz. yukarısı) başarı sonrası liste en son filtrelerle
  /// yeniden çekilir — örn. "Bekleyen" filtresi açıkken reddedilen öneri
  /// listeden düşer.
  Future<bool> dismissRecommendation(int recommendationId) async {
    _mutatingRecommendationIds.add(recommendationId);
    _mutationErrorMessage = null;
    notifyListeners();

    try {
      await _apiService.dismissMaintenanceRecommendation(recommendationId);
      await fetchRecommendations(
        statusFilter: _lastStatusFilter,
        urgencyFilter: _lastUrgencyFilter,
      );
      return true;
    } catch (e) {
      _mutationErrorMessage = e.toString();
      return false;
    } finally {
      _mutatingRecommendationIds.remove(recommendationId);
      notifyListeners();
    }
  }
}
