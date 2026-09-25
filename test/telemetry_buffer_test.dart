import 'dart:io';

import 'package:confidence_openfeature_provider/src/storage/outbox.dart';
import 'package:confidence_openfeature_provider/src/storage/provider_storage.dart';
import 'package:confidence_openfeature_provider/src/telemetry_buffer.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late ProviderStorage storage;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('confidence-buffer-test-');
    storage = ProviderStorage(root);
  });
  tearDown(() => root.delete(recursive: true));
  EventRecord event(String id, int year) => EventRecord(
    id: id,
    name: 'event',
    time: DateTime.utc(year),
    payload: {'text': '🙂' * 100},
  );

  test('drop oldest across queues with real UTF-8 byte accounting', () async {
    final initial = Outbox(visitorId: 'visitor', importedSources: ['source']);
    await storage.updateOutbox((_) => initial);
    final buffer = TelemetryBuffer(
      storage,
      initial,
      maxBytes: 750,
      onPersistenceError: () {},
    );
    buffer.apply(
      ApplyRecord(token: 'token', flag: 'flag', time: DateTime.utc(2020)),
    );
    buffer.track(event('old', 2021));
    buffer.track(event('new', 2022));
    await buffer.persist();
    final box = await storage.readOutbox();
    expect(box.apply, isEmpty);
    expect(box.events.single.id, 'new');
    expect(box.droppedRecords, 2);
    expect(box.visitorId, 'visitor');
    expect(box.importedSources, {'source'});
    expect(
      await File('${root.path}/outbox.json').length(),
      lessThanOrEqualTo(750),
    );
    expect((await ProviderStorage(root).readOutbox()).droppedRecords, 2);
  });

  test(
    'repeated reads deduplicate across pending and durable apply work',
    () async {
      final applied = ApplyRecord(
        token: 'token',
        flag: 'flag',
        time: DateTime.utc(2020),
      );
      final buffer = TelemetryBuffer(
        storage,
        Outbox(),
        onPersistenceError: () {},
      );
      buffer.apply(applied);
      buffer.apply(applied);
      await buffer.persist();
      buffer.apply(applied);
      await buffer.persist();
      final restored = await storage.readOutbox();
      final restarted = TelemetryBuffer(
        storage,
        restored,
        onPersistenceError: () {},
      );
      restarted.apply(applied);
      await restarted.persist();
      expect((await storage.readOutbox()).apply, hasLength(1));
    },
  );

  test(
    'a failed commit retains enqueues for a later explicit persistence attempt',
    () async {
      var fail = true;
      final unreliable = ProviderStorage(
        root,
        commit: (file, contents) async {
          if (fail) throw const FileSystemException('Disk unavailable');
          await ProviderStorage.atomicWrite(file, contents);
        },
      );
      final buffer = TelemetryBuffer(
        unreliable,
        Outbox(),
        onPersistenceError: () {},
      );
      buffer.track(event('a', 2020));
      await expectLater(buffer.persist(), throwsA(isA<FileSystemException>()));
      fail = false;
      await buffer.persist();
      expect((await storage.readOutbox()).events.single.id, 'a');
    },
  );

  test('metadata is never silently evicted', () async {
    final initial = Outbox(visitorId: 'visitor', importedSources: ['x' * 2000]);
    await storage.updateOutbox((_) => initial);
    final buffer = TelemetryBuffer(
      storage,
      initial,
      maxBytes: 1000,
      onPersistenceError: () {},
    );
    buffer.track(event('a', 2020));
    await expectLater(buffer.persist(), throwsStateError);
    expect((await storage.readOutbox()).importedSources.single, 'x' * 2000);
  });

  test(
    'startup applies the cap to imported queues before new enqueues',
    () async {
      final initial = Outbox(events: [event('old', 2020), event('new', 2021)]);
      await storage.updateOutbox((_) => initial);
      final buffer = TelemetryBuffer(
        storage,
        initial,
        maxBytes: 750,
        onPersistenceError: () {},
      );
      await buffer.persist();
      expect((await storage.readOutbox()).events.single.id, 'new');
    },
  );

  test(
    'oversized new record is rejected without evicting smaller existing work',
    () async {
      final initial = Outbox(events: [event('old', 2020)]);
      await storage.updateOutbox((_) => initial);
      final buffer = TelemetryBuffer(
        storage,
        initial,
        maxBytes: 750,
        onPersistenceError: () {},
      );
      buffer.track(
        EventRecord(
          id: 'huge',
          name: 'event',
          time: DateTime.utc(2021),
          payload: {'text': 'x' * 1000},
        ),
      );
      await buffer.persist();
      final box = await storage.readOutbox();
      expect(box.events.single.id, 'old');
      expect(box.droppedRecords, 1);
    },
  );
}
