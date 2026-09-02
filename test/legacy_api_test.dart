import 'dart:async';
import 'dart:convert';

import 'package:confidence_flutter_sdk/src/confidence.dart';
import 'package:confidence_flutter_sdk/src/legacy_api.dart';
import 'package:confidence_flutter_sdk/src/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _resolveResponse({
  String flag = 'hawkflag',
  Map<String, dynamic>? value = const {
    'message': 'watch the skies',
    'enabled': true,
    'metadata': {'episode': 4},
  },
}) {
  return {
    'resolvedFlags': [
      {
        'flag': 'flags/$flag',
        'variant': 'flags/$flag/variants/treatment',
        if (value != null) 'value': value,
        'reason': 'RESOLVE_REASON_MATCH',
        'shouldApply': false,
      },
    ],
    'resolveToken': 'token-abc',
  };
}

Confidence _buildConfidence(http.Client client, Storage storage) {
  return Confidence.builder(clientSecret: 'test-secret')
      .httpClient(client)
      .storage(storage)
      .build();
}

Future<void> _pumpPendingFetches() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('ConfidenceFlutterSdk legacy API', () {
    test('setup passes custom resolve base URL to confidence factory',
        () async {
      String? capturedResolveBaseUrl;
      final sdk = ConfidenceFlutterSdk(
        confidenceFactory: (_, {resolveBaseUrl}) async {
          capturedResolveBaseUrl = resolveBaseUrl;
          return _buildConfidence(
            MockClient(
              (_) async => http.Response(jsonEncode(_resolveResponse()), 200),
            ),
            MemoryStorage(),
          );
        },
      );

      await sdk.setup(
        'test-secret',
        LoggingLevel.WARN,
        'http://localhost:8090',
      );
      await sdk.fetchAndActivate();

      expect(capturedResolveBaseUrl, equals('http://localhost:8090'));
    });

    test('getObject returns whole flag object for a root flag key', () async {
      final sdk = ConfidenceFlutterSdk(
        confidenceFactory: (_, {resolveBaseUrl}) async => _buildConfidence(
          MockClient(
            (_) async => http.Response(jsonEncode(_resolveResponse()), 200),
          ),
          MemoryStorage(),
        ),
      );

      await sdk.setup('test-secret');
      expect(
        sdk.getObject('hawkflag', {'message': 'default'}),
        equals({'message': 'default'}),
      );

      await sdk.fetchAndActivate();

      expect(
        sdk.getObject('hawkflag', {'message': 'default'}),
        equals({
          'message': 'watch the skies',
          'enabled': true,
          'metadata': {'episode': 4},
        }),
      );
    });

    test('getObject returns nested object for a dotted object key', () async {
      final sdk = ConfidenceFlutterSdk(
        confidenceFactory: (_, {resolveBaseUrl}) async => _buildConfidence(
          MockClient(
            (_) async => http.Response(jsonEncode(_resolveResponse()), 200),
          ),
          MemoryStorage(),
        ),
      );

      await sdk.setup('test-secret');
      await sdk.fetchAndActivate();

      expect(
        sdk.getObject('hawkflag.metadata', {'episode': 0}),
        equals({'episode': 4}),
      );
      expect(
        sdk.getObject('hawkflag.message', {'message': 'default'}),
        equals({'message': 'default'}),
      );
    });

    test('getObject returns default when no flag value exists', () async {
      final sdk = ConfidenceFlutterSdk(
        confidenceFactory: (_, {resolveBaseUrl}) async => _buildConfidence(
          MockClient(
            (_) async => http.Response(
              jsonEncode(_resolveResponse(value: null)),
              200,
            ),
          ),
          MemoryStorage(),
        ),
      );

      await sdk.setup('test-secret');
      await sdk.fetchAndActivate();

      expect(
        sdk.getObject('hawkflag', {'message': 'default'}),
        equals({'message': 'default'}),
      );
      expect(
        sdk.getObject('missing', {'message': 'default'}),
        equals({'message': 'default'}),
      );
    });

    test('putContext refreshes flags after initialization', () async {
      final sdk = ConfidenceFlutterSdk(
        confidenceFactory: (_, {resolveBaseUrl}) async => _buildConfidence(
          MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final context = body['evaluationContext'] as Map<String, dynamic>;
            final message = context['user_id'] == 'new-user'
                ? 'new assignment'
                : 'old assignment';
            return http.Response(
              jsonEncode(_resolveResponse(value: {'message': message})),
              200,
            );
          }),
          MemoryStorage(),
        ),
      );

      await sdk.setup('test-secret');
      await sdk.fetchAndActivate();
      expect(sdk.getString('hawkflag.message', ''), equals('old assignment'));

      await sdk.putContext('user_id', 'new-user');

      expect(sdk.getString('hawkflag.message', ''), equals('new assignment'));
    });

    test('putAllContext refreshes flags once after initialization', () async {
      var resolveCalls = 0;
      final sdk = ConfidenceFlutterSdk(
        confidenceFactory: (_, {resolveBaseUrl}) async => _buildConfidence(
          MockClient((request) async {
            resolveCalls++;
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final context = body['evaluationContext'] as Map<String, dynamic>;
            final message =
                context['country'] == 'SE' && context['user_id'] == 'new-user'
                    ? 'new assignment'
                    : 'old assignment';
            return http.Response(
              jsonEncode(_resolveResponse(value: {'message': message})),
              200,
            );
          }),
          MemoryStorage(),
        ),
      );

      await sdk.setup('test-secret');
      await sdk.fetchAndActivate();
      expect(sdk.getString('hawkflag.message', ''), equals('old assignment'));

      await sdk.putAllContext({
        'country': 'SE',
        'user_id': 'new-user',
      });

      expect(resolveCalls, equals(2));
      expect(sdk.getString('hawkflag.message', ''), equals('new assignment'));
    });

    test('putAllContext queues context before initialization', () async {
      var factoryCalls = 0;
      var resolveCalls = 0;
      Map<String, dynamic>? resolvedContext;
      final sdk = ConfidenceFlutterSdk(
        confidenceFactory: (_, {resolveBaseUrl}) async {
          factoryCalls++;
          return _buildConfidence(
            MockClient((request) async {
              resolveCalls++;
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              resolvedContext =
                  body['evaluationContext'] as Map<String, dynamic>;
              return http.Response(jsonEncode(_resolveResponse()), 200);
            }),
            MemoryStorage(),
          );
        },
      );

      await sdk.setup('test-secret');
      await sdk.putContext('user_id', 'queued-user');
      await sdk.putAllContext({'country': 'SE'});

      expect(factoryCalls, equals(0));
      expect(resolveCalls, equals(0));

      await sdk.fetchAndActivate();

      expect(factoryCalls, equals(1));
      expect(resolveCalls, equals(1));
      expect(resolvedContext, containsPair('user_id', 'queued-user'));
      expect(resolvedContext, containsPair('country', 'SE'));
    });

    test('activateAndFetchAsync activates cached values across instances',
        () async {
      final storage = MemoryStorage();
      final secondFetchCompleter = Completer<void>();
      var resolveCalls = 0;

      ConfidenceFlutterSdk createSdk() {
        return ConfidenceFlutterSdk(
          confidenceFactory: (_, {resolveBaseUrl}) async => _buildConfidence(
            MockClient((_) async {
              resolveCalls++;
              if (resolveCalls == 2) {
                await secondFetchCompleter.future;
              }
              return http.Response(
                jsonEncode(
                  _resolveResponse(
                    value: {'message': 'resolved-$resolveCalls'},
                  ),
                ),
                200,
              );
            }),
            storage,
          ),
        );
      }

      final first = createSdk();
      await first.setup('test-secret');
      await first.fetchAndActivate();
      expect(first.getString('hawkflag.message', ''), equals('resolved-1'));

      final second = createSdk();
      await second.setup('test-secret');
      await second.activateAndFetchAsync();

      expect(second.getString('hawkflag.message', ''), equals('resolved-1'));

      secondFetchCompleter.complete();
      await _pumpPendingFetches();
      expect(resolveCalls, equals(2));
    });
  });
}
