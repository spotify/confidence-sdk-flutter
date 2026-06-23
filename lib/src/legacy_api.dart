import 'confidence.dart';
import 'confidence_value.dart';
import 'resolve_client.dart';
import 'storage.dart';

extension ConfidenceLegacyApi on Confidence {
  bool getBool(String key, bool defaultValue) =>
      getValue<bool>(key, defaultValue);

  String getString(String key, String defaultValue) =>
      getValue<String>(key, defaultValue);

  int getInt(String key, int defaultValue) =>
      getValue<int>(key, defaultValue);

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

class ConfidenceFlutterSdk {
  Confidence? _confidence;
  String? _apiKey;

  Future<void> setup(String apiKey,
      [LoggingLevel loggingLevel = LoggingLevel.WARN]) async {
    _apiKey = apiKey;
  }

  Future<void> putContext(String key, dynamic value) async {
    _confidence?.putContextLocal(key, _toConfidenceValue(value));
  }

  Future<void> putAllContext(Map<String, dynamic> context) async {
    final c = _confidence;
    if (c != null) {
      for (final entry in context.entries) {
        c.putContextLocal(entry.key, _toConfidenceValue(entry.value));
      }
    } else {
      _pendingContext = context;
    }
  }

  Map<String, dynamic>? _pendingContext;

  Future<void> fetchAndActivate() async {
    _confidence ??= _buildConfidence();
    final c = _confidence!;
    if (_pendingContext != null) {
      for (final entry in _pendingContext!.entries) {
        c.putContextLocal(entry.key, _toConfidenceValue(entry.value));
      }
      _pendingContext = null;
    }
    await c.fetchAndActivate();
  }

  Future<void> activateAndFetchAsync() async {
    _confidence ??= _buildConfidence();
    await _confidence!.activateAndFetchAsync();
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
      String key, Map<String, dynamic> defaultValue) =>
      defaultValue;

  void track(String eventName, Map<String, dynamic> data) {
    _confidence?.track(eventName,
        data.map((k, v) => MapEntry(k, _toConfidenceValue(v))));
  }

  void flush() {
    _confidence?.flush();
  }

  Future<bool> isStorageEmpty() async => true;

  Confidence _buildConfidence() {
    return Confidence.builder(clientSecret: _apiKey ?? '')
        .region(ConfidenceRegion.eu)
        .storage(MemoryStorage())
        .build();
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
