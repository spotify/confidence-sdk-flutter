import 'dart:async';

import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk_experimental.dart';
import 'package:test/test.dart';

// This probe checks the published SDK boundary, not Confidence behavior.
// Keep real networking, storage, and migration out of the contract fixture.
void main() {
  test(
    'registration, synchronous reads, context, tracking, and shutdown',
    () async {
      final api = createIsolatedOpenFeatureAPI();
      addTearDown(api.shutdown);
      final provider = _ContractProbe();
      final initial = EvaluationContext(targetingKey: 'user-a');
      await api.setEvaluationContextAndWait(initial);
      await api.setProviderAndWait(provider);

      expect(provider.context?.targetingKey, 'user-a');
      final client = api.getClient();
      expect(client.getBooleanValue('enabled', false), isTrue);
      expect(client.getStringValue('title', ''), 'hello');
      expect(client.getIntegerValue('count', 0), 3);
      expect(client.getDoubleValue('ratio', 0), 0.5);
      expect(client.getStructureValue('object', {}), {'nested': true});

      await api.setEvaluationContextAndWait(
        EvaluationContext(targetingKey: 'user-b'),
      );
      expect(provider.previousContext?.targetingKey, 'user-a');
      expect(provider.context?.targetingKey, 'user-b');
      client.track('checkout', details: TrackingEventDetails(value: 12));
      expect(provider.trackedName, 'checkout');
      expect(provider.trackedContext?.targetingKey, 'user-b');
      expect(provider.trackedDetails?.value, 12);

      await api.shutdown();
      expect(provider.stopped, isTrue);
    },
  );

  test(
    'a provider with one active context cannot bind to two domains',
    () async {
      final api = createIsolatedOpenFeatureAPI();
      addTearDown(api.shutdown);
      final provider = _ContractProbe();
      await api.setProviderForDomainAndWait('first', provider);
      await expectLater(
        api.setProviderForDomainAndWait('second', provider),
        throwsA(isA<OpenFeatureException>()),
      );
    },
  );

  test('provider stale events reach the client', () async {
    final api = createIsolatedOpenFeatureAPI();
    addTearDown(api.shutdown);
    final provider = _ContractProbe();
    final received = Completer<ProviderEventDetails>();
    api.addHandler(ProviderEventType.stale, received.complete);
    await api.setProviderAndWait(provider);
    provider.controller.add(ProviderEvent(type: ProviderEventType.stale));
    final event = await received.future.timeout(const Duration(seconds: 2));
    expect(event.type, ProviderEventType.stale);
    expect(event.providerMetadata.name, 'Contract probe');
  });
}

final class _ContractProbe
    implements
        FeatureProvider,
        InitializableProvider,
        ContextReconciliationProvider,
        DomainScopedProvider,
        ProviderEventSource,
        TrackingProvider,
        ShutdownProvider {
  final controller = StreamController<ProviderEvent>.broadcast();
  EvaluationContext? context;
  EvaluationContext? previousContext;
  String? trackedName;
  EvaluationContext? trackedContext;
  TrackingEventDetails? trackedDetails;
  bool stopped = false;

  @override
  ProviderMetadata get metadata =>
      const ProviderMetadata(name: 'Contract probe');

  @override
  Stream<ProviderEvent> get events => controller.stream;

  @override
  Future<void> initialize(EvaluationContext context, {String? domain}) async {
    this.context = context;
    controller.add(ProviderEvent(type: ProviderEventType.ready));
  }

  @override
  Future<void> onContextChanged(
    EvaluationContext previousContext,
    EvaluationContext newContext,
  ) async {
    this.previousContext = previousContext;
    context = newContext;
    controller.add(ProviderEvent(type: ProviderEventType.contextChanged));
  }

  @override
  void track(
    String trackingEventName,
    EvaluationContext context, {
    TrackingEventDetails? details,
  }) {
    trackedName = trackingEventName;
    trackedContext = context;
    trackedDetails = details;
  }

  @override
  Future<void> shutdown() async {
    stopped = true;
    await controller.close();
  }

  @override
  ResolutionDetails<bool> resolveBooleanValue(
    String flagKey,
    bool defaultValue,
    EvaluationContext context,
  ) => ResolutionDetails(value: true);

  @override
  ResolutionDetails<String> resolveStringValue(
    String flagKey,
    String defaultValue,
    EvaluationContext context,
  ) => ResolutionDetails(value: 'hello');

  @override
  ResolutionDetails<int> resolveIntegerValue(
    String flagKey,
    int defaultValue,
    EvaluationContext context,
  ) => ResolutionDetails(value: 3);

  @override
  ResolutionDetails<double> resolveDoubleValue(
    String flagKey,
    double defaultValue,
    EvaluationContext context,
  ) => ResolutionDetails(value: 0.5);

  @override
  ResolutionDetails<Map<String, Object?>> resolveStructureValue(
    String flagKey,
    Map<String, Object?> defaultValue,
    EvaluationContext context,
  ) => ResolutionDetails(value: {'nested': true});
}
