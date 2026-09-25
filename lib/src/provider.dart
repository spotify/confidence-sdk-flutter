import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk.dart';
import 'package:path_provider/path_provider.dart';

import 'configuration.dart';
import 'evaluator.dart';
import 'resolver.dart';
import 'storage/legacy_decoder.dart';
import 'storage/legacy_migrator.dart';
import 'storage/legacy_storage.dart';
import 'storage/outbox.dart';
import 'storage/provider_storage.dart';
import 'telemetry_buffer.dart';
import 'telemetry_delivery.dart';
import 'transport.dart';

final class ConfidenceProviderBuilder {
  /// Pass the Confidence flag client's client secret as [clientSecret].
  // Keep the credential field private while preserving the named API argument.
  ConfidenceProviderBuilder({required String clientSecret})
    // ignore: prefer_initializing_formals
    : _clientSecret = clientSecret;
  final String _clientSecret;
  ConfidenceRegion _region = ConfidenceRegion.global;
  ConfidenceLoggingLevel _logging = ConfidenceLoggingLevel.warn;
  InitializationStrategy _strategy = InitializationStrategy.fetchAndActivate;
  Uri? _baseUrl;

  ConfidenceProviderBuilder withRegion(ConfidenceRegion region) {
    _region = region;
    return this;
  }

  ConfidenceProviderBuilder withLoggingLevel(ConfidenceLoggingLevel level) {
    _logging = level;
    return this;
  }

  ConfidenceProviderBuilder withInitializationStrategy(
    InitializationStrategy strategy,
  ) {
    _strategy = strategy;
    return this;
  }

  ConfidenceProviderBuilder withResolveBaseUrl(Uri url) {
    _baseUrl = url;
    return this;
  }

  /// Construction performs no network, disk, or plugin work.
  ConfidenceProvider build() {
    final configuration = ConfidenceConfiguration(
      clientSecret: _clientSecret,
      region: _region,
      loggingLevel: _logging,
      initializationStrategy: _strategy,
      resolveBaseUrl: _baseUrl,
    );
    return createConfidenceProvider(configuration);
  }
}

/// Internal seam for tests; only the provider and builder are exported publicly.
final class ProviderResources {
  ProviderResources({
    required this.storage,
    required this.resolver,
    required this.visitorId,
  });
  final ProviderStorage storage;
  final ConfidenceResolver resolver;
  final String visitorId;
}

ConfidenceProvider createConfidenceProvider(
  ConfidenceConfiguration configuration, {
  Future<ProviderResources> Function(String? domain)? prepare,
  JsonTransport? transport,
  DateTime Function()? now,
}) => ConfidenceProvider._(
  configuration,
  prepare ??
      (domain) => _mobileResources(configuration, domain, transport: transport),
  now ?? DateTime.now,
);

