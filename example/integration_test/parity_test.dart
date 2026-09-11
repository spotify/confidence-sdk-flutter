// This file deliberately uses only the API shared by the bridged and Dart SDKs.
// Run the exact same file on both revisions; see plans/native-dart-parity.md.
import 'dart:convert';
import 'dart:io';

import 'package:confidence_flutter_sdk/confidence_flutter_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late _Resolver resolver;
  late ConfidenceFlutterSdk sdk;

  setUp(() async {
    resolver = await _Resolver.start();
    sdk = ConfidenceFlutterSdk();
    await sdk.setup('parity-test-secret', LoggingLevel.ERROR, resolver.url);
    await sdk.putAllContext({'targeting_key': 'parity-user', 'country': 'SE'});
  });

  tearDown(() async => resolver.close());

  testWidgets('defaults before fetching', (_) async {
    expect(sdk.getString('missing.text', 'fallback'), 'fallback');
    expect(sdk.getBool('missing.enabled', false), false);
    expect(sdk.getInt('missing.count', -1), -1);
    expect(sdk.getDouble('missing.ratio', -1.0), -1.0);
    expect(sdk.getObject('missing', {'fallback': true}), {'fallback': true});
  });

  testWidgets('resolve request and primitive values', (_) async {
    await sdk.fetchAndActivate();
    expect(sdk.getString('parity.text', ''), 'hello parity-user');
    expect(sdk.getBool('parity.enabled', false), true);
    expect(sdk.getInt('parity.count', -1), 42);
    expect(sdk.getDouble('parity.ratio', -1.0), 1.25);
    final request = resolver.resolves.last;
    expect(request['clientSecret'], 'parity-test-secret');
    expect(request['apply'], false);
    expect(request['evaluationContext'], containsPair('country', 'SE'));
    expect(request['sdk'], contains('id'));
    expect(request['sdk'], contains('version'));
    expect(await sdk.isStorageEmpty(), false);
  });

  testWidgets('schema controls numeric types, including integral doubles',
      (_) async {
    await sdk.fetchAndActivate();
    expect(sdk.getDouble('parity.wholeDouble', -1.0), 2.0);
    expect(sdk.getInt('parity.jsonDoubleInt', -1), 7);
    expect(sdk.getDouble('parity.nested.wholeDouble', -1.0), 3.0);
  });

  testWidgets('root and nested objects preserve nulls', (_) async {
    await sdk.fetchAndActivate();
    final object = sdk.getObject('parity', {});
    expect(object['text'], 'hello parity-user');
    expect(object['nothing'], null);
    expect(sdk.getObject('parity.nested', {}),
        {'text': 'nested', 'wholeDouble': 3.0});
    expect(sdk.getString('parity.nested.text', ''), 'nested');
  });

  // Android SDK 0.6.9 cannot decode listSchema. Keep that existing platform
  // limitation separate from the common migration contract.
  testWidgets('list-valued flags preserve their elements', (_) async {
    resolver.includeList = true;
    await sdk.fetchAndActivate();
    expect(sdk.getObject('parity', {})['tags'], ['one', 'two']);
  }, skip: Platform.isAndroid);

  testWidgets('missing flag and property use caller defaults', (_) async {
    await sdk.fetchAndActivate();
    expect(sdk.getString('absent.text', 'fallback'), 'fallback');
    expect(sdk.getInt('parity.absent', -1), -1);
    expect(
        sdk.getObject('parity.absent', {'fallback': true}), {'fallback': true});
    expect(sdk.getString('unmatched.text', 'fallback'), 'fallback');
  });

  testWidgets('context changes refresh targeting and preserve typed data',
      (_) async {
    await sdk.fetchAndActivate();
    await sdk.putAllContext({
      'targeting_key': 'second-user',
      'boolean': true,
      'integer': 9,
      'double': 2.5,
      'nested': {
        'list': ['a', false, 3]
      },
    });
    expect(sdk.getString('parity.text', ''), 'hello second-user');
    final context = resolver.resolves.last['evaluationContext'] as Map;
    expect(context['country'], 'SE');
    expect(context['boolean'], true);
    expect(context['integer'], 9);
    expect(context['double'], 2.5);
    expect(context['nested'], {
      'list': ['a', false, 3]
    });
    await sdk.putContext('targeting_key', 'third-user');
    expect(sdk.getString('parity.text', ''), 'hello third-user');
  });

  testWidgets('unsupported legacy context values retain their string value',
      (_) async {
    final date = DateTime.utc(2026, 1, 2);
    await sdk.putAllContext({
      'date': date,
      'null': null,
      'nested': {'date': date},
    });
    await sdk.fetchAndActivate();
    final context = resolver.resolves.last['evaluationContext'] as Map;
    expect(context['date'], date.toString());
    expect(context['null'], 'null');
    expect(context['nested'], {'date': date.toString()});
  });

  testWidgets('repeated reads deduplicate a delivered exposure', (_) async {
    await sdk.fetchAndActivate();
    sdk.getString('parity.text', '');
    await _eventually(() => resolver.applied('parity').length == 1);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    for (var i = 0; i < 5; i++) {
      sdk.getString('parity.text', '');
      sdk.getBool('parity.enabled', false);
    }
    sdk.flush();
    await _eventually(() => resolver.applied('parity').isNotEmpty);
    // Allow a second native batch to expose delayed duplicates.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(resolver.applied('parity'), hasLength(1));
    final apply =
        resolver.applies.firstWhere((r) => r['resolveToken'] == resolver.token);
    expect(apply['clientSecret'], 'parity-test-secret');
    expect(apply['resolveToken'], resolver.token);
    expect(DateTime.tryParse(apply['sendTime'] as String), isNotNull);
    expect(
        DateTime.tryParse(
            resolver.applied('parity').single['applyTime'] as String),
        isNotNull);
  });

  testWidgets('object reads report exposure without a scalar read', (_) async {
    await sdk.fetchAndActivate();
    expect(sdk.getObject('parity', {}), isNotEmpty);
    sdk.flush();
    await _eventually(() => resolver.applied('parity').isNotEmpty);
    expect(resolver.applied('parity'), hasLength(1));
  });

  testWidgets('nested object reads report exposure', (_) async {
    await sdk.fetchAndActivate();
    expect(sdk.getObject('parity.nested', {}), isNotEmpty);
    sdk.flush();
    await _eventually(() => resolver.applied('parity').isNotEmpty);
    expect(resolver.applied('parity'), hasLength(1));
  });

  testWidgets('new resolve token allows another exposure', (_) async {
    await sdk.fetchAndActivate();
    sdk.getString('parity.text', '');
    sdk.flush();
    await _eventually(() => resolver.applied('parity').length == 1);
    await sdk.fetchAndActivate();
    sdk.getString('parity.text', '');
    sdk.flush();
    await _eventually(() => resolver.applied('parity').length == 2);
    expect(
        resolver.applies
            .where(resolver.ownsToken)
            .map((r) => r['resolveToken'])
            .toSet(),
        hasLength(2));
  });

  testWidgets('cached startup returns values while network is unavailable',
      (_) async {
    await sdk.fetchAndActivate();
    resolver.statusCode = 503;
    final restarted = ConfidenceFlutterSdk();
    await restarted.setup(
        'parity-test-secret', LoggingLevel.ERROR, resolver.url);
    await restarted.activateAndFetchAsync();
    expect(restarted.getString('parity.text', ''), 'hello parity-user');
    expect(restarted.getDouble('parity.wholeDouble', -1.0), 2.0);
    expect(await restarted.isStorageEmpty(), false);
  });

  testWidgets('cold fetchAndActivate falls back to disk when offline',
      (_) async {
    await sdk.fetchAndActivate();
    resolver.statusCode = 503;
    final restarted = ConfidenceFlutterSdk();
    await restarted.setup(
        'parity-test-secret', LoggingLevel.ERROR, resolver.url);
    await restarted.fetchAndActivate();
    expect(restarted.getString('parity.text', ''), 'hello parity-user');
    expect(restarted.getDouble('parity.wholeDouble', -1.0), 2.0);
  });

  testWidgets('failed refresh retains the last activated values', (_) async {
    await sdk.fetchAndActivate();
    resolver.statusCode = 503;
    // The legacy bridge contains native resolve errors instead of throwing.
    await sdk.fetchAndActivate();
    expect(sdk.getString('parity.text', ''), 'hello parity-user');
  });

  testWidgets('setup again uses the new resolver configuration', (_) async {
    await sdk.fetchAndActivate();
    final replacement = await _Resolver.start();
    try {
      await sdk.setup(
          'replacement-secret', LoggingLevel.ERROR, replacement.url);
      await sdk.putContext('targeting_key', 'replacement-user');
      await sdk.fetchAndActivate();
      expect(replacement.resolves, isNotEmpty);
      expect(replacement.resolves.last['clientSecret'], 'replacement-secret');
      expect(sdk.getString('parity.text', ''), 'hello replacement-user');
    } finally {
      await replacement.close();
    }
  });
}

