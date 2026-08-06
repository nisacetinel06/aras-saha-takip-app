import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../services/offline_queue_service.dart';

/// Ayarlar ve Çevrimdışı Mod (Modül 17) — uygulama genelinde tek bağlantı
/// durumu kaynağı. `connectivity_plus` yalnızca bir ağ ARAYÜZÜNÜN (WiFi/mobil
/// veri) var olduğunu söyler, gerçek internet erişimini garanti etmez (örn.
/// WiFi'a bağlı ama internetsiz bir ağ) — ama bu projenin kapsamı için (bkz.
/// ARCHITECTURE.md Modül 17 "Kapsam Netliği") bu basit sinyal yeterlidir;
/// asıl doğruluk zaten her API çağrısının kendi başarı/başarısızlığında ortaya
/// çıkar (bkz. CacheService, OfflineQueueService).
class ConnectivityProvider extends ChangeNotifier {
  ConnectivityProvider._();
  // OfflineQueueService ile AYNI singleton deseni: WorkOrderDetailProvider
  // gibi widget ağacı dışındaki (BuildContext'i olmayan) sınıfların da
  // mevcut bağlantı durumunu okuyabilmesi için — main.dart bu TEK örneği
  // ChangeNotifierProvider.value ile widget ağacına da bağlar, böylece UI
  // tarafı normal `context.watch<ConnectivityProvider>()` ile reaktif kalır.
  static final ConnectivityProvider instance = ConnectivityProvider._();

  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool get isOnline => _isOnline;

  /// main() içinde uygulama açılışında bir kez çağrılır: mevcut durumu okur
  /// ve sonraki değişiklikleri dinlemeye başlar.
  Future<void> initialize() async {
    final initial = await Connectivity().checkConnectivity();
    _isOnline = _hasConnection(initial);

    _subscription = Connectivity().onConnectivityChanged.listen((results) {
      final wasOffline = !_isOnline;
      _isOnline = _hasConnection(results);
      notifyListeners();

      // Çevrimdışı -> çevrimiçi GEÇİŞİ (yalnızca bu yönde) çevrimdışı yazma
      // kuyruğundaki bekleyen işlemleri otomatik tetikler — bkz.
      // offline_queue_service.dart processQueue().
      if (wasOffline && _isOnline) {
        OfflineQueueService.instance.processQueue();
      }
    });
  }

  bool _hasConnection(List<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
