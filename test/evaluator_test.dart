import 'package:confidence_openfeature_provider/src/evaluator.dart';
import 'package:confidence_openfeature_provider/src/snapshot.dart';
import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk.dart';
import 'package:test/test.dart';

void main() {
  late FlagEvaluator evaluator;
  late List<(String, String)> exposures;
  const context = {'visitor_id': 'visitor'};
  void activate({
    Object? value = const {
      'enabled': true,
      'count': 1,
      'ratio': 1.0,
      'nested': {
        'text': 'hello',
        'optional': null,
        'list': [1, 2],
      },
    },
    String reason = 'RESOLVE_REASON_MATCH',
    bool apply = true,
    String token = 'token',
  }) {
    evaluator.active = FlagSnapshot(
      context: context,
      resolveToken: token,
      flags: {
        'example': ResolvedFlag(
          name: 'example',
          value: value,
          reason: reason,
          variant: 'variant',
          shouldApply: apply,
        ),
      },
    );
    evaluator.ready = true;
  }

  setUp(() {
    exposures = [];
    evaluator = FlagEvaluator(
      onExposure: (token, flag) => exposures.add((token, flag)),
    );
  });

  test('distinguishes uninitialized from ready without assignments', () {
    expect(
      evaluator.evaluate('example', false, context).errorCode,
      ErrorCode.providerNotReady,
    );
    evaluator.ready = true;
    expect(
      evaluator.evaluate('example', false, context).errorCode,
      ErrorCode.flagNotFound,
    );
    expect(exposures, isEmpty);
  });

  test('typed nested reads are immediate and return metadata', () {
    activate();
    expect(evaluator.evaluate('example.enabled', false, context).value, isTrue);
    expect(evaluator.evaluate('example.count', 0, context).value, 1);
    expect(evaluator.evaluate('example.ratio', 0.0, context).value, 1.0);
    final result = evaluator.evaluate('example.nested.text', '', context);
    expect(result.value, 'hello');
    expect(result.variant, 'variant');
    expect(result.reason, 'TARGETING_MATCH');
    expect(result.errorCode, isNull);
    expect(
      result.flagMetadata['confidence.resolveReason'],
      'RESOLVE_REASON_MATCH',
    );
    expect(exposures, List.filled(4, ('token', 'example')));
  });

  test('structure read preserves nested lists and immutable maps', () {
    activate();
    final result = evaluator.evaluate<Map<String, Object?>>(
      'example.nested',
      {},
      context,
    );
    expect(result.value['list'], [1, 2]);
    expect(() => result.value.clear(), throwsUnsupportedError);
  });

  test('integer and double reads are not interchangeable', () {
    activate();
    expect(
      evaluator.evaluate('example.count', 0.0, context).errorCode,
      ErrorCode.typeMismatch,
    );
    expect(
      evaluator.evaluate('example.ratio', 0, context).errorCode,
      ErrorCode.typeMismatch,
    );
    expect(exposures, isEmpty);
  });

  test('missing properties and invalid paths do not report exposure', () {
    activate();
    for (final key in [
      'unknown.enabled',
      'example.missing',
      'example.nested.list.0',
    ]) {
      expect(
        evaluator.evaluate(key, false, context).errorCode,
        ErrorCode.flagNotFound,
      );
    }
    for (final key in ['', '.example', 'example..enabled']) {
      expect(
        evaluator.evaluate(key, false, context).errorCode,
        ErrorCode.parseError,
      );
    }
    expect(exposures, isEmpty);
  });

  test('null leaf is an eligible backend-directed default', () {
    activate();
    final result = evaluator.evaluate(
      'example.nested.optional',
      'fallback',
      context,
    );
    expect(result.value, 'fallback');
    expect(result.errorCode, isNull);
    expect(result.reason, 'DEFAULT');
    expect(exposures, [('token', 'example')]);
  });

  test('backend default reasons succeed without property/type validation', () {
    for (final reason in [
      'RESOLVE_REASON_NO_SEGMENT_MATCH',
      'RESOLVE_REASON_NO_TREATMENT_MATCH',
      'RESOLVE_REASON_FLAG_ARCHIVED',
    ]) {
      activate(reason: reason, value: null);
      final result = evaluator.evaluate('example.enabled', true, context);
      expect(result.value, isTrue);
      expect(result.errorCode, isNull);
    }
    expect(exposures, hasLength(3));
  });

  test('backend errors and unknown reasons never report exposure', () {
    for (final reason in [
      'RESOLVE_REASON_ERROR',
      'RESOLVE_REASON_UNSPECIFIED',
      'RESOLVE_REASON_TARGETING_KEY_ERROR',
      'RESOLVE_REASON_UNRECOGNIZED_TARGETING_RULE',
      'FUTURE_REASON',
    ]) {
      activate(reason: reason);
      expect(
        evaluator.evaluate('example.enabled', false, context).errorCode,
        isNotNull,
      );
    }
    expect(exposures, isEmpty);
  });

  test('another identity is rejected even when snapshot is stale', () {
    activate();
    evaluator.stale = true;
    expect(
      evaluator.evaluate('example.enabled', false, {
        'visitor_id': 'other',
      }).errorCode,
      ErrorCode.invalidContext,
    );
    expect(exposures, isEmpty);
    expect(
      evaluator.evaluate('example.enabled', false, context).reason,
      'STALE',
    );
  });

  test('backend eligibility and token are required for exposure', () {
    activate(apply: false);
    expect(evaluator.evaluate('example.enabled', false, context).value, isTrue);
    activate(token: '');
    expect(evaluator.evaluate('example.enabled', false, context).value, isTrue);
    expect(exposures, isEmpty);
  });

  test(
    'context comparison handles nested structures and null versus missing',
    () {
      expect(
        sameValue(
          {
            'a': [1, null],
            'b': true,
          },
          {
            'b': true,
            'a': [1, null],
          },
        ),
        isTrue,
      );
      expect(sameValue({'a': null}, <String, Object?>{}), isFalse);
      expect(sameValue([1, 2], [2, 1]), isFalse);
    },
  );
}
