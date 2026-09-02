import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:arassaha_flutter/main.dart' as app;
import 'package:arassaha_flutter/services/api_service.dart';

// Access + Refresh Token Sistemi — GERÇEK cihaz + GERÇEK (yerel) backend
// üzerinde çalışan e2e kanıt testi (bkz. critical_flow_test.dart ile AYNI
// gereksinim deseni). Bu dosya, görev talimatının doğrudan isteği olan iki
// senaryoyu kanıtlar:
//   TEST 6: bir API isteği tam access_token süresi dolarken/dolduktan sonra
//           gönderilirse, kullanıcı HİÇBİR KESİNTİ görmeden (sessiz
//           refresh + otomatik tekrar deneme) devam edebilmeli.
//   TEST 7: refresh_token'ın KENDİSİ de geçersiz/iptal edilmişse, kullanıcı
//           GERÇEKTEN Login ekranına düşmeli.
//
// GEREKSİNİMLER (çalıştırmadan önce):
// 1) Backend'i, access_token ömrünü GERÇEK zamanda hızlıca test edilebilir
//    kılmak için ACCESS_TOKEN_EXPIRES_IN_OVERRIDE ile ayağa kaldır (bkz.
//    utils/authToken.js — bu değişken yalnızca YEREL testler içindir,
//    Railway'de HİÇ tanımlı değildir, production 15dk'da SABİT kalır):
//      cd arassaha-backend
//      node seed.js
//      ACCESS_TOKEN_EXPIRES_IN_OVERRIDE=8s node server.js
// 2) Gerçek cihaz + USB: `adb reverse tcp:3000 tcp:3000` çalıştırıp:
//      flutter test integration_test/refresh_token_flow_test.dart \
//        --dart-define=API_HOST=http://localhost:3000 -d <device-id>
//    --dart-define VERİLMEZSE varsayılan zaten localhost:3000'dir (bkz.
//    ApiService.host, backend artık yalnızca lokal çalışır) — Android
//    emülatörde `10.0.2.2:3000` gerekir, localhost emülatörün kendi içini
//    işaret eder.
const _sicilNo = '1001';
const _password = 'sifre123';

