import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';

/// Ayarlar ve Çevrimdışı Mod (Modül 17) — Okuma Önbelleği (Read-Through
/// Cache) deseninin TEK ortak uygulaması. Her ana listeleme provider'ı
/// (WorkOrderListProvider, EquipmentProvider, NotificationProvider) AYNI
/// Hive kodunu tekrar tekrar yazmak yerine bu sınıfın `get`/`set`
/// metodlarını çağırır.
///
/// Değer, ham bir Map/List olarak DEĞİL, `jsonEncode` edilmiş bir STRING
/// olarak saklanır — Hive'ın iç içe (nested) Map'leri geri okurken dynamic
/// anahtarlı bir Map'e dönüştürmesi (String anahtarlı Map bekleyen model
/// `fromJson` fabrikalarını TypeError'a düşürebilen bilinen bir Hive
/// davranışı), veriyi tekrar `jsonDecode` ederek tamamen bertaraf edilir —
/// önbellekten okunan veri, canlı bir API yanıtından `jsonDecode` edilmiş
/// veriyle BİREBİR aynı Dart tipindedir.
class CacheEntry {
  final dynamic data;
  final DateTime cachedAt;
  const CacheEntry(this.data, this.cachedAt);
}

class CacheService {
  CacheService._();

  static const _boxName = 'cache_box';
  static Box<String>? _box;

  /// main() içinde Hive.initFlutter()'dan sonra bir kez çağrılır.
  static Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  /// [key]: genelde `'endpoint?filtre=değer'` şeklinde, çağıran tarafın
  /// kendi ürettiği benzersiz bir önbellek anahtarı (örn. WorkOrderListProvider
  /// için `'work_orders:${statusFilter ?? 'all'}'`).
  /// [jsonData]: API'den dönen, zaten `jsonDecode` edilmiş ham veri
  /// (`List<dynamic>` ya da `Map<String, dynamic>`).
  static Future<void> set(String key, dynamic jsonData) async {
    final box = _box;
    if (box == null) return;
    await box.put(
      key,
      jsonEncode({
        'data': jsonData,
        'cached_at': DateTime.now().toIso8601String(),
      }),
    );
  }

  /// Önbellekte kayıt yoksa null döner.
  static CacheEntry? get(String key) {
    final box = _box;
    if (box == null) return null;
    final raw = box.get(key);
    if (raw == null) return null;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return CacheEntry(
      decoded['data'],
      DateTime.parse(decoded['cached_at'] as String),
    );
  }

  /// Ayarlar ekranındaki "Önbelleği Temizle" aksiyonu tarafından çağrılır.
  static Future<void> clear() async {
    await _box?.clear();
  }
}

/// "12 dakika önce" gibi bir göreli zaman metni üretir — çevrimdışı bant/not
/// metinlerinde (bkz. widgets/offline_banner.dart, read-through cache
/// notları) tekrarlanmasın diye tek bir yerde.
String formatCacheAge(DateTime cachedAt) {
  final diff = DateTime.now().difference(cachedAt);
  if (diff.inMinutes < 1) return 'az önce';
  if (diff.inMinutes < 60) return '${diff.inMinutes} dakika önce';
  if (diff.inHours < 24) return '${diff.inHours} saat önce';
  return '${diff.inDays} gün önce';
}
