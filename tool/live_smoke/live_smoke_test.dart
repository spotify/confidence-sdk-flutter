import 'dart:io';
import 'dart:convert';

import 'package:confidence_openfeature_provider/src/configuration.dart';
import 'package:confidence_openfeature_provider/src/provider.dart';
import 'package:confidence_openfeature_provider/src/resolver.dart';
import 'package:confidence_openfeature_provider/src/storage/provider_storage.dart';
import 'package:confidence_openfeature_provider/src/transport.dart';
import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk_experimental.dart';
import 'package:test/test.dart';

void main() {
  for (final isIOS in [false, true]) {
    test(
      'live ${isIOS ? 'iOS' : 'Android'} resolve, typed read, apply and deduplication',
      () async {
        final env = Platform.environment;
        final secret = env['CONFIDENCE_FLAG_CLIENT_SECRET'];
        final configuredFlag = env['CONFIDENCE_TEST_FLAG'];
        final targeting = env['CONFIDENCE_TARGETING_KEY'];
        if (secret == null || configuredFlag == null || targeting == null) {
          fail('Run using the opt-in smoke runner with an approved env file.');
        }
        final key = configuredFlag.replaceFirst(RegExp(r'^flags/'), '');
        final root = await Directory.systemTemp.createTemp('confidence-live-');
        addTearDown(() => root.delete(recursive: true));
        final storage = ProviderStorage(root);
        final transport = StatusTransport();
        final config = ConfidenceConfiguration(
          clientSecret: secret,
          loggingLevel: ConfidenceLoggingLevel.none,
        );
        final provider = createConfidenceProvider(
          config,
          prepare: (_) async => ProviderResources(
            storage: storage,
            resolver: ConfidenceResolver(
              config,
              isIOS: isIOS,
              transport: transport,
            ),
            visitorId: 'dart-provider-smoke',
          ),
        );
        final api = createIsolatedOpenFeatureAPI(
          lifecycleTimeout: const Duration(seconds: 20),
        );
        addTearDown(api.shutdown);
        final context = EvaluationContext(targetingKey: targeting);
        await api.setEvaluationContextAndWait(context);
        await api.setProviderAndWait(provider);
        expect(
          transport.statuses['/v1/flags:resolve'],
          [200],
          reason: 'Live resolve must succeed.',
        );
        final snapshot = await storage.readSnapshot();
        expect(
          snapshot != null,
          isTrue,
          reason: 'Response must decode and persist.',
        );
        final flag = snapshot!.flags[key.split('.').first];
        expect(
          flag != null,
          isTrue,
          reason: 'Configured flag must be in the resolved snapshot.',
        );
        expect(
          flag!.shouldApply,
          isTrue,
          reason: 'Smoke flag must permit exposure reporting.',
        );
        Object? selected = flag.value;
        for (final part in key.split('.').skip(1)) {
          if (selected is! Map<String, Object?>) {
            fail('Configured flag property is unavailable.');
          }
          selected = selected[part];
        }
        void read() {
          final ResolutionDetails<Object?> details = switch (selected) {
            bool() => provider.resolveBooleanValue(key, false, context),
            String() => provider.resolveStringValue(key, '', context),
            int() => provider.resolveIntegerValue(key, 0, context),
            double() => provider.resolveDoubleValue(key, 0, context),
            Map<String, Object?>() => provider.resolveStructureValue(
              key,
              {},
              context,
            ),
            _ => throw StateError(
              'Smoke requires an assigned supported typed value.',
            ),
          };
          expect(
            details.errorCode == null,
            isTrue,
            reason: 'Typed read must succeed.',
          );
        }

        read();
        read();
        expect((await provider.inspectStorage()).pendingExposures, 1);
        final result = await provider.flush();
        expect(
          transport.statuses['/v1/flags:apply'],
          [200],
          reason: 'Live apply must succeed.',
        );
        expect(result.acceptedRecords, 1);
        expect(result.droppedRecords, 0);
        expect(result.pendingRecords, 0);
        read();
        expect((await provider.flush()).acceptedRecords, 0);
        expect(transport.statuses['/v1/flags:apply']!.length, 1);
        final event = env['CONFIDENCE_SMOKE_EVENT'];
        if (event != null) {
          api.getClient().track(event, details: TrackingEventDetails(value: 1));
          final published = await provider.flush();
          expect(transport.statuses['/v1/events:publish'], [200]);
          expect(
            transport.eventRejections,
            0,
            reason: 'Backend must accept the synthetic payload.',
          );
          expect(published.acceptedRecords, 1);
          expect(published.droppedRecords, 0);
          expect(published.pendingRecords, 0);
          expect((await provider.flush()).acceptedRecords, 0);
          expect(transport.statuses['/v1/events:publish']!.length, 1);
        }
      },
    );
  }
}

/// Capture status codes only: no credentials, context, flags, tokens or bodies.
final class StatusTransport implements JsonTransport {
  final delegate = IoTransport();
  final statuses = <String, List<int>>{};
  int eventRejections = 0;
  @override
  Future<WireResponse> post(Uri uri, Map<String, Object?> body) async {
    final response = await delegate.post(uri, body);
    statuses.putIfAbsent(uri.path, () => []).add(response.status);
    if (uri.path == '/v1/events:publish' && response.status == 200) {
      final decoded = jsonDecode(response.body) as Map<String, Object?>;
      eventRejections += (decoded['errors'] as List<Object?>? ?? []).length;
    }
    return response;
  }

  @override
  void close() => delegate.close();
}