// Backend'in ACCESS_TOKEN_EXPIRES_IN_OVERRIDE=8s ile başlatıldığı varsayılır
// (bkz. dosya başı notu) — bu süreden FAZLA beklemek, test edilen isteğin
// GERÇEKTEN süresi dolmuş bir access_token ile gönderildiğini garanti eder.
const _accessTokenLifetime = Duration(seconds: 8);
const _safetyMargin = Duration(seconds: 3);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Access + Refresh Token Sistemi (gerçek cihaz + gerçek backend)', () {
    testWidgets(
      'TEST 6: access_token süresi dolmuşken gönderilen bir istek, kullanıcıya HİÇ '
      'fark ettirmeden sessizce yenilenir ve otomatik tekrar denenir (login ekranına düşmez)',
      (tester) async {
        await app.main();
        await tester.pumpAndSettle();
        // İlk soğuk başlatmada native splash kaldırma + ilk frame arasında
        // bazı cihazlarda ekstra bir gecikme olabiliyor (bkz. main.dart
        // FlutterNativeSplash.preserve) — bu, yalnızca bu dosyanın İLK
        // testWidgets'ı için ekstra bir güvenlik payı.
        await tester.pump(const Duration(milliseconds: 500));

        await tester.enterText(
          find.byKey(const Key('login_sicil_no_field')),
          _sicilNo,
        );
        await tester.enterText(
          find.byKey(const Key('login_password_field')),
          _password,
        );
        await tester.tap(find.byKey(const Key('login_submit_button')));
        await tester.pumpAndSettle(const Duration(seconds: 5));

        expect(
          find.byKey(const Key('login_submit_button')),
          findsNothing,
          reason: 'login başarılı olmalı, MainShell\'e geçilmeli',
        );
        expect(
          ApiService.authToken,
          isNotNull,
          reason: 'login sonrası bir access_token belleğe yüklenmiş olmalı',
        );
        expect(
          ApiService.refreshToken,
          isNotNull,
          reason: 'login sonrası bir refresh_token da belleğe yüklenmiş olmalı',
        );
        final accessTokenBeforeExpiry = ApiService.authToken;

        // access_token'ın GERÇEKTEN süresinin dolmasını bekle (bkz. dosya
        // başı notu — backend ACCESS_TOKEN_EXPIRES_IN_OVERRIDE=8s ile ayakta).
        await tester.pump(_accessTokenLifetime + _safetyMargin);

        // Artık kesinlikle süresi dolmuş bir access_token ile, GERÇEK
        // ApiService/_authenticated kod yolundan (production kodu BİREBİR
        // AYNI, UI'ye dokunmadan) kimlik doğrulama gerektiren bir istek
        // gönderiliyor. Bu isteğin HİÇ bir SessionExpiredException/hata
        // FIRLATMADAN tamamlanması, sessiz yenilemenin GERÇEKTEN çalıştığının
        // kanıtıdır — aksi halde bu satır bir exception ile patlardı.
        await ApiService().getWorkOrders();

        // KANIT 1: kullanıcı LoginScreen'e DÜŞMEDİ — sessiz yenileme
        // BAŞARILI olduğu için oturum kesintiye uğramadı.
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('login_submit_button')),
          findsNothing,
          reason:
              'sessiz yenileme (401 -> POST /refresh -> tekrar dene) başarısız '
              'olduysa kullanıcı burada Login ekranına düşerdi',
        );

        // KANIT 2: ApiService.authToken GERÇEKTEN YENİ bir değere değişti —
        // yani _authenticated/_refreshAccessToken GERÇEKTEN devreye girdi,
        // bu yalnızca "istek her nasılsa başka bir sebeple başarılı oldu"
        // DEĞİL, refresh mekanizmasının BİZZAT çalıştığının kanıtıdır.
        expect(
          ApiService.authToken,
          isNot(equals(accessTokenBeforeExpiry)),
          reason: 'sessiz yenileme GERÇEKTEN yeni bir access_token üretmiş olmalı',
        );
      },
    );

    testWidgets(
      'TEST 7: refresh_token backend tarafında (başka bir yerden) iptal edilmişse, '
      'sonraki bir istek kullanıcıyı GERÇEKTEN Login ekranına düşürür',
      (tester) async {
        await app.main();
        await tester.pumpAndSettle();

        // ÖNEMLİ: bu, AYNI test SÜRECİNDE (process) TEST 6'dan sonra
        // çalışıyor ve flutter_secure_storage GERÇEK Android Keystore'a
        // yazıyor (mock DEĞİL) — bu yüzden TEST 6'nın login sırasında
        // kalıcı depolamaya yazdığı access+refresh token çifti burada HÂLÂ
        // duruyor olabilir. `tryAutoLogin()` bunu bulup OTOMATİK giriş
        // yapmış olabilir (bu da GERÇEK bir kanıttır: kalıcı depolama
        // gerçekten çalışıyor) — bu durumda LoginScreen hiç görünmez ve
        // manuel login adımları ATLANIR. Aksi halde (örn. TEST 6'nın erişim
        // token'ı bu ara süresi dolduysa VE otomatik yenileme her nasılsa
        // devreye girmediyse) normal UI login akışı izlenir.
        final alreadyAuthenticated =
            find.byKey(const Key('login_submit_button')).evaluate().isEmpty;
        if (!alreadyAuthenticated) {
          await tester.enterText(
            find.byKey(const Key('login_sicil_no_field')),
            _sicilNo,
          );
          await tester.enterText(
            find.byKey(const Key('login_password_field')),
            _password,
          );
          await tester.tap(find.byKey(const Key('login_submit_button')));
          await tester.pumpAndSettle(const Duration(seconds: 5));
        }

        expect(find.byKey(const Key('login_submit_button')), findsNothing);
        final refreshTokenValue = ApiService.refreshToken;
        expect(refreshTokenValue, isNotNull);

        // Bu refresh_token'ı UYGULAMANIN DIŞINDAN, doğrudan backend'e
        // POST /api/auth/logout ile iptal ettiriyoruz — bu, "başka bir
        // cihazdan çıkış yapıldı" / "sunucu tarafında oturum sonlandırıldı"
        // (örn. yönetici hesabı pasifleştirdi, ya da rotasyon yeniden-kullanım
        // tespiti tüm oturumları iptal etti) senaryosunu GERÇEKÇİ biçimde simüle
        // eder — uygulamanın kendisi bunu HENÜZ bilmiyor.
        final revokeResponse = await http.post(
          Uri.parse('${ApiService.baseUrl}/auth/logout'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refresh_token': refreshTokenValue}),
        );
        expect(revokeResponse.statusCode, 200);

        // access_token'ın da GERÇEKTEN süresinin dolmasını bekle — aksi
        // halde uygulama /refresh'i hiç TETİKLEMEZ (access_token hâlâ
        // geçerliyken hiçbir istek 401 almaz), bu da iptal edilmiş
        // refresh_token'ın hiç sınanmamasına yol açardı.
        await tester.pump(_accessTokenLifetime + _safetyMargin);

        // GERÇEK ApiService/_authenticated kod yolundan (UI navigasyonuna
        // bağlı olmadan, doğrudan) kimlik doğrulama gerektiren bir istek —
        // bu, hem access_token'ın süresinin dolmuş olması HEM DE
        // refresh_token'ın backend'de iptal edilmiş olması nedeniyle
        // SessionExpiredException FIRLATMALI (bkz. api_service.dart
        // _authenticated dokümantasyonu).
        await expectLater(
          () => ApiService().getWorkOrders(),
          throwsA(isA<SessionExpiredException>()),
        );

        // onUnauthorized (-> AuthProvider.handleSessionExpired) çağrısı
        // SessionExpiredException fırlatılmadan HEMEN ÖNCE tetiklenir, AMA
        // `onUnauthorized` alanı `void Function()` tipinde olduğu için (bkz.
        // api_service.dart) handleSessionExpired'ın kendi İÇİNDEKİ
        // await'ler (SecureStorageService.clearAll + SharedPreferences —
        // GERÇEK platform kanalı çağrıları) burada BEKLENMEZ, arka planda
        // devam eder — notifyListeners() ancak bunlar bittikten SONRA
        // çağrılır. pumpAndSettle() yalnızca ZATEN PLANLANMIŞ frame'leri
        // bekler; henüz gelmemiş bu asenkron kuyruğu beklemez. Bu yüzden
        // önce GERÇEK bir kısa süre (platform kanalı round-trip'i için)
        // bekleniyor, ANCAK sonra pumpAndSettle ile ortaya çıkan
        // (notifyListeners -> AuthGate rebuild) frame'lerin tamamlanması
        // sağlanıyor.
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();

        // KANIT: ApiService.onUnauthorized -> AuthProvider.handleSessionExpired
        // tetiklendi, AuthGate kullanıcıyı GERÇEKTEN LoginScreen'e düşürdü.
        expect(
          find.byKey(const Key('login_submit_button')),
          findsOneWidget,
          reason: 'refresh_token iptal edilmişse kullanıcı Login ekranına düşmeli',
        );
        expect(ApiService.authToken, isNull);
        expect(ApiService.refreshToken, isNull);
      },
    );
  });
}
