import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:arassaha_flutter/providers/work_order_list_provider.dart';
import 'package:arassaha_flutter/services/api_service.dart';
import 'package:arassaha_flutter/models/work_order.dart';
import '../helpers/mocks.dart';
import '../helpers/testFixtures.dart';

/// Liste + filtre içeren bir provider için aynı şablon (bkz.
/// auth_provider_test.dart) — burada ayrıca boş liste ve "hata sırasında eski
/// veri korunur mu" senaryoları da gösteriliyor.
///
/// Not: WorkOrderListProvider başarısız bir çekmede önce Hive tabanlı
/// CacheService'e düşer (bkz. lib/services/cache_service.dart). Testlerde
/// CacheService.init() hiç çağrılmadığı (Hive.initFlutter() gerektirir) için
/// önbellek her zaman boştur — bu da provider'ı gerçek davranışının bir
/// parçası olan "önbellek de yoksa, bellekteki ESKİ liste olduğu gibi kalır,
/// errorMessage set edilir" dalına düşürür. Bu yüzden aşağıdaki test,
/// önbelleği mocklamaya gerek kalmadan gerçek kod yolunu doğrular.
void main() {
  late MockApiService mockApiService;
  late WorkOrderListProvider provider;

  setUp(() {
    mockApiService = MockApiService();
    provider = WorkOrderListProvider(apiService: mockApiService);
  });

  group('WorkOrderListProvider - loadWorkOrders (success)', () {
    test('API veri döndürdüğünde workOrders dolmalı, hata olmamalı', () async {
      when(() => mockApiService.getWorkOrders(statusFilter: any(named: 'statusFilter')))
          .thenAnswer((_) async => [testWorkOrder1, testWorkOrder2]);

      await provider.loadWorkOrders();

      expect(provider.isLoading, false);
      expect(provider.workOrders.length, 2);
      expect(provider.errorMessage, isNull);
    });

    test('API boş liste döndürdüğünde workOrders boş kalmalı, hata olmamalı', () async {
      when(() => mockApiService.getWorkOrders(statusFilter: any(named: 'statusFilter')))
          .thenAnswer((_) async => []);

      await provider.loadWorkOrders();

      expect(provider.workOrders, isEmpty);
      expect(provider.errorMessage, isNull);
      expect(provider.isLoading, false);
    });
  });

  group('WorkOrderListProvider - loadWorkOrders (error)', () {
    test('API hata fırlattığında errorMessage set edilmeli, bellekteki eski veri korunmalı', () async {
      when(() => mockApiService.getWorkOrders(statusFilter: any(named: 'statusFilter')))
          .thenAnswer((_) async => [testWorkOrder1]);
      await provider.loadWorkOrders();
      expect(provider.workOrders.length, 1);

      when(() => mockApiService.getWorkOrders(statusFilter: any(named: 'statusFilter')))
          .thenThrow(ApiException(500, 'Bağlantı hatası'));
      await provider.loadWorkOrders();

      expect(provider.errorMessage, 'Sunucuda bir hata oluştu, lütfen daha sonra tekrar deneyin');
      expect(provider.isLoading, false);
      expect(
        provider.workOrders.length,
        1,
        reason: 'önbellek boşken (Hive başlatılmadığı için) provider bellekteki ESKİ listeyi korumalı, sıfırlamamalı',
      );
    });
  });

  group('WorkOrderListProvider - setFilter', () {
    test('statü filtresi değiştiğinde getWorkOrders doğru statusFilter ile çağrılmalı', () async {
      when(() => mockApiService.getWorkOrders(statusFilter: 'yolda'))
          .thenAnswer((_) async => [testWorkOrder2]);

      await provider.setFilter(WorkOrderStatus.yolda);

      expect(provider.filterStatus, WorkOrderStatus.yolda);
      verify(() => mockApiService.getWorkOrders(statusFilter: 'yolda')).called(1);
    });
  });

  group('WorkOrderListProvider - notifyListeners', () {
    test('loadWorkOrders sırasında en az 2 kez tetiklenmeli (loading=true, işlem bitince)', () async {
      when(() => mockApiService.getWorkOrders(statusFilter: any(named: 'statusFilter')))
          .thenAnswer((_) async => [testWorkOrder1]);

      var notifyCount = 0;
      provider.addListener(() => notifyCount++);

      await provider.loadWorkOrders();

      expect(notifyCount, greaterThanOrEqualTo(2));
    });
  });
}
