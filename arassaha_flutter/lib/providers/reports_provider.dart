import 'package:flutter/foundation.dart';
import '../models/equipment_risk.dart' show RiskModelPerformance;
import '../models/isg_report.dart' show DamageModelPerformance;
import '../models/report.dart';
import '../services/api_service.dart';
import '../utils/error_mapper.dart';

/// Raporlar / Analitik Sayfası (Modül 14) state'i: bölgesel risk özeti,
/// bölgeye/ekipman tipine göre arıza dağılımı, aylık arıza trendi, bölgeye
/// göre anomali dağılımı, en çok kullanılan malzemeler.
///
/// LAZY LOADING (bkz. reports_screen.dart TabBarView): her `fetchX` metodu
/// kendi `_xLoaded` bayrağını kontrol eder — sekme daha önce hiç açılmadıysa
/// veri çeker, ikinci kez aynı sekmeye gelindiğinde (force=false) TEKRAR
/// istek atmaz. Bu, MaterialProvider/RiskProvider'daki basit "her
/// initState'te çek" deseninden BİLİNÇLİ bir sapma — burada 6 farklı
/// endpoint var ve ekran açılır açılmaz hepsini birden çekmek (PROMPT'un
/// açıkça yasakladığı gibi) performansı gereksiz düşürür. Aşağı çekip
/// yenileme (RefreshIndicator) `force: true` ile bu bayrağı yok sayar.
class ReportsProvider extends ChangeNotifier {
  final ApiService _apiService;

  ReportsProvider({ApiService? apiService})
    : _apiService = apiService ?? ApiService();

  // --- Sekme 1a: Risk Yoğunluk Haritası ---
  List<RegionalRiskSummary> _regionalRiskSummary = [];
  bool _isLoadingRegionalRisk = false;
  String? _regionalRiskErrorMessage;
  bool _regionalRiskLoaded = false;

  List<RegionalRiskSummary> get regionalRiskSummary => _regionalRiskSummary;
  bool get isLoadingRegionalRisk => _isLoadingRegionalRisk;
  String? get regionalRiskErrorMessage => _regionalRiskErrorMessage;

  // --- Sekme 1b: Arıza Dağılımı (Bölgeye Göre) ---
  List<RegionFaultCount> _faultByRegion = [];
  bool _isLoadingFaultByRegion = false;
  String? _faultByRegionErrorMessage;
  bool _faultByRegionLoaded = false;

  List<RegionFaultCount> get faultByRegion => _faultByRegion;
  bool get isLoadingFaultByRegion => _isLoadingFaultByRegion;
  String? get faultByRegionErrorMessage => _faultByRegionErrorMessage;

  // --- Sekme 1c: Risk Modeli Performansı (TEST-19) ---
  RiskModelPerformance? _riskModelPerformance;
  bool _isLoadingRiskModelPerformance = false;
  String? _riskModelPerformanceErrorMessage;
  bool _riskModelPerformanceLoaded = false;

  RiskModelPerformance? get riskModelPerformance => _riskModelPerformance;
  bool get isLoadingRiskModelPerformance => _isLoadingRiskModelPerformance;
  String? get riskModelPerformanceErrorMessage =>
      _riskModelPerformanceErrorMessage;

  // --- Sekme 1d: Hasar Tespiti Modeli Performansı (TEST-20) ---
  DamageModelPerformance? _damageModelPerformance;
  bool _isLoadingDamageModelPerformance = false;
  String? _damageModelPerformanceErrorMessage;
  bool _damageModelPerformanceLoaded = false;

  DamageModelPerformance? get damageModelPerformance => _damageModelPerformance;
  bool get isLoadingDamageModelPerformance => _isLoadingDamageModelPerformance;
  String? get damageModelPerformanceErrorMessage =>
      _damageModelPerformanceErrorMessage;