final class ConfidenceProvider
    implements
        FeatureProvider,
        InitializableProvider,
        ProviderEventSource,
        DomainScopedProvider,
        TrackingProvider,
        ShutdownProvider,
        ContextReconciliationProvider {
  ConfidenceProvider._(this._configuration, this._prepare, this._now) {
    _evaluator = FlagEvaluator(
      onExposure: (token, flag) {
        _buffer?.apply(
          ApplyRecord(token: token, flag: flag, time: _now().toUtc()),
        );
      },
    );
  }
  final ConfidenceConfiguration _configuration;
  final Future<ProviderResources> Function(String?) _prepare;
  final DateTime Function() _now;
  final _events = StreamController<ProviderEvent>.broadcast(sync: true);
  late final FlagEvaluator _evaluator;
  ProviderResources? _resources;
  TelemetryBuffer? _buffer;
  TelemetryDelivery? _delivery;
  bool _closed = false;
  bool _started = false;
  int _epoch = 0;
  Object? _snapshotOwner;
  Map<String, Object?>? _requested;

  @override
  ProviderMetadata get metadata => const ProviderMetadata(name: 'Confidence');
  @override
  Stream<ProviderEvent> get events => _events.stream;

  Map<String, Object?> _context(EvaluationContext context) => {
    if (_resources != null) 'visitor_id': _resources!.visitorId,
    ...context.attributes,
    if (context.targetingKey != null) 'targeting_key': context.targetingKey,
  };

  @override
  Future<void> initialize(EvaluationContext context, {String? domain}) async {
    if (_started || _closed) {
      throw StateError('Provider cannot be initialized again.');
    }
    _started = true;
    final epoch = ++_epoch;
    try {
      final resources = await _prepare(domain);
      if (_closed) {
        resources.resolver.close();
        return;
      }
      _resources = resources;
      _snapshotOwner = resources.storage.claimSnapshotWriter();
      final initialOutbox = await resources.storage.readOutbox();
      if (_closed) return;
      _buffer = TelemetryBuffer(
        resources.storage,
        initialOutbox,
        onPersistenceError: () => _warn('Unable to persist telemetry.'),
      );
      final requested = _context(context);
      _requested = requested;
      final cached = await resources.storage.readSnapshot();
      if (_closed) return;
      _evaluator.active = cached != null && sameValue(cached.context, requested)
          ? cached
          : null;
      if (_configuration.initializationStrategy ==
          InitializationStrategy.fetchAndActivate) {
        await _fetch(requested, epoch, activate: true);
      }
      if (_closed) return;
      _delivery = TelemetryDelivery(
        resources.storage,
        _buffer!,
        resources.resolver,
        now: _now,
        onFailure: () => _warn('Unable to flush telemetry.'),
      )..start();
      _evaluator.ready = true;
      _emit(ProviderEventType.ready);
      if (_evaluator.stale) _emit(ProviderEventType.stale);
      if (_configuration.initializationStrategy ==
          InitializationStrategy.activateAndFetchAsync) {
        unawaited(_fetch(requested, epoch, activate: false));
      }
    } catch (_) {
      _releaseSnapshotWriter();
      _emit(ProviderEventType.error);
      throw const OpenFeatureException('Confidence initialization failed.');
    }
  }

  Future<bool> _fetch(
    Map<String, Object?> context,
    int epoch, {
    required bool activate,
  }) async {
    try {
      final snapshot = await _resources!.resolver.resolve(context);
      if (!_current(epoch)) return false;
      await _resources!.storage.writeSnapshot(
        snapshot,
        shouldWrite: () => _current(epoch),
      );
      if (!_current(epoch)) return false;
      if (activate) _evaluator.active = snapshot;
      _evaluator.stale = false;
      return true;
    } catch (_) {
      if (!_current(epoch)) return false;
      _evaluator.stale = _evaluator.active != null;
      _warn('Unable to refresh flags.');
      if (_evaluator.ready && _evaluator.stale) _emit(ProviderEventType.stale);
      return false;
    }
  }

  bool _current(int epoch) =>
      !_closed &&
      epoch == _epoch &&
      _snapshotOwner != null &&
      _resources!.storage.isSnapshotWriter(_snapshotOwner!);

  void _releaseSnapshotWriter() {
    final owner = _snapshotOwner;
    if (owner != null) _resources?.storage.releaseSnapshotWriter(owner);
    _snapshotOwner = null;
  }

  @override
  Future<void> onContextChanged(
    EvaluationContext previousContext,
    EvaluationContext newContext,
  ) async {
    if (_closed || !_evaluator.ready) {
      throw StateError('Provider is not ready.');
    }
    final epoch = ++_epoch;
    _requested = _context(newContext);
    _emit(ProviderEventType.reconciling);
    final success = await _fetch(_requested!, epoch, activate: true);
    if (_closed || epoch != _epoch) return;
    if (success) {
      _emit(ProviderEventType.contextChanged);
    } else {
      _emit(ProviderEventType.error);
      throw const OpenFeatureException(
        'Confidence context refresh failed.',
        errorCode: ErrorCode.invalidContext,
      );
    }
  }

  ResolutionDetails<T> _evaluate<T>(
    String key,
    T fallback,
    EvaluationContext context,
  ) {
    final mapped = _context(context);
    if (_evaluator.ready && !sameValue(mapped, _requested)) {
      return ResolutionDetails(
        value: fallback,
        reason: 'ERROR',
        errorCode: ErrorCode.invalidContext,
        errorMessage:
            'Evaluation context does not match the requested context.',
      );
    }
    return _evaluator.evaluate(key, fallback, mapped);
  }

  @override
  ResolutionDetails<bool> resolveBooleanValue(
    String key,
    bool fallback,
    EvaluationContext context,
  ) => _evaluate(key, fallback, context);
  @override
  ResolutionDetails<String> resolveStringValue(
    String key,
    String fallback,
    EvaluationContext context,
  ) => _evaluate(key, fallback, context);
  @override
  ResolutionDetails<int> resolveIntegerValue(
    String key,
    int fallback,
    EvaluationContext context,
  ) => _evaluate(key, fallback, context);
  @override
  ResolutionDetails<double> resolveDoubleValue(
    String key,
    double fallback,
    EvaluationContext context,
  ) => _evaluate(key, fallback, context);
  @override
  ResolutionDetails<Map<String, Object?>> resolveStructureValue(
    String key,
    Map<String, Object?> fallback,
    EvaluationContext context,
  ) => _evaluate(key, fallback, context);

  @override
  void track(
    String trackingEventName,
    EvaluationContext context, {
    TrackingEventDetails? details,
  }) {
    if (_closed || !_evaluator.ready || trackingEventName.isEmpty) return;
    _buffer!.track(
      EventRecord(
        id: _newId(),
        name: trackingEventName,
        time: _now().toUtc(),
        payload: {
          ..._context(context),
          ...?details?.attributes,
          if (details?.value != null) 'value': details!.value,
        },
      ),
    );
  }

  /// Counts only; no credentials, tokens, identities, or event payloads exposed.
  Future<ConfidenceStorageInspection> inspectStorage() async {
    final resources = _resources;
    if (resources == null || _closed) {
      throw StateError('Provider is not initialized.');
    }
    await _buffer!.persist();
    final box = await resources.storage.readOutbox();
    return ConfidenceStorageInspection(
      pendingEvents: box.events.length,
      pendingExposures: box.apply.where((a) => !a.sent).length,
      droppedRecords: box.droppedRecords,
      cachedFlags: (await resources.storage.readSnapshot())?.flags.length ?? 0,
    );
  }

  /// Persists queued work and attempts each pending batch once. Transient
  /// failures remain queued; disk failures throw. New enqueues may remain.
  Future<ConfidenceFlushResult> flush() {
    if (_closed || _delivery == null) {
      throw StateError('Provider is not ready.');
    }
    return _delivery!.flush();
  }

  @override
  Future<void> shutdown() async {
    if (_closed) return;
    _closed = true;
    _epoch++;
    _evaluator.ready = false;
    try {
      await (_delivery?.flush() ?? _buffer?.persist() ?? Future<void>.value())
          .timeout(const Duration(seconds: 2));
    } on TimeoutException {
      _warn('Shutdown flush deadline reached.');
    } finally {
      _delivery?.close();
      _resources?.resolver.close();
      _releaseSnapshotWriter();
      await _events.close();
    }
  }

  void _emit(ProviderEventType type) {
    if (!_closed) _events.add(ProviderEvent(type: type));
  }

  void _warn(String message) {
    if (_configuration.loggingLevel.index <=
        ConfidenceLoggingLevel.warn.index) {
      stderr.writeln('Confidence: $message');
    }
  }
}

