import 'dart:convert';
import 'dart:io';

import 'package:confidence_openfeature_provider/confidence_openfeature_provider.dart';
import 'package:confidence_openfeature_provider/src/configuration.dart';
import 'package:confidence_openfeature_provider/src/provider.dart';
import 'package:confidence_openfeature_provider/src/resolver.dart';
import 'package:confidence_openfeature_provider/src/storage/provider_storage.dart';
import 'package:confidence_openfeature_provider/src/transport.dart';
import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk_experimental.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late ProviderStorage storage;
  final configuration = ConfidenceConfiguration(
    clientSecret: 'test',
    loggingLevel: ConfidenceLoggingLevel.none,
  );
  setUp(() async {
    root = await Directory.systemTemp.createTemp('confidence-provider-test-');
    storage = ProviderStorage(root);
  });
  tearDown(() => root.delete(recursive: true));
  ConfidenceProvider provider() => createConfidenceProvider(
    configuration,
    prepare: (_) async => ProviderResources(
      storage: storage,
      visitorId: 'visitor',
      resolver: ConfidenceResolver(
        configuration,
        isIOS: false,
        transport: TestTransport(),
      ),
    ),
    now: () => DateTime.utc(2024),
  );

  test(
    'builder validates configuration without any plugin or network access',
    () {
      final built = ConfidenceProviderBuilder(clientSecret: 'test')
          .withRegion(ConfidenceRegion.eu)
          .withLoggingLevel(ConfidenceLoggingLevel.none)
          .withResolveBaseUrl(Uri.parse('https://example.test/proxy'))
          .withInitializationStrategy(
            InitializationStrategy.activateAndFetchAsync,
          )
          .build();
      expect(built.metadata.name, 'Confidence');
      expect(
        built
            .resolveBooleanValue('flag.enabled', false, EvaluationContext.empty)
            .errorCode,
        ErrorCode.providerNotReady,
      );
      expect(
        () => ConfidenceProviderBuilder(clientSecret: '').build(),
        throwsArgumentError,
      );
      addTearDown(built.shutdown);
    },
  );

  test(
    'real OpenFeature registration completes, reads work and telemetry persists',
    () async {
      final api = createIsolatedOpenFeatureAPI();
      final p = provider();
      addTearDown(api.shutdown);
      await api.setProviderAndWait(p);
      final client = api.getClient();
      expect(client.getBooleanValue('flag.enabled', false), isTrue);
      expect(client.getBooleanValue('flag.enabled', false), isTrue);
      expect(
        client.getStringDetails('flag.enabled', '').errorCode,
        ErrorCode.typeMismatch,
      );
      client.track(
        'checkout',
        details: TrackingEventDetails(
          attributes: {'product': 'book'},
          value: 5,
        ),
      );
      final inspection = await p.inspectStorage();
      expect(inspection.pendingExposures, 1);
      expect(inspection.pendingEvents, 1);
      expect(inspection.cachedFlags, 1);
      expect(inspection.droppedRecords, 0);
      final box = await storage.readOutbox();
      expect(box.events.single.payload, {
        'visitor_id': 'visitor',
        'product': 'book',
        'value': 5,
      });
      expect(box.events.single.time, DateTime.utc(2024));
    },
  );

  test('provider is domain-scoped according to the upstream SDK', () async {
    final api = createIsolatedOpenFeatureAPI();
    final p = provider();
    addTearDown(api.shutdown);
    await api.setProviderForDomainAndWait('first', p);
    await expectLater(
      api.setProviderForDomainAndWait('second', p),
      throwsA(isA<OpenFeatureException>()),
    );
  });
}

final class TestTransport implements JsonTransport {
  @override
  Future<WireResponse> post(Uri uri, Map<String, Object?> body) async =>
      WireResponse(
        200,
        jsonEncode({
          'resolveToken': 'token',
          'resolvedFlags': [
            {
              'flag': 'flags/flag',
              'reason': 'RESOLVE_REASON_MATCH',
              'shouldApply': true,
              'value': {'enabled': true},
              'flagSchema': {
                'schema': {
                  'enabled': {'boolSchema': <String, Object?>{}},
                },
              },
            },
          ],
        }),
      );
  @override
  void close() {}
}
