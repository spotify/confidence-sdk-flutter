import 'dart:convert';
import 'dart:io';

import 'package:confidence_flutter_sdk/src/apply_client.dart';
import 'package:confidence_flutter_sdk/src/apply_manager.dart';
import 'package:confidence_flutter_sdk/src/confidence.dart';
import 'package:confidence_flutter_sdk/src/events_client.dart';
import 'package:confidence_flutter_sdk/src/native_storage_migration.dart';
import 'package:confidence_flutter_sdk/src/resolve_client.dart';
import 'package:confidence_flutter_sdk/src/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final format in NativeStorageFormat.values) {
    group(format.name, () {
      late MemoryStorage source;
      late MemoryStorage destination;
      late NativeStorageMigration migration;
      final flagsKey = format == NativeStorageFormat.ios
          ? 'confidence.flags.resolve'
          : 'confidence_flags_cache.json';
      final applyKey = format == NativeStorageFormat.ios
          ? 'confidence.flags.apply'
          : 'confidence_apply_cache.json';

      dynamic tagged(String type, dynamic value) =>
          format == NativeStorageFormat.ios
              ? {
                  type: {'_0': value}
                }
              : {type: value};
      Map<String, dynamic> flags() {
        final value = {
          'text': tagged('string', 'old'),
          'count': tagged('integer', 42),
          'ratio': tagged('double', 2),
          'enabled': tagged('boolean', true),
          'nested': tagged(
              format == NativeStorageFormat.ios ? 'structure' : 'map',
              {'double': tagged('double', 3)}),
          'items': tagged('list', [tagged('string', 'a'), tagged('double', 4)]),
          'nothing': format == NativeStorageFormat.ios ? {'null': {}} : {},
        };
        return {
          'context': {},
          'resolveToken': 'token',
          'flags': [
            {
              'flag': 'flag',
              'variant': 'variant',
              'shouldApply': false,
              (format == NativeStorageFormat.ios ? 'resolveReason' : 'reason'):
                  'RESOLVE_REASON_MATCH',
              'value': format == NativeStorageFormat.ios
                  ? tagged('structure', value)
                  : value
            },
            {
              'flag': 'unmatched',
              'variant': '',
              'shouldApply': false,
              (format == NativeStorageFormat.ios ? 'resolveReason' : 'reason'):
                  'RESOLVE_REASON_NO_SEGMENT_MATCH',
              if (format == NativeStorageFormat.android) 'value': {}
            },
          ]
        };
      }

      final originalTime = DateTime.utc(2026, 1, 2, 3, 4, 5, 123);
      Map<String, dynamic> applies() => format == NativeStorageFormat.ios
          ? {
              'resolveEvents': [
                {
                  'resolveToken': 'token',
                  'events': [
                    for (final state in ['created', 'sending', 'sent'])
                      {
                        'name': state,
                        'status': {state: {}},
                        'applyTime': originalTime
                                .difference(DateTime.utc(2001))
                                .inMicroseconds /
                            1000000
                      },
                  ]
                }
              ]
            }
          : {
              'token': {
                for (final state in ['created', 'sending', 'sent'])
                  state: {
                    'time': originalTime.toIso8601String(),
                    'eventStatus': state.toUpperCase()
                  }
              }
            };

      setUp(() async {
        source = MemoryStorage();
        destination = MemoryStorage();
        await source.write(flagsKey, jsonEncode(flags()));
        await source.write(applyKey, jsonEncode(applies()));
        migration = NativeStorageMigration(
            source: source, destination: destination, format: format);
      });

      test('offline activation preserves every cached value and numeric type',
          () async {
        await migration.migrate();
        final sdk = Confidence.builder(clientSecret: 'test')
            .storage(destination)
            .httpClient(MockClient((_) async => http.Response('{}', 503)))
            .build();
        expect(await sdk.isStorageEmpty(), false);
        await sdk.activate();
        expect(sdk.getValue('flag.text', ''), 'old');
        expect(sdk.getValue('flag.count', -1), 42);
        expect(sdk.getValue('flag.ratio', -1.0), 2.0);
        expect(sdk.getValue('flag.enabled', false), true);
        expect(sdk.getValue('flag.nested.double', -1.0), 3.0);
        final object = sdk.getValue<Map<String, dynamic>>('flag', {});
        expect(object['items'], ['a', 4.0]);
        expect(object['nothing'], null);
        expect(sdk.getValue('unmatched.text', 'default'), 'default');
      });

      test(
          'retries created/sending with original time and skips acknowledged sends',
          () async {
        await migration.migrate();
        final sent = <Map<String, dynamic>>[];
        var status = 503;
        ApplyManager manager() => ApplyManager(
            storage: destination,
            applyClient: ApplyClient(
              clientSecret: 'test',
              region: ConfidenceRegion.global,
              httpClient: MockClient((request) async {
                sent.add(jsonDecode(request.body) as Map<String, dynamic>);
                return http.Response('{}', status);
              }),
            ));
        await manager().restore();
        expect(sent.map((r) => r['flags'][0]['flag']),
            ['flags/created', 'flags/sending']);
        for (final request in sent) {
          expect(DateTime.parse(request['flags'][0]['applyTime'] as String),
              originalTime);
          expect(request['resolveToken'], 'token');
        }
        status = 200;
        await manager().restore();
        expect(sent, hasLength(4));
        // A restart and another migration must not resurrect consumed records.
        await migration.migrate();
        await manager().restore();
        await manager().apply('created', 'token');
        expect(sent, hasLength(4));
      });

      test(
          'buffered events survive failed uploads and retain time/context on retry',
          () async {
        final event = {
          (format == NativeStorageFormat.ios ? 'name' : 'eventDefinition'):
              'eventDefinitions/purchase',
          'eventTime': format == NativeStorageFormat.ios
              ? originalTime.difference(DateTime.utc(2001)).inMicroseconds /
                  1000000
              : originalTime.toIso8601String(),
          'payload': {
            'amount': tagged('double', 2),
            'context': tagged(
                format == NativeStorageFormat.ios ? 'structure' : 'map',
                {'visitor_id': tagged('string', 'original-visitor')}),
          },
        };
        final bytes = jsonEncode(event) +
            (format == NativeStorageFormat.ios ? '\n' : ',\n');
        await source.write('events', bytes);
        final migrator = NativeStorageMigration(
            source: source,
            destination: destination,
            format: format,
            eventSource: source,
            eventFiles: ['events']);
        await migrator.migrate();
        var status = 503;
        final requests = <Map<String, dynamic>>[];
        EventsClient client() => EventsClient(
            storage: destination,
            clientSecret: 'test',
            region: ConfidenceRegion.eu,
            httpClient: MockClient((request) async {
              requests.add(jsonDecode(request.body) as Map<String, dynamic>);
              return http.Response('{}', status);
            }));
        await client().restore();
        final persisted = await destination.read(EventsClient.legacyStorageKey);
        expect(jsonDecode(persisted!) as List, hasLength(1));
        status = 200;
        await client().restore();
        expect(requests, hasLength(2));
        expect(requests.first['events'], requests.last['events']);
        expect(
            DateTime.parse(requests.first['events'][0]['eventTime'] as String),
            originalTime);
        expect(requests.first['events'][0]['payload'], {
          'amount': 2.0,
          'context': {'visitor_id': 'original-visitor'}
        });
        await migrator.migrate();
        await client().restore();
        expect(requests, hasLength(2));
        expect(await source.read('events'), bytes);
      });

      test(
          'corrupt event files remain available for recovery without losing other files',
          () async {
        await source.write('events', '{partial');
        await NativeStorageMigration(
            source: source,
            destination: destination,
            format: format,
            eventSource: source,
            eventFiles: ['events']).migrate();
        expect(await source.read('events'), '{partial');
        expect(await destination.read(EventsClient.legacyStorageKey), null);
        expect(await destination.read('confidence.flags.resolve'), isNotNull);
      });

      test('new Dart data wins, including empty completed queues', () async {
        await destination.write('confidence.flags.resolve', 'newer');
        await destination.write(ApplyManager.storageKey, '{}');
        await migration.migrate();
        expect(await destination.read('confidence.flags.resolve'), 'newer');
        expect(await destination.read(ApplyManager.storageKey), '{}');
      });

      test('keeps native bytes and unrelated user files unchanged', () async {
        final beforeFlags = await source.read(flagsKey);
        final beforeApplies = await source.read(applyKey);
        await source.write('user-settings', 'do not touch');
        await destination.write('user-document', 'also keep');
        await migration.migrate();
        await migration.migrate();
        expect(await source.read(flagsKey), beforeFlags);
        expect(await source.read(applyKey), beforeApplies);
        expect(await source.read('user-settings'), 'do not touch');
        expect(await destination.read('user-document'), 'also keep');
      });

      for (final bad in ['', '{truncated', '[]', '{"unexpected":true}']) {
        test('malformed native files do not prevent startup: $bad', () async {
          await source.write(flagsKey, bad);
          await source.write(applyKey, bad);
          await migration.migrate();
          expect(await destination.read('confidence.flags.resolve'), null);
          expect(await source.read(flagsKey), bad);
          expect(await source.read(applyKey), bad);
        });
      }

      test('missing files are a clean install', () async {
        await source.delete(flagsKey);
        await source.delete(applyKey);
        await migration.migrate();
        expect(await destination.read('confidence.flags.resolve'), null);
        expect(await destination.read(ApplyManager.storageKey), null);
      });

      test('interrupted import resumes per file without overwriting newer data',
          () async {
        final faulty = _FailSecondWrite();
        final migrator = NativeStorageMigration(
            source: source, destination: faulty, format: format);
        await expectLater(
            migrator.migrate(), throwsA(isA<FileSystemException>()));
        expect(await faulty.read('confidence.flags.resolve'), isNotNull);
        expect(await faulty.read(ApplyManager.storageKey), null);
        await faulty.write(
            'confidence.flags.resolve', 'newer after interrupted import');
        await migrator.migrate();
        expect(await faulty.read('confidence.flags.resolve'),
            'newer after interrupted import');
        expect(await faulty.read(ApplyManager.storageKey), isNotNull);
      });
    });
  }

  test('a malformed Dart cache falls back and does not block background fetch',
      () async {
    final storage = MemoryStorage();
    await storage.write('confidence.flags.resolve', '{truncated');
    final sdk = Confidence.builder(clientSecret: 'test')
        .storage(storage)
        .httpClient(MockClient((_) async =>
            http.Response('{"resolvedFlags":[],"resolveToken":"new"}', 200)))
        .build();
    await sdk.activate();
    expect(await sdk.isStorageEmpty(), true);
    expect(sdk.getValue('flag.text', 'fallback'), 'fallback');
    await sdk.fetchAndActivate();
    expect(await sdk.isStorageEmpty(), false);
  });
}

class _FailSecondWrite extends MemoryStorage {
  int writes = 0;
  @override
  Future<void> write(String key, String data) {
    if (++writes == 2) throw const FileSystemException('interrupted migration');
    return super.write(key, data);
  }
}
