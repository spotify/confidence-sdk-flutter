import 'dart:convert';
import 'dart:io';

import 'package:confidence_flutter_sdk/confidence_flutter_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'upgrade_sdk.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment('UPGRADE_PHASE', defaultValue: 'seed');
  const encoded =
      String.fromEnvironment('UPGRADE_EXPECTED', defaultValue: '{}');

  testWidgets('in-place upgrade: $phase', (_) async {
    final support = await getApplicationSupportDirectory();
    final sentinel = File('${support.path}/upgrade-test-user-data.txt');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <Map<String, dynamic>>[];
    final applies = <Map<String, dynamic>>[];
    final events = <Map<String, dynamic>>[];
    var eventsOffline = true;
    var offline = phase != 'seed';
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, dynamic>;
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path.endsWith(':resolve')) {
        requests.add(body);
        request.response.statusCode = offline ? 503 : 200;
        request.response
            .write(jsonEncode(offline ? {} : _response(phase == 'seed')));
      } else if (request.uri.path.endsWith(':apply')) {
        applies.add(body);
        final pending =
            (body['flags'] as List).any((f) => f['flag'] == 'flags/pending');
        // Leave a genuine native exposure in SENDING, then kill the old app.
        if (phase == 'seed' && pending) return;
        request.response.statusCode = 200;
        request.response.write('{}');
      } else if (request.uri.path.endsWith('events:publish')) {
        events.add(body);
        request.response.statusCode = eventsOffline ? 503 : 200;
        request.response.write('{}');
      } else {
        request.response.statusCode = 404;
        request.response.write('{}');
      }
      await request.response.close();
    });
    if (phase != 'seed') addTearDown(() => server.close(force: true));

    final sdk = createUpgradeSdk(Uri.parse('http://127.0.0.1:${server.port}'));
    await sdk.setup('upgrade-test-secret', LoggingLevel.ERROR,
        'http://127.0.0.1:${server.port}');
    // Deliberately omit targeting_key: visitor_id must remain usable for targeting.
    if (phase == 'seed') {
      await sdk.fetchAndActivate();
      _expectCachedValues(sdk, 'old-value');
      await _until(() => applies.any((r) =>
          (r['flags'] as List).any((f) => f['flag'] == 'flags/upgrade')));
      sdk.getString('pending.text', '');
      await _until(() => applies.any((r) =>
          (r['flags'] as List).any((f) => f['flag'] == 'flags/pending')));
      final paths = Platform.isIOS
          ? [
              'com.confidence.cache/com.example.confidenceFlutterSdkExample/confidence.flags.resolve',
              'com.confidence.cache/com.example.confidenceFlutterSdkExample/confidence.flags.apply'
            ]
          : ['confidence_flags_cache.json', 'confidence_apply_cache.json'];
      await _until(
          () => paths.every((p) => File('${support.path}/$p').existsSync()));
      // Swift persists SENDING; Android keeps CREATED on disk during sends.
      await _until(() {
        final file = File('${support.path}/${paths.last}');
        try {
          final text = file.readAsStringSync();
          return Platform.isIOS
              ? text.contains('sending')
              : text.contains('CREATED') || text.contains('SENDING');
        } catch (_) {
          return false;
        }
      });
      sdk.track('upgrade-event', {'screen': 'checkout', 'amount': 2});
      final eventRoot = Platform.isIOS
          ? 'com.confidence.events.storage/com.example.confidenceFlutterSdkExample/events'
          : '../app_events';
      final eventDir = Directory('${support.path}/$eventRoot');
      await _until(() =>
          eventDir.existsSync() &&
          eventDir.listSync().whereType<File>().any(
              (file) => file.readAsStringSync().contains('upgrade-event')));
      for (final file in eventDir.listSync().whereType<File>()) {
        paths.add('$eventRoot/${file.uri.pathSegments.last}');
      }
      final marker = 'user-data-${DateTime.now().microsecondsSinceEpoch}';
      await sentinel.writeAsString(marker, flush: true);
      final files = <String, String>{};
      for (final path in paths) {
        files[path] =
            base64Encode(await File('${support.path}/$path').readAsBytes());
      }
      final context = requests.last['evaluationContext'] as Map;
      expect(context['visitor_id'], isA<String>());
      expect(context['visitor_id'], isNotEmpty);
      binding.reportData = {
        'platform': Platform.isIOS ? 'ios' : 'android',
        'visitorId': context['visitor_id'],
        'sentinel': marker,
        'files': files,
      };
      return;
    }

    final expected = jsonDecode(encoded) as Map<String, dynamic>;
    // This fails if Flutter or the installer uninstalls/clears data between phases.
    expect(await sentinel.readAsString(), expected['sentinel']);
    expect(await sdk.isStorageEmpty(), false,
        reason: 'Persisted flags must be visible after setup');
    if (phase == 'restart') {
      await sdk.fetchAndActivate();
    } else {
      await sdk.activateAndFetchAsync();
    }
    _expectCachedValues(sdk, phase == 'verify' ? 'old-value' : 'new-value');
    await _until(() => requests.isNotEmpty);
    expect((requests.last['evaluationContext'] as Map)['visitor_id'],
        expected['visitorId']);
    if (phase == 'verify') {
      await _until(() => events.isNotEmpty);
      final replay = (events.first['events'] as List).firstWhere(
              (e) => e['eventDefinition'] == 'eventDefinitions/upgrade-event')
          as Map;
      expect(replay['payload']['screen'], 'checkout');
      expect(replay['payload']['amount'], 2);
      expect(replay['payload']['context']['visitor_id'], expected['visitorId']);
      final eventCache =
          File('${support.path}/confidence/confidence.events.migrated');
      expect(jsonDecode(await eventCache.readAsString()), isNotEmpty,
          reason: 'A failed event upload must remain persisted');
      eventsOffline = false;
      sdk.flush();
      await _until(() => eventCache.readAsStringSync() == '[]');
      expect(events, hasLength(2));
      expect(events.last['events'], events.first['events'],
          reason: 'Retry must preserve the original event time and context');

      await _until(() => applies.any((r) =>
          r['resolveToken'] == 'native-token' &&
          (r['flags'] as List).any((f) => f['flag'] == 'flags/pending')));
      final nativeApplyPath = Platform.isIOS
          ? 'com.confidence.cache/com.example.confidenceFlutterSdkExample/confidence.flags.apply'
          : 'confidence_apply_cache.json';
      final nativeApplies = jsonDecode(utf8
          .decode(base64Decode(expected['files'][nativeApplyPath] as String)));
      final originalTime = Platform.isIOS
          ? DateTime.utc(2001).add(Duration(
              microseconds: (((nativeApplies['resolveEvents'] as List)
                              .first['events'] as List)
                          .firstWhere(
                              (e) => e['name'] == 'pending')['applyTime'] *
                      1000000)
                  .round()))
          : DateTime.parse(
              nativeApplies['native-token']['pending']['time'] as String);
      final pending = applies
          .where((r) => r['resolveToken'] == 'native-token')
          .expand((r) => r['flags'] as List)
          .firstWhere((f) => f['flag'] == 'flags/pending');
      expect(DateTime.parse(pending['applyTime'] as String), originalTime);
      // Already acknowledged exposures must not be replayed with the old token.
      expect(
          applies
              .where((r) => r['resolveToken'] == 'native-token')
              .expand((r) => r['flags'] as List)
              .where((f) => f['flag'] == 'flags/upgrade'),
          isEmpty);
      offline = false;
      await sdk.fetchAndActivate();
      _expectCachedValues(sdk, 'new-value');
      await _until(() => applies.any((r) => r['resolveToken'] == 'dart-token'));
      await _until(() {
        final receipts = jsonDecode(
            File('${support.path}/confidence/confidence.apply.cache')
                .readAsStringSync());
        return receipts['dart-token']?['upgrade']?['sent'] == true;
      });
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(events, isEmpty,
          reason: 'Relaunch must not replay migrated events');
      expect(applies, isEmpty,
          reason: 'Relaunch must not resurrect old pending/sent exposures');
    }
    for (final entry in (expected['files'] as Map<String, dynamic>).entries) {
      expect(
          base64Encode(
              await File('${support.path}/${entry.key}').readAsBytes()),
          entry.value,
          reason:
              'Migration must retain the original native file: ${entry.key}');
    }
    expect(await sentinel.readAsString(), expected['sentinel']);
    binding.reportData = {'phase': phase, 'passed': true};
  });
}

