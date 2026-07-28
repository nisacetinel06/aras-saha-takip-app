import 'package:flutter_test/flutter_test.dart';

import 'package:arassaha_flutter/main.dart';

void main() {
  testWidgets('ArasSahaApp açılır ve İş Emirleri başlığını gösterir', (WidgetTester tester) async {
    await tester.pumpWidget(const ArasSahaApp());
    await tester.pump();

    expect(find.text('İş Emirleri'), findsOneWidget);
  });
}
