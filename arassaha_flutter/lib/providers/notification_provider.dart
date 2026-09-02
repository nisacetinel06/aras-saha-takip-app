import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/app_notification.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/local_notification_service.dart';
import '../utils/error_mapper.dart';

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
  final ApiService _apiService;

  NotificationProvider({ApiService? apiService})
    : _apiService = apiService ?? ApiService();

  static const _pollInterval = Duration(seconds: 30);

  List<AppNotification> _notifications = [];
  int _unreadCount = 0;
  bool _isLoading = false;
  String? _errorMessage;

  // Alt navigasyondaki "Mesajlar" sekmesi rozeti (Yöneticiden Çalışana Duyuru
  // Sistemi) — genel bildirim sayacından (yukarısı) BAĞIMSIZ, AYNI 30 saniyelik
  // polling döngüsüne eklendi (bkz. startPolling/_pollOnce), ayrı bir Timer
  // AÇILMADI. Yönetici için backend her zaman 0 döner (bkz. api_service.dart
  // getUnreadManagerMessageCount notu) — bu yüzden rozet yöneticide hiç görünmez.
  int _unreadMessageCount = 0;

  Timer? _pollTimer;
  bool _isPolling = false;

  // Ayarlar ve Çevrimdışı Mod (Modül 17) — Okuma Önbelleği. bkz.
  // WorkOrderListProvider'daki AYNI desen ve gerekçe notu.
  bool _isFromCache = false;
  DateTime? _cachedAt;

  List<AppNotification> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  int get unreadMessageCount => _unreadMessageCount;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isFromCache => _isFromCache;
  DateTime? get cachedAt => _cachedAt;

  static const _cacheKey = 'notifications:all';

  Future<void> fetchNotifications() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _notifications = await _apiService.getNotifications();
      _unreadCount = _notifications.where((n) => !n.isRead).length;
      _isFromCache = false;
      _cachedAt = null;
      await CacheService.set(
        _cacheKey,
        _notifications.map((n) => n.toJson()).toList(),
      );
    } catch (e) {
      final cached = CacheService.get(_cacheKey);
      if (cached != null) {
        final rawList = cached.data as List<dynamic>;
        _notifications = rawList
            .map(
              (json) => AppNotification.fromJson(json as Map<String, dynamic>),
            )
            .toList();
        _unreadCount = _notifications.where((n) => !n.isRead).length;
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

  Future<void> fetchUnreadMessageCount() async {
    try {
      _unreadMessageCount = await _apiService.getUnreadManagerMessageCount();
      notifyListeners();
    } catch (_) {
      // Sessizce yutulur — bkz. fetchUnreadCount üstündeki AYNI gerekçe.
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
      _errorMessage = mapExceptionToUserMessage(e);
      notifyListeners();
    }
  }

  Future<void> markAllAsRead() async {
    try {
      await _apiService.markAllNotificationsRead();
      _notifications = _notifications
          .map((n) => n.copyWith(isRead: true))
          .toList();
      _unreadCount = 0;
      notifyListeners();
    } catch (e) {
      _errorMessage = mapExceptionToUserMessage(e);
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
    fetchUnreadMessageCount();

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
    _unreadMessageCount = 0;
  }

  Future<void> _pollOnce() async {
    final previousCount = _unreadCount;
    await fetchUnreadCount();
    await fetchUnreadMessageCount();

    if (_unreadCount > previousCount) {
      // Acil Durum (SOS) Modülü: normalde artışın kaynağı burada tekrar
      // sorgulanmaz (genel bir mesaj yeterlidir, spesifik içeriği kullanıcı
      // Bildirimler ekranını açınca görür) — AMA bir SOS bildirimi sıradan
      // bir bildirimden (iş emri, İSG vb.) AYIRT EDİLEBİLİR olmalı (bkz.
      // PROMPT madde 8). Bu yüzden yalnızca BU durumda (artış tespit edildiğinde,
      // yani nadiren — her 30 sn'de bir DEĞİL) tam listeyi çekip en yeni
      // okunmamış bildirimin türüne bakıyoruz.
      var isSosAlert = false;
      String body = 'Yeni bildiriminiz var';
      try {
        final latest = await _apiService.getNotifications(unreadOnly: true);
        if (latest.isNotEmpty) {
          final newest = latest.first;
          isSosAlert = newest.relatedType == NotificationRelatedType.sosAlert;
          if (isSosAlert) body = newest.message;
        }
      } catch (_) {
        // Tür tespiti başarısız olursa (ağ hatası vb.) sessizce genel
        // bildirime düşülür — polling akışı asla kullanıcıya hata göstermez
        // (bkz. fetchUnreadCount üstündeki AYNI gerekçe).
      }

      await LocalNotificationService.instance.showNotification(
        isSosAlert ? '🚨 ACİL DURUM' : 'ArasSaha',
        body,
        isUrgent: isSosAlert,
      );
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
