import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/work_order.dart';
import '../providers/connectivity_provider.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/offline_queue_service.dart';
import '../utils/error_mapper.dart';

/// İş emri detay ekranının state'ini yönetir: detay çekme, durum güncelleme,
/// fotoğraf ekleme ve bu işlemler sırasındaki yükleniyor/hata durumları.
class WorkOrderDetailProvider extends ChangeNotifier {
  final ApiService _apiService;
  final int workOrderId;

  WorkOrderDetailProvider(this.workOrderId, {ApiService? apiService})
    : _apiService = apiService ?? ApiService();

  WorkOrder? _workOrder;
  bool _isLoading = false;
  bool _isUpdating = false;
  String? _errorMessage;
  // Modül 17 — çevrimdışıyken kuyruğa alınan, henüz gerçek sunucu yanıtıyla
  // doğrulanmamış bir durum güncellemesi varken true. UI bunu bir "bekliyor"
  // rozeti göstermek için okur (bkz. work_order_detail_screen.dart).
  bool _hasPendingStatusUpdate = false;
  // Okuma Önbelleği (Modül 17) — liste ekranlarındaki AYNI desen burada da
  // uygulanır. Bu, yalnızca kozmetik değil: bir teknisyenin sahaya çıkmadan
  // ÖNCE (çevrimiçiyken) açtığı bir iş emrini, sinyal kesildiğinde TEKRAR
  // AÇIP durumunu güncelleyebilmesi (çevrimdışı yazma kuyruğunun asıl amacı)
  // bu önbellek olmadan İMKANSIZDIR — detay ekranı her açılışta sıfırdan yeni
  // bir provider örneği oluşturduğu için (bkz. work_order_detail_screen.dart),
  // önbellek olmadan çevrimdışı bir yeniden açılış her zaman sert bir hata
  // ekranına düşer ve "Durum Güncelle" butonuna hiç ulaşılamaz.
  bool _isFromCache = false;
  DateTime? _cachedAt;

  WorkOrder? get workOrder => _workOrder;
  bool get isLoading => _isLoading;
  bool get isUpdating => _isUpdating;
  String? get errorMessage => _errorMessage;
  bool get hasPendingStatusUpdate => _hasPendingStatusUpdate;
  bool get isFromCache => _isFromCache;
  DateTime? get cachedAt => _cachedAt;

  String get _cacheKey => 'work_order_detail:$workOrderId';

  Future<void> loadDetail() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _workOrder = await _apiService.getWorkOrderDetail(workOrderId);
      _isFromCache = false;
      _cachedAt = null;
      await CacheService.set(_cacheKey, _workOrder!.toJson());
    } catch (e) {
      final cached = CacheService.get(_cacheKey);
      if (cached != null) {
        _workOrder = WorkOrder.fromJson(cached.data as Map<String, dynamic>);
        _isFromCache = true;
        _cachedAt = cached.cachedAt;
      } else {
        _errorMessage = mapExceptionToUserMessage(e);
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Statüyü günceller. Başarılıysa true, başarısızsa false döner
  /// (hata mesajı errorMessage üzerinden okunabilir).
  ///
  /// ÇEVRİMDIŞI DAVRANIŞ (Modül 17): bağlantı yoksa istek backend'e HİÇ
  /// atılmaz — doğrudan çevrimdışı yazma kuyruğuna eklenir (bkz.
  /// OfflineQueueService) ve ekrandaki durum İYİMSER (optimistic UI) olarak
  /// hemen güncellenir; gerçek senkronizasyon bağlantı gelince otomatik
  /// olur. Bu, yalnızca durum güncellemesi gibi küçük/geri alınabilir bir
  /// işlem için güvenlidir — fotoğraf yükleme gibi işlemler bu yolu hiç
  /// kullanmaz (bkz. OfflineQueueService kapsam notu).
  Future<bool> updateStatus(WorkOrderStatus newStatus) async {
    if (!ConnectivityProvider.instance.isOnline) {
      final current = _workOrder;
      if (current == null) return false;

      await OfflineQueueService.instance.enqueueWorkOrderStatusUpdate(
        workOrderId: workOrderId,
        workOrderTitle: current.title,
        status: newStatus.toJson(),
      );
      _workOrder = current.copyWith(status: newStatus);
      _hasPendingStatusUpdate = true;
      notifyListeners();
      return true;
    }

    _isUpdating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _workOrder = await _apiService.updateStatus(
        workOrderId,
        newStatus.toJson(),
      );
      return true;
    } catch (e) {
      _errorMessage = mapExceptionToUserMessage(e);
      return false;
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
  }

  /// Var olan iş emrinin atanan kişisini değiştirir (yalnızca dispeçer/
  /// yönetici — bkz. WorkOrderDetailScreen "Atanan Kişiyi Değiştir").
  Future<bool> reassign(int newAssignedUserId) async {
    _isUpdating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _workOrder = await _apiService.assignWorkOrder(
        workOrderId,
        newAssignedUserId,
      );
      return true;
    } catch (e) {
      _errorMessage = mapExceptionToUserMessage(e);
      return false;
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
  }

  Future<bool> addPhoto(File imageFile) async {
    _isUpdating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final photo = await _apiService.addPhoto(workOrderId, imageFile);
      if (_workOrder != null) {
        _workOrder = _workOrder!.copyWith(
          photos: [photo, ..._workOrder!.photos],
        );
      }
      return true;
    } catch (e) {
      _errorMessage = mapExceptionToUserMessage(e);
      return false;
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
  }
}
