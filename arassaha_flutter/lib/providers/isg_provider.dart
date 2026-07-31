import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/isg_report.dart';
import '../services/api_service.dart';

/// İSG (İş Sağlığı ve Güvenliği) Bildirimi (Modül 5) ekranlarının state'ini
/// yönetir: bildirim listesi/detayı çekme, yeni bildirim gönderme (gerçek
/// fotoğraf + gerçek GPS ile) ve durum güncelleme.
class IsgProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  List<IsgReport> _reports = [];
  bool _isListLoading = false;
  String? _listErrorMessage;
  IsgStatus? _filterStatus;

  IsgReport? _selectedReport;
  bool _isDetailLoading = false;
  String? _detailErrorMessage;

  bool _isSubmitting = false;
  String? _submitErrorMessage;

  bool _isUpdatingStatus = false;

  List<IsgReport> get reports => _reports;
  bool get isListLoading => _isListLoading;
  String? get listErrorMessage => _listErrorMessage;
  IsgStatus? get filterStatus => _filterStatus;

  IsgReport? get selectedReport => _selectedReport;
  bool get isDetailLoading => _isDetailLoading;
  String? get detailErrorMessage => _detailErrorMessage;

  bool get isSubmitting => _isSubmitting;
  String? get submitErrorMessage => _submitErrorMessage;

  bool get isUpdatingStatus => _isUpdatingStatus;

  Future<void> fetchReports() async {
    _isListLoading = true;
    _listErrorMessage = null;
    notifyListeners();

    try {
      _reports = await _apiService.getIsgReports(statusFilter: _filterStatus?.toJson());
    } catch (e) {
      _listErrorMessage = e.toString();
    } finally {
      _isListLoading = false;
      notifyListeners();
    }
  }

  Future<void> setFilter(IsgStatus? status) async {
    _filterStatus = status;
    await fetchReports();
  }

  Future<void> fetchReportDetail(int id) async {
    _isDetailLoading = true;
    _detailErrorMessage = null;
    notifyListeners();

    try {
      _selectedReport = await _apiService.getIsgReportDetail(id);
    } catch (e) {
      _detailErrorMessage = e.toString();
    } finally {
      _isDetailLoading = false;
      notifyListeners();
    }
  }

  /// Yeni bildirim gönderir. Başarılıysa true döner ve listeyi tazeler.
  /// "Bildiren kişi" burada YOK — backend bunu giriş yapmış kullanıcının
  /// token'ından otomatik doldurur (bkz. ApiService.submitIsgReport).
  Future<bool> submitReport({
    required String description,
    required IsgCategory category,
    required double lat,
    required double lng,
    String? locationName,
    required File photo,
  }) async {
    _isSubmitting = true;
    _submitErrorMessage = null;
    notifyListeners();

    try {
      await _apiService.submitIsgReport(
        description: description,
        category: category,
        lat: lat,
        lng: lng,
        locationName: locationName,
        photo: photo,
      );
      return true;
    } catch (e) {
      _submitErrorMessage = e.toString();
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<bool> updateReportStatus(int id, IsgStatus newStatus, {String? reviewerNote}) async {
    _isUpdatingStatus = true;
    _detailErrorMessage = null;
    notifyListeners();

    try {
      _selectedReport = await _apiService.updateIsgReportStatus(id, newStatus, reviewerNote: reviewerNote);
      final index = _reports.indexWhere((r) => r.id == id);
      if (index != -1) _reports[index] = _selectedReport!;
      return true;
    } catch (e) {
      _detailErrorMessage = e.toString();
      return false;
    } finally {
      _isUpdatingStatus = false;
      notifyListeners();
    }
  }
}
