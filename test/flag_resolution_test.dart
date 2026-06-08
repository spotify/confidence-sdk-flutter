import 'package:flutter_test/flutter_test.dart';
import 'package:confidence_flutter_sdk/src/confidence_value.dart';
import 'package:confidence_flutter_sdk/src/evaluation.dart';
import 'package:confidence_flutter_sdk/src/flag_resolution.dart';

void main() {
  late FlagResolution resolution;

  setUp(() {
    resolution = FlagResolution(
      flags: [
        ResolvedFlag(
          flag: 'my-flag',
          variant: 'flags/my-flag/variants/treatment',
          value: ConfidenceValue.structure({
            'color': ConfidenceValue.string('red'),
            'size': ConfidenceValue.integer(42),
            'enabled': ConfidenceValue.boolean(true),
            'rate': ConfidenceValue.double_(0.5),
            'nested': ConfidenceValue.structure({
              'deep': ConfidenceValue.string('found'),
              'level': ConfidenceValue.integer(3),
            }),
          }) as ConfidenceValueStructure,
          reason: ResolveReason.match,
          shouldApply: true,
        ),
        ResolvedFlag(
          flag: 'other-flag',
          variant: 'flags/other-flag/variants/control',
          value: ConfidenceValue.structure({
            'message': ConfidenceValue.string('hello'),
          }) as ConfidenceValueStructure,
          reason: ResolveReason.match,
          shouldApply: true,
        ),
        ResolvedFlag(
          flag: 'no-match-flag',
          variant: '',
          value: null,
          reason: ResolveReason.noSegmentMatch,
          shouldApply: false,
        ),
      ],
      resolveToken: 'test-token-123',
    );
  });

  group('dot-path evaluation', () {
    test('evaluates top-level string property', () {
      final eval = resolution.evaluate<String>('my-flag.color', 'default');
      expect(eval.value, equals('red'));
      expect(eval.variant, equals('flags/my-flag/variants/treatment'));
      expect(eval.reason, equals(ResolveReason.match));
    });

    test('evaluates top-level integer property', () {
      final eval = resolution.evaluate<int>('my-flag.size', 0);
      expect(eval.value, equals(42));
    });

    test('evaluates top-level boolean property', () {
      final eval = resolution.evaluate<bool>('my-flag.enabled', false);
      expect(eval.value, isTrue);
    });

    test('evaluates top-level double property', () {
      final eval = resolution.evaluate<double>('my-flag.rate', 0.0);
      expect(eval.value, equals(0.5));
    });

    test('evaluates nested property with dot notation', () {
      final eval = resolution.evaluate<String>('my-flag.nested.deep', 'default');
      expect(eval.value, equals('found'));
    });

    test('evaluates nested integer property', () {
      final eval = resolution.evaluate<int>('my-flag.nested.level', 0);
      expect(eval.value, equals(3));
    });

    test('returns default for non-existent flag', () {
      final eval = resolution.evaluate<String>('nonexistent.color', 'default');
      expect(eval.value, equals('default'));
      expect(eval.reason, equals(ResolveReason.error));
    });

    test('returns default for non-existent property', () {
      final eval = resolution.evaluate<String>(
        'my-flag.nonexistent',
        'default',
      );
      expect(eval.value, equals('default'));
      expect(eval.reason, equals(ResolveReason.error));
    });

    test('returns default for non-existent nested property', () {
      final eval = resolution.evaluate<String>(
        'my-flag.nested.nonexistent',
        'default',
      );
      expect(eval.value, equals('default'));
    });

    test('returns default on type mismatch', () {
      final eval = resolution.evaluate<int>('my-flag.color', 99);
      expect(eval.value, equals(99));
      expect(eval.reason, equals(ResolveReason.error));
    });

    test('evaluates flag with no segment match', () {
      final eval = resolution.evaluate<String>(
        'no-match-flag.something',
        'default',
      );
      expect(eval.value, equals('default'));
      expect(eval.reason, equals(ResolveReason.noSegmentMatch));
    });

    test('evaluates different flag', () {
      final eval = resolution.evaluate<String>(
        'other-flag.message',
        'default',
      );
      expect(eval.value, equals('hello'));
    });

    test('flag path with only flag name returns default', () {
      final eval = resolution.evaluate<String>('my-flag', 'default');
      expect(eval.value, equals('default'));
    });
  });

  group('JSON serialization', () {
    test('round-trips through JSON', () {
      final json = resolution.toJson();
      final restored = FlagResolution.fromJson(json);

      expect(restored.resolveToken, equals('test-token-123'));
      expect(restored.flags, hasLength(3));
      expect(restored.flags[0].flag, equals('my-flag'));
      expect(restored.flags[0].reason, equals(ResolveReason.match));
      expect(restored.flags[0].shouldApply, isTrue);
    });

    test('preserves flag values through JSON', () {
      final json = resolution.toJson();
      final restored = FlagResolution.fromJson(json);

      final eval = restored.evaluate<String>('my-flag.color', 'default');
      expect(eval.value, equals('red'));
    });

    test('preserves nested values through JSON', () {
      final json = resolution.toJson();
      final restored = FlagResolution.fromJson(json);

      final eval = restored.evaluate<String>(
        'my-flag.nested.deep',
        'default',
      );
      expect(eval.value, equals('found'));
    });
  });

  group('empty resolution', () {
    test('empty resolution returns defaults', () {
      final empty = FlagResolution(flags: [], resolveToken: '');
      final eval = empty.evaluate<String>('any-flag.prop', 'default');
      expect(eval.value, equals('default'));
      expect(eval.reason, equals(ResolveReason.error));
    });
  });
}