final class ConfidenceStorageInspection {
  const ConfidenceStorageInspection({
    required this.pendingEvents,
    required this.pendingExposures,
    required this.droppedRecords,
    required this.cachedFlags,
  });
  final int pendingEvents;
  final int pendingExposures;
  final int droppedRecords;
  final int cachedFlags;
}

final Map<String, ProviderStorage> _stores = {};
Future<void> _mobilePreparation = Future.value();

Future<ProviderResources> _mobileResources(
  ConfidenceConfiguration config,
  String? domain, {
  JsonTransport? transport,
}) {
  final result = _mobilePreparation.then((_) async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      throw UnsupportedError('Confidence supports Android and iOS.');
    }
    final support = await getApplicationSupportDirectory();
    final root = Directory('${support.path}/confidence-dart');
    final identity = File('${root.path}/visitor.json');
    final legacy = await LegacyStorage.locate();
    String? visitor;
    try {
      final data = jsonDecode(await identity.readAsString());
      if (data is String && data.isNotEmpty) visitor = data;
    } on PathNotFoundException {
      /* First launch. */
    } on FormatException {
      await identity.delete();
    }
    visitor ??= await legacy.readVisitorId() ?? _newId();
    await ProviderStorage.atomicWrite(identity, jsonEncode(visitor));
    final scope = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              config.clientSecret,
              config.region.name,
              config.resolveBaseUrl?.toString(),
              domain,
            ]),
          ),
        )
        .toString();
    final directory = Directory('${root.path}/$scope');
    final storage = _stores.putIfAbsent(
      directory.path,
      () => ProviderStorage(directory),
    );
    if (domain == null) {
      await LegacyMigrator(
        platform: Platform.isIOS
            ? LegacyPlatform.swift
            : LegacyPlatform.android,
        flags: legacy.flags,
        apply: legacy.apply,
        events: legacy.events,
        readVisitorId: () async => visitor,
        destination: storage,
      ).run();
    }
    return ProviderResources(
      storage: storage,
      resolver: ConfidenceResolver(
        config,
        isIOS: Platform.isIOS,
        transport: transport,
      ),
      visitorId: visitor,
    );
  });
  _mobilePreparation = result.then<void>(
    (_) {},
    onError: (Object _, StackTrace _) {},
  );
  return result;
}

String _newId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
