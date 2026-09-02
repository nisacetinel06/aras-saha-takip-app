import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:arassaha_flutter/main.dart' as app;
import 'package:arassaha_flutter/models/work_order.dart';
import 'package:arassaha_flutter/widgets/work_order_card.dart';

// Kritik akış E2E testi: Login -> İş Emri Listesi -> Seçim -> Durum
// Güncelleme -> UI + kalıcılık doğrulaması. Bilinçli olarak TEK bir akışla
// sınırlı (bkz. görev kartı) — başka ekran/senaryo eklenmedi.
//
// GEREKSİNİMLER (çalıştırmadan önce):
// 1) Backend, bu teste özel AYRI bir SQLite dosyasıyla ('e2e_test.db',
//    Adım 2 — Seçenek B), gerçek dinleyen bir sunucu olarak ayakta olmalı:
//      cd arassaha-backend
//      DB_PATH=./e2e_test.db node seed.js     # deterministik veriyi sıfırdan yaz
//      DB_PATH=./e2e_test.db node server.js   # http://localhost:3000 dinler
//    (NODE_ENV=test KULLANILMAZ — o mod :memory: DB kullanır ve app.listen()
//    hiç çağrılmaz, bu yüzden gerçek bir Flutter uygulaması ona bağlanamaz;
//    bkz. database.js/server.js.) Backend'i durdurmadan seed.js'i TEKRAR
//    çalıştırma — SQLite dosyası sunucu tarafından açıkken kilitlenir.
// 2) Test, Flutter'ın Android emulator loopback adresine (10.0.2.2, backend
//    ana makinedeki localhost:3000'e karşılık gelir) karşı derlenmeli:
//      flutter test integration_test/critical_flow_test.dart \
//        --dart-define=API_HOST=http://10.0.2.2:3000 -d <device-id>
//    Gerçek cihaz + USB kullanıyorsan: `adb reverse tcp:3000 tcp:3000` çalıştırıp
//    --dart-define=API_HOST=http://localhost:3000 kullan.
//    --dart-define VERİLMEZSE varsayılan zaten localhost:3000'dir (bkz.
//    ApiService.host, backend artık yalnızca lokal çalışır) — Android
//    emülatörde `10.0.2.2:3000` gerekir, localhost emülatörün kendi içini
//    işaret eder.
// 3) seed.js her çalıştığında users/work_orders dahil TÜM tabloyu sıfırdan
//    yazdığı için (bkz. seed.js), teknisyen 1001 (Ahmet Yılmaz, şifre
//    "sifre123") HER SEED'DE garantili 3 'acik' iş emrine sahiptir. Bu test
//    her başarılı çalıştırmada BİR 'acik' emri 'yolda'ya taşıdığı (ve bu
//    kalıcı olduğu) için, DB'yi yeniden kullanmadan önce (3. çalıştırmadan
//    sonra artık 'acik' kalmaz) yeniden seed etmen gerekir.
const _sicilNo = '1001';
const _password = 'sifre123';
const _wrongPassword = 'yanlis-sifre-e2e-test';

