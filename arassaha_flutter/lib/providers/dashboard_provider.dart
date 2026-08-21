import 'package:flutter/foundation.dart';
import '../models/dashboard_summary.dart';
import '../services/api_service.dart';
import '../utils/error_mapper.dart';

/// Dashboard ekranının state'ini yönetir: özet istatistikleri çekme,
/// yükleniyor/hata durumları.
class DashboardProvider extends ChangeNotifier {
  final ApiService _apiService;

  DashboardProvider({ApiService? apiService})
    : _apiService = apiService ?? ApiService();

  DashboardSummary? _summary;
  bool _isLoading = false;
  String? _errorMessage;

  DashboardSummary? get summary => _summary;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> fetchSummary() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _summary = await _apiService.getDashboardSummary();
    } catch (e) {
      _errorMessage = mapExceptionToUserMessage(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
