import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:confidence_flutter_sdk_example/main.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Verify Platform version', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    MyApp myApp = MyApp();
    await tester.pumpWidget(myApp);
    await myApp.initDone();
    // expect a list item with text evaluation exist
    await tester.pumpAndSettle();
    final listTiles = find.byType(ListTile);
    expect(listTiles, findsNWidgets(2));

    final messageText = (find.descendant(of: listTiles.at(0), matching: find.byType(Text)).evaluate().first.widget as Text).data?.trim() ?? "";
    expect(["Goodbye", "Welcome"].contains(messageText), true);

    final objectText = (find.descendant(of: listTiles.at(1), matching: find.byType(Text)).evaluate().first.widget as Text).data?.trim() ?? "";
    expect(objectText.contains("enabled"), true);
    expect(objectText.contains("message"), true);
    expect(objectText.contains("color"), true);
});
}
