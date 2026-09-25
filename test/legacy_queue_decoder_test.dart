import 'dart:convert';
import 'dart:io';

import 'package:confidence_openfeature_provider/src/storage/legacy_decoder.dart';
import 'package:confidence_openfeature_provider/src/storage/legacy_queue.dart';
import 'package:test/test.dart';

void main() {
  final timestamp = DateTime.utc(2023, 11, 14, 22, 13, 20);
  for (final platform in LegacyPlatform.values) {
    final swift = platform == LegacyPlatform.swift;
    final decoder = LegacyDecoder(platform);
    String fixture(String name) =>
        File('test/fixtures/legacy/${platform.name}/$name').readAsStringSync();
    final apply = fixture('apply.json');
    final event = fixture(swift ? 'events.READY' : 'events.ready');
    final record = event.trim().replaceFirst(RegExp(r',$'), '');
    String frame(String record) => swift ? '\n$record' : '$record,\n';

    group(platform.name, () {
      test('reads native apply fixture with original status and timestamp', () {
        final entries = decoder.decodeApply(apply);
        expect(entries, hasLength(3));
        for (final entry in entries) {
          expect(entry.resolveToken, 'fixture-token');
          expect(entry.time, timestamp);
          expect(entry.flag, entry.status.name);
        }
        expect(
          entries.map((e) => e.status).toSet(),
          LegacyApplyStatus.values.toSet(),
        );
        expect(() => entries.clear(), throwsUnsupportedError);
      });

      test('accepts empty native apply cache', () {
        expect(
          decoder.decodeApply(swift ? '{"resolveEvents":[]}' : '{}'),
          isEmpty,
        );
      });

      test('same flag under different resolve tokens is retained', () {
        final root = jsonDecode(apply) as Map<String, dynamic>;
        if (swift) {
          final group = Map<String, dynamic>.from(
            root['resolveEvents'][0] as Map,
          );
          group['resolveToken'] = 'second-token';
          root['resolveEvents'].add(group);
        } else {
          root['second-token'] = root['fixture-token'];
        }
        expect(decoder.decodeApply(jsonEncode(root)), hasLength(6));
      });

      test('rejects malformed apply state without leaking payloads', () {
        for (final field
            in swift
                ? ['status', 'applyTime', 'name']
                : ['eventStatus', 'time']) {
          final root = jsonDecode(apply) as Map<String, dynamic>;
          final entry = swift
              ? root['resolveEvents'][0]['events'][0]
              : root['fixture-token']['created'];
          entry[field] = field == 'name' ? null : 'secret-invalid-value';
          expect(
            () => decoder.decodeApply(jsonEncode(root)),
            throwsA(
              isA<FormatException>()
                  .having(
                    (e) => e.message,
                    'message',
                    'Invalid legacy apply cache.',
                  )
                  .having((e) => e.source, 'source', isNull),
            ),
          );
        }
        expect(() => decoder.decodeApply('{"secret":'), throwsFormatException);
      });

      if (swift) {
        test('rejects ambiguous duplicate token/flag entries', () {
          final root = jsonDecode(apply) as Map<String, dynamic>;
          root['resolveEvents'].add(root['resolveEvents'][0]);
          expect(
            () => decoder.decodeApply(jsonEncode(root)),
            throwsFormatException,
          );
        });
      }

      for (final file in [
        swift ? 'events.READY' : 'events.ready',
        'events-unfinished',
      ]) {
        test(
          'reads native $file with original merged context and timestamp',
          () {
            final batch = decoder.decodeEvents(fixture(file));
            expect(batch.rejectedLines, isEmpty);
            final entry = batch.events.single;
            expect(entry.sourceLine, swift ? 2 : 1);
            expect(entry.name, 'checkout');
            expect(entry.time, timestamp);
            expect(entry.payload, {
              'visitor_id': 'fixture-visitor',
              'targeting_key': 'user-a',
              'enabled': true,
              'count': 7,
              'ratio': 0.5,
              'label': 'hello\nworld',
              'optional': null,
              'nested': {
                'items': [1, 2],
              },
              'timestamp': timestamp,
            });
            expect(entry.payload['count'], isA<int>());
            expect(entry.payload['ratio'], isA<double>());
            expect(() => entry.payload.clear(), throwsUnsupportedError);
            expect(() => batch.events.clear(), throwsUnsupportedError);
            expect(() => batch.rejectedLines.clear(), throwsUnsupportedError);
            final items = (entry.payload['nested'] as Map)['items'] as List;
            expect(() => items.clear(), throwsUnsupportedError);
          },
        );
      }

      test('keeps identical events separate with stable source positions', () {
        final source = '${frame(record)}${frame(record)}';
        final first = decoder.decodeEvents(source);
        final repeated = decoder.decodeEvents(source);
        expect(first.events, hasLength(2));
        expect(first.events.map((e) => e.sourceLine), swift ? [2, 3] : [1, 2]);
        expect(
          repeated.events.map((e) => e.sourceLine),
          first.events.map((e) => e.sourceLine),
        );
      });

      test('recovers good records around corruption and a truncated tail', () {
        final source =
            '${frame(record)}${frame('{"broken":')}${frame(record)}${frame('{"tail":')}';
        final batch = decoder.decodeEvents(source);
        expect(batch.events, hasLength(2));
        expect(batch.events.map((e) => e.sourceLine), swift ? [2, 4] : [1, 3]);
        expect(batch.rejectedLines, swift ? [3, 5] : [2, 4]);
      });

      test(
        'rejects malformed event fields without losing adjacent records',
        () {
          for (final field in [
            swift ? 'name' : 'eventDefinition',
            'eventTime',
            'payload',
          ]) {
            final invalid = jsonDecode(record) as Map<String, dynamic>;
            invalid[field] = null;
            final batch = decoder.decodeEvents(
              '${frame(jsonEncode(invalid))}${frame(record)}',
            );
            expect(batch.events, hasLength(1));
            expect(batch.rejectedLines, hasLength(1));
          }
        },
      );

      test('accepts complete final record without delimiter', () {
        expect(decoder.decodeEvents(record).events, hasLength(1));
      });

      test('empty files contain no work or diagnostics', () {
        final batch = decoder.decodeEvents('\n\n');
        expect(batch.events, isEmpty);
        expect(batch.rejectedLines, isEmpty);
      });
    });
  }
}
