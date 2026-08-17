import 'package:flutter/foundation.dart';
import '../models/meter_anomaly.dart';
import '../services/api_service.dart';

/// Kayıp-Kaçak / Anormal Tüketim Tespiti (Modül 11) ekranlarının state'ini
/// yönetir: Şüpheli Sayaçlar listesi, Ekipman Detayı'ndaki tekil anomali
/// skoru ve tüketim geçmişi grafiği. RiskProvider (Modül 9) ile AYNI desen.
///
/// DÜRÜSTLÜK NOTU: Skorları üreten model SENTETİK (kural tabanlı üretilmiş)
/// bir tüketim geçmişiyle eğitildi — bkz. arassaha-ml/README.md.
class AnomalyProvider extends ChangeNotifier {
  final ApiService _apiService;

  AnomalyProvider({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  List<SuspiciousMeterSummary> _suspiciousMeters = [];
  bool _isSuspiciousListLoading = false;
  String? _suspiciousListErrorMessage;

  final Map<int, MeterAnomaly> _anomalyByEquipmentId = {};
  final Set<int> _loadingAnomalyEquipmentIds = {};
  String? _anomalyErrorMessage;

  final Map<int, List<MeterConsumptionEntry>> _consumptionByEquipmentId = {};
  final Set<int> _loadingConsumptionEquipmentIds = {};
  String? _consumptionErrorMessage;

  List<SuspiciousMeterSummary> get suspiciousMeters => _suspiciousMeters;
  bool get isSuspiciousListLoading => _isSuspiciousListLoading;
  String? get suspiciousListErrorMessage => _suspiciousListErrorMessage;

  String? get anomalyErrorMessage => _anomalyErrorMessage;
  String? get consumptionErrorMessage => _consumptionErrorMessage;

  MeterAnomaly? anomalyFor(int equipmentId) =>
      _anomalyByEquipmentId[equipmentId];
  bool isAnomalyLoading(int equipmentId) =>
      _loadingAnomalyEquipmentIds.contains(equipmentId);

  List<MeterConsumptionEntry>? consumptionFor(int equipmentId) =>
      _consumptionByEquipmentId[equipmentId];
  bool isConsumptionLoading(int equipmentId) =>
      _loadingConsumptionEquipmentIds.contains(equipmentId);

  Future<void> fetchSuspiciousMeters() async {
    _isSuspiciousListLoading = true;
    _suspiciousListErrorMessage = null;
    notifyListeners();

    try {
      _suspiciousMeters = await _apiService.getSuspiciousMeters();
    } catch (e) {
      _suspiciousListErrorMessage = e.toString();
    } finally {
      _isSuspiciousListLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchEquipmentAnomaly(int equipmentId) async {
    _loadingAnomalyEquipmentIds.add(equipmentId);
    _anomalyErrorMessage = null;
    notifyListeners();

    try {
      _anomalyByEquipmentId[equipmentId] = await _apiService
          .getEquipmentAnomaly(equipmentId);
    } catch (e) {
      _anomalyErrorMessage = e.toString();
    } finally {
      _loadingAnomalyEquipmentIds.remove(equipmentId);
      notifyListeners();
    }
  }

  Future<void> fetchEquipmentConsumption(int equipmentId) async {
    _loadingConsumptionEquipmentIds.add(equipmentId);
    _consumptionErrorMessage = null;
    notifyListeners();

    try {
      _consumptionByEquipmentId[equipmentId] = await _apiService
          .getEquipmentConsumption(equipmentId);
    } catch (e) {
      _consumptionErrorMessage = e.toString();
    } finally {
      _loadingConsumptionEquipmentIds.remove(equipmentId);
      notifyListeners();
    }
  }
}
