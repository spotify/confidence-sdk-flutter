import 'dart:convert';

import 'package:http/http.dart' as http;

import 'resolve_client.dart';
import 'sdk_metadata.dart' as sdk_meta;

class ApplyClient {
  final http.Client _httpClient;
  final String _clientSecret;
  final ConfidenceRegion _region;
  final String? _resolveBaseUrl;

  ApplyClient({
    required http.Client httpClient,
    required String clientSecret,
    required ConfidenceRegion region,
    String? resolveBaseUrl,
  })  : _httpClient = httpClient,
        _clientSecret = clientSecret,
        _region = region,
        _resolveBaseUrl = resolveBaseUrl;

  Future<bool> sendApply({
    required String flagName,
    required String resolveToken,
    required DateTime applyTime,
  }) async {
    final url = Uri.parse(
      '${_region.resolverEndpoint(_resolveBaseUrl)}/v1/flags:apply',
    );
    final now = DateTime.now().toUtc();

    final body = jsonEncode({
      'flags': [
        {
          'flag': 'flags/$flagName',
          'applyTime': applyTime.toUtc().toIso8601String(),
        },
      ],
      'sendTime': now.toIso8601String(),
      'clientSecret': _clientSecret,
      'resolveToken': resolveToken,
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

    return response.statusCode == 200;
  }
}
