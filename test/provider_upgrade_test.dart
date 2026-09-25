import 'dart:convert';
import 'dart:io';

import 'package:confidence_openfeature_provider/src/configuration.dart';
import 'package:confidence_openfeature_provider/src/provider.dart';
import 'package:confidence_openfeature_provider/src/resolver.dart';
import 'package:confidence_openfeature_provider/src/storage/legacy_decoder.dart';
import 'package:confidence_openfeature_provider/src/storage/legacy_migrator.dart';
import 'package:confidence_openfeature_provider/src/storage/provider_storage.dart';
import 'package:confidence_openfeature_provider/src/transport.dart';
import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk_experimental.dart';
import 'package:test/test.dart';

void main() {
  for (final platform in LegacyPlatform.values) {
    test(
      '${platform.name} native import survives offline runtime and replays after restart',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'confidence-upgrade-',
        );
        addTearDown(() => root.delete(recursive: true));
        final events = await Directory('${root.path}/events').create();
        final source = 'test/fixtures/legacy/${platform.name}';
        final flags = await File(
          '$source/flags.json',
        ).copy('${root.path}/flags');
        final apply = await File(
          '$source/apply.json',
        ).copy('${root.path}/apply');
        await File(
          '$source/events-unfinished',
        ).copy('${events.path}/unfinished');
        await File(
          '$source/${platform == LegacyPlatform.swift ? 'events.READY' : 'events.ready'}',
        ).copy('${events.path}/sealed');
        final directory = Directory('${root.path}/dart');
        final transport = UpgradeTransport();
        final config = ConfidenceConfiguration(
          apiKey: 'test',
          loggingLevel: ConfidenceLoggingLevel.none,
        );
        ConfidenceProvider create() => createConfidenceProvider(
          config,
          prepare: (_) async {
            final storage = ProviderStorage(directory);
            await LegacyMigrator(
              platform: platform,
              flags: flags,
              apply: apply,
              events: events,
              readVisitorId: () async => 'fixture-visitor',
              destination: storage,
            ).run();
            return ProviderResources(
              storage: storage,
              visitorId: 'fixture-visitor',
              resolver: ConfidenceResolver(
                config,
                isIOS: platform == LegacyPlatform.swift,
                transport: transport,
              ),
            );
          },
        );
        final context = EvaluationContext(targetingKey: 'user-a');
        final api = createIsolatedOpenFeatureAPI();
        addTearDown(api.shutdown);
        await api.setEvaluationContextAndWait(context);
        final old = create();
        await api.setProviderAndWait(old);
        expect(
          api.getClient().getBooleanValue('example.enabled', false),
          isTrue,
        );
        expect(
          api.getClient().getStringDetails('example.enabled', '').errorCode,
          ErrorCode.typeMismatch,
        );
        api.getClient().track(
          'new-event',
          details: TrackingEventDetails(attributes: {'purchase': 1}),
        );
        final offline = await old.flush();
        expect(offline.retryNeeded, isTrue);
        expect(offline.pendingRecords, 6);
        await api.shutdown();

        final restartedApi = createIsolatedOpenFeatureAPI();
        addTearDown(restartedApi.shutdown);
        await restartedApi.setEvaluationContextAndWait(context);
        final restarted = create();
        await restartedApi.setProviderAndWait(restarted);
        expect(
          restartedApi.getClient().getBooleanValue('example.enabled', false),
          isTrue,
        );
        // Re-reading the cached flag must not duplicate its durable exposure.
        final inspection = await restarted.inspectStorage();
        expect(inspection.pendingExposures, 3);
        expect(inspection.pendingEvents, 3);
        transport.online = true;
        transport.requests.clear();
        final result = await restarted.flush();
        expect(result.acceptedRecords, 6);
        expect(result.pendingRecords, 0);
        expect(result.droppedRecords, 0);
        final published = transport.requests
            .where((r) => r.path.endsWith(':publish'))
            .expand((r) => r.body['events']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .toList();
        final legacy = published
            .where((e) => e['eventDefinition'] == 'eventDefinitions/checkout')
            .toList();
        expect(legacy, hasLength(2));
        for (final event in legacy) {
          expect(
            DateTime.parse(event['eventTime']! as String),
            DateTime.utc(2023, 11, 14, 22, 13, 20),
          );
          final payload = event['payload']! as Map<String, Object?>;
          expect(payload['visitor_id'], 'fixture-visitor');
          expect(payload['targeting_key'], 'user-a');
          expect(payload['timestamp'], '2023-11-14T22:13:20.000Z');
          expect(payload['count'], 7);
        }
        expect((await restarted.flush()).acceptedRecords, 0);
        expect(await flags.exists(), isFalse);
        expect(await apply.exists(), isFalse);
        expect(await events.list().isEmpty, isTrue);
      },
    );
  }
}

final class UpgradeTransport implements JsonTransport {
  bool online = false;
  final requests = <({String path, Map<String, Object?> body})>[];
  @override
  Future<WireResponse> post(Uri uri, Map<String, Object?> body) async {
    // Round-trip through JSON just like the real HTTP transport.
    requests.add((
      path: uri.path,
      body: jsonDecode(jsonEncode(body)) as Map<String, Object?>,
    ));
    return WireResponse(online ? 200 : 503, '{}');
  }

  @override
  void close() {}
}
