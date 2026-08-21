import 'package:flutter/foundation.dart';
import '../models/kvkk_models.dart';
import '../services/api_service.dart';
import '../utils/error_mapper.dart';

/// KVKK Uyum Modülü ekranlarının state'ini yönetir: aydınlatma metni, kendi
/// veri özetim, silme talebi oluşturma ve (yalnızca yönetici) talep listesi
/// + onay/red akışı — bkz. screens/kvkk/*, screens/admin/deletion_requests_screen.dart.
class KvkkProvider extends ChangeNotifier {
  final ApiService _apiService;

  KvkkProvider({ApiService? apiService})
    : _apiService = apiService ?? ApiService();

  String? _aydinlatmaMetni;
  String? _draftWarning;
  bool _isLoadingAydinlatmaMetni = false;
  String? _aydinlatmaMetniErrorMessage;

  KvkkDataSummary? _dataSummary;
  bool _isLoadingSummary = false;
  String? _summaryErrorMessage;

  bool _isSubmitting = false;
  String? _submitErrorMessage;

  List<KvkkDeletionRequest> _allRequests = [];
  bool _isLoadingRequests = false;
  String? _requestsErrorMessage;

  bool _isProcessingRequest = false;
  String? _processErrorMessage;

  String? get aydinlatmaMetni => _aydinlatmaMetni;
  String? get draftWarning => _draftWarning;
  bool get isLoadingAydinlatmaMetni => _isLoadingAydinlatmaMetni;
  String? get aydinlatmaMetniErrorMessage => _aydinlatmaMetniErrorMessage;

  KvkkDataSummary? get dataSummary => _dataSummary;
  bool get isLoadingSummary => _isLoadingSummary;
  String? get summaryErrorMessage => _summaryErrorMessage;

  bool get isSubmitting => _isSubmitting;
  String? get submitErrorMessage => _submitErrorMessage;

  List<KvkkDeletionRequest> get allRequests => _allRequests;
  bool get isLoadingRequests => _isLoadingRequests;
  String? get requestsErrorMessage => _requestsErrorMessage;

  bool get isProcessingRequest => _isProcessingRequest;
  String? get processErrorMessage => _processErrorMessage;

  Future<void> fetchAydinlatmaMetni() async {
    _isLoadingAydinlatmaMetni = true;
    _aydinlatmaMetniErrorMessage = null;
    notifyListeners();

    try {
      final result = await _apiService.getKvkkAydinlatmaMetni();
      _aydinlatmaMetni = result.content;
      _draftWarning = result.draftWarning;
    } catch (e) {
      _aydinlatmaMetniErrorMessage = mapExceptionToUserMessage(e);
    } finally {
      _isLoadingAydinlatmaMetni = false;
      notifyListeners();
    }
  }

  Future<void> fetchMyDataSummary() async {
    _isLoadingSummary = true;
    _summaryErrorMessage = null;
    notifyListeners();

    try {
      _dataSummary = await _apiService.getMyDataSummary();
    } catch (e) {
      _summaryErrorMessage = mapExceptionToUserMessage(e);
    } finally {
      _isLoadingSummary = false;
      notifyListeners();
    }
  }

  Future<bool> submitDeletionRequest({
    required KvkkRequestType requestType,
    String? reason,
  }) async {
    _isSubmitting = true;
    _submitErrorMessage = null;
    notifyListeners();

    try {
      await _apiService.submitDeletionRequest(
        requestType: requestType,
        reason: reason,
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

  Future<void> fetchAllDeletionRequests() async {
    _isLoadingRequests = true;
    _requestsErrorMessage = null;
    notifyListeners();

    try {
      _allRequests = await _apiService.getAllDeletionRequests();
    } catch (e) {
      _requestsErrorMessage = mapExceptionToUserMessage(e);
    } finally {
      _isLoadingRequests = false;
      notifyListeners();
    }
  }

  /// Onay sonrası backend'in döndüğü satırda `user`/`reviewed_by` gömülü
  /// DEĞİLDİR (yalnızca GET listesi bunları JOIN'ler) — bu yüzden listeyi
  /// yerel olarak "birleştirmek" yerine tamamen YENİDEN çekiyoruz; böylece
  /// liste satırındaki kullanıcı bilgisi asla eksik/eski kalmaz.
  Future<bool> approveRequest(int id) async {
    _isProcessingRequest = true;
    _processErrorMessage = null;
    notifyListeners();

    try {
      await _apiService.approveDeletionRequest(id);
      await fetchAllDeletionRequests();
      return true;
    } catch (e) {
      _processErrorMessage = mapExceptionToUserMessage(e);
      return false;
    } finally {
      _isProcessingRequest = false;
      notifyListeners();
    }
  }

  Future<bool> rejectRequest(int id, String reviewerNote) async {
    _isProcessingRequest = true;
    _processErrorMessage = null;
    notifyListeners();

    try {
      await _apiService.rejectDeletionRequest(id, reviewerNote);
      await fetchAllDeletionRequests();
      return true;
    } catch (e) {
      _processErrorMessage = mapExceptionToUserMessage(e);
      return false;
    } finally {
      _isProcessingRequest = false;
      notifyListeners();
    }
  }
}
