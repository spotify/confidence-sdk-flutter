import 'dart:convert';
import 'dart:io';

import 'package:confidence_openfeature_provider/src/snapshot.dart';
import 'package:confidence_openfeature_provider/src/storage/legacy_decoder.dart';
import 'package:confidence_openfeature_provider/src/storage/storage_codec.dart'
    as codec;
import 'package:test/test.dart';

void main() {
  for (final platform in LegacyPlatform.values) {
    test(
      '${platform.name} earliest tagged native format remains readable',
      () async {
        final path = 'test/fixtures/legacy/${platform.name}-old';
        final decoder = LegacyDecoder(platform);
        final flags = decoder.decodeFlags(
          await File('$path/flags.json').readAsString(),
        );
        expect(flags.flags['example']!.shouldApply, isTrue);
        expect(flags.context['visitor_id'], 'fixture-visitor');
        final apply = decoder.decodeApply(
          await File('$path/apply.json').readAsString(),
        );
        expect(apply, hasLength(3));
        for (final name in [
          'events-unfinished',
          platform == LegacyPlatform.swift ? 'events.READY' : 'events.ready',
        ]) {
          final batch = decoder.decodeEventBytes(
            await File('$path/$name').readAsBytes(),
          );
          expect(batch.rejectedLines, isEmpty);
          expect(batch.events.single.payload['targeting_key'], 'user-a');
        }
      },
    );
  }

  test(
    'Swift native calendar metadata survives migration without timezone projection',
    () async {
      final values = jsonDecode(
        await File(
          'test/fixtures/legacy/swift-old/calendar.json',
        ).readAsString(),
      );
      final snapshot = const LegacyDecoder(LegacyPlatform.swift).decodeFlags(
        jsonEncode({
          'context': values,
          'flags': <Object?>[],
          'resolveToken': '',
        }),
      );
      final restored = codec.decodeSnapshot(
        jsonDecode(jsonEncode(codec.encodeSnapshot(snapshot))),
      );
      final date = restored.context['leapDay'] as CalendarDate;
      expect(date.components['year'], 2024);
      expect(date.components['day'], 29);
      expect((date.components['timeZone'] as Map)['identifier'], 'GMT+0100');
      expect((date.components['calendar'] as Map)['identifier'], 'gregorian');
      expect((restored.context['partial'] as CalendarDate).components, {
        'year': 2024,
      });
      expect(
        restored.context['beforeEpoch'],
        DateTime.utc(2000, 12, 31, 23, 59, 59, 750),
      );
    },
  );
}
