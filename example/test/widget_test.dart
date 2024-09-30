import 'package:flutter/cupertino.dart';
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
    await tester.pump();
    final textWidgets = find.byType(Text);
    int count = 0;
    textWidgets.evaluate().forEach((element) {
      if(count == 0) {
        final textWidget = element.widget as Text;
        final string = textWidget.data?.trim() ?? "";
        expect(string, "1337");
      }
      if(count == 1) {
        final textWidget = element.widget as Text;
        final string = textWidget.data?.trim() ?? "";
        expect(string.contains("enabled"), true);
        expect(string.contains("message"), true);
        expect(string.contains("color"), true);
      }
      count++;
    });
});
}
