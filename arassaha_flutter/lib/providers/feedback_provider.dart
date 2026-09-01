import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/feedback_item.dart';
import '../services/api_service.dart';
import '../utils/error_mapper.dart';

/// Öneri / Şikayet Kutusu (Modül 17) ekranlarının state'ini yönetir —
/// providers/isg_provider.dart'ın yapısını BİREBİR takip eder: liste/detay
/// çekme, yeni bildirim gönderme, durum güncelleme.
class FeedbackProvider extends ChangeNotifier {
  final ApiService _apiService;

  FeedbackProvider({ApiService? apiService})
    : _apiService = apiService ?? ApiService();

  List<FeedbackItem> _items = [];
  bool _isListLoading = false;
  String? _listErrorMessage;
  FeedbackStatus? _filterStatus;

  FeedbackItem? _selectedItem;
  bool _isDetailLoading = false;
  String? _detailErrorMessage;

  bool _isSubmitting = false;
  String? _submitErrorMessage;

  bool _isUpdatingStatus = false;

  List<FeedbackItem> get items => _items;
  bool get isListLoading => _isListLoading;
  String? get listErrorMessage => _listErrorMessage;
  FeedbackStatus? get filterStatus => _filterStatus;

  FeedbackItem? get selectedItem => _selectedItem;
  bool get isDetailLoading => _isDetailLoading;
  String? get detailErrorMessage => _detailErrorMessage;

  bool get isSubmitting => _isSubmitting;
  String? get submitErrorMessage => _submitErrorMessage;

  bool get isUpdatingStatus => _isUpdatingStatus;

  // --- Ana Sayfa "Öneri/Şikayet" rozeti (yalnızca yönetici) ---
  // QrGenerationProvider.unprintedCount ile AYNI desen: Ana Sayfa'daki Çabuk
  // Erişim rozeti için AYRI, hafif bir istek — liste ekranının kendi filtre
  // state'ini (yukarısı) etkilemez/etkilenmez.
  int? _pendingCount;
  int? get pendingCount => _pendingCount;

  Future<void> fetchPendingCount() async {
    try {
      final list = await _apiService.getFeedbackItems(statusFilter: 'bekliyor');
      _pendingCount = list.length;
      notifyListeners();
    } catch (_) {
      // Sessiz başarısızlık: bu yalnızca bir Çabuk Erişim rozeti göstergesi
      // (bkz. QrGenerationProvider.fetchUnprintedCount AYNI gerekçe).
    }
  }

  Future<void> fetchFeedbackItems() async {
    _isListLoading = true;
    _listErrorMessage = null;
    notifyListeners();

    try {
      _items = await _apiService.getFeedbackItems(
        statusFilter: _filterStatus?.toJson(),
      );
    } catch (e) {
      _listErrorMessage = mapExceptionToUserMessage(e);
    } finally {
      _isListLoading = false;
      notifyListeners();
    }
  }

  Future<void> setFilter(FeedbackStatus? status) async {
    _filterStatus = status;
    await fetchFeedbackItems();
  }

  Future<void> fetchItemDetail(int id) async {
    _isDetailLoading = true;
    _detailErrorMessage = null;
    notifyListeners();

    try {
      _selectedItem = await _apiService.getFeedbackItemDetail(id);
    } catch (e) {
      _detailErrorMessage = mapExceptionToUserMessage(e);
    } finally {
      _isDetailLoading = false;
      notifyListeners();
    }
  }

  /// Yeni bildirim gönderir. Başarılıysa true döner. "Bildiren kişi" burada
  /// YOK — backend bunu giriş yapmış kullanıcının token'ından otomatik
  /// doldurur (bkz. ApiService.submitFeedback). `photo` opsiyoneldir.
  Future<bool> submitFeedback({
    required String description,
    required FeedbackCategory category,
    required bool isAnonymous,
    File? photo,
  }) async {
    _isSubmitting = true;
    _submitErrorMessage = null;
    notifyListeners();

    try {
      await _apiService.submitFeedback(
        description: description,
        category: category,
        isAnonymous: isAnonymous,
        photo: photo,
      );
      return true;
    } catch (e) {
      _submitErrorMessage = mapExceptionToUserMessage(e);
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<bool> updateItemStatus(
    int id,
    FeedbackStatus newStatus, {
    String? reviewerNote,
  }) async {
    _isUpdatingStatus = true;
    _detailErrorMessage = null;
    notifyListeners();

    try {
      _selectedItem = await _apiService.updateFeedbackStatus(
        id,
        newStatus,
        reviewerNote: reviewerNote,
      );
      final index = _items.indexWhere((r) => r.id == id);
      if (index != -1) _items[index] = _selectedItem!;
      return true;
    } catch (e) {
      _detailErrorMessage = mapExceptionToUserMessage(e);
      return false;
    } finally {
      _isUpdatingStatus = false;
      notifyListeners();
    }
  }
}