Future<void> _eventually(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Expected request was not received within 10 seconds');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class _Resolver {
  final HttpServer server;
  final resolves = <Map<String, dynamic>>[];
  final applies = <Map<String, dynamic>>[];
  int statusCode = 200;
  bool includeList = false;
  bool _closing = false;
  String get url => 'http://127.0.0.1:${server.port}';
  String get token => 'token-${server.port}-${resolves.length}';

  _Resolver(this.server);

  static Future<_Resolver> start() async {
    final resolver =
        _Resolver(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    resolver.server.listen(resolver.handle);
    return resolver;
  }

  Future<void> close() async {
    _closing = true;
    await server.close(force: true);
  }

  bool ownsToken(Map<String, dynamic> request) =>
      (request['resolveToken'] as String).startsWith('token-${server.port}-');

  List<Map<String, dynamic>> applied(String flag) => applies
      .where(ownsToken)
      .expand((r) => (r['flags'] as List).cast<Map<String, dynamic>>())
      .where((f) => f['flag'] == 'flags/$flag')
      .toList();

  Future<void> handle(HttpRequest request) async {
    try {
      await _handle(request);
    } on HttpException {
      // Teardown deliberately closes any native background request mid-read.
      if (!_closing) rethrow;
    } on SocketException {
      if (!_closing) rethrow;
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final body = jsonDecode(await utf8.decoder.bind(request).join())
        as Map<String, dynamic>;
    expectSync(request.method, 'POST');
    expectSync(request.headers.contentType?.mimeType, 'application/json');
    request.response.headers.contentType = ContentType.json;
    switch (request.uri.path) {
      case '/v1/flags:resolve':
        resolves.add(body);
        request.response.statusCode = statusCode;
        request.response.write(jsonEncode(statusCode == 200
            ? response((body['evaluationContext'] as Map)['targeting_key'])
            : {'message': 'test outage'}));
      case '/v1/flags:apply':
        applies.add(body);
        request.response.write('{}');
      default:
        request.response.statusCode = 404;
        request.response.write('{}');
    }
    await request.response.close();
  }

  Map<String, dynamic> response(dynamic user) => {
        'resolveToken': token,
        'resolvedFlags': [
          {
            'flag': 'flags/parity',
            'variant': 'flags/parity/variants/treatment',
            'reason': 'RESOLVE_REASON_MATCH',
            'shouldApply': true,
            'value': {
              'text': 'hello $user',
              'enabled': true,
              'count': 42,
              'ratio': 1.25,
              'wholeDouble': 2,
              'jsonDoubleInt': 7.0,
              if (includeList) 'tags': ['one', 'two'],
              'nothing': null,
              'nested': {'text': 'nested', 'wholeDouble': 3},
            },
            'flagSchema': {
              'schema': {
                'text': {'stringSchema': {}},
                'enabled': {'boolSchema': {}},
                'count': {'intSchema': {}},
                'ratio': {'doubleSchema': {}},
                'wholeDouble': {'doubleSchema': {}},
                'jsonDoubleInt': {'intSchema': {}},
                if (includeList)
                  'tags': {
                    'listSchema': {'stringSchema': {}}
                  },
                'nothing': {'stringSchema': {}},
                'nested': {
                  'structSchema': {
                    'schema': {
                      'text': {'stringSchema': {}},
                      'wholeDouble': {'doubleSchema': {}},
                    },
                  },
                },
              },
            },
          },
          {
            'flag': 'flags/unmatched',
            'variant': '',
            'reason': 'RESOLVE_REASON_NO_SEGMENT_MATCH',
            'shouldApply': true,
          },
        ],
      };
}
