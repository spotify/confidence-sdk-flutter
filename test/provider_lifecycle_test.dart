import 'dart:async';
import 'dart:io';

import 'package:confidence_openfeature_provider/src/configuration.dart';
import 'package:confidence_openfeature_provider/src/provider.dart';
import 'package:confidence_openfeature_provider/src/resolver.dart';
import 'package:confidence_openfeature_provider/src/storage/provider_storage.dart';
import 'package:confidence_openfeature_provider/src/transport.dart';
import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk_experimental.dart';
import 'package:test/test.dart';

import 'provider_test.dart' show TestTransport;

void main() {
  late Directory directory;
  late ProviderStorage storage;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('confidence-lifecycle-');
    storage = ProviderStorage(directory);
  });
  tearDown(() => directory.delete(recursive: true));
  ConfidenceProvider create(
    ControlledTransport transport, {
    bool background = false,
  }) {
    final config = ConfidenceConfiguration(
      apiKey: 'test',
      loggingLevel: ConfidenceLoggingLevel.none,
      initializationStrategy: background
          ? InitializationStrategy.activateAndFetchAsync
          : InitializationStrategy.fetchAndActivate,
    );
    final provider = createConfidenceProvider(
      config,
      prepare: (_) async => ProviderResources(
        storage: storage,
        resolver: ConfidenceResolver(
          config,
          isIOS: false,
          transport: transport,
        ),
        visitorId: 'visitor',
      ),
    );
    addTearDown(provider.shutdown);
    return provider;
  }

  final empty = EvaluationContext.empty;
  final alice = EvaluationContext(attributes: {'user': 'alice'});
  final bob = EvaluationContext(attributes: {'user': 'bob'});

  test('offline first launch becomes ready with defaults', () async {
    final transport = ControlledTransport();
    final p = create(transport);
    final init = p.initialize(empty);
    await transport.respond(0, offline: true);
    await init;
    expect(
      p.resolveBooleanValue('flag.enabled', false, empty).errorCode,
      ErrorCode.flagNotFound,
    );
  });

  test(
    'matching offline cache is stale; another identity cannot use it',
    () async {
      final first = ControlledTransport();
      final p = create(first);
      final init = p.initialize(alice);
      await first.respond(0);
      await init;
      await p.shutdown();
      final offline = ControlledTransport();
      final cached = create(offline);
      final events = <ProviderEventType>[];
      final sub = cached.events.listen((event) => events.add(event.type));
      addTearDown(sub.cancel);
      final restart = cached.initialize(alice);
      await offline.respond(0, offline: true);
      await restart;
      expect(
        cached.resolveBooleanValue('flag.enabled', false, alice).value,
        isTrue,
      );
      expect(events, contains(ProviderEventType.stale));
      expect(
        cached.resolveBooleanValue('flag.enabled', false, bob).errorCode,
        ErrorCode.invalidContext,
      );
    },
  );

  test('real OpenFeature context reconciliation finishes', () async {
    final transport = ControlledTransport();
    final api = createIsolatedOpenFeatureAPI();
    addTearDown(api.shutdown);
    final init = api.setProviderAndWait(create(transport));
    await transport.respond(0);
    await init;
    final changed = api.setEvaluationContextAndWait(alice);
    await transport.respond(1);
    await changed;
    expect(api.getClient().getBooleanValue('flag.enabled', false), isTrue);
    expect((await storage.readSnapshot())!.context['user'], 'alice');
  });

  test('failed transition rejects reads from the previous identity', () async {
    final transport = ControlledTransport();
    final p = create(transport);
    final init = p.initialize(alice);
    await transport.respond(0);
    await init;
    final changed = p.onContextChanged(alice, bob);
    final assertion = expectLater(
      changed,
      throwsA(isA<OpenFeatureException>()),
    );
    await transport.respond(1, offline: true);
    await assertion;
    expect(
      p.resolveBooleanValue('flag.enabled', false, alice).errorCode,
      ErrorCode.invalidContext,
    );
    expect(p.resolveBooleanValue('flag.enabled', false, bob).value, isFalse);
  });

  test(
    'out of order context responses cannot overwrite the latest identity',
    () async {
      final transport = ControlledTransport();
      final p = create(transport);
      final init = p.initialize(empty);
      await transport.respond(0);
      await init;
      final older = p.onContextChanged(empty, alice);
      final newer = p.onContextChanged(alice, bob);
      await transport.respond(2);
      await newer;
      await transport.respond(1);
      await older;
      expect((await storage.readSnapshot())!.context['user'], 'bob');
      expect(p.resolveBooleanValue('flag.enabled', false, bob).value, isTrue);
    },
  );

  test('background resolve persists without activating this session', () async {
    final transport = ControlledTransport();
    final p = create(transport, background: true);
    await p.initialize(empty);
    await transport.respond(0);
    await until(() async => await storage.readSnapshot() != null);
    expect(p.resolveBooleanValue('flag.enabled', false, empty).value, isFalse);
  });

  test(
    'shutdown prevents a late background response from persisting',
    () async {
      final transport = ControlledTransport();
      final p = create(transport, background: true);
      await p.initialize(empty);
      await p.shutdown();
      await transport.respond(0);
      await Future<void>.delayed(Duration.zero);
      expect(await storage.readSnapshot(), isNull);
      expect(
        p.resolveBooleanValue('flag.enabled', false, empty).errorCode,
        ErrorCode.providerNotReady,
      );
    },
  );

  test(
    'replacement prevents old background work from overwriting its snapshot',
    () async {
      final oldTransport = ControlledTransport();
      final old = create(oldTransport, background: true);
      await old.initialize(alice);
      final transport = ControlledTransport();
      final replacement = create(transport);
      final init = replacement.initialize(bob);
      await transport.respond(0);
      await init;
      await oldTransport.respond(0);
      await Future<void>.delayed(Duration.zero);
      expect((await storage.readSnapshot())!.context['user'], 'bob');
    },
  );
}

Future<void> until(Future<bool> Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!await predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Lifecycle operation did not finish.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

final class ControlledTransport implements JsonTransport {
  final requests = <Completer<WireResponse>>[];
  @override
  Future<WireResponse> post(Uri uri, Map<String, Object?> body) {
    final result = Completer<WireResponse>();
    requests.add(result);
    return result.future;
  }

  Future<void> respond(int index, {bool offline = false}) async {
    await until(() async => requests.length > index);
    requests[index].complete(
      offline
          ? const WireResponse(503, '')
          : await TestTransport().post(Uri.parse('https://example.test'), {}),
    );
  }

  @override
  void close() {}
}
