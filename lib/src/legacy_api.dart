import 'confidence.dart';
import 'confidence_value.dart';
import 'flutter/confidence_flutter.dart';
import 'resolve_client.dart';

extension ConfidenceLegacyApi on Confidence {
  bool getBool(String key, bool defaultValue) =>
      getValue<bool>(key, defaultValue);

  String getString(String key, String defaultValue) =>
      getValue<String>(key, defaultValue);

  int getInt(String key, int defaultValue) => getValue<int>(key, defaultValue);

  double getDouble(String key, double defaultValue) =>
      getValue<double>(key, defaultValue);
}

enum LoggingLevel {
  VERBOSE,
  DEBUG,
  WARN,
  ERROR,
  NONE,
}

typedef ConfidenceFactory = Future<Confidence> Function(
  String clientSecret, {
  String? resolveBaseUrl,
});

class ConfidenceFlutterSdk {
  Confidence? _confidence;
  String? _apiKey;
  String? _resolveBaseUrl;
  Map<String, dynamic>? _pendingContext;
  final ConfidenceFactory _confidenceFactory;

  ConfidenceFlutterSdk({
    ConfidenceFactory? confidenceFactory,
  }) : _confidenceFactory = confidenceFactory ?? _defaultConfidenceFactory;

  Future<void> setup(String apiKey,
      [LoggingLevel loggingLevel = LoggingLevel.WARN,
      String? resolveBaseUrl]) async {
    _apiKey = apiKey;
    _resolveBaseUrl = resolveBaseUrl;
  }

  Future<void> putContext(String key, dynamic value) async {
    final c = _confidence;
    if (c != null) {
      c.putContextLocal(key, _toConfidenceValue(value));
      await c.fetchAndActivate();
    } else {
      _pendingContext ??= {};
      _pendingContext![key] = value;
    }
  }

  Future<void> putAllContext(Map<String, dynamic> context) async {
    final c = _confidence;
    if (c != null) {
      for (final entry in context.entries) {
        c.putContextLocal(entry.key, _toConfidenceValue(entry.value));
      }
      await c.fetchAndActivate();
    } else {
      _pendingContext ??= {};
      _pendingContext!.addAll(context);
    }
  }

  Future<void> fetchAndActivate() async {
    final c = await _ensureConfidence();
    await c.fetchAndActivate();
  }

  Future<void> activateAndFetchAsync() async {
    final c = await _ensureConfidence();
    await c.activateAndFetchAsync();
  }

  String getString(String key, String defaultValue) =>
      _confidence?.getValue<String>(key, defaultValue) ?? defaultValue;

  bool getBool(String key, bool defaultValue) =>
      _confidence?.getValue<bool>(key, defaultValue) ?? defaultValue;

  int getInt(String key, int defaultValue) =>
      _confidence?.getValue<int>(key, defaultValue) ?? defaultValue;

  double getDouble(String key, double defaultValue) =>
      _confidence?.getValue<double>(key, defaultValue) ?? defaultValue;

  Map<String, dynamic> getObject(
      String key, Map<String, dynamic> defaultValue) {
    final c = _confidence;
    if (c == null) return defaultValue;
    final resolution = c.currentResolution;
    if (resolution == null) return defaultValue;

    final parts = key.split('.');
    final flagName = parts[0];
    final flag = resolution.flags.where((f) => f.flag == flagName).firstOrNull;
    ConfidenceValue? value = flag?.value;
    for (final property in parts.skip(1)) {
      if (value is! ConfidenceValueStructure) return defaultValue;
      value = value.value[property];
    }
    if (value is! ConfidenceValueStructure) return defaultValue;
    return value.toPlainJson() as Map<String, dynamic>;
  }

  void track(String eventName, Map<String, dynamic> data) {
    _confidence?.track(
        eventName, data.map((k, v) => MapEntry(k, _toConfidenceValue(v))));
  }

  void flush() {
    _confidence?.flush();
  }

  Future<bool> isStorageEmpty() async => _confidence?.isStorageEmpty() ?? true;

  Future<Confidence> _ensureConfidence() async {
    final existing = _confidence;
    if (existing != null) return existing;

    final created = await _confidenceFactory(
      _apiKey ?? '',
      resolveBaseUrl: _resolveBaseUrl,
    );
    _confidence = created;
    _applyPendingContext(created);
    return created;
  }

  void _applyPendingContext(Confidence confidence) {
    final pendingContext = _pendingContext;
    if (pendingContext == null) return;

    for (final entry in pendingContext.entries) {
      confidence.putContextLocal(entry.key, _toConfidenceValue(entry.value));
    }
    _pendingContext = null;
  }

  static Future<Confidence> _defaultConfidenceFactory(
    String clientSecret, {
    String? resolveBaseUrl,
  }) async {
    return ConfidenceFlutter.create(
      clientSecret: clientSecret,
      region: ConfidenceRegion.eu,
      resolveBaseUrl: resolveBaseUrl,
    );
  }

  static ConfidenceValue _toConfidenceValue(dynamic value) {
    if (value is String) return ConfidenceValue.string(value);
    if (value is bool) return ConfidenceValue.boolean(value);
    if (value is int) return ConfidenceValue.integer(value);
    if (value is double) return ConfidenceValue.double_(value);
    if (value is Map<String, dynamic>) {
      return ConfidenceValue.structure(
          value.map((k, v) => MapEntry(k, _toConfidenceValue(v))));
    }
    if (value is List) {
      return ConfidenceValue.list(value.map(_toConfidenceValue).toList());
    }
    return ConfidenceValue.null_();
  }
}
