import 'package:flutter/foundation.dart';
import '../models/managed_device.dart';
import '../services/api_service.dart';
import '../services/device_telemetry_service.dart';
import '../utils/error_mapper.dart';

/// Cihaz Yönetimi (MDM simülasyonu) ekranlarının state'ini yönetir: cihaz
/// listesi/detayı çekme ve simüle aksiyonları (kilitle/kilidi aç/hesap sil/
/// zorla senkronize et) tetikleme. Bkz. DESIGN_SYSTEM.md — bu aksiyonlar
/// gerçek bir cihaza komut GÖNDERMEZ, yalnızca backend'deki durumu değiştirir.
class DeviceProvider extends ChangeNotifier {
  final ApiService _apiService;

  DeviceProvider({ApiService? apiService})
    : _apiService = apiService ?? ApiService();

  List<ManagedDevice> _devices = [];
  bool _isLoading = false;
  String? _errorMessage;

  ManagedDevice? _selectedDevice;
  bool _isDetailLoading = false;
  String? _detailErrorMessage;
  bool _isPerformingAction = false;

  List<ManagedDevice> get devices => _devices;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  ManagedDevice? get selectedDevice => _selectedDevice;
  bool get isDetailLoading => _isDetailLoading;
  String? get detailErrorMessage => _detailErrorMessage;
  bool get isPerformingAction => _isPerformingAction;

  Future<void> fetchDevices() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _devices = await _apiService.getDevices();
    } catch (e) {
      _errorMessage = mapExceptionToUserMessage(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchDeviceDetail(int id) async {
    _isDetailLoading = true;
    _detailErrorMessage = null;
    notifyListeners();

    try {
      _selectedDevice = await _apiService.getDeviceDetail(id);
    } catch (e) {
      _detailErrorMessage = mapExceptionToUserMessage(e);
    } finally {
      _isDetailLoading = false;
      notifyListeners();
    }
  }

  /// actionType: 'lock' | 'unlock' | 'wipe' | 'force-sync'.
  /// `telemetry` yalnızca 'force-sync' için anlamlıdır — uygulamanın o an
  /// çalıştığı gerçek cihazdan okunan pil/model/OS bilgisidir (bkz.
  /// DeviceTelemetryService). Verilmezse backend yalnızca senkron zamanını günceller.
  Future<bool> performAction(
    int id,
    String actionType, {
    DeviceTelemetry? telemetry,
  }) async {
    _isPerformingAction = true;
    notifyListeners();

    try {
      switch (actionType) {
        case 'lock':
          await _apiService.lockDevice(id);
          break;
        case 'unlock':
          await _apiService.unlockDevice(id);
          break;
        case 'wipe':
          await _apiService.wipeDevice(id);
          break;
        case 'force-sync':
          await _apiService.forceSyncDevice(
            id,
            batteryLevel: telemetry?.batteryLevel,
            deviceModel: telemetry?.deviceModel,
            osVersion: telemetry?.osVersion,
          );
          break;
        default:
          throw ArgumentError('Bilinmeyen aksiyon: $actionType');
      }

      // Aksiyon endpoint'i logs alanını dönmüyor; işlem geçmişinin de güncel
      // görünmesi için detayı tekrar çekiyoruz.
      _selectedDevice = await _apiService.getDeviceDetail(id);
      final index = _devices.indexWhere((d) => d.id == id);
      if (index != -1) _devices[index] = _selectedDevice!;
      _detailErrorMessage = null;
      return true;
    } catch (e) {
      _detailErrorMessage = mapExceptionToUserMessage(e);
      return false;
    } finally {
      _isPerformingAction = false;
      notifyListeners();
    }
  }
}