  // --- Sekme 2a: Aylık Arıza Trendi ---
  List<MonthlyFaultCount> _faultTrend = [];
  bool _isLoadingFaultTrend = false;
  String? _faultTrendErrorMessage;
  bool _faultTrendLoaded = false;

  List<MonthlyFaultCount> get faultTrend => _faultTrend;
  bool get isLoadingFaultTrend => _isLoadingFaultTrend;
  String? get faultTrendErrorMessage => _faultTrendErrorMessage;

  // --- Sekme 2b: Ekipman Tipine Göre Arıza Sıklığı ---
  List<EquipmentTypeFaultCount> _faultByEquipmentType = [];
  bool _isLoadingFaultByEquipmentType = false;
  String? _faultByEquipmentTypeErrorMessage;
  bool _faultByEquipmentTypeLoaded = false;

  List<EquipmentTypeFaultCount> get faultByEquipmentType =>
      _faultByEquipmentType;
  bool get isLoadingFaultByEquipmentType => _isLoadingFaultByEquipmentType;
  String? get faultByEquipmentTypeErrorMessage =>
      _faultByEquipmentTypeErrorMessage;

  // --- Sekme 2c: Anomali/Şüpheli Sayaç Dağılımı ---
  List<RegionAnomalySummary> _anomalyByRegion = [];
  bool _isLoadingAnomalyByRegion = false;
  String? _anomalyByRegionErrorMessage;
  bool _anomalyByRegionLoaded = false;

  List<RegionAnomalySummary> get anomalyByRegion => _anomalyByRegion;
  bool get isLoadingAnomalyByRegion => _isLoadingAnomalyByRegion;
  String? get anomalyByRegionErrorMessage => _anomalyByRegionErrorMessage;

  // --- Sekme 3: Malzeme Kullanımı ---
  List<TopMaterialUsage> _topMaterialUsage = [];
  bool _isLoadingTopMaterialUsage = false;
  String? _topMaterialUsageErrorMessage;
  bool _topMaterialUsageLoaded = false;

  List<TopMaterialUsage> get topMaterialUsage => _topMaterialUsage;
  bool get isLoadingTopMaterialUsage => _isLoadingTopMaterialUsage;
  String? get topMaterialUsageErrorMessage => _topMaterialUsageErrorMessage;

  Future<void> fetchRegionalRiskSummary({bool force = false}) async {
    if (_regionalRiskLoaded && !force) return;
    _isLoadingRegionalRisk = true;
    _regionalRiskErrorMessage = null;
    notifyListeners();

    try {
      _regionalRiskSummary = await _apiService.getRegionalRiskSummary();
      _regionalRiskLoaded = true;
    } catch (e) {
      _regionalRiskErrorMessage = mapExceptionToUserMessage(e);
    } finally {
      _isLoadingRegionalRisk = false;
      notifyListeners();
    }
  }

  Future<void> fetchFaultByRegion({bool force = false}) async {
    if (_faultByRegionLoaded && !force) return;
    _isLoadingFaultByRegion = true;
    _faultByRegionErrorMessage = null;
    notifyListeners();

    try {
      _faultByRegion = await _apiService.getFaultByRegion();
      _faultByRegionLoaded = true;
    } catch (e) {
      _faultByRegionErrorMessage = mapExceptionToUserMessage(e);
    } finally {
      _isLoadingFaultByRegion = false;
      notifyListeners();
    }
  }

  Future<void> fetchFaultTrend({bool force = false}) async {
    if (_faultTrendLoaded && !force) return;
    _isLoadingFaultTrend = true;
    _faultTrendErrorMessage = null;
    notifyListeners();

    try {
      _faultTrend = await _apiService.getFaultTrend();
      _faultTrendLoaded = true;
    } catch (e) {
      _faultTrendErrorMessage = mapExceptionToUserMessage(e);
    } finally {
      _isLoadingFaultTrend = false;
      notifyListeners();
    }
  }

