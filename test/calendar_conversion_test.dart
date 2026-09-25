import 'dart:convert';
import 'dart:io';

import 'package:confidence_openfeature_provider/src/calendar_conversion.dart';
import 'package:confidence_openfeature_provider/src/configuration.dart';
import 'package:confidence_openfeature_provider/src/resolver.dart';
import 'package:confidence_openfeature_provider/src/snapshot.dart';
import 'package:confidence_openfeature_provider/src/storage/outbox.dart';
import 'package:confidence_openfeature_provider/src/storage/provider_storage.dart';
import 'package:confidence_openfeature_provider/src/telemetry_buffer.dart';
import 'package:confidence_openfeature_provider/src/telemetry_delivery.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'telemetry_delivery_test.dart' show RecordingTransport;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(
    'confidence_openfeature_provider/legacy_calendar',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('ordinary timestamps do not need a platform channel', () async {
    expect(await eventWireValue({'time': DateTime.utc(2024)}), {
      'time': '2024-01-01T00:00:00.000Z',
    });
  });

  test(
    'nested calendar metadata crosses unchanged in one batched call',
    () async {
      final components = <String, Object?>{
        'year': 2024,
        'month': 2,
        'day': 29,
        'timeZone': {'identifier': 'GMT+0100'},
      };
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls++;
        expect(call.method, 'convertDates');
        expect(
          (call.arguments as List<Object?>).map(
            (v) => jsonDecode(v! as String),
          ),
          [
            components,
            {'year': 2024},
          ],
        );
        return ['2024-02-28', '2024-01-01'];
      });
      expect(
        await eventWireValue({
          'dates': [
            CalendarDate(components),
            {
              'partial': CalendarDate({'year': 2024}),
            },
          ],
          'count': 7,
        }),
        {
          'dates': [
            '2024-02-28',
            {'partial': '2024-01-01'},
          ],
          'count': 7,
        },
      );
      expect(calls, 1);
    },
  );

  test('conversion failure is sanitized', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(
        code: 'invalid_calendar',
        message: 'private payload',
      );
    });
    await expectLater(
      eventWireValue(CalendarDate({'year': 2024})),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          isNot(contains('private')),
        ),
      ),
    );
  });

  test(
    'missing plugin and wrong result length fail without flattening dates',
    () async {
      final date = CalendarDate({'year': 2024});
      await expectLater(eventWireValue(date), throwsFormatException);
      messenger.setMockMethodCallHandler(channel, (_) async => <String>[]);
      await expectLater(eventWireValue(date), throwsFormatException);
    },
  );

  test(
    'failed conversion preserves event; retry delivers converted value and original timestamp',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'confidence-calendar-',
      );
      addTearDown(() => root.delete(recursive: true));
      final storage = ProviderStorage(root);
      final buffer = TelemetryBuffer(
        storage,
        Outbox(),
        onPersistenceError: () {},
      );
      final transport = RecordingTransport();
      final delivery = TelemetryDelivery(
        storage,
        buffer,
        ConfidenceResolver(
          ConfidenceConfiguration(clientSecret: 'test'),
          isIOS: true,
          transport: transport,
        ),
        onFailure: () {},
      );
      addTearDown(delivery.close);
      buffer.track(
        EventRecord(
          id: 'calendar',
          name: 'date-event',
          time: DateTime.utc(2023),
          payload: {
            'date': CalendarDate({'year': 2024}),
          },
        ),
      );
      buffer.track(
        EventRecord(
          id: 'ordinary',
          name: 'other-event',
          time: DateTime.utc(2023),
          payload: {'ok': true},
        ),
      );
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'failure'),
      );
      final failed = await delivery.flush();
      expect(failed.acceptedRecords, 1);
      expect(failed.pendingRecords, 1);
      expect(failed.droppedRecords, 0);
      final saved = (await storage.readOutbox()).events.single;
      expect((saved.payload['date']! as CalendarDate).components, {
        'year': 2024,
      });
      messenger.setMockMethodCallHandler(channel, (_) async => ['2024-01-01']);
      final retried = await delivery.flush();
      expect(retried.acceptedRecords, 1);
      expect(retried.pendingRecords, 0);
      expect(transport.calls.last.body['events'], [
        {
          'eventDefinition': 'eventDefinitions/date-event',
          'eventTime': '2023-01-01T00:00:00.000Z',
          'payload': {'date': '2024-01-01'},
        },
      ]);
    },
  );
}
