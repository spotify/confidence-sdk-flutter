import 'dart:convert';
import 'dart:io';

import 'package:confidence_openfeature_provider/src/configuration.dart';
import 'package:confidence_openfeature_provider/src/provider.dart';
import 'package:confidence_openfeature_provider/src/transport.dart';
import 'package:flutter/widgets.dart';
import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk_experimental.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final support = await getApplicationSupportDirectory();
  final report = File('${support.path}/provider-result.json');
  final api = createIsolatedOpenFeatureAPI();
  try {
    final previous =
        jsonDecode(
              await File('${support.path}/legacy-result.json').readAsString(),
            )
            as Map<String, Object?>;
    check(previous['ok'] == true, 'Legacy app did not complete.');
    final phase = await report.exists()
        ? (jsonDecode(await report.readAsString())
              as Map<String, Object?>)['phase']
        : null;
    final transport = OfflineThenOnline();
    final provider = createConfidenceProvider(
      ConfidenceConfiguration(
        apiKey: 'synthetic-upgrade-client',
        loggingLevel: ConfidenceLoggingLevel.none,
      ),
      transport: transport,
    );
    await api.setEvaluationContextAndWait(
      EvaluationContext(targetingKey: 'user-a'),
    );
    await api.setProviderAndWait(provider);
    check(
      api.getClient().getBooleanValue('example.enabled', false),
      'Offline cached flag unavailable.',
    );
    if (phase == null) api.getClient().track('new-event');
    final stored = await provider.inspectStorage();
    check(
      stored.pendingExposures == (phase == 'complete' ? 0 : 3) &&
          stored.pendingEvents == (phase == 'complete' ? 0 : 3),
      'Unexpected imported queue counts.',
    );
    final offline = await provider.flush();
    check(
      offline.pendingRecords == (phase == 'complete' ? 0 : 6) &&
          (phase == 'complete' || offline.retryNeeded),
      'Offline work was lost.',
    );
    if (phase == null) {
      await api.shutdown();
      await report.writeAsString(
        jsonEncode({
          'ok': true,
          'phase': 'offline',
          'pending': offline.pendingRecords,
        }),
        flush: true,
      );
      runApp(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Text('Offline upgrade persisted'),
        ),
      );
      return;
    }
    transport.online = true;
    final sent = await provider.flush();
    check(
      sent.acceptedRecords == (phase == 'complete' ? 0 : 6) &&
          sent.pendingRecords == 0,
      'Pending records did not replay.',
    );
    final historical = transport.events
        .where((e) => e['eventDefinition'] == 'eventDefinitions/checkout')
        .toList();
    check(
      historical.length == (phase == 'complete' ? 0 : 2),
      'Imported records duplicated or missing.',
    );
    for (final event in historical) {
      final payload = event['payload']! as Map<String, Object?>;
      check(
        payload['visitor_id'] == 'fixture-visitor' &&
            payload['targeting_key'] == 'user-a',
        'Identity changed.',
      );
      check(
        event['eventTime'] == '2023-11-14T22:13:20.000Z',
        'Original event time changed.',
      );
    }
    check(
      (await provider.flush()).acceptedRecords == 0,
      'Repeated flush duplicated work.',
    );
    await api.shutdown();
    await report.writeAsString(
      jsonEncode({
        'ok': true,
        'phase': 'complete',
        'accepted': sent.acceptedRecords,
        'historicalEvents': historical.length,
      }),
      flush: true,
    );
  } catch (error) {
    await report.writeAsString(
      jsonEncode({'ok': false, 'error': '$error'}),
      flush: true,
    );
    await api.shutdown();
  }
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Text('Provider upgrade check complete'),
    ),
  );
}

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

final class OfflineThenOnline implements JsonTransport {
  bool online = false;
  final events = <Map<String, Object?>>[];
  @override
  Future<WireResponse> post(Uri uri, Map<String, Object?> body) async {
    if (!online) return const WireResponse(503, '{}');
    if (uri.path.endsWith(':publish')) {
      final wire = jsonDecode(jsonEncode(body)) as Map<String, Object?>;
      events.addAll(
        (wire['events']! as List<Object?>).cast<Map<String, Object?>>(),
      );
    }
    return const WireResponse(200, '{}');
  }

  @override
  void close() {}
}
