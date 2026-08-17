import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:arassaha_flutter/providers/auth_provider.dart';
import 'package:arassaha_flutter/services/api_service.dart';
import '../helpers/mocks.dart';
import '../helpers/testFixtures.dart';

/// Diğer tüm provider testlerinin izleyeceği şablon: başlangıç durumu,
/// başarılı akış (loading -> success), başarısız akış (loading -> error) ve
/// notifyListeners doğrulaması. Yeni bir provider için test yazarken bu
/// dosyadaki dört group'u kopyalayıp ApiService metodunu/state alanlarını
/// değiştirmek yeterli.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockApiService mockApiService;
  late AuthProvider authProvider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockApiService = MockApiService();
    authProvider = AuthProvider(apiService: mockApiService);
  });

  group('AuthProvider - başlangıç durumu', () {
    test('token, kullanıcı ve hata mesajı boş, isLoading false olmalı', () {
      expect(authProvider.isLoading, false);
      expect(authProvider.token, isNull);
      expect(authProvider.currentUser, isNull);
      expect(authProvider.errorMessage, isNull);
      expect(authProvider.isAuthenticated, false);
    });
  });

  group('AuthProvider - login (success)', () {
    test('başarılı login sonrası token/kullanıcı set edilmeli, hata olmamalı', () async {
      when(() => mockApiService.login(sicilNo: '1001', password: 'sifre123'))
          .thenAnswer((_) async => (token: 'sahte-token', user: testUser));

      final result = await authProvider.login('1001', 'sifre123');

      expect(result, true);
      expect(authProvider.isLoading, false);
      expect(authProvider.token, 'sahte-token');
      expect(authProvider.currentUser, testUser);
      expect(authProvider.errorMessage, isNull);
      expect(authProvider.isAuthenticated, true);
      expect(ApiService.authToken, 'sahte-token');
    });

    test('login isteği sırasında (await edilmeden önce) isLoading true olmalı', () {
      when(() => mockApiService.login(sicilNo: '1001', password: 'sifre123'))
          .thenAnswer((_) async => (token: 'sahte-token', user: testUser));

      final future = authProvider.login('1001', 'sifre123');
      expect(authProvider.isLoading, true);

      return future;
    });
  });

  group('AuthProvider - login (error)', () {
    test('başarısız login sonrası errorMessage set edilmeli, kullanıcı boş kalmalı', () async {
      when(() => mockApiService.login(sicilNo: '1001', password: 'yanlisSifre'))
          .thenThrow(ApiException('Sicil no veya şifre hatalı'));

      final result = await authProvider.login('1001', 'yanlisSifre');

      expect(result, false);
      expect(authProvider.isLoading, false);
      expect(authProvider.currentUser, isNull);
      expect(authProvider.isAuthenticated, false);
      expect(authProvider.errorMessage, 'Sicil no veya şifre hatalı');
    });
  });

  group('AuthProvider - notifyListeners', () {
    test('başarılı login sırasında en az 2 kez tetiklenmeli (loading=true, işlem bitince)', () async {
      when(() => mockApiService.login(sicilNo: any(named: 'sicilNo'), password: any(named: 'password')))
          .thenAnswer((_) async => (token: 'x', user: testUser));

      var notifyCount = 0;
      authProvider.addListener(() => notifyCount++);

      await authProvider.login('1001', 'sifre123');

      expect(notifyCount, greaterThanOrEqualTo(2));
    });
  });
}
