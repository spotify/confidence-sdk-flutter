import 'package:confidence_openfeature_provider/src/calendar_conversion.dart';
import 'package:confidence_openfeature_provider/src/snapshot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('registered iOS helper converts nested legacy calendars', (
    tester,
  ) async {
    expect(
      await eventWireValue({
        'dates': [
          CalendarDate({'year': 2024, 'month': 2, 'day': 29}),
          CalendarDate({'year': 2024}),
        ],
      }),
      {
        'dates': ['2024-02-29', '2024-01-01'],
      },
    );
    await expectLater(
      eventWireValue(CalendarDate({'year': 'invalid'})),
      throwsFormatException,
    );
    // A malformed input does not poison the channel for the next request.
    expect(
      await eventWireValue(CalendarDate({'year': 2025, 'month': 1, 'day': 1})),
      '2025-01-01',
    );
  });
}
