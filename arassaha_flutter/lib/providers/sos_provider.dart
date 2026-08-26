import 'package:flutter/foundation.dart';
import '../models/sos_alert.dart';
import '../services/api_service.dart';
import '../utils/error_mapper.dart';

/// Acil Durum / SOS Bildirimi Modülü ekranlarının state'ini yönetir.
///
/// [triggerSosAlert]/[addNote] teknisyen tarafından (bkz.
/// screens/sos/sos_confirm_screen.dart, sos_sent_screen.dart) — backend
/// requireRole UYGULAMAZ, herkes acil durum bildirebilir. [fetchActiveAlerts]/
/// [acknowledgeAlert]/[closeAlert] SADECE dispeçer/yönetici ekranlarından
/// çağrılır (bkz. screens/sos/sos_alerts_screen.dart) — backend
/// requireRole('dispecer', 'yonetici') ile zaten korunuyor.
class SosProvider extends ChangeNotifier {
  final ApiService _apiService;

  SosProvider({ApiService? apiService})
    : _apiService = apiService ?? ApiService();

  List<SosAlert> _alerts = [];
  bool _isListLoading = false;
  String? _listErrorMessage;

  bool _isSending = false;
  String? _sendErrorMessage;

  List<SosAlert> get alerts => _alerts;
  bool get isListLoading => _isListLoading;
  String? get listErrorMessage => _listErrorMessage;

  bool get isSending => _isSending;
  String? get sendErrorMessage => _sendErrorMessage;

  /// SOS Uyarıları ekranının/Ana Sayfa rozetinin okuduğu sayı — hâlâ
  /// 'aktif' (henüz "gördüm/ilgileniyorum" bile denmemiş) bildirim sayısı.
  int get activeCount => _alerts.where((a) => a.isActive).length;

  /// POST /api/sos-alerts. Başarılıysa oluşan bildirimin id'sini döner
  /// (sonradan not eklenebilmesi için, bkz. addNote) — başarısızsa null.
  Future<int?> triggerSosAlert({
    required double lat,
    required double lng,
  }) async {
    _isSending = true;
    _sendErrorMessage = null;
    notifyListeners();

    try {
      final id = await _apiService.createSosAlert(lat: lat, lng: lng);
      return id;
    } catch (e) {
      _sendErrorMessage = mapExceptionToUserMessage(e);
      return null;
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  /// PATCH /api/sos-alerts/:id/note — hız için gönderim akışından TAMAMEN
  /// AYRI, opsiyonel bir adım (bkz. SosSentScreen). Başarılıysa true döner.
  Future<bool> addNote(int id, String note) async {
    try {
      await _apiService.addSosAlertNote(id, note);
      return true;
    } catch (e) {
      _sendErrorMessage = mapExceptionToUserMessage(e);
      notifyListeners();
      return false;
    }
  }

  Future<void> fetchActiveAlerts() async {
    _isListLoading = true;
    _listErrorMessage = null;
    notifyListeners();

    try {
      _alerts = await _apiService.getSosAlerts();
    } catch (e) {
      _listErrorMessage = mapExceptionToUserMessage(e);
    } finally {
      _isListLoading = false;
      notifyListeners();
    }
  }

  /// "Gördüm/İlgileniyorum" — listedeki karşılığını iyimser (optimistic)
  /// günceller, NotificationProvider.markAsRead ile AYNI desen.
  Future<void> acknowledgeAlert(int id) async {
    try {
      await _apiService.acknowledgeSosAlert(id);
      final index = _alerts.indexWhere((a) => a.id == id);
      if (index != -1) {
        _alerts[index] = _alerts[index].copyWith(
          status: SosAlertStatus.onaylandi,
          acknowledgedAt: DateTime.now(),
        );
      }
      notifyListeners();
    } catch (e) {
      _listErrorMessage = mapExceptionToUserMessage(e);
      notifyListeners();
    }
  }

  /// "Kapat" — opsiyonel bir çözüm notuyla. İyimser güncelleme.
  Future<void> closeAlert(int id, {String? note}) async {
    try {
      await _apiService.closeSosAlert(id, closedNote: note);
      final index = _alerts.indexWhere((a) => a.id == id);
      if (index != -1) {
        _alerts[index] = _alerts[index].copyWith(
          status: SosAlertStatus.kapatildi,
          closedAt: DateTime.now(),
          closedNote: note,
        );
      }
      notifyListeners();
    } catch (e) {
      _listErrorMessage = mapExceptionToUserMessage(e);
      notifyListeners();
    }
  }
}
