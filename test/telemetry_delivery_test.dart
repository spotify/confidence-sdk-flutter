import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:confidence_openfeature_provider/src/configuration.dart';
import 'package:confidence_openfeature_provider/src/resolver.dart';
import 'package:confidence_openfeature_provider/src/storage/outbox.dart';
import 'package:confidence_openfeature_provider/src/storage/provider_storage.dart';
import 'package:confidence_openfeature_provider/src/telemetry_buffer.dart';
import 'package:confidence_openfeature_provider/src/telemetry_delivery.dart';
import 'package:confidence_openfeature_provider/src/transport.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late ProviderStorage storage;
  late RecordingTransport transport;
  late TelemetryBuffer buffer;
  late TelemetryDelivery delivery;
  final time = DateTime.utc(2024, 2, 29, 12);
  EventRecord event(String id) => EventRecord(
    id: id,
    name: 'checkout',
    time: time,
    payload: {
      'visitor_id': 'original-user',
      'date': time,
      'nested': {'value': 3},
    },
  );
  ApplyRecord apply(String flag, {String token = 'token'}) =>
      ApplyRecord(token: token, flag: flag, time: time);
  TelemetryDelivery createDelivery(
    ProviderStorage store,
    TelemetryBuffer queue,
  ) => TelemetryDelivery(
    store,
    queue,
    ConfidenceResolver(
      ConfidenceConfiguration(
        clientSecret: 'secret',
        region: ConfidenceRegion.eu,
        resolveBaseUrl: Uri.parse('https://proxy.test/base'),
      ),
      isIOS: true,
      transport: transport,
    ),
    now: () => time.add(const Duration(hours: 1)),
    onFailure: () {},
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('confidence-delivery-');
    storage = ProviderStorage(directory);
    transport = RecordingTransport();
    buffer = TelemetryBuffer(storage, Outbox(), onPersistenceError: () {});
    delivery = createDelivery(storage, buffer);
  });
  tearDown(() async {
    delivery.close();
    await buffer.persist();
    await directory.delete(recursive: true);
  });

  test(
    'wire requests preserve payload/time, regional events, override and SDK',
    () async {
      buffer.track(event('one'));
      buffer.apply(apply('feature'));
      final result = await delivery.flush();
      expect(result.acceptedRecords, 2);
      expect(result.pendingRecords, 0);
      expect(result.retryNeeded, isFalse);
      final exposure = transport.calls[0];
      expect(exposure.uri.toString(), 'https://proxy.test/base/v1/flags:apply');
      expect(exposure.body['resolveToken'], 'token');
      expect(exposure.body['flags'], [
        {'flag': 'flags/feature', 'applyTime': time.toIso8601String()},
      ]);
      final publish = transport.calls[1];
      expect(publish.uri.host, 'events.eu.confidence.dev');
      expect(publish.body['clientSecret'], 'secret');
      expect(publish.body['sdk'], {
        'id': 'SDK_ID_FLUTTER_IOS_CONFIDENCE',
        'version': providerVersion,
      });
      expect(
        publish.body['sendTime'],
        time.add(const Duration(hours: 1)).toIso8601String(),
      );
      expect(publish.body['events'], [
        {
          'eventDefinition': 'eventDefinitions/checkout',
          'eventTime': time.toIso8601String(),
          'payload': {
            'visitor_id': 'original-user',
            'date': time.toIso8601String(),
            'nested': {'value': 3},
          },
        },
      ]);
      expect((await storage.readOutbox()).apply.single.sent, isTrue);
      buffer.apply(apply('feature'));
      await delivery.flush();
      expect(transport.calls, hasLength(2));
    },
  );

  test(
    'batches ten events and twenty flags without mixing resolve tokens',
    () async {
      for (var i = 0; i < 23; i++) {
        buffer.track(event('$i'));
        buffer.apply(apply('$i'));
      }
      buffer.apply(apply('other', token: 'other'));
      await delivery.flush();
      final applies = transport.calls.where(
        (c) => c.uri.path.endsWith(':apply'),
      );
      expect(applies.map((c) => (c.body['flags']! as List<Object?>).length), [
        20,
        3,
        1,
      ]);
      final events = transport.calls.where(
        (c) => c.uri.path.endsWith(':publish'),
      );
      expect(events.map((c) => (c.body['events']! as List<Object?>).length), [
        10,
        10,
        3,
      ]);
    },
  );

  for (final status in [408, 429, 500, 503, 302]) {
    test('HTTP $status retains both queues for retry', () async {
      transport.response = WireResponse(status, '{}');
      buffer.track(event('one'));
      buffer.apply(apply('feature'));
      final result = await delivery.flush();
      expect(result.pendingRecords, 2);
      expect(result.retryNeeded, isTrue);
      expect(result.droppedRecords, 0);
      transport.response = const WireResponse(200, '{}');
      expect((await delivery.flush()).acceptedRecords, 2);
    });
  }
  for (final status in [400, 401, 403, 404, 413]) {
    test('HTTP $status discards and counts permanent rejections', () async {
      transport.response = WireResponse(status, '{}');
      buffer.track(event('one'));
      buffer.apply(apply('feature'));
      final result = await delivery.flush();
      expect(result.droppedRecords, 2);
      expect(result.acceptedRecords, 0);
      expect(result.pendingRecords, 0);
      expect((await storage.readOutbox()).droppedRecords, 2);
    });
  }
  test('partial rejection counts rejected indices', () async {
    transport.response = WireResponse(
      200,
      jsonEncode({
        'errors': [
          {'index': 1, 'reason': 'EVENT_SCHEMA_VALIDATION_FAILED'},
        ],
      }),
    );
    buffer.track(event('one'));
    buffer.track(event('two'));
    final result = await delivery.flush();
    expect(result.acceptedRecords, 1);
    expect(result.droppedRecords, 1);
    expect(result.pendingRecords, 0);
  });
  test('malformed success and unknown rejection retain batch', () async {
    buffer.track(event('one'));
    for (final body in [
      'not json',
      '{"errors":[{"index":5}]}',
      '{"errors":[{"reason":"NEW_REASON"}]}',
    ]) {
      transport.response = WireResponse(200, body);
      expect((await delivery.flush()).pendingRecords, 1);
    }
  });
  test('concurrent enqueue survives acknowledgement', () async {
    final waiting = Completer<WireResponse>();
    transport.handler = (_) => waiting.future;
    buffer.track(event('one'));
    final flushing = delivery.flush();
    await until(() => transport.calls.isNotEmpty);
    buffer.track(event('two'));
    await buffer.persist();
    waiting.complete(const WireResponse(200, '{}'));
    await flushing;
    expect((await storage.readOutbox()).events.single.id, 'two');
  });
  test('ack failure retains work for restart and replay', () async {
    await buffer.persist();
    var failCommit = false;
    final failing = ProviderStorage(
      directory,
      commit: (file, data) async {
        if (failCommit) throw const FileSystemException('injected');
        await ProviderStorage.atomicWrite(file, data);
      },
    );
    final queue = TelemetryBuffer(failing, Outbox(), onPersistenceError: () {});
    final worker = createDelivery(failing, queue);
    addTearDown(worker.close);
    queue.track(event('one'));
    await queue.persist();
    transport.handler = (_) async {
      failCommit = true;
      return const WireResponse(200, '{}');
    };
    await expectLater(worker.flush(), throwsA(isA<FileSystemException>()));
    expect((await storage.readOutbox()).events.single.id, 'one');
    transport.handler = null;
    expect((await delivery.flush()).acceptedRecords, 1);
    expect(transport.calls, hasLength(2));
  });
  test('replacement workers serialize sends', () async {
    final waiting = Completer<WireResponse>();
    transport.handler = (_) => waiting.future;
    buffer.track(event('one'));
    final first = delivery.flush();
    await until(() => transport.calls.isNotEmpty);
    final otherBuffer = TelemetryBuffer(
      storage,
      await storage.readOutbox(),
      onPersistenceError: () {},
    );
    final other = createDelivery(storage, otherBuffer);
    addTearDown(other.close);
    final second = other.flush();
    waiting.complete(const WireResponse(200, '{}'));
    await Future.wait([first, second]);
    expect(transport.calls, hasLength(1));
  });
  test('close prevents acknowledgement of a late response', () async {
    final waiting = Completer<WireResponse>();
    transport.handler = (_) => waiting.future;
    buffer.track(event('one'));
    final flushing = delivery.flush();
    await until(() => transport.calls.isNotEmpty);
    delivery.close();
    waiting.complete(const WireResponse(200, '{}'));
    expect((await flushing).pendingRecords, 1);
  });
  test('scheduler delivers and retries without a caller flush', () async {
    final automatic = TelemetryDelivery(
      storage,
      buffer,
      ConfidenceResolver(
        ConfidenceConfiguration(clientSecret: 'test'),
        isIOS: false,
        transport: transport,
      ),
      interval: const Duration(milliseconds: 10),
      random: () => 0,
      onFailure: () {},
    );
    addTearDown(automatic.close);
    transport.response = const WireResponse(503, '{}');
    buffer.track(event('automatic'));
    automatic.start();
    await until(() => transport.calls.isNotEmpty);
    transport.response = const WireResponse(200, '{}');
    await until(() => transport.calls.length == 2);
    // Wait for the durable acknowledgement before inspecting it.
    await storage.serializeDelivery(() async {});
    automatic.close();
    expect((await storage.readOutbox()).events, isEmpty);
  });

  test('transport failure leaves records pending', () async {
    transport.handler = (_) => Future.error(const TransportException());
    buffer.track(event('one'));
    final result = await delivery.flush();
    expect(result.retryNeeded, isTrue);
    expect(result.pendingRecords, 1);
  });
}

Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('No delivery request.');
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

final class RecordingTransport implements JsonTransport {
  final calls = <({Uri uri, Map<String, Object?> body})>[];
  WireResponse response = const WireResponse(200, '{}');
  Future<WireResponse> Function(Map<String, Object?>)? handler;
  @override
  Future<WireResponse> post(Uri uri, Map<String, Object?> body) async {
    calls.add((uri: uri, body: body));
    return handler == null ? response : handler!(body);
  }

  @override
  void close() {}
}