// Test 2'de güncellenen iş emrinin id'si, Test 3'ün (restart + kalıcılık
// doğrulaması) hangi kaydı arayacağını bilmesi için burada taşınır. İki ayrı
// testWidgets kullanılmasının sebebi: flutter_test, testWidgets'lar ARASINDA
// tam bir teardown yapar (önceki MainShell'in dispose'u tamamlanır) — AYNI
// testWidgets içinde app.main()'i İKİNCİ KEZ çağırmak (bir "restart"
// simüle etmek için) önceki MainShell'in dispose sürecindeki asenkron işler
// (bkz. LocalNotificationService.requestPermission) ile YENİ MainShell'in
// başlangıcı arasında yarış durumu yaratıp sahte/ilgisiz test hatalarına yol
// açıyordu — testin KENDİ assertion'ları her zaman doğru geçmişti, hata
// yalnızca bu örtüşmeden kaynaklanıyordu.
late int _updatedWorkOrderId;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Kritik Akış: Login -> İş Emri -> Durum Güncelleme', () {
    testWidgets('başarısız login: yanlış şifreyle hata mesajı gösterilmeli', (
      tester,
    ) async {
      await app.main();
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('login_sicil_no_field')),
        _sicilNo,
      );
      await tester.enterText(
        find.byKey(const Key('login_password_field')),
        _wrongPassword,
      );
      await tester.tap(find.byKey(const Key('login_submit_button')));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.byKey(const Key('login_error_message')), findsOneWidget);
      // Yanlış yönlendirme olmamalı — hâlâ login ekranındayız.
      expect(find.byKey(const Key('login_submit_button')), findsOneWidget);
    });

    testWidgets(
      'login -> liste -> detay -> durum güncelleme -> UI anlık doğrulaması',
      (tester) async {
        await app.main();
        await tester.pumpAndSettle();

        // 1. LOGIN
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

        // AuthGate reaktif olarak MainShell'e geçmiş olmalı (login ekranı
        // artık ağaçta değil — bkz. main.dart AuthGate.build).
        expect(find.byKey(const Key('login_submit_button')), findsNothing);

        // 2. İŞ EMRİ LİSTESİNE GİT, "Açık" İLE FİLTRELE
        await tester.tap(find.text('İş Emirleri'));
        await tester.pumpAndSettle(const Duration(seconds: 3));

        await tester.tap(find.widgetWithText(ChoiceChip, 'Açık'));
        await tester.pumpAndSettle(const Duration(seconds: 3));

        expect(
          find.byType(WorkOrderCard),
          findsWidgets,
          reason:
              'sicil no 1001 (Ahmet Yılmaz) seed.js tarafından garantili en az '
              '1 "acik" iş emrine sahip olmalı (bkz. workOrderPlanByTechnicianIndex) '
              '— eğer bu test daha önce aynı DB üzerinde çalışıp hepsini "yolda"ya '
              'taşıdıysa, DB\'yi yeniden seed et (bkz. dosya başı not 3)',
        );

        // Başlıklar seed.js'te rastgele üretildiği için (bkz. seed.js) sabit
        // bir metin ARANMAZ — listedeki İLK kartın gerçek workOrder nesnesi
        // (id + status) doğrudan widget ağacından okunur.
        final firstCard = tester.widget<WorkOrderCard>(
          find.byType(WorkOrderCard).first,
        );
        _updatedWorkOrderId = firstCard.workOrder.id;
        expect(firstCard.workOrder.status, WorkOrderStatus.acik);

        // 3. İŞ EMRİ SEÇİMİ
        await tester.tap(
          find.byKey(Key('work_order_card_$_updatedWorkOrderId')),
        );
        await tester.pumpAndSettle(const Duration(seconds: 3));

        final statusBadge = find.byKey(const Key('current_status_badge'));
        expect(statusBadge, findsOneWidget);
        expect(
          find.descendant(of: statusBadge, matching: find.text('Açık')),
          findsOneWidget,
        );

        // 4. İŞ EMRİ DURUMUNUN GÜNCELLENMESİ (acik -> yolda)
        await tester.tap(find.byKey(const Key('status_update_button_yolda')));
        await tester.pumpAndSettle(const Duration(seconds: 5));

        // 5. GÜNCEL DURUMUN UI ÜZERİNDE ANLIK DOĞRULANMASI
        expect(
          find.descendant(of: statusBadge, matching: find.text('Yolda')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: statusBadge, matching: find.text('Açık')),
          findsNothing,
        );
        // Bir sonraki geçiş (yolda -> sahada) butonu artık görünür olmalı.
        expect(
          find.byKey(const Key('status_update_button_sahada')),
          findsOneWidget,
        );
        // Güncelleme çevrimdışı kuyruğa DEĞİL, gerçek bir API isteğiyle
        // gitmiş olmalı (bkz. WorkOrderDetailProvider.updateStatus —
        // ConnectivityProvider offline algılarsa OfflineQueueService'e
        // düşer ve bu rozet görünür; Test 3'teki kalıcılık kontrolü ancak
        // bu YOKSA anlamlıdır).
        expect(find.text('Senkronizasyon bekliyor'), findsNothing);

        // Durum güncellemesi bir SnackBar gösterir (varsayılan ~4 saniye
        // gerçek zaman — integration_test GERÇEK saat kullanır, sahte/
        // simüle zaman DEĞİL). Bu testWidgets burada bitip bir SONRAKİ test
        // kendi widget ağacını kurmaya başlarsa, SnackBar'ın henüz tamamlanmamış
        // kapanış animasyonu YENİ ağaçta "deactivated widget" hatasına yol
        // açar — bu yüzden SnackBar'ın tamamen kapanmasını burada, bu testin
        // içinde bekliyoruz.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'kalıcılık: uygulama yeniden başlatıldığında güncellenen durum backend\'den okunmalı',
      (tester) async {
        // Adım 4 — Gerçek Persistans Doğrulaması: bir UI hatası "iyimser
        // güncelleme" yapıp aslında hiçbir şey kaydetmemiş olabilir — bunu
        // ayırt etmenin tek yolu, TAZE bir uygulama örneğinin (bu testin
        // KENDİ app.main() çağrısı, önceki testin widget ağacından TAMAMEN
        // bağımsız) backend'den TEKRAR çektiği veriyi doğrulamak.
        await app.main();
        await tester.pumpAndSettle(const Duration(seconds: 5));

        // login()'de SharedPreferences'a yazılan token GERÇEKTEN diskte
        // kalıcı olduğu için (bu bir integration_test, mock SharedPreferences
        // DEĞİL), tryAutoLogin() bunu bulup GET /api/auth/me ile doğrular ve
        // AuthGate doğrudan MainShell'e döner — LoginScreen görünmemeli.
        expect(find.byKey(const Key('login_submit_button')), findsNothing);

        await tester.tap(find.text('İş Emirleri'));
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // Artık 'acik' değil, 'yolda' filtresiyle arıyoruz — kayıt HÂLÂ
        // burada görünüyorsa, güncelleme backend'e GERÇEKTEN yazılmış demektir.
        await tester.tap(find.widgetWithText(ChoiceChip, 'Yolda'));
        await tester.pumpAndSettle(const Duration(seconds: 3));

        expect(
          find.byKey(Key('work_order_card_$_updatedWorkOrderId')),
          findsOneWidget,
          reason:
              'durum güncellemesi backend\'e kalıcı yazılmamışsa (yalnızca '
              'geçici bir UI state\'iyse) restart sonrası bu kayıt "Yolda" '
              'filtresinde ARTIK görünmez',
        );

        // Detaya tekrar girip rozetin de kalıcı olarak "Yolda" gösterdiğini
        // doğrula (liste VE detay endpoint'i ikisi de tutarlı).
        await tester.tap(
          find.byKey(Key('work_order_card_$_updatedWorkOrderId')),
        );
        await tester.pumpAndSettle(const Duration(seconds: 3));

        expect(
          find.descendant(
            of: find.byKey(const Key('current_status_badge')),
            matching: find.text('Yolda'),
          ),
          findsOneWidget,
        );
      },
    );
  });
}
