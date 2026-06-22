import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:confidence_flutter_sdk_example/main.dart';
import 'package:integration_test/integration_test.dart';

String _listTileText(Finder listTiles, int index) {
  return (find
              .descendant(
                  of: listTiles.at(index), matching: find.byType(Text))
              .evaluate()
              .first
              .widget as Text)
          .data
          ?.trim() ??
      "";
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Verify flag resolution', (WidgetTester tester) async {
    MyApp myApp = MyApp();
    await tester.pumpWidget(myApp);
    await myApp.initDone();

    String messageText = "";
    for (int i = 0; i < 30; i++) {
      await tester.pumpAndSettle();
      final listTiles = find.byType(ListTile);
      if (listTiles.evaluate().length == 2) {
        messageText = _listTileText(listTiles, 0);
        if (["Goodbye", "Welcome"].contains(messageText)) break;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }

    expect(["Goodbye", "Welcome"].contains(messageText), isTrue,
        reason: 'Expected "Goodbye" or "Welcome" but got "$messageText"');
  });
}
