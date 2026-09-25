import 'dart:convert';
import 'dart:io';

import 'package:confidence_openfeature_provider/src/storage/legacy_decoder.dart';
import 'package:confidence_openfeature_provider/src/storage/legacy_migrator.dart';
import 'package:confidence_openfeature_provider/src/storage/provider_storage.dart';
import 'package:test/test.dart';

void main() {
  for (final platform in LegacyPlatform.values) {
    group(platform.name, () {
      late Directory root;
      late Directory events;
      late File flags;
      late File apply;
      late ProviderStorage storage;
      Future<LegacyMigrator> migrator({ProviderStorage? destination}) async =>
          LegacyMigrator(
            platform: platform,
            flags: flags,
            apply: apply,
            events: events,
            readVisitorId: () async => 'fixture-visitor',
            destination: destination ?? storage,
          );
      setUp(() async {
        root = await Directory.systemTemp.createTemp('confidence-import-test-');
        events = await Directory('${root.path}/events').create();
        flags = File('${root.path}/flags');
        apply = File('${root.path}/apply');
        storage = ProviderStorage(Directory('${root.path}/destination'));
        final source = 'test/fixtures/legacy/${platform.name}';
        await File('$source/flags.json').copy(flags.path);
        await File('$source/apply.json').copy(apply.path);
        await File(
          '$source/events-unfinished',
        ).copy('${events.path}/unfinished');
        await File(
          '$source/${platform == LegacyPlatform.swift ? 'events.READY' : 'events.ready'}',
        ).copy('${events.path}/sealed');
      });
      tearDown(() => root.delete(recursive: true));

      test(
        'imports all native stores offline and repeat runs add no work',
        () async {
          final importer = await migrator();
          final report = await importer.run();
          expect(report.importedEvents, 2);
          expect(report.importedApply, 3);
          final box = await storage.readOutbox();
          expect(box.visitorId, 'fixture-visitor');
          expect(box.events, hasLength(2));
          expect(box.events.map((e) => e.id).toSet(), hasLength(2));
          expect(box.apply.where((a) => !a.sent).map((a) => a.flag).toSet(), {
            'created',
            'sending',
          });
          expect(box.apply.singleWhere((a) => a.sent).flag, 'sent');
          expect((await storage.readSnapshot())!.resolveToken, 'fixture-token');
          expect(await flags.exists(), isFalse);
          expect(await apply.exists(), isFalse);
          expect(await events.list().isEmpty, isTrue);
          await importer.run();
          expect((await storage.readOutbox()).events, hasLength(2));
        },
      );

      test(
        'failure before queue commit retains sources and retry imports once',
        () async {
          var fail = true;
          final failing = ProviderStorage(
            storage.directory,
            commit: (file, contents) async {
              if (fail && contents.contains('checkout')) {
                fail = false;
                throw const FileSystemException('Interrupted import');
              }
              await ProviderStorage.atomicWrite(file, contents);
            },
          );
          final importer = await migrator(destination: failing);
          await expectLater(
            importer.run(),
            throwsA(isA<FileSystemException>()),
          );
          expect(await events.list().length, 2);
          await importer.run();
          expect((await storage.readOutbox()).events, hasLength(2));
        },
      );

      test(
        'restart after commit before cleanup does not duplicate acknowledged import',
        () async {
          var interrupt = true;
          final interrupted = ProviderStorage(
            storage.directory,
            commit: (file, contents) async {
              await ProviderStorage.atomicWrite(file, contents);
              if (interrupt && contents.contains('checkout')) {
                interrupt = false;
                throw const FileSystemException('Process stopped after rename');
              }
            },
          );
          await expectLater(
            (await migrator(destination: interrupted)).run(),
            throwsA(isA<FileSystemException>()),
          );
          expect((await storage.readOutbox()).events, hasLength(1));
          root = await root.rename('${root.path}-relocated');
          events = Directory('${root.path}/events');
          flags = File('${root.path}/flags');
          apply = File('${root.path}/apply');
          storage = ProviderStorage(Directory('${root.path}/destination'));
          await (await migrator()).run();
          expect((await storage.readOutbox()).events, hasLength(2));
        },
      );

      test(
        'corrupt caches and invalid UTF-8 do not erase valid event lines',
        () async {
          await flags.writeAsString('{');
          await apply.writeAsBytes([255]);
          final file = File('${events.path}/unfinished');
          final valid = await file.readAsBytes();
          await file.writeAsBytes([
            ...valid,
            10,
            255,
            10,
            ...valid,
            ...utf8.encode('\n{"truncated":'),
          ]);
          final report = await (await migrator()).run();
          expect(report.corruptCaches, 2);
          expect(report.rejectedEvents, 2);
          expect((await storage.readOutbox()).events, hasLength(3));
          expect(await storage.readSnapshot(), isNull);
        },
      );
    });
  }
}
