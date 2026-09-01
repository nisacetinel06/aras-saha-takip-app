import 'package:flutter/foundation.dart';
import '../models/my_performance.dart';
import '../services/api_service.dart';
import '../utils/error_mapper.dart';

/// Performansım (Modül 16) ekranının state'i — DashboardProvider ile AYNI
/// desen (tek istek, yükleniyor/hata state'leri, mapExceptionToUserMessage).
class MyPerformanceProvider extends ChangeNotifier {
  final ApiService _apiService;

  MyPerformanceProvider({ApiService? apiService})
    : _apiService = apiService ?? ApiService();

  MyPerformanceSummary? _summary;
  bool _isLoading = false;
  String? _errorMessage;

  MyPerformanceSummary? get summary => _summary;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> fetchMyPerformance() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _summary = await _apiService.getMyPerformance();
    } catch (e) {
      _errorMessage = mapExceptionToUserMessage(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
