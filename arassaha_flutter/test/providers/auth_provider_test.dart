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
  late MockSecureStorageService mockSecureStorage;
  late AuthProvider authProvider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockApiService = MockApiService();
    mockSecureStorage = MockSecureStorageService();

    // Varsayılan (çoğu testin ihtiyaç duyduğu) davranış: güvenli depolamada
    // henüz kayıtlı bir token yok, yazma/silme çağrıları normal tamamlanır.
    // tryAutoLogin'e özel testler bunu kendi içinde override eder.
    when(() => mockSecureStorage.getToken()).thenAnswer((_) async => null);
    when(() => mockSecureStorage.saveToken(any())).thenAnswer((_) async {});
    when(() => mockSecureStorage.clearAll()).thenAnswer((_) async {});

    authProvider = AuthProvider(apiService: mockApiService, secureStorage: mockSecureStorage);
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
      // Token artık SharedPreferences DEĞİL, güvenli depolamaya yazılmalı.
      verify(() => mockSecureStorage.saveToken('sahte-token')).called(1);
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

  group('AuthProvider - tryAutoLogin (güvenli depolama)', () {
    test('güvenli depolamada token varken doğru kullanıcı geri yüklenmeli', () async {
      when(() => mockSecureStorage.getToken()).thenAnswer((_) async => 'guvenli-token');
      when(() => mockApiService.getMe('guvenli-token')).thenAnswer((_) async => testUser);

      await authProvider.tryAutoLogin();

      expect(authProvider.isAuthenticated, true);
      expect(authProvider.token, 'guvenli-token');
      expect(authProvider.currentUser, testUser);
      // Migration denenmemeli — güvenli depolamada zaten token vardı.
      verifyNever(() => mockSecureStorage.saveToken(any()));
    });

    test('hiçbir yerde token yoksa oturum açılmamalı (login ekranında kalınır)', () async {
      await authProvider.tryAutoLogin();

      expect(authProvider.isAuthenticated, false);
      expect(authProvider.isLoading, false);
      verifyNever(() => mockApiService.getMe(any()));
    });

    test(
      'MIGRATION: güvenli depolama boşken eski SharedPreferences\'ta token varsa, '
      'güvenli depolamaya taşınır ve eski anahtar silinir',
      () async {
        // Bu değişiklikten ÖNCEKİ bir sürümde giriş yapmış bir kullanıcıyı
        // simüle eder: token hâlâ eski (düz metin) SharedPreferences
        // anahtarında ('auth_token'), güvenli depolamada YOK.
        SharedPreferences.setMockInitialValues({'auth_token': 'eski-duz-metin-token'});
        when(() => mockApiService.getMe('eski-duz-metin-token')).thenAnswer((_) async => testUser);

        await authProvider.tryAutoLogin();

        expect(authProvider.isAuthenticated, true, reason: 'kullanıcı habersizce çıkış yaptırılmamalı');
        expect(authProvider.token, 'eski-duz-metin-token');

        // Token GERÇEKTEN güvenli depolamaya yazılmış olmalı...
        verify(() => mockSecureStorage.saveToken('eski-duz-metin-token')).called(1);

        // ...ve eski (güvensiz) konumdan SİLİNMİŞ olmalı.
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('auth_token'), isNull, reason: 'eski düz metin token artık diskte kalmamalı');
      },
    );
  });

  group('AuthProvider - logout', () {
    test('logout() güvenli depolamayı gerçekten temizlemeli (clearAll)', () async {
      when(() => mockApiService.login(sicilNo: any(named: 'sicilNo'), password: any(named: 'password')))
          .thenAnswer((_) async => (token: 'x', user: testUser));
      await authProvider.login('1001', 'sifre123');
      expect(authProvider.isAuthenticated, true);

      await authProvider.logout();

      expect(authProvider.isAuthenticated, false);
      expect(authProvider.token, isNull);
      expect(authProvider.currentUser, isNull);
      verify(() => mockSecureStorage.clearAll()).called(1);
    });
  });
}
