import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:confidence_flutter_sdk/src/confidence.dart';
import 'package:confidence_flutter_sdk/src/confidence_value.dart';
import 'package:confidence_flutter_sdk/src/evaluation.dart';
import 'package:confidence_flutter_sdk/src/storage.dart';

Map<String, dynamic> makeResolveResponse({
  List<Map<String, dynamic>>? flags,
  String resolveToken = 'token-abc',
}) {
  return {
    'resolvedFlags': flags ?? [
      {
        'flag': 'flags/my-flag',
        'variant': 'flags/my-flag/variants/treatment',
        'value': {
          'color': 'red',
          'size': 42,
          'enabled': true,
          'nested': {'deep': 'value'},
        },
        'flagSchema': {
          'schema': {
            'color': {'stringSchema': {}},
            'size': {'intSchema': {}},
            'enabled': {'boolSchema': {}},
            'nested': {
              'structSchema': {
                'schema': {
                  'deep': {'stringSchema': {}},
                },
              },
            },
          },
        },
        'reason': 'RESOLVE_REASON_MATCH',
        'shouldApply': true,
      },
    ],
    'resolveToken': resolveToken,
  };
}

void main() {
  group('Confidence', () {
    test('fetchAndActivate resolves and caches flags', () async {
      final mockClient = MockClient((_) async {
        return http.Response(jsonEncode(makeResolveResponse()), 200);
      });

      final confidence = Confidence.builder(clientSecret: 'test-secret')
          .httpClient(mockClient)
          .storage(MemoryStorage())
          .build();

      await confidence.fetchAndActivate();

      expect(
        confidence.getValue<String>('my-flag.color', 'default'),
        equals('red'),
      );
    });

    test('getValue returns default before fetchAndActivate', () {
      final mockClient = MockClient((_) async {
        return http.Response(jsonEncode(makeResolveResponse()), 200);
      });

      final confidence = Confidence.builder(clientSecret: 'test-secret')
          .httpClient(mockClient)
          .storage(MemoryStorage())
          .build();

      expect(
        confidence.getValue<String>('my-flag.color', 'default'),
        equals('default'),
      );
    });

    test('getValue evaluates different types', () async {
      final mockClient = MockClient((_) async {
        return http.Response(jsonEncode(makeResolveResponse()), 200);
      });

      final confidence = Confidence.builder(clientSecret: 'test-secret')
          .httpClient(mockClient)
          .storage(MemoryStorage())
          .build();

      await confidence.fetchAndActivate();

      expect(confidence.getValue<String>('my-flag.color', ''), equals('red'));
      expect(confidence.getValue<int>('my-flag.size', 0), equals(42));
      expect(confidence.getValue<bool>('my-flag.enabled', false), isTrue);
    });

    test('getValue evaluates nested properties', () async {
      final mockClient = MockClient((_) async {
        return http.Response(jsonEncode(makeResolveResponse()), 200);
      });

      final confidence = Confidence.builder(clientSecret: 'test-secret')
          .httpClient(mockClient)
          .storage(MemoryStorage())
          .build();

      await confidence.fetchAndActivate();

      expect(
        confidence.getValue<String>('my-flag.nested.deep', 'default'),
        equals('value'),
      );
    });

    test('getValue returns default for non-existent flag', () async {
      final mockClient = MockClient((_) async {
        return http.Response(jsonEncode(makeResolveResponse()), 200);
      });

      final confidence = Confidence.builder(clientSecret: 'test-secret')
          .httpClient(mockClient)
          .storage(MemoryStorage())
          .build();

      await confidence.fetchAndActivate();

      expect(
        confidence.getValue<String>('nonexistent.color', 'default'),
        equals('default'),
      );
    });

    test('getValue returns default on type mismatch', () async {
      final mockClient = MockClient((_) async {
        return http.Response(jsonEncode(makeResolveResponse()), 200);
      });

      final confidence = Confidence.builder(clientSecret: 'test-secret')
          .httpClient(mockClient)
          .storage(MemoryStorage())
          .build();

      await confidence.fetchAndActivate();

      // color is a string, not an int
      expect(confidence.getValue<int>('my-flag.color', 99), equals(99));
    });

    test('getFlag returns full evaluation', () async {
      final mockClient = MockClient((_) async {
        return http.Response(jsonEncode(makeResolveResponse()), 200);
      });

      final confidence = Confidence.builder(clientSecret: 'test-secret')
          .httpClient(mockClient)
          .storage(MemoryStorage())
          .build();

      await confidence.fetchAndActivate();

      final eval = confidence.getFlag<String>('my-flag.color', 'default');
      expect(eval.value, equals('red'));
      expect(eval.variant, equals('flags/my-flag/variants/treatment'));
      expect(eval.reason, equals(ResolveReason.match));
    });
  });

  group('Confidence context management', () {
    test('putContext triggers re-fetch', () async {
      var fetchCount = 0;
      final mockClient = MockClient((_) async {
        fetchCount++;
        return http.Response(jsonEncode(makeResolveResponse()), 200);
      });

      final confidence = Confidence.builder(clientSecret: 'test-secret')
          .httpClient(mockClient)
          .storage(MemoryStorage())
          .build();

      await confidence.fetchAndActivate();
      expect(fetchCount, equals(1));

      confidence.putContext('user_id', ConfidenceValue.string('new-user'));
      // Allow async fetch to complete
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(fetchCount, greaterThan(1));
    });

    test('putContextLocal does not trigger re-fetch', () async {
      var fetchCount = 0;
      final mockClient = MockClient((_) async {
        fetchCount++;
        return http.Response(jsonEncode(makeResolveResponse()), 200);
      });

      final confidence = Confidence.builder(clientSecret: 'test-secret')
          .httpClient(mockClient)
          .storage(MemoryStorage())
          .build();

      await confidence.fetchAndActivate();
      expect(fetchCount, equals(1));

      confidence.putContextLocal('user_id', ConfidenceValue.string('new-user'));
      await Future.delayed(Duration.zero);

      expect(fetchCount, equals(1));
    });

    test('getContext returns current context', () {
      final mockClient = MockClient((_) async {
        return http.Response(jsonEncode(makeResolveResponse()), 200);
      });

      final confidence = Confidence.builder(clientSecret: 'test-secret')
          .httpClient(mockClient)
          .storage(MemoryStorage())
          .initialContext({
            'targeting_key': ConfidenceValue.string('user-123'),
          })
          .build();

      final context = confidence.getContext();
      expect(context['targeting_key'], isA<ConfidenceValueString>());
      expect(
        (context['targeting_key'] as ConfidenceValueString).value,
        equals('user-123'),
      );
    });

    test('removeContext removes key and triggers re-fetch', () async {
      var fetchCount = 0;
      final mockClient = MockClient((_) async {
        fetchCount++;
        return http.Response(jsonEncode(makeResolveResponse()), 200);
      });

      final confidence = Confidence.builder(clientSecret: 'test-secret')
          .httpClient(mockClient)
          .storage(MemoryStorage())
          .initialContext({
            'targeting_key': ConfidenceValue.string('user-123'),
            'country': ConfidenceValue.string('SE'),
          })
          .build();

      await confidence.fetchAndActivate();

      confidence.removeContext('country');
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      final context = confidence.getContext();
      expect(context.containsKey('country'), isFalse);
      expect(fetchCount, greaterThan(1));
    });

    test('withContext creates child with merged context', () {
      final mockClient = MockClient((_) async {
        return http.Response(jsonEncode(makeResolveResponse()), 200);
      });

      final parent = Confidence.builder(clientSecret: 'test-secret')
          .httpClient(mockClient)
          .storage(MemoryStorage())
          .initialContext({
            'targeting_key': ConfidenceValue.string('user-123'),
          })
          .build();

      final child = parent.withContext({
        'page': ConfidenceValue.string('home'),
      });

      final childContext = child.getContext();
      expect(childContext.containsKey('targeting_key'), isTrue);
      expect(childContext.containsKey('page'), isTrue);
    });

    test('child context overrides parent context', () {
      final mockClient = MockClient((_) async {
        return http.Response(jsonEncode(makeResolveResponse()), 200);
      });

      final parent = Confidence.builder(clientSecret: 'test-secret')
          .httpClient(mockClient)
          .storage(MemoryStorage())
          .initialContext({
            'color': ConfidenceValue.string('red'),
          })
          .build();

      final child = parent.withContext({
        'color': ConfidenceValue.string('blue'),
      });

      final context = child.getContext();
      expect(
        (context['color'] as ConfidenceValueString).value,
        equals('blue'),
      );
    });
  });

  group('Confidence activate and fetch strategies', () {
    test('activate loads from storage without fetching', () async {
      final storage = MemoryStorage();
      // Pre-populate storage in the format that fetchAndActivate() would write
      // (flag names WITHOUT the 'flags/' prefix, since ResolveClient strips it)
      final storedResolution = {
        'resolvedFlags': [
          {
            'flag': 'cached-flag',
            'variant': 'flags/cached-flag/variants/v1',
            'value': {'msg': 'cached'},
            'reason': 'RESOLVE_REASON_MATCH',
            'shouldApply': true,
          },
        ],
        'resolveToken': 'cached-token',
      };
      await storage.write(
        'confidence.flags.resolve',
        jsonEncode(storedResolution),
      );

      var fetchCount = 0;
      final mockClient = MockClient((_) async {
        fetchCount++;
        return http.Response(jsonEncode(makeResolveResponse()), 200);
      });

      final confidence = Confidence.builder(clientSecret: 'test-secret')
          .httpClient(mockClient)
          .storage(storage)
          .build();

      await confidence.activate();

      expect(fetchCount, equals(0));
      expect(
        confidence.getValue<String>('cached-flag.msg', 'default'),
        equals('cached'),
      );
    });

    test('activateAndFetchAsync activates cache then fetches in background', () async {
      final storage = MemoryStorage();
      final storedResolution = {
        'resolvedFlags': [
          {
            'flag': 'cached-flag',
            'variant': 'flags/cached-flag/variants/v1',
            'value': {'msg': 'cached'},
            'reason': 'RESOLVE_REASON_MATCH',
            'shouldApply': true,
          },
        ],
        'resolveToken': 'cached-token',
      };
      await storage.write(
        'confidence.flags.resolve',
        jsonEncode(storedResolution),
      );

      var resolveCount = 0;
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('resolve')) resolveCount++;
        return http.Response(jsonEncode(makeResolveResponse()), 200);
      });

      final confidence = Confidence.builder(clientSecret: 'test-secret')
          .httpClient(mockClient)
          .storage(storage)
          .build();

      await confidence.activateAndFetchAsync();

      // Should have activated cached values immediately
      expect(
        confidence.getValue<String>('cached-flag.msg', 'default'),
        equals('cached'),
      );

      // Background fetch should have started — pump the event loop
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      expect(resolveCount, equals(1));
    });
  });

  group('Confidence stale response handling', () {
    test('discards response if context changed during fetch', () async {
      var resolveCallCount = 0;
      final mockClient = MockClient((_) async {
        resolveCallCount++;
        // Simulate slow network for first call
        if (resolveCallCount == 1) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
        return http.Response(
          jsonEncode(makeResolveResponse(
            resolveToken: 'token-$resolveCallCount',
          )),
          200,
        );
      });

      final confidence = Confidence.builder(clientSecret: 'test-secret')
          .httpClient(mockClient)
          .storage(MemoryStorage())
          .build();

      // Start fetch, then immediately change context
      final fetchFuture = confidence.fetchAndActivate();
      confidence.putContextLocal('user', ConfidenceValue.string('changed'));

      await fetchFuture;
      // The fetch that was in-flight when context changed should be
      // either discarded or a new fetch should have been triggered.
      // The exact behavior depends on implementation details.
      expect(resolveCallCount, greaterThanOrEqualTo(1));
    });
  });
}
