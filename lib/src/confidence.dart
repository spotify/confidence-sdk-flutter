import 'dart:convert';

import 'package:http/http.dart' as http;

import 'confidence_value.dart';
import 'evaluation.dart';
import 'flag_resolution.dart';
import 'resolve_client.dart';
import 'storage.dart';

class Confidence {
  final _ConfidenceState _state;
  final Confidence? _parent;
  final Map<String, ConfidenceValue> _localContext;
  final Set<String> _removedKeys;

  Confidence._({
    required _ConfidenceState state,
    Confidence? parent,
    Map<String, ConfidenceValue> localContext = const {},
    Set<String> removedKeys = const {},
  })  : _state = state,
        _parent = parent,
        _localContext = Map.of(localContext),
        _removedKeys = Set.of(removedKeys);

  static ConfidenceBuilder builder({required String clientSecret}) =>
      ConfidenceBuilder._(clientSecret: clientSecret);

  // -- Flag lifecycle --

  Future<void> fetchAndActivate() async {
    final resolution = await _state.resolveClient.resolve(getContext());
    await _state.storage.write(
      'confidence.flags.resolve',
      jsonEncode(resolution.toJson()),
    );
    _state.currentResolution = resolution;
  }

  Future<void> activate() async {
    final stored = await _state.storage.read('confidence.flags.resolve');
    if (stored != null) {
      final json = jsonDecode(stored) as Map<String, dynamic>;
      _state.currentResolution = FlagResolution.fromJson(json);
    }
  }

  Future<void> asyncFetch() async {
    final resolution = await _state.resolveClient.resolve(getContext());
    await _state.storage.write(
      'confidence.flags.resolve',
      jsonEncode(resolution.toJson()),
    );
  }

  Future<void> activateAndFetchAsync() async {
    await activate();
    // Fire-and-forget background fetch
    asyncFetch().ignore();
  }

  // -- Flag evaluation --

  T getValue<T>(String flagPath, T defaultValue) =>
      getFlag<T>(flagPath, defaultValue).value;

  Evaluation<T> getFlag<T>(String flagPath, T defaultValue) {
    final resolution = _state.currentResolution;
    if (resolution == null) {
      return Evaluation(
        value: defaultValue,
        reason: ResolveReason.error,
        errorCode: 'NOT_READY',
        errorMessage: 'No flag resolution available. Call fetchAndActivate() or activate() first.',
      );
    }
    return resolution.evaluate<T>(flagPath, defaultValue);
  }

  // -- Context management --

  Map<String, ConfidenceValue> getContext() {
    final parentContext = _parent?.getContext() ?? {};
    final merged = Map<String, ConfidenceValue>.from(parentContext)
      ..addAll(_localContext);
    for (final key in _removedKeys) {
      merged.remove(key);
    }
    return merged;
  }

  void putContext(String key, ConfidenceValue value) {
    _localContext[key] = value;
    _removedKeys.remove(key);
    _triggerRefetch();
  }

  void putContextLocal(String key, ConfidenceValue value) {
    _localContext[key] = value;
    _removedKeys.remove(key);
  }

  void removeContext(String key) {
    _localContext.remove(key);
    _removedKeys.add(key);
    _triggerRefetch();
  }

  Confidence withContext(Map<String, ConfidenceValue> context) {
    return Confidence._(
      state: _state,
      parent: this,
      localContext: context,
    );
  }

  void _triggerRefetch() {
    fetchAndActivate().ignore();
  }
}

class ConfidenceBuilder {
  final String _clientSecret;
  ConfidenceRegion _region = ConfidenceRegion.global;
  Storage? _storage;
  http.Client? _httpClient;
  Map<String, ConfidenceValue> _initialContext = {};

  ConfidenceBuilder._({required String clientSecret})
      : _clientSecret = clientSecret;

  ConfidenceBuilder region(ConfidenceRegion region) {
    _region = region;
    return this;
  }

  ConfidenceBuilder storage(Storage storage) {
    _storage = storage;
    return this;
  }

  ConfidenceBuilder httpClient(http.Client client) {
    _httpClient = client;
    return this;
  }

  ConfidenceBuilder initialContext(Map<String, ConfidenceValue> context) {
    _initialContext = context;
    return this;
  }

  Confidence build() {
    final storage = _storage ?? MemoryStorage();
    final httpClient = _httpClient ?? http.Client();

    final resolveClient = ResolveClient(
      httpClient: httpClient,
      clientSecret: _clientSecret,
      region: _region,
    );

    final state = _ConfidenceState(
      storage: storage,
      resolveClient: resolveClient,
    );

    return Confidence._(
      state: state,
      localContext: _initialContext,
    );
  }
}

class _ConfidenceState {
  final Storage storage;
  final ResolveClient resolveClient;
  FlagResolution? currentResolution;

  _ConfidenceState({
    required this.storage,
    required this.resolveClient,
  });
}
