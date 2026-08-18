import 'package:mocktail/mocktail.dart';
import 'package:arassaha_flutter/services/api_service.dart';
import 'package:arassaha_flutter/services/secure_storage_service.dart';
import 'package:arassaha_flutter/models/work_order.dart';

/// Tüm provider testlerinin ortak sahte [ApiService] örneği. Provider'lar
/// artık Adım 0 refactor'ü sayesinde bunu constructor'dan enjekte edilebiliyor
/// (bkz. `WorkOrderListProvider({ApiService? apiService})` deseni) — bu
/// sınıfı her provider testinde tekrar tanımlamak yerine buradan içe aktar.
class MockApiService extends Mock implements ApiService {}

/// AuthProvider'ın token/kullanıcı bilgisini artık flutter_secure_storage
/// üzerinden okuyup yazdığı (bkz. AuthProvider({SecureStorageService?})) için
/// aynı enjeksiyon deseniyle mocklanır — testler gerçek Android Keystore/iOS
/// Keychain'e hiç dokunmaz.
class MockSecureStorageService extends Mock implements SecureStorageService {}

/// mocktail, `any()`/`any(named: ...)` matcher'ını kullanabilmek için o tipin
/// bir "fallback" (örnek) değerine ihtiyaç duyar — kayıt yapılmazsa
/// çalışma zamanında hata fırlatır. Enum/özel tip parametre alan metodları
/// (örn. `getWorkOrders(statusFilter: ...)` gibi String parametreler DEĞİL,
/// doğrudan enum/özel tip alan metodlar) mocklayan her test dosyasının
/// `setUpAll` içinde bunu bir kez çağırması yeterlidir.
void registerFallbackValues() {
  registerFallbackValue(WorkOrderStatus.acik);
}
