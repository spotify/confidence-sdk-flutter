import 'dart:io';

import 'package:confidence_openfeature_provider/src/snapshot.dart';
import 'package:confidence_openfeature_provider/src/storage/legacy_decoder.dart';
import 'package:confidence_openfeature_provider/src/storage/outbox.dart';
import 'package:confidence_openfeature_provider/src/storage/provider_storage.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late ProviderStorage storage;
  final time = DateTime.utc(2024);
  EventRecord event(String id) => EventRecord(
    id: id,
    name: 'checkout',
    time: time,
    payload: {
      'count': 1,
      'ratio': 1.0,
      'nested': [
        null,
        time,
        CalendarDate({'year': 2024, 'month': 1, 'day': 1}),
      ],
    },
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'confidence-storage-test-',
    );
    storage = ProviderStorage(directory);
  });
  tearDown(() => directory.delete(recursive: true));

  test('new storage has no assignments or pending work', () async {
    expect(await storage.readSnapshot(), isNull);
    expect((await storage.readOutbox()).events, isEmpty);
  });

  for (final platform in LegacyPlatform.values) {
    test(
      '${platform.name} snapshot survives storage restart with native types',
      () async {
        final snapshot = LegacyDecoder(platform).decodeFlags(
          await File(
            'test/fixtures/legacy/${platform.name}/flags.json',
          ).readAsString(),
        );
        await storage.writeSnapshot(snapshot);
        final read = (await ProviderStorage(directory).readSnapshot())!;
        expect(read.context, snapshot.context);
        expect(read.resolveToken, snapshot.resolveToken);
        final flag = read.flags['example']!;
        expect(flag.value, snapshot.flags['example']!.value);
        expect((flag.value as Map)['count'], isA<int>());
        expect((flag.value as Map)['ratio'], isA<double>());
        expect(flag.shouldApply, isTrue);
        expect(flag.reason, snapshot.flags['example']!.reason);
      },
    );
  }

  test(
    'outbox round trip retains metadata, sent dedupe and immutable values',
    () async {
      await storage.updateOutbox(
        (_) => Outbox(
          events: [event('a')],
          apply: [
            ApplyRecord(token: 'token', flag: 'flag', time: time, sent: true),
          ],
          visitorId: 'visitor',
          importedSources: ['source'],
        ),
      );
      final restored = await ProviderStorage(directory).readOutbox();
      expect(restored.visitorId, 'visitor');
      expect(restored.importedSources, {'source'});
      expect(restored.apply.single.sent, isTrue);
      expect(restored.apply.single.time, time);
      expect(restored.events.single.id, 'a');
      expect(restored.events.single.payload['ratio'], isA<double>());
      final nested = restored.events.single.payload['nested'] as List;
      expect(nested[1], time);
      expect((nested[2] as CalendarDate).components['year'], 2024);
      expect(() => nested.clear(), throwsUnsupportedError);
    },
  );

  test('concurrent updates retain every enqueue', () async {
    await Future.wait(
      List.generate(
        20,
        (i) => storage.updateOutbox(
          (box) => box.copyWith(events: [...box.events, event('$i')]),
        ),
      ),
    );
    expect(
      (await storage.readOutbox()).events.map((e) => e.id),
      List.generate(20, (i) => '$i'),
    );
  });

  test(
    'failed rename keeps committed work and does not poison later updates',
    () async {
      await storage.updateOutbox((_) => Outbox(events: [event('a')]));
      var fail = true;
      final interrupted = ProviderStorage(
        directory,
        commit: (file, contents) async {
          if (fail) {
            fail = false;
            await File('${file.path}.tmp').writeAsString(contents, flush: true);
            throw const FileSystemException(
              'Simulated interruption before rename',
            );
          }
          await ProviderStorage.atomicWrite(file, contents);
        },
      );
      await expectLater(
        interrupted.updateOutbox((_) => Outbox()),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        (await ProviderStorage(directory).readOutbox()).events.single.id,
        'a',
      );
      await interrupted.updateOutbox(
        (box) => box.copyWith(events: [...box.events, event('b')]),
      );
      expect((await storage.readOutbox()).events.map((e) => e.id), ['a', 'b']);
    },
  );

  test('rejects duplicate work without overwriting the last commit', () async {
    await storage.updateOutbox((_) => Outbox(events: [event('a')]));
    await expectLater(
      storage.updateOutbox((_) => Outbox(events: [event('a'), event('a')])),
      throwsFormatException,
    );
    expect((await storage.readOutbox()).events, hasLength(1));
  });

  test('corrupt snapshots are discarded without deleting the outbox', () async {
    await storage.updateOutbox((_) => Outbox(events: [event('a')]));
    final file = File('${directory.path}/snapshot.json');
    for (final bytes in [
      [123],
      [255, 254],
    ]) {
      await file.writeAsBytes(bytes);
      expect(await storage.readSnapshot(), isNull);
      expect(await file.exists(), isFalse);
      expect((await storage.readOutbox()).events, hasLength(1));
    }
  });

  test(
    'unsupported versions are retained and surfaced rather than erased',
    () async {
      final file = File('${directory.path}/outbox.json');
      await file.writeAsString('{"version":2,"data":{}}');
      await expectLater(storage.readOutbox(), throwsUnsupportedError);
      expect(await file.exists(), isTrue);
      await expectLater(
        storage.updateOutbox((_) => Outbox()),
        throwsUnsupportedError,
      );
    },
  );
}