  Future<void> fetchFaultByEquipmentType({bool force = false}) async {
    if (_faultByEquipmentTypeLoaded && !force) return;
    _isLoadingFaultByEquipmentType = true;
    _faultByEquipmentTypeErrorMessage = null;
    notifyListeners();

    try {
      _faultByEquipmentType = await _apiService.getFaultByEquipmentType();
      _faultByEquipmentTypeLoaded = true;
    } catch (e) {
      _faultByEquipmentTypeErrorMessage = mapExceptionToUserMessage(e);
    } finally {
      _isLoadingFaultByEquipmentType = false;
      notifyListeners();
    }
  }

  Future<void> fetchAnomalyByRegion({bool force = false}) async {
    if (_anomalyByRegionLoaded && !force) return;
    _isLoadingAnomalyByRegion = true;
    _anomalyByRegionErrorMessage = null;
    notifyListeners();

    try {
      _anomalyByRegion = await _apiService.getAnomalyByRegion();
      _anomalyByRegionLoaded = true;
    } catch (e) {
      _anomalyByRegionErrorMessage = mapExceptionToUserMessage(e);
    } finally {
      _isLoadingAnomalyByRegion = false;
      notifyListeners();
    }
  }

  Future<void> fetchTopMaterialUsage({bool force = false}) async {
    if (_topMaterialUsageLoaded && !force) return;
    _isLoadingTopMaterialUsage = true;
    _topMaterialUsageErrorMessage = null;
    notifyListeners();

    try {
      _topMaterialUsage = await _apiService.getTopMaterialUsage();
      _topMaterialUsageLoaded = true;
    } catch (e) {
      _topMaterialUsageErrorMessage = mapExceptionToUserMessage(e);
    } finally {
      _isLoadingTopMaterialUsage = false;
      notifyListeners();
    }
  }

  Future<void> fetchRiskModelPerformance({bool force = false}) async {
    if (_riskModelPerformanceLoaded && !force) return;
    _isLoadingRiskModelPerformance = true;
    _riskModelPerformanceErrorMessage = null;
    notifyListeners();

    try {
      _riskModelPerformance = await _apiService.getRiskModelPerformance();
      _riskModelPerformanceLoaded = true;
    } catch (e) {
      _riskModelPerformanceErrorMessage = mapExceptionToUserMessage(e);
    } finally {
      _isLoadingRiskModelPerformance = false;
      notifyListeners();
    }
  }

  Future<void> fetchDamageModelPerformance({bool force = false}) async {
    if (_damageModelPerformanceLoaded && !force) return;
    _isLoadingDamageModelPerformance = true;
    _damageModelPerformanceErrorMessage = null;
    notifyListeners();

    try {
      _damageModelPerformance = await _apiService.getDamageModelPerformance();
      _damageModelPerformanceLoaded = true;
    } catch (e) {
      _damageModelPerformanceErrorMessage = mapExceptionToUserMessage(e);
    } finally {
      _isLoadingDamageModelPerformance = false;
      notifyListeners();
    }
  }

  /// Sekme 1'in dördü (harita + çubuk grafik + risk model performansı +
  /// hasar tespiti model performansı) ekran ilk açıldığında birlikte
  /// çekilir — aynı sekmenin bölümleri olduğu için ayrı ayrı "lazy"
  /// davranmaya gerek yok (kullanıcı sekmeye girdiği an dördü de görünür).
  Future<void> fetchRegionalTabData({bool force = false}) {
    return Future.wait([
      fetchRegionalRiskSummary(force: force),
      fetchFaultByRegion(force: force),
      fetchRiskModelPerformance(force: force),
      fetchDamageModelPerformance(force: force),
    ]);
  }

  /// Sekme 2'nin üç bölümü — AYNI sebeple birlikte çekilir.
  Future<void> fetchTrendsTabData({bool force = false}) {
    return Future.wait([
      fetchFaultTrend(force: force),
      fetchFaultByEquipmentType(force: force),
      fetchAnomalyByRegion(force: force),
    ]);
  }
}
