import 'dart:convert';

import 'package:http/http.dart' as http;

import 'confidence_value.dart';
import 'flag_resolution.dart';
import 'evaluation.dart';
import 'sdk_metadata.dart' as sdk_meta;

enum ConfidenceRegion {
  global,
  eu,
  us;

  String get resolverBaseUrl => switch (this) {
        ConfidenceRegion.global => 'https://resolver.confidence.dev',
        ConfidenceRegion.eu => 'https://resolver.eu.confidence.dev',
        ConfidenceRegion.us => 'https://resolver.us.confidence.dev',
      };

  String get eventsBaseUrl => switch (this) {
        ConfidenceRegion.global => 'https://events.confidence.dev',
        ConfidenceRegion.eu => 'https://events.eu.confidence.dev',
        ConfidenceRegion.us => 'https://events.us.confidence.dev',
      };
}

extension ConfidenceRegionEndpoints on ConfidenceRegion {
  String resolverEndpoint([String? resolveBaseUrl]) =>
      _stripTrailingSlashes(resolveBaseUrl ?? resolverBaseUrl);
}

String _stripTrailingSlashes(String url) =>
    url.replaceFirst(RegExp(r'/+$'), '');

class ResolveClient {
  final http.Client _httpClient;
  final String _clientSecret;
  final ConfidenceRegion _region;
  final String? _resolveBaseUrl;

  ResolveClient({
    required http.Client httpClient,
    required String clientSecret,
    required ConfidenceRegion region,
    String? resolveBaseUrl,
  })  : _httpClient = httpClient,
        _clientSecret = clientSecret,
        _region = region,
        _resolveBaseUrl = resolveBaseUrl;

  Future<FlagResolution> resolve(
    Map<String, ConfidenceValue> context,
  ) async {
    final url = Uri.parse(
      '${_region.resolverEndpoint(_resolveBaseUrl)}/v1/flags:resolve',
    );

    final plainContext = context.map((k, v) => MapEntry(k, v.toPlainJson()));

    final body = jsonEncode({
      'flags': <String>[],
      'evaluationContext': plainContext,
      'clientSecret': _clientSecret,
      'apply': false,
      'sdk': sdk_meta.sdkInfo(),
    });

    final response = await _httpClient.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: body,
    );

    if (response.statusCode != 200) {
      throw ResolveException(
        'Resolve failed with status ${response.statusCode}: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return _parseResponse(json);
  }

  FlagResolution _parseResponse(Map<String, dynamic> json) {
    final resolvedFlags = (json['resolvedFlags'] as List?)
            ?.map((f) => _parseResolvedFlag(f as Map<String, dynamic>))
            .toList() ??
        [];

    return FlagResolution(
      flags: resolvedFlags,
      resolveToken: json['resolveToken'] as String? ?? '',
    );
  }

  ResolvedFlag _parseResolvedFlag(Map<String, dynamic> json) {
    final rawFlag = json['flag'] as String? ?? '';
    final flagName =
        rawFlag.startsWith('flags/') ? rawFlag.substring(6) : rawFlag;

    final valueJson = json['value'];
    ConfidenceValueStructure? value;
    if (valueJson != null && valueJson is Map<String, dynamic>) {
      value = _parseValue(valueJson, {'structSchema': json['flagSchema']})
          as ConfidenceValueStructure;
    }

    return ResolvedFlag(
      flag: flagName,
      variant: json['variant'] as String? ?? '',
      value: value,
      reason: ResolveReason.fromString(json['reason'] as String? ?? ''),
      shouldApply: json['shouldApply'] as bool? ?? true,
    );
  }

  // JSON numbers do not carry the flag's declared numeric type. Use the
  // resolver schema, as the native SDKs do, including nested fields/lists.
  ConfidenceValue _parseValue(dynamic value, Map<String, dynamic>? schema) {
    if (value is num) {
      if (schema?.containsKey('doubleSchema') ?? false) {
        return ConfidenceValue.double_(value.toDouble());
      }
      if (schema?.containsKey('intSchema') ?? false) {
        return ConfidenceValue.integer(value.toInt());
      }
    }
    if (value is Map<String, dynamic>) {
      final fields =
          schema?['structSchema']?['schema'] as Map<String, dynamic>?;
      return ConfidenceValue.structure(value.map((key, value) => MapEntry(
          key, _parseValue(value, fields?[key] as Map<String, dynamic>?))));
    }
    if (value is List) {
      final elementSchema = schema?['listSchema'] as Map<String, dynamic>?;
      return ConfidenceValue.list(
          value.map((item) => _parseValue(item, elementSchema)).toList());
    }
    return ConfidenceValue.fromJson(value);
  }
}

class ResolveException implements Exception {
  final String message;
  ResolveException(this.message);

  @override
  String toString() => 'ResolveException: $message';
}
