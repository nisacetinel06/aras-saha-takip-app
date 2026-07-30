import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/work_order.dart';
import '../services/api_service.dart';

/// İş emri detay ekranının state'ini yönetir: detay çekme, durum güncelleme,
/// fotoğraf ekleme ve bu işlemler sırasındaki yükleniyor/hata durumları.
class WorkOrderDetailProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  final int workOrderId;

  WorkOrderDetailProvider(this.workOrderId);

  WorkOrder? _workOrder;
  bool _isLoading = false;
  bool _isUpdating = false;
  String? _errorMessage;

  WorkOrder? get workOrder => _workOrder;
  bool get isLoading => _isLoading;
  bool get isUpdating => _isUpdating;
  String? get errorMessage => _errorMessage;

  Future<void> loadDetail() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _workOrder = await _apiService.getWorkOrderDetail(workOrderId);
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Statüyü günceller. Başarılıysa true, başarısızsa false döner
  /// (hata mesajı errorMessage üzerinden okunabilir).
  Future<bool> updateStatus(WorkOrderStatus newStatus) async {
    _isUpdating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _workOrder = await _apiService.updateStatus(workOrderId, newStatus.toJson());
      return true;
    } catch (e) {
      _errorMessage = e.toString();
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
      _workOrder = await _apiService.assignWorkOrder(workOrderId, newAssignedUserId);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
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
      _errorMessage = e.toString();
      return false;
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
  }
}
