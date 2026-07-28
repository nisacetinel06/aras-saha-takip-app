import 'package:flutter_test/flutter_test.dart';

import 'package:arassaha_flutter/main.dart';
import 'package:arassaha_flutter/providers/theme_provider.dart';

void main() {
  testWidgets('ArasSahaApp açılır ve İş Emirleri başlığını gösterir', (WidgetTester tester) async {
    await tester.pumpWidget(ArasSahaApp(themeProvider: ThemeProvider()));
    await tester.pump();

    expect(find.text('İş Emirleri'), findsOneWidget);
  });
}
