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

class ResolveClient {
  final http.Client _httpClient;
  final String _clientSecret;
  final ConfidenceRegion _region;

  ResolveClient({
    required http.Client httpClient,
    required String clientSecret,
    required ConfidenceRegion region,
  })  : _httpClient = httpClient,
        _clientSecret = clientSecret,
        _region = region;

  Future<FlagResolution> resolve(
    Map<String, ConfidenceValue> context,
  ) async {
    final url = Uri.parse('${_region.resolverBaseUrl}/v1/flags:resolve');

    final plainContext =
        context.map((k, v) => MapEntry(k, v.toPlainJson()));

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
      value = ConfidenceValue.fromJson(valueJson) as ConfidenceValueStructure;
    }

    return ResolvedFlag(
      flag: flagName,
      variant: json['variant'] as String? ?? '',
      value: value,
      reason: ResolveReason.fromString(json['reason'] as String? ?? ''),
      shouldApply: json['shouldApply'] as bool? ?? true,
    );
  }
}

class ResolveException implements Exception {
  final String message;
  ResolveException(this.message);

  @override
  String toString() => 'ResolveException: $message';
}
