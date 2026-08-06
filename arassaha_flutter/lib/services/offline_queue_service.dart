import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'api_service.dart';

/// Çevrimdışıyken kuyruğa alınan tek bir işlem. `payload`'ın şekli
/// `actionType`'a göre değişir — bugün tek bir actionType
/// ('update_work_order_status') var, ama alan isimlerinin serbest bir
/// Map olması ileride başka bir "güvenli, metin tabanlı" işlem türü
/// eklenirse (bkz. OfflineQueueService üstündeki kapsam notu) şemayı
/// değiştirmeye gerek bırakmaz.
class PendingAction {
  final String id;
  final String actionType;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  const PendingAction({
    required this.id,
    required this.actionType,
    required this.payload,
    required this.createdAt,
  });

  factory PendingAction.fromJson(Map<String, dynamic> json) => PendingAction(
    id: json['id'] as String,
    actionType: json['action_type'] as String,
    payload: Map<String, dynamic>.from(json['payload'] as Map),
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'action_type': actionType,
    'payload': payload,
    'created_at': createdAt.toIso8601String(),
  };
}

/// Ayarlar ve Çevrimdışı Mod (Modül 17) — Çevrimdışı Yazma Kuyruğu.
///
/// KAPSAM BİLİNÇLİ OLARAK SINIRLI (bkz. ARCHITECTURE.md Modül 17): yalnızca
/// iş emri durum güncellemesi gibi küçük, metin tabanlı ve GERİ ALINABİLİR
/// işlemler buraya alınır. Fotoğraf yükleme gerektiren işlemler (İSG
/// bildirimi, iş emri/malzeme fotoğrafı) KUYRUĞA HİÇ ALINMAZ — büyük
/// dosyaların güvenilir şekilde kuyruklanıp senkronize edilmesi (kısmi
/// yükleme, bozuk dosya, disk alanı, çok büyük Hive kaydı) tam bir
/// offline-first mimarinin çözmesi gereken ayrı ve karmaşık bir mühendislik
/// problemidir; bu projenin kapsamında gereksiz risk taşır. Bu ekranlar
/// çevrimdışıyken kullanıcıya doğrudan "bu işlem internet gerektirir"
/// mesajı gösterir, hiçbir şeyi kuyruğa almaz (bkz. isg_report_form_screen.dart
/// ve work_order_detail_screen.dart fotoğraf bölümleri).
///
/// `ChangeNotifier`dir (Provider'daki diğer state sınıflarıyla AYNI desen)
/// — Ayarlar ekranı ve İş Emri Detay ekranındaki "bekliyor" rozeti bu sayede
/// kuyruk her değiştiğinde (enqueue/senkronize) otomatik yeniden çizilir.
class OfflineQueueService extends ChangeNotifier {
  OfflineQueueService._();
  static final OfflineQueueService instance = OfflineQueueService._();

  static const _boxName = 'pending_actions_box';
  static final Uuid _uuid = Uuid();
  Box<String>? _box;

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  /// main() içinde Hive.initFlutter()'dan sonra bir kez çağrılır.
  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  List<PendingAction> get pending {
    final box = _box;
    if (box == null) return [];
    final items = box.values
        .map(
          (raw) =>
              PendingAction.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        )
        .toList();
    items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return items;
  }

  int get pendingCount => pending.length;

  /// İş Emri Detay ekranındaki durum güncelleme butonu, ConnectivityProvider
  /// çevrimdışı olduğunda (backend'e HİÇ istek atmadan) bunu çağırır.
  /// `workOrderTitle`, Ayarlar ekranındaki bekleyen işlemler listesinde
  /// "hangi iş emri" sorusuna cevap vermek için ayrıca bir API çağrısına
  /// gerek kalmadan burada saklanır.
  Future<String> enqueueWorkOrderStatusUpdate({
    required int workOrderId,
    required String workOrderTitle,
    required String status,
  }) async {
    final box = _box;
    if (box == null) throw StateError('OfflineQueueService başlatılmadı.');

    final action = PendingAction(
      id: _uuid.v4(),
      actionType: 'update_work_order_status',
      payload: {
        'work_order_id': workOrderId,
        'work_order_title': workOrderTitle,
        'status': status,
      },
      createdAt: DateTime.now(),
    );
    await box.put(action.id, jsonEncode(action.toJson()));
    notifyListeners();
    return action.id;
  }

  /// ConnectivityProvider, bağlantı çevrimdışı->çevrimiçi geçtiğinde bunu
  /// OTOMATİK çağırır; Ayarlar ekranındaki "Şimdi Senkronize Et" butonu da
  /// MANUEL olarak aynı metodu tetikler.
  ///
  /// Kuyruk SIRAYLA (paralel DEĞİL) işlenir — aynı iş emrine ait birden
  /// fazla bekleyen güncelleme varsa (örn. çevrimdışıyken art arda "Yolda"
  /// sonra "Sahadayım" durumuna geçildiyse), backend'e gönderilme sırası
  /// kullanıcının gerçekte tıkladığı sırayla AYNI kalmalı — aksi halde son
  /// durum yanlış olurdu.
  Future<void> processQueue() async {
    if (_isProcessing) return;
    final box = _box;
    if (box == null) return;

    _isProcessing = true;
    notifyListeners();

    try {
      for (final action in pending) {
        try {
          switch (action.actionType) {
            case 'update_work_order_status':
              await ApiService().updateStatus(
                action.payload['work_order_id'] as int,
                action.payload['status'] as String,
                clientActionId: action.id,
              );
          }
          await box.delete(action.id);
        } on ApiException {
          // Bağlantı yine kesildi ya da sunucu hata döndü — bu işlemi
          // kuyrukta BIRAKIP dur; sıradaki işlemleri aynı anda denemenin
          // anlamı yok (muhtemelen onlar da başarısız olur). Bir sonraki
          // bağlantı geçişinde ya da manuel "Şimdi Senkronize Et" ile
          // tekrar denenecek.
          break;
        }
      }
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Ayarlar ekranındaki "Önbelleği Temizle" aksiyonunun KAPSAMI DIŞINDA —
  /// bilinçli olarak ayrı bir metod: kullanıcı önbelleği temizlerken
  /// gönderilmeyi bekleyen GERÇEK bir işlemi yanlışlıkla kaybetmesin diye
  /// `CacheService.clear()` bu kutuya hiç dokunmaz.
  Future<void> clearAll() async {
    await _box?.clear();
    notifyListeners();
  }
}