void _expectCachedValues(ConfidenceFlutterSdk sdk, String text) {
  expect(sdk.getString('upgrade.text', 'fallback'), text);
  expect(sdk.getInt('upgrade.count', -1), 42);
  expect(sdk.getDouble('upgrade.ratio', -1.0), 2.0);
  expect(sdk.getBool('upgrade.enabled', false), true);
  expect(sdk.getObject('upgrade.nested', {}), {'color': 'blue', 'amount': 3.0});
}

Future<void> _until(bool Function() predicate) async {
  final end = DateTime.now().add(const Duration(seconds: 10));
  while (!predicate()) {
    if (DateTime.now().isAfter(end)) {
      fail('Upgrade condition not satisfied within 10 seconds');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Map<String, dynamic> _response(bool native) => {
      'resolveToken': native ? 'native-token' : 'dart-token',
      'resolvedFlags': [
        {
          'flag': 'flags/upgrade',
          'variant': 'flags/upgrade/variants/a',
          'reason': 'RESOLVE_REASON_MATCH',
          'shouldApply': true,
          'value': {
            'text': native ? 'old-value' : 'new-value',
            'count': 42,
            'ratio': 2,
            'enabled': true,
            'nested': {'color': 'blue', 'amount': 3}
          },
          'flagSchema': {
            'schema': {
              'text': {'stringSchema': {}},
              'count': {'intSchema': {}},
              'ratio': {'doubleSchema': {}},
              'enabled': {'boolSchema': {}},
              'nested': {
                'structSchema': {
                  'schema': {
                    'color': {'stringSchema': {}},
                    'amount': {'doubleSchema': {}}
                  }
                }
              },
            }
          },
        },
        {
          'flag': 'flags/pending',
          'variant': 'flags/pending/variants/a',
          'reason': 'RESOLVE_REASON_MATCH',
          'shouldApply': true,
          'value': {'text': 'pending'},
          'flagSchema': {
            'schema': {
              'text': {'stringSchema': {}}
            }
          },
        },
      ],
    };
