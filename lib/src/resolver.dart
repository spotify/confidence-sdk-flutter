import 'dart:convert';

import 'configuration.dart';
import 'endpoints.dart';
import 'snapshot.dart';
import 'transport.dart';

const providerVersion = '0.0.1-dev.1'; // x-release-please-version

final class ConfidenceResolver {
  ConfidenceResolver(
    this.configuration, {
    required bool isIOS,
    JsonTransport? transport,
  }) : endpoints = ConfidenceEndpoints(configuration),
       sdk = Map.unmodifiable({
         'id': isIOS
             ? 'SDK_ID_FLUTTER_IOS_CONFIDENCE'
             : 'SDK_ID_FLUTTER_ANDROID_CONFIDENCE',
         'version': providerVersion,
       }),
       transport = transport ?? IoTransport();
  final ConfidenceConfiguration configuration;
  final ConfidenceEndpoints endpoints;
  final Map<String, String> sdk;
  final JsonTransport transport;

  Future<FlagSnapshot> resolve(Map<String, Object?> context) async {
    final frozen = freezeValue(context) as Map<String, Object?>;
    final response = await transport.post(endpoints.resolve, {
      'clientSecret': configuration.apiKey,
      'evaluationContext': wireValue(frozen),
      'flags': <String>[],
      'apply': false,
      'sdk': sdk,
    });
    if (response.status != 200) throw ResolveException(status: response.status);
    try {
      return decodeResolution(jsonDecode(response.body), frozen);
    } on FormatException {
      throw const ResolveException();
    }
  }

  void close() => transport.close();
}

/// Confidence protobuf Struct values use JSON scalars; timestamps are UTC text.
Object? wireValue(Object? value) => switch (value) {
  null || bool() || String() => value,
  num() when value.isFinite => value,
  DateTime() => value.toUtc().toIso8601String(),
  List<Object?>() => value.map(wireValue).toList(),
  Map<String, Object?>() => value.map((k, v) => MapEntry(k, wireValue(v))),
  _ => throw const FormatException('Unsupported Confidence context value.'),
};

final class ResolveException implements Exception {
  const ResolveException({this.status});
  final int? status;
  @override
  String toString() => status == null
      ? 'Invalid Confidence resolve response.'
      : 'Confidence resolve failed (HTTP $status).';
}

FlagSnapshot decodeResolution(Object? input, Map<String, Object?> context) {
  final root = _map(input);
  final flags = <String, ResolvedFlag>{};
  final entries = root['resolvedFlags'] ?? <Object?>[];
  if (entries is! List) _invalid();
  for (final input in entries) {
    final flag = _map(input);
    final resource = _string(flag['flag']);
    if (!RegExp(r'^flags/[^/.]+$').hasMatch(resource)) _invalid();
    final name = resource.substring(6);
    if (flags.containsKey(name)) _invalid();
    final schema = flag['flagSchema'];
    final value = flag['value'];
    Object? decoded;
    if (schema == null) {
      if (value != null && _map(value).isNotEmpty) _invalid();
    } else {
      decoded = value == null ? null : _structure(value, schema);
    }
    final apply = flag['shouldApply'] ?? false; // Protobuf bool default.
    if (apply is! bool) _invalid();
    flags[name] = ResolvedFlag(
      name: name,
      value: decoded,
      reason: _string(flag['reason'] ?? 'RESOLVE_REASON_UNSPECIFIED'),
      variant: flag['variant'] == null ? null : _string(flag['variant']),
      shouldApply: apply,
    );
  }
  return FlagSnapshot(
    context: context,
    flags: flags,
    resolveToken: _string(root['resolveToken'] ?? ''),
  );
}

Map<String, Object?> _structure(Object? input, Object? schema) {
  final fields = _map(input);
  final types = _map(_map(schema)['schema'] ?? <String, Object?>{});
  return fields.map((key, value) {
    if (!types.containsKey(key)) _invalid();
    return MapEntry(key, _typed(value, types[key]));
  });
}

Object? _typed(Object? value, Object? input) {
  final schema = _map(input);
  if (schema.length != 1) _invalid();
  final type = schema.keys.single;
  final definition = _map(schema[type]);
  if (!const {
    'boolSchema',
    'stringSchema',
    'intSchema',
    'doubleSchema',
    'structSchema',
    'listSchema',
  }.contains(type)) {
    _invalid();
  }
  if (value == null) return null;
  return switch (type) {
    'boolSchema' => value is bool ? value : _invalid(),
    'stringSchema' => value is String ? value : _invalid(),
    'intSchema' => _integer(value),
    'doubleSchema' =>
      value is num && value.isFinite ? value.toDouble() : _invalid(),
    'structSchema' => _structure(value, definition),
    'listSchema' =>
      value is List
          ? value.map((v) => _typed(v, definition['elementSchema'])).toList()
          : _invalid(),
    _ => _invalid(),
  };
}

int _integer(Object value) {
  if (value is int) return value;
  if (value is! double ||
      !value.isFinite ||
      value % 1 != 0 ||
      value < -9223372036854775808.0 ||
      value >= 9223372036854775808.0) {
    _invalid();
  }
  return value.toInt();
}

Map<String, Object?> _map(Object? v) =>
    v is Map<String, Object?> ? v : _invalid();
String _string(Object? v) => v is String ? v : _invalid();
Never _invalid() =>
    throw const FormatException('Invalid Confidence resolve response.');
