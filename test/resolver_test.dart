import 'dart:convert';
import 'dart:io';

import 'package:confidence_openfeature_provider/src/configuration.dart';
import 'package:confidence_openfeature_provider/src/resolver.dart';
import 'package:confidence_openfeature_provider/src/transport.dart';
import 'package:test/test.dart';

Map<String, Object?> response() => {
  'resolveToken': 'token',
  'resolvedFlags': [
    {
      'flag': 'flags/example',
      'variant': 'flags/example/variants/on',
      'reason': 'RESOLVE_REASON_MATCH',
      'shouldApply': true,
      'value': {
        'count': 7.0,
        'ratio': 1,
        'nested': {
          'items': [true, null],
        },
      },
      'flagSchema': {
        'schema': {
          'count': {'intSchema': <String, Object?>{}},
          'ratio': {'doubleSchema': <String, Object?>{}},
          'nested': {
            'structSchema': {
              'schema': {
                'items': {
                  'listSchema': {
                    'elementSchema': {'boolSchema': <String, Object?>{}},
                  },
                },
              },
            },
          },
        },
      },
    },
  ],
};

void main() {
  test(
    'nested context timestamps become UTC strings without changing numbers',
    () {
      expect(
        wireValue({
          'nested': [DateTime.utc(2024), 1, 1.5],
        }),
        {
          'nested': ['2024-01-01T00:00:00.000Z', 1, 1.5],
        },
      );
      expect(() => wireValue(double.nan), throwsFormatException);
    },
  );

  test('reported SDK version matches package version', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('version: $providerVersion\n'),
    );
  });

  test('request timeout is bounded and sanitized', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final transport = IoTransport(timeout: const Duration(milliseconds: 50));
    addTearDown(() async {
      transport.close();
      await server.close(force: true);
    });
    server.listen((request) {
      request.drain<void>();
    });
    await expectLater(
      transport.post(Uri.parse('http://127.0.0.1:${server.port}/secret'), {}),
      throwsA(isA<TransportException>()),
    );
  });
  test(
    'schema conversion preserves types, metadata and nested null defaults',
    () {
      final snapshot = decodeResolution(response(), {'visitor_id': 'visitor'});
      expect(snapshot.context, {'visitor_id': 'visitor'});
      expect(snapshot.resolveToken, 'token');
      final value = snapshot.flags['example']!.value as Map;
      expect(value['count'], isA<int>());
      expect(value['ratio'], isA<double>());
      expect(value['nested'], {
        'items': [true, null],
      });
      expect(snapshot.flags['example']!.shouldApply, isTrue);
    },
  );

  test('empty protobuf response and default-only flag are accepted', () {
    expect(decodeResolution(<String, Object?>{}, {}).flags, isEmpty);
    final snapshot = decodeResolution({
      'resolvedFlags': [
        {'flag': 'flags/default', 'reason': 'RESOLVE_REASON_NO_SEGMENT_MATCH'},
      ],
    }, {});
    expect(snapshot.flags['default']!.value, isNull);
    expect(snapshot.flags['default']!.shouldApply, isFalse);
  });

  test(
    'rejects fractional integers, wrong scalar types and missing schemas',
    () {
      for (final value in [7.5, '7', true, 1e30]) {
        final root = jsonDecode(jsonEncode(response())) as Map;
        root['resolvedFlags'][0]['value']['count'] = value;
        expect(() => decodeResolution(root, {}), throwsFormatException);
      }
      final root = jsonDecode(jsonEncode(response())) as Map;
      root['resolvedFlags'][0].remove('flagSchema');
      expect(() => decodeResolution(root, {}), throwsFormatException);
    },
  );

  for (final isIOS in [true, false]) {
    test(
      'HTTP bulk resolve sends credentials, SDK and apply=false (${isIOS ? 'iOS' : 'Android'})',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final resolver = ConfidenceResolver(
          ConfidenceConfiguration(
            apiKey: 'test-secret',
            resolveBaseUrl: Uri.parse('http://127.0.0.1:${server.port}/proxy'),
          ),
          isIOS: isIOS,
        );
        addTearDown(() async {
          resolver.close();
          await server.close(force: true);
        });
        final handled = server.first.then((request) async {
          expect(request.method, 'POST');
          expect(request.uri.path, '/proxy/v1/flags:resolve');
          final body =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          expect(body['apply'], isFalse);
          expect(body['flags'], isEmpty);
          expect(body['clientSecret'], 'test-secret');
          expect(body['evaluationContext'], {'targeting_key': 'user'});
          expect(body['sdk'], {
            'id': isIOS
                ? 'SDK_ID_FLUTTER_IOS_CONFIDENCE'
                : 'SDK_ID_FLUTTER_ANDROID_CONFIDENCE',
            'version': providerVersion,
          });
          request.response.write(jsonEncode(response()));
          await request.response.close();
        });
        expect(
          (await resolver.resolve({'targeting_key': 'user'})).flags,
          hasLength(1),
        );
        await handled;
      },
    );
  }

  test(
    'HTTP failures and invalid responses never expose response bodies',
    () async {
      for (final status in [200, 401, 429, 500]) {
        final resolver = ConfidenceResolver(
          ConfidenceConfiguration(apiKey: 'secret'),
          isIOS: false,
          transport: StubTransport(WireResponse(status, 'private-data')),
        );
        await expectLater(
          resolver.resolve({}),
          throwsA(
            isA<ResolveException>().having(
              (e) => e.toString(),
              'sanitized error',
              isNot(contains('private-data')),
            ),
          ),
        );
      }
    },
  );

  test('redirect is not followed with credentials', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final transport = IoTransport();
    addTearDown(() async {
      transport.close();
      await server.close(force: true);
    });
    var count = 0;
    server.listen((request) async {
      count++;
      await request.drain<void>();
      request.response.statusCode = 307;
      request.response.headers.set('location', '/redirect');
      await request.response.close();
    });
    final result = await transport.post(
      Uri.parse('http://127.0.0.1:${server.port}'),
      {'clientSecret': 'secret'},
    );
    expect(result.status, 307);
    expect(count, 1);
  });
}

final class StubTransport implements JsonTransport {
  StubTransport(this.response);
  final WireResponse response;
  @override
  Future<WireResponse> post(Uri uri, Map<String, Object?> body) async =>
      response;
  @override
  void close() {}
}
