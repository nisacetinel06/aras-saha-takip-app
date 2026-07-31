import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/app_notification.dart';
import '../services/api_service.dart';
import '../services/local_notification_service.dart';

/// Bildirim Sistemi (Modül 6) — bildirim listesi/sayısı state'i VE cihaz içi
/// polling mekanizması.
///
/// NEDEN POLLING + YEREL BİLDİRİM (FCM DEĞİL): Gerçek bir sunucu-push
/// altyapısı (Firebase Cloud Messaging) Firebase projesi açmayı, sunucu
/// tarafında bir service account/sunucu anahtarı yönetmeyi ve native
/// platformlarda ek kurulum yapmayı gerektirir — bir staj projesi kapsamında
/// bu, işin asıl amacına (bildirimin uçtan uca gerçekten çalıştığını
/// göstermek) oranla gereksiz bir karmaşıklık katar. Bunun yerine uygulama
/// ön plandayken her 30 saniyede bir GET /api/notifications/unread-count
/// çağrılır (bkz. startPolling); okunmamış sayıda ARTIŞ tespit edilirse
/// (yalnızca artışta — kullanıcı bir bildirimi okuyup sayı azaldığında değil)
/// flutter_local_notifications ile cihazda gerçek bir OS bildirimi gösterilir.
/// Kullanıcı deneyimi FCM ile aynıdır; yalnızca "sunucu cihaza iter" yerine
/// "cihaz sunucuyu düzenli aralıklarla sorar" (pull) yaklaşımı kullanılır.
class NotificationProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  static const _pollInterval = Duration(seconds: 30);

  List<AppNotification> _notifications = [];
  int _unreadCount = 0;
  bool _isLoading = false;
  String? _errorMessage;

  Timer? _pollTimer;
  bool _isPolling = false;

  List<AppNotification> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> fetchNotifications() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _notifications = await _apiService.getNotifications();
      _unreadCount = _notifications.where((n) => !n.isRead).length;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchUnreadCount() async {
    try {
      _unreadCount = await _apiService.getUnreadNotificationCount();
      notifyListeners();
    } catch (_) {
      // Sessizce yutulur — bu, arka planda periyodik bir kontrol; kullanıcıya
      // her 30 saniyede bir "bağlantı hatası" göstermek gürültü olurdu.
      // Bildirimler ekranı açıldığında fetchNotifications zaten hatayı gösterir.
    }
  }

  Future<void> markAsRead(int id) async {
    try {
      final updated = await _apiService.markNotificationRead(id);
      final index = _notifications.indexWhere((n) => n.id == id);
      if (index != -1) _notifications[index] = updated;
      _unreadCount = _notifications.where((n) => !n.isRead).length;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> markAllAsRead() async {
    try {
      await _apiService.markAllNotificationsRead();
      _notifications = _notifications.map((n) => n.copyWith(isRead: true)).toList();
      _unreadCount = 0;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// Kullanıcı giriş yaptıktan sonra, uygulama ön plandayken çağrılır (bkz.
  /// MainShell — yalnızca kimlik doğrulanmış kullanıcının gördüğü kabukta
  /// başlatılır, bu sayede login öncesi hiç çalışmaz). Zaten çalışan bir
  /// timer varsa tekrar başlatılmaz.
  void startPolling() {
    if (_isPolling) return;
    _isPolling = true;

    // İlk kontrol hemen yapılır — 30 saniye beklemeden mevcut sayı bilinir,
    // böylece bir sonraki tick'te yalnızca GERÇEK bir artış bildirim üretir.
    fetchUnreadCount();

    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollOnce());
  }

  /// Kullanıcı çıkış yaptığında (ya da oturumu 401 ile düşürüldüğünde,
  /// bkz. main.dart AuthGate) çağrılır — bellek sızıntısı/gereksiz istek
  /// olmasın diye timer kesinlikle durdurulur.
  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _isPolling = false;
    _notifications = [];
    _unreadCount = 0;
  }

  Future<void> _pollOnce() async {
    final previousCount = _unreadCount;
    await fetchUnreadCount();

    if (_unreadCount > previousCount) {
      // Artışın kaynağını burada tekrar sorgulamıyoruz — genel bir mesaj
      // yeterli, spesifik içeriği kullanıcı Bildirimler ekranını açınca görür
      // (bkz. ARCHITECTURE.md).
      await LocalNotificationService.instance.showNotification(
        'ArasSaha',
        'Yeni bildiriminiz var',
      );
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
