import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:confidence_flutter_sdk/src/confidence_value.dart';
import 'package:confidence_flutter_sdk/src/resolve_client.dart';
import 'package:confidence_flutter_sdk/src/flag_resolution.dart';
import 'package:confidence_flutter_sdk/src/evaluation.dart';

void main() {
  group('ResolveClient', () {
    const clientSecret = 'test-secret';

    Map<String, dynamic> makeResolveResponse({
      List<Map<String, dynamic>>? flags,
      String resolveToken = 'token-abc',
    }) {
      return {
        'resolvedFlags': flags ?? [
          {
            'flag': 'flags/my-flag',
            'variant': 'flags/my-flag/variants/treatment',
            'value': {'color': 'red', 'size': 42},
            'flagSchema': {
              'schema': {
                'color': {'stringSchema': {}},
                'size': {'intSchema': {}},
              },
            },
            'reason': 'RESOLVE_REASON_MATCH',
            'shouldApply': true,
          },
        ],
        'resolveToken': resolveToken,
      };
    }

    test('sends correct request format', () async {
      late http.Request capturedRequest;
      final mockClient = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode(makeResolveResponse()),
          200,
        );
      });

      final client = ResolveClient(
        httpClient: mockClient,
        clientSecret: clientSecret,
        region: ConfidenceRegion.global,
      );

      await client.resolve({
        'targeting_key': ConfidenceValue.string('user-123'),
        'country': ConfidenceValue.string('SE'),
      });

      expect(capturedRequest.method, equals('POST'));
      expect(
        capturedRequest.url.toString(),
        equals('https://resolver.confidence.dev/v1/flags:resolve'),
      );
      expect(
        capturedRequest.headers['Content-Type'],
        equals('application/json'),
      );

      final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(body['clientSecret'], equals(clientSecret));
      expect(body['apply'], isFalse);
      expect(body['evaluationContext'], isA<Map>());
      expect(body['sdk'], isA<Map>());
    });

    test('parses resolve response correctly', () async {
      final mockClient = MockClient((_) async {
        return http.Response(
          jsonEncode(makeResolveResponse()),
          200,
        );
      });

      final client = ResolveClient(
        httpClient: mockClient,
        clientSecret: clientSecret,
        region: ConfidenceRegion.global,
      );

      final resolution = await client.resolve({});

      expect(resolution.resolveToken, equals('token-abc'));
      expect(resolution.flags, hasLength(1));
      expect(resolution.flags[0].flag, equals('my-flag'));
      expect(
        resolution.flags[0].variant,
        equals('flags/my-flag/variants/treatment'),
      );
      expect(resolution.flags[0].reason, equals(ResolveReason.match));
      expect(resolution.flags[0].shouldApply, isTrue);
    });

    test('parses flag values from response', () async {
      final mockClient = MockClient((_) async {
        return http.Response(
          jsonEncode(makeResolveResponse()),
          200,
        );
      });

      final client = ResolveClient(
        httpClient: mockClient,
        clientSecret: clientSecret,
        region: ConfidenceRegion.global,
      );

      final resolution = await client.resolve({});
      final eval = resolution.evaluate<String>('my-flag.color', 'default');
      expect(eval.value, equals('red'));
    });

    test('uses EU region URL', () async {
      late Uri capturedUrl;
      final mockClient = MockClient((request) async {
        capturedUrl = request.url;
        return http.Response(
          jsonEncode(makeResolveResponse()),
          200,
        );
      });

      final client = ResolveClient(
        httpClient: mockClient,
        clientSecret: clientSecret,
        region: ConfidenceRegion.eu,
      );

      await client.resolve({});
      expect(
        capturedUrl.toString(),
        equals('https://resolver.eu.confidence.dev/v1/flags:resolve'),
      );
    });

    test('uses US region URL', () async {
      late Uri capturedUrl;
      final mockClient = MockClient((request) async {
        capturedUrl = request.url;
        return http.Response(
          jsonEncode(makeResolveResponse()),
          200,
        );
      });

      final client = ResolveClient(
        httpClient: mockClient,
        clientSecret: clientSecret,
        region: ConfidenceRegion.us,
      );

      await client.resolve({});
      expect(
        capturedUrl.toString(),
        equals('https://resolver.us.confidence.dev/v1/flags:resolve'),
      );
    });

    test('throws on HTTP 500 error', () async {
      final mockClient = MockClient((_) async {
        return http.Response('Internal Server Error', 500);
      });

      final client = ResolveClient(
        httpClient: mockClient,
        clientSecret: clientSecret,
        region: ConfidenceRegion.global,
      );

      expect(
        () => client.resolve({}),
        throwsException,
      );
    });

    test('throws on HTTP 404 error', () async {
      final mockClient = MockClient((_) async {
        return http.Response('Not Found', 404);
      });

      final client = ResolveClient(
        httpClient: mockClient,
        clientSecret: clientSecret,
        region: ConfidenceRegion.global,
      );

      expect(
        () => client.resolve({}),
        throwsException,
      );
    });

    test('handles response with multiple flags', () async {
      final mockClient = MockClient((_) async {
        return http.Response(
          jsonEncode(makeResolveResponse(
            flags: [
              {
                'flag': 'flags/flag-a',
                'variant': 'flags/flag-a/variants/v1',
                'value': {'key': 'value-a'},
                'flagSchema': {'schema': {'key': {'stringSchema': {}}}},
                'reason': 'RESOLVE_REASON_MATCH',
                'shouldApply': true,
              },
              {
                'flag': 'flags/flag-b',
                'variant': 'flags/flag-b/variants/v2',
                'value': {'key': 'value-b'},
                'flagSchema': {'schema': {'key': {'stringSchema': {}}}},
                'reason': 'RESOLVE_REASON_NO_SEGMENT_MATCH',
                'shouldApply': false,
              },
            ],
          )),
          200,
        );
      });

      final client = ResolveClient(
        httpClient: mockClient,
        clientSecret: clientSecret,
        region: ConfidenceRegion.global,
      );

      final resolution = await client.resolve({});
      expect(resolution.flags, hasLength(2));
      expect(resolution.flags[0].flag, equals('flag-a'));
      expect(resolution.flags[1].flag, equals('flag-b'));
      expect(
        resolution.flags[1].reason,
        equals(ResolveReason.noSegmentMatch),
      );
    });

    test('handles response with no segment match (null value)', () async {
      final mockClient = MockClient((_) async {
        return http.Response(
          jsonEncode(makeResolveResponse(
            flags: [
              {
                'flag': 'flags/my-flag',
                'variant': '',
                'value': null,
                'reason': 'RESOLVE_REASON_NO_SEGMENT_MATCH',
                'shouldApply': false,
              },
            ],
          )),
          200,
        );
      });

      final client = ResolveClient(
        httpClient: mockClient,
        clientSecret: clientSecret,
        region: ConfidenceRegion.global,
      );

      final resolution = await client.resolve({});
      expect(resolution.flags[0].value, isNull);
      expect(
        resolution.flags[0].reason,
        equals(ResolveReason.noSegmentMatch),
      );
    });

    test('sends context values in evaluation context', () async {
      late Map<String, dynamic> capturedBody;
      final mockClient = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode(makeResolveResponse()),
          200,
        );
      });

      final client = ResolveClient(
        httpClient: mockClient,
        clientSecret: clientSecret,
        region: ConfidenceRegion.global,
      );

      await client.resolve({
        'targeting_key': ConfidenceValue.string('user-abc'),
        'country': ConfidenceValue.string('SE'),
        'age': ConfidenceValue.integer(30),
      });

      final context =
          capturedBody['evaluationContext'] as Map<String, dynamic>;
      expect(context['targeting_key'], equals('user-abc'));
      expect(context['country'], equals('SE'));
      expect(context['age'], equals(30));
    });
  });
}
