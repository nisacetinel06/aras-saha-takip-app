import 'package:flutter/foundation.dart';
import '../models/equipment_risk.dart';
import '../services/api_service.dart';

/// Arıza Risk Tahmini (Modül 9) ekranlarının state'ini yönetir: Dashboard'un
/// "Riskli Ekipmanlar" listesi ve Ekipman Detayı'ndaki tekil risk skoru.
///
/// DÜRÜSTLÜK NOTU: Skorları üreten model SENTETİK (kural tabanlı üretilmiş)
/// bir veri setiyle eğitildi — bkz. arassaha-ml/README.md. Model eğitimi ve
/// servis entegrasyonu gerçektir; yalnızca eğitim verisi sentetiktir.
class RiskProvider extends ChangeNotifier {
  final ApiService _apiService;

  RiskProvider({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  List<RiskyEquipmentSummary> _riskyEquipment = [];
  bool _isRiskyListLoading = false;
  String? _riskyListErrorMessage;

  final Map<int, EquipmentRisk> _riskByEquipmentId = {};
  final Set<int> _loadingEquipmentIds = {};
  String? _riskErrorMessage;

  List<RiskyEquipmentSummary> get riskyEquipment => _riskyEquipment;
  bool get isRiskyListLoading => _isRiskyListLoading;
  String? get riskyListErrorMessage => _riskyListErrorMessage;

  String? get riskErrorMessage => _riskErrorMessage;

  EquipmentRisk? riskFor(int equipmentId) => _riskByEquipmentId[equipmentId];
  bool isRiskLoading(int equipmentId) =>
      _loadingEquipmentIds.contains(equipmentId);

  Future<void> fetchRiskyEquipment({int limit = 5}) async {
    _isRiskyListLoading = true;
    _riskyListErrorMessage = null;
    notifyListeners();

    try {
      _riskyEquipment = await _apiService.getRiskyEquipment(limit: limit);
    } catch (e) {
      _riskyListErrorMessage = e.toString();
    } finally {
      _isRiskyListLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchEquipmentRisk(int equipmentId) async {
    _loadingEquipmentIds.add(equipmentId);
    _riskErrorMessage = null;
    notifyListeners();

    try {
      _riskByEquipmentId[equipmentId] = await _apiService.getEquipmentRisk(
        equipmentId,
      );
    } catch (e) {
      _riskErrorMessage = e.toString();
    } finally {
      _loadingEquipmentIds.remove(equipmentId);
      notifyListeners();
    }
  }
}
