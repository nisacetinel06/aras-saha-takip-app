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
///
/// Access + Refresh Token Sistemi (bkz. services/api_service.dart,
/// providers/auth_provider.dart): login/verifyTwoFactor artık TEK bir
/// `token` DEĞİL, `accessToken` + `refreshToken` çifti döner; bu dosyadaki
/// mock yanıtları bu yeni şekle göre güncellendi. Ayrıca tryAutoLogin'in
/// "access token süresi dolmuş ama refresh_token hâlâ geçerli -> sessiz
/// yenileme" ve "logout() sunucu tarafında GERÇEKTEN iptal eder" davranışları
/// için yeni testler eklendi.
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
    // henüz kayıtlı bir token/refresh_token yok, yazma/silme çağrıları
    // normal tamamlanır. tryAutoLogin/logout'a özel testler bunu kendi
    // içinde override eder.
    when(() => mockSecureStorage.getToken()).thenAnswer((_) async => null);
    when(() => mockSecureStorage.getRefreshToken()).thenAnswer((_) async => null);
    when(() => mockSecureStorage.saveToken(any())).thenAnswer((_) async {});
    when(() => mockSecureStorage.saveRefreshToken(any())).thenAnswer((_) async {});
    when(() => mockSecureStorage.clearAll()).thenAnswer((_) async {});
    when(() => mockApiService.logout(any())).thenAnswer((_) async {});

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
    test('başarılı login sonrası HEM access_token HEM refresh_token set edilmeli, hata olmamalı', () async {
      when(() => mockApiService.login(sicilNo: '1001', password: 'sifre123')).thenAnswer(
        (_) async => (
          accessToken: 'sahte-access-token',
          refreshToken: 'sahte-refresh-token',
          user: testUser,
          requiresTwoFactor: false,
          pendingToken: null,
        ),
      );

      final result = await authProvider.login('1001', 'sifre123');

      expect(result, true);
      expect(authProvider.isLoading, false);
      expect(authProvider.token, 'sahte-access-token');
      expect(authProvider.currentUser, testUser);
      expect(authProvider.errorMessage, isNull);
      expect(authProvider.isAuthenticated, true);
      expect(ApiService.authToken, 'sahte-access-token');
      expect(ApiService.refreshToken, 'sahte-refresh-token');
      // İkisi de KALICI (güvenli) depolamaya yazılmalı — yalnızca access
      // token DEĞİL, refresh_token da (bkz. SecureStorageService.saveRefreshToken).
      verify(() => mockSecureStorage.saveToken('sahte-access-token')).called(1);
      verify(() => mockSecureStorage.saveRefreshToken('sahte-refresh-token')).called(1);
    });

    test('login isteği sırasında (await edilmeden önce) isLoading true olmalı', () {
      when(() => mockApiService.login(sicilNo: '1001', password: 'sifre123')).thenAnswer(
        (_) async => (
          accessToken: 'sahte-access-token',
          refreshToken: 'sahte-refresh-token',
          user: testUser,
          requiresTwoFactor: false,
          pendingToken: null,
        ),
      );

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
      when(() => mockApiService.login(sicilNo: any(named: 'sicilNo'), password: any(named: 'password'))).thenAnswer(
        (_) async => (
          accessToken: 'x',
          refreshToken: 'y',
          user: testUser,
          requiresTwoFactor: false,
          pendingToken: null,
        ),
      );

      var notifyCount = 0;
      authProvider.addListener(() => notifyCount++);

      await authProvider.login('1001', 'sifre123');

      expect(notifyCount, greaterThanOrEqualTo(2));
    });
  });

  group('AuthProvider - login (2FA gerekli)', () {
    test('requiresTwoFactor:true dönerse: login() false döner ama errorMessage BOŞ kalır, requiresTwoFactor true olur', () async {
      when(() => mockApiService.login(sicilNo: '3001', password: 'sifre123')).thenAnswer(
        (_) async => (
          accessToken: null,
          refreshToken: null,
          user: null,
          requiresTwoFactor: true,
          pendingToken: 'ara-token',
        ),
      );

      final result = await authProvider.login('3001', 'sifre123');

      expect(result, false);
      expect(authProvider.requiresTwoFactor, true);
      expect(authProvider.errorMessage, isNull, reason: '2FA gerekmesi bir HATA değildir');
      expect(authProvider.isAuthenticated, false, reason: 'giriş HENÜZ tamamlanmadı');
    });

    test('verifyTwoFactor: doğru kod sonrası hem access hem refresh token/kullanıcı set edilir, isAuthenticated true olur', () async {
      when(() => mockApiService.login(sicilNo: '3001', password: 'sifre123')).thenAnswer(
        (_) async => (
          accessToken: null,
          refreshToken: null,
          user: null,
          requiresTwoFactor: true,
          pendingToken: 'ara-token',
        ),
      );
      await authProvider.login('3001', 'sifre123');

      when(() => mockApiService.verifyTwoFactor(pendingToken: 'ara-token', code: '123456')).thenAnswer(
        (_) async => (accessToken: 'tam-access-token', refreshToken: 'tam-refresh-token', user: testUser),
      );

      final result = await authProvider.verifyTwoFactor('123456');

      expect(result, true);
      expect(authProvider.isAuthenticated, true);
      expect(authProvider.token, 'tam-access-token');
      expect(ApiService.refreshToken, 'tam-refresh-token');
      expect(authProvider.requiresTwoFactor, false, reason: 'başarılı doğrulama sonrası bekleyen token temizlenmeli');
      verify(() => mockSecureStorage.saveToken('tam-access-token')).called(1);
      verify(() => mockSecureStorage.saveRefreshToken('tam-refresh-token')).called(1);
    });

    test('verifyTwoFactor: yanlış kod sonrası hata mesajı set edilir, isAuthenticated false kalır', () async {
      when(() => mockApiService.login(sicilNo: '3001', password: 'sifre123')).thenAnswer(
        (_) async => (
          accessToken: null,
          refreshToken: null,
          user: null,
          requiresTwoFactor: true,
          pendingToken: 'ara-token',
        ),
      );
      await authProvider.login('3001', 'sifre123');

      when(() => mockApiService.verifyTwoFactor(pendingToken: 'ara-token', code: '000000'))
          .thenThrow(ApiException('Geçersiz kod.'));

      final result = await authProvider.verifyTwoFactor('000000');

      expect(result, false);
      expect(authProvider.isAuthenticated, false);
      expect(authProvider.errorMessage, 'Geçersiz kod.');
    });

    test('cancelTwoFactor: bekleyen token temizlenir, requiresTwoFactor false olur', () async {
      when(() => mockApiService.login(sicilNo: '3001', password: 'sifre123')).thenAnswer(
        (_) async => (
          accessToken: null,
          refreshToken: null,
          user: null,
          requiresTwoFactor: true,
          pendingToken: 'ara-token',
        ),
      );
      await authProvider.login('3001', 'sifre123');
      expect(authProvider.requiresTwoFactor, true);

      authProvider.cancelTwoFactor();

      expect(authProvider.requiresTwoFactor, false);
    });
  });

  group('AuthProvider - tryAutoLogin (güvenli depolama)', () {
    test('güvenli depolamada geçerli bir access token varken doğru kullanıcı geri yüklenmeli', () async {
      when(() => mockSecureStorage.getToken()).thenAnswer((_) async => 'guvenli-token');
      when(() => mockApiService.getMe('guvenli-token')).thenAnswer((_) async => testUser);

      await authProvider.tryAutoLogin();

      expect(authProvider.isAuthenticated, true);
      expect(authProvider.token, 'guvenli-token');
      expect(authProvider.currentUser, testUser);
      // Migration denenmemeli — güvenli depolamada zaten token vardı.
      verifyNever(() => mockSecureStorage.saveToken(any()));
      // Access token hâlâ geçerli olduğu için refresh HİÇ denenmemeli.
      verifyNever(() => mockApiService.refresh(any()));
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

    test(
      '[TEST 3/6 — Access + Refresh Token] access token süresi dolmuş AMA refresh_token hâlâ geçerliyse: '
      'kullanıcıya HİÇ fark ettirmeden sessizce yenilenir, oturum GERİ YÜKLENİR',
      () async {
        when(() => mockSecureStorage.getToken()).thenAnswer((_) async => 'suresi-dolmus-token');
        when(() => mockSecureStorage.getRefreshToken()).thenAnswer((_) async => 'gecerli-refresh-token');
        when(() => mockApiService.getMe('suresi-dolmus-token'))
            .thenThrow(ApiException('Oturum geçersiz.'));
        when(() => mockApiService.refresh('gecerli-refresh-token')).thenAnswer(
          (_) async => (accessToken: 'yeni-access-token', refreshToken: 'yeni-refresh-token'),
        );
        when(() => mockApiService.getMe('yeni-access-token')).thenAnswer((_) async => testUser);

        await authProvider.tryAutoLogin();

        expect(authProvider.isAuthenticated, true, reason: 'sessiz yenileme başarılıysa oturum KESİNTİYE UĞRAMAMALI');
        expect(authProvider.token, 'yeni-access-token');
        expect(authProvider.currentUser, testUser);
        expect(ApiService.refreshToken, 'yeni-refresh-token');
        // YENİ çift GERÇEKTEN kalıcı depolamaya yazılmış olmalı — aksi
        // halde bir sonraki açılışta hâlâ artık iptal edilmiş (rotasyon)
        // eski refresh_token kullanılmaya çalışılırdı.
        verify(() => mockSecureStorage.saveToken('yeni-access-token')).called(1);
        verify(() => mockSecureStorage.saveRefreshToken('yeni-refresh-token')).called(1);
      },
    );

    test(
      '[TEST 7 — Access + Refresh Token] refresh_token DE geçersiz/süresi dolmuşsa: '
      'oturum GERÇEKTEN temizlenir, kullanıcı Login ekranına düşer',
      () async {
        when(() => mockSecureStorage.getToken()).thenAnswer((_) async => 'suresi-dolmus-token');
        when(() => mockSecureStorage.getRefreshToken()).thenAnswer((_) async => 'gecersiz-refresh-token');
        when(() => mockApiService.getMe('suresi-dolmus-token'))
            .thenThrow(ApiException('Oturum geçersiz.'));
        when(() => mockApiService.refresh('gecersiz-refresh-token'))
            .thenThrow(ApiException('Güvenlik ihlali tespit edildi, lütfen tekrar giriş yapın.'));

        await authProvider.tryAutoLogin();

        expect(authProvider.isAuthenticated, false, reason: 'refresh de başarısızsa oturum GERÇEKTEN bitmeli');
        expect(authProvider.token, isNull);
        expect(authProvider.currentUser, isNull);
        verify(() => mockSecureStorage.clearAll()).called(1);
      },
    );
  });

  group('AuthProvider - logout', () {
    test('logout() ÖNCE backend\'e POST /auth/logout ile refresh_token\'ı iptal ettirir, SONRA güvenli depolamayı temizler', () async {
      when(() => mockApiService.login(sicilNo: any(named: 'sicilNo'), password: any(named: 'password'))).thenAnswer(
        (_) async => (
          accessToken: 'x',
          refreshToken: 'aktif-refresh-token',
          user: testUser,
          requiresTwoFactor: false,
          pendingToken: null,
        ),
      );
      await authProvider.login('1001', 'sifre123');
      expect(authProvider.isAuthenticated, true);
      // login() sonrası getRefreshToken artık bu değeri döndürmeli ki
      // logout() onu backend'e gönderebilsin.
      when(() => mockSecureStorage.getRefreshToken()).thenAnswer((_) async => 'aktif-refresh-token');

      await authProvider.logout();

      // GERÇEK sunucu taraflı iptal — yalnızca yerel temizlik YETERSİZDİR
      // (bkz. "Güvenli Token Saklama" görevi notu).
      verify(() => mockApiService.logout('aktif-refresh-token')).called(1);
      expect(authProvider.isAuthenticated, false);
      expect(authProvider.token, isNull);
      expect(authProvider.currentUser, isNull);
      verify(() => mockSecureStorage.clearAll()).called(1);
    });

    test('logout(): kayıtlı bir refresh_token yoksa backend çağrısı YAPILMAZ, yerel temizlik yine de gerçekleşir', () async {
      // Varsayılan setUp zaten getRefreshToken() -> null döndürüyor.
      await authProvider.logout();

      verifyNever(() => mockApiService.logout(any()));
      expect(authProvider.isAuthenticated, false);
      verify(() => mockSecureStorage.clearAll()).called(1);
    });
  });

  group('AuthProvider - handleSessionExpired (global oturum-bitti mekanizması)', () {
    test('AuthProvider oluşturulurken ApiService.onUnauthorized MUTLAKA bir callback\'e bağlanır (boş kalmaz)', () {
      // ApiService._authenticated, bir istek 401 dönüp sessiz yenileme DE
      // başarısız olduğunda (bkz. api_service.dart SessionExpiredException
      // dokümantasyonu) bu callback'i tetikler — hangi provider'dan/hangi
      // ekrandan geldiği ÖNEMSİZDİR, TEK bir global mekanizma her zaman
      // bağlı olmalıdır.
      expect(ApiService.onUnauthorized, isNotNull);
    });

    test(
      'ApiService.onUnauthorized tetiklendiğinde (401 + başarısız sessiz yenileme, HERHANGİ bir '
      'ekrandaki bir istekten gelebilir), oturum GERÇEKTEN temizlenir',
      () async {
        when(() => mockApiService.login(sicilNo: any(named: 'sicilNo'), password: any(named: 'password'))).thenAnswer(
          (_) async => (
            accessToken: 'x',
            refreshToken: 'y',
            user: testUser,
            requiresTwoFactor: false,
            pendingToken: null,
          ),
        );
        await authProvider.login('1001', 'sifre123');
        expect(authProvider.isAuthenticated, true);

        // handleSessionExpired GERÇEKTEN budur: ApiService.onUnauthorized
        // (bkz. yukarıdaki test) bu metodu tetikler, biz burada onu
        // DOĞRUDAN çağırarak asıl etkiyi (oturumun GERÇEKTEN temizlendiğini)
        // deterministik biçimde kanıtlıyoruz.
        await authProvider.handleSessionExpired();

        expect(authProvider.isAuthenticated, false, reason: 'AuthGate bunu görüp kullanıcıyı Login ekranına düşürmeli');
        expect(authProvider.token, isNull);
        verify(() => mockSecureStorage.clearAll()).called(1);
      },
    );
  });
}
