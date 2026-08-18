import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Auth (Modül 7) — oturum bilgisinin (JWT token) TEK, merkezi güvenli
/// depolama noktası. Doğrudan her yerde `FlutterSecureStorage` çağırmak
/// yerine bu servis kullanılır — hem tutarlılık hem de test edilebilirlik
/// için (bkz. `AuthProvider({ApiService? apiService})` ile AYNI dependency
/// injection deseni, test/helpers/mocks.dart'taki MockSecureStorageService).
///
/// NEDEN SharedPreferences DEĞİL: çalınan bir JWT token, süresi dolana kadar
/// (Modül 7'de 7 gün) o kullanıcı gibi davranmak için TEK BAŞINA yeterlidir —
/// şifre bile gerekmez. SharedPreferences diskte düz metin (plaintext) XML/
/// dosya olarak durur; cihaz root'lanmışsa veya ADB ile fiziksel erişim
/// sağlanırsa doğrudan okunabilir. flutter_secure_storage ise Android'de
/// Keystore-destekli EncryptedSharedPreferences, iOS'ta Keychain kullanır —
/// bu, uygulamanın en kritik güvenlik yüzeylerinden birini kapatır.
///
/// KAPSAM NETLİĞİ: yalnızca kimlik doğrulama/oturum verisi (token) burada
/// tutulur. Modül 17'deki Hive önbelleği (cache_box) iş emri listesi gibi,
/// zaten sunucudan tekrar çekilebilen, kimlik doğrulama değeri TAŞIMAYAN
/// görüntüleme verisi içerir — bu yüzden bilinçli olarak bu görevin/servisin
/// kapsamı DIŞINDA bırakıldı, güvenli depolamaya taşınmadı.
class SecureStorageService {
  final FlutterSecureStorage _storage;

  SecureStorageService({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // Android'de önerilen, en güncel şifreleme yöntemi.
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  static const _tokenKey = 'jwt_token';
  static const _userJsonKey = 'current_user';

  Future<void> saveToken(String token) => _storage.write(key: _tokenKey, value: token);
  Future<String?> getToken() => _storage.read(key: _tokenKey);
  Future<void> deleteToken() => _storage.delete(key: _tokenKey);

  // AuthProvider şu an kullanıcı bilgisini diskte AYRICA saklamıyor (uygulama
  // açılışında token'ın geçerliliği zaten GET /api/auth/me ile doğrulanırken
  // güncel kullanıcı bilgisi de aynı istekle çekiliyor, bkz.
  // AuthProvider.tryAutoLogin). Bu iki metod, ileride bu davranış
  // değişirse (örn. çevrimdışı açılışta son bilinen kullanıcıyı göstermek
  // gibi) kullanılabilecek şekilde servis arayüzünde tutuluyor.
  Future<void> saveUserJson(String userJson) => _storage.write(key: _userJsonKey, value: userJson);
  Future<String?> getUserJson() => _storage.read(key: _userJsonKey);
  Future<void> deleteUserJson() => _storage.delete(key: _userJsonKey);

  Future<void> clearAll() => _storage.deleteAll();
}
