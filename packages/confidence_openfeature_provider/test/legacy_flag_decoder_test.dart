import 'dart:convert';
import 'dart:io';

import 'package:confidence_openfeature_provider/src/snapshot.dart';
import 'package:confidence_openfeature_provider/src/storage/legacy_flag_decoder.dart';
import 'package:test/test.dart';

void main() {
  for (final platform in LegacyPlatform.values) {
    final decoder = LegacyFlagDecoder(platform);
    final source = File(
      'test/fixtures/legacy/${platform.name}/flags.json',
    ).readAsStringSync();
    Map<String, dynamic> fixture() =>
        jsonDecode(source) as Map<String, dynamic>;
    Map<String, dynamic> tagged(String type, Object? value) => {
      type: platform == LegacyPlatform.swift ? {'_0': value} : value,
    };
    FlagSnapshot withValue(Object? value) {
      final root = fixture();
      root['context'] = {'test': value};
      return decoder.decode(jsonEncode(root));
    }

    group(platform.name, () {
      test('decodes native fixture without losing types or metadata', () {
        final snapshot = decoder.decode(source);
        expect(snapshot.context, {
          'visitor_id': 'fixture-visitor',
          'targeting_key': 'user-a',
        });
        expect(snapshot.resolveToken, 'fixture-token');
        final flag = snapshot.flags['example']!;
        expect(flag.name, 'example');
        expect(flag.variant, 'flags/example/variants/on');
        expect(flag.reason, 'RESOLVE_REASON_MATCH');
        expect(flag.shouldApply, isTrue);
        final value = flag.value as Map<String, Object?>;
        expect(value, {
          'enabled': true,
          'count': 7,
          'ratio': 0.5,
          'label': 'hello\nworld',
          'optional': null,
          'nested': {
            'items': [1, 2],
          },
          'timestamp': DateTime.utc(2023, 11, 14, 22, 13, 20),
        });
        expect(value['count'], isA<int>());
        expect(value['ratio'], isA<double>());
        expect(() => snapshot.flags.clear(), throwsUnsupportedError);
        expect(() => snapshot.context.clear(), throwsUnsupportedError);
        expect(() => value.clear(), throwsUnsupportedError);
        final nested = value['nested'] as Map<String, Object?>;
        expect(() => nested.clear(), throwsUnsupportedError);
        expect(() => (nested['items'] as List).clear(), throwsUnsupportedError);
      });

      test('keeps integral doubles distinct from integers', () {
        expect(withValue(tagged('double', 1)).context['test'], isA<double>());
      });

      test('retains false eligibility and unknown reasons', () {
        final root = fixture();
        root['flags'][0]['shouldApply'] = false;
        root['flags'][0][platform == LegacyPlatform.swift
                ? 'resolveReason'
                : 'reason'] =
            'FUTURE_REASON';
        final flag = decoder.decode(jsonEncode(root)).flags['example']!;
        expect(flag.shouldApply, isFalse);
        expect(flag.reason, 'FUTURE_REASON');
      });

      test('accepts empty snapshots', () {
        expect(
          decoder.decode('{"context":{},"flags":[],"resolveToken":""}').flags,
          isEmpty,
        );
      });

      test('rejects duplicate flags', () {
        final root = fixture();
        root['flags'].add(root['flags'][0]);
        expect(() => decoder.decode(jsonEncode(root)), throwsFormatException);
      });

      test('rejects malformed flag metadata', () {
        for (final entry in <String, Object?>{
          'flag': null,
          'variant': 7,
          'shouldApply': 'true',
          platform == LegacyPlatform.swift ? 'resolveReason' : 'reason': null,
          'value': platform == LegacyPlatform.swift ? 7 : null,
        }.entries) {
          final root = fixture();
          root['flags'][0][entry.key] = entry.value;
          expect(() => decoder.decode(jsonEncode(root)), throwsFormatException);
        }
      });

      test('rejects absent required snapshot fields', () {
        for (final field in ['flags', 'context', 'resolveToken']) {
          final root = fixture()..remove(field);
          expect(() => decoder.decode(jsonEncode(root)), throwsFormatException);
        }
      });

      test('rejects malformed typed values', () {
        for (final value in [
          null,
          7,
          <Object?>[],
          tagged('integer', 1.5),
          tagged('integer', '7'),
          tagged('boolean', 'true'),
          tagged('string', false),
          tagged('double', '1'),
          tagged('double', double.infinity.toString()),
          tagged('list', {}),
          tagged('unknown', 1),
          {...tagged('integer', 1), ...tagged('string', 'one')},
        ]) {
          expect(() => withValue(value), throwsFormatException);
        }
      });

      test('errors never include cache contents', () {
        for (final input in [
          '{"secret-token":',
          '{"context":"secret-token"}',
        ]) {
          try {
            decoder.decode(input);
            fail('Expected invalid cache');
          } on FormatException catch (error) {
            expect(error.message, 'Invalid legacy flag cache.');
            expect(error.source, isNull);
            expect(error.toString(), isNot(contains('secret-token')));
          }
        }
      });

      test('calendar dates remain distinct from timestamps', () {
        final value = platform == LegacyPlatform.swift
            ? {'year': 2024, 'month': 2, 'day': 29}
            : '2024-02-29';
        final date =
            withValue(tagged('date', value)).context['test'] as CalendarDate;
        expect(date.components, {'year': 2024, 'month': 2, 'day': 29});
        expect(() => date.components.clear(), throwsUnsupportedError);
      });

      if (platform == LegacyPlatform.swift) {
        test(
          'uses native optional fields and backward-compatible apply default',
          () {
            final root = fixture();
            root['flags'][0]
              ..remove('value')
              ..remove('variant')
              ..remove('shouldApply');
            final flag = decoder.decode(jsonEncode(root)).flags['example']!;
            expect(flag.value, isNull);
            expect(flag.variant, isNull);
            expect(flag.shouldApply, isTrue);
          },
        );
        test('converts fractional and pre-reference timestamps', () {
          expect(
            withValue(tagged('timestamp', -0.25)).context['test'],
            DateTime.utc(2000, 12, 31, 23, 59, 59, 750),
          );
          expect(
            () => withValue(tagged('timestamp', 1e300)),
            throwsFormatException,
          );
        });
        test('rejects malformed enum wrappers', () {
          for (final value in [
            {'integer': 1},
            {'integer': <String, Object?>{}},
            {
              'null': {'_0': null},
            },
            <String, Object?>{},
          ]) {
            expect(() => withValue(value), throwsFormatException);
          }
        });
      } else {
        test('missing value uses native empty map default', () {
          final root = fixture();
          root['flags'][0].remove('value');
          expect(
            decoder.decode(jsonEncode(root)).flags['example']!.value,
            isEmpty,
          );
        });
        test(
          'rejects invalid dates and timestamps rather than normalizing',
          () {
            for (final value in [
              tagged('date', '2024-02-30'),
              tagged('dateTime', '2024-01-01'),
              tagged('dateTime', '2024-01-01T25:00:00Z'),
            ]) {
              expect(() => withValue(value), throwsFormatException);
            }
          },
        );
      }
    });
  }

  test('snapshot defensively copies caller-owned containers', () {
    final values = <Object?>[1];
    final context = <String, Object?>{'items': values};
    final flag = ResolvedFlag(
      name: 'flag',
      value: context,
      reason: 'reason',
      variant: null,
      shouldApply: false,
    );
    final flags = {'flag': flag};
    final snapshot = FlagSnapshot(
      context: context,
      flags: flags,
      resolveToken: 'token',
    );
    values.clear();
    context.clear();
    flags.clear();
    expect(snapshot.context, {
      'items': [1],
    });
    expect(snapshot.flags['flag']!.value, {
      'items': [1],
    });
  });
}
