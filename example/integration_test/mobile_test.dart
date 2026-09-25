import 'dart:io';

import 'package:confidence_openfeature_provider/src/calendar_conversion.dart';
import 'package:confidence_openfeature_provider/src/snapshot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:confidence_openfeature_provider_example/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('example starts without credentials', (tester) async {
    await app.main();
    await tester.pumpAndSettle();
    expect(
      find.text('Set CONFIDENCE_CLIENT_SECRET to run this example.'),
      findsOneWidget,
    );
  });
  testWidgets('iOS calendar helper is registered', (tester) async {
    expect(
      await eventWireValue(CalendarDate({'year': 2024, 'month': 2, 'day': 29})),
      '2024-02-29',
    );
  }, skip: !Platform.isIOS);
}
