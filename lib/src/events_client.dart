import 'dart:convert';

import 'package:http/http.dart' as http;

import 'confidence_value.dart';
import 'resolve_client.dart';
import 'sdk_metadata.dart' as sdk_meta;

class EventsClient {
  final http.Client _httpClient;
  final String _clientSecret;
  final ConfidenceRegion _region;

  EventsClient({
    required http.Client httpClient,
    required String clientSecret,
    required ConfidenceRegion region,
  })  : _httpClient = httpClient,
        _clientSecret = clientSecret,
        _region = region;

  Future<void> send({
    required String eventName,
    required Map<String, ConfidenceValue> payload,
    Map<String, ConfidenceValue> context = const {},
  }) async {
    final url = Uri.parse('${_region.eventsBaseUrl}/v1/events:publish');
    final now = DateTime.now().toUtc();

    final plainPayload =
        payload.map((k, v) => MapEntry(k, v.toPlainJson()));

    if (context.isNotEmpty) {
      plainPayload['context'] =
          context.map((k, v) => MapEntry(k, v.toPlainJson()));
    }

    final body = jsonEncode({
      'clientSecret': _clientSecret,
      'events': [
        {
          'eventDefinition': 'eventDefinitions/$eventName',
          'eventTime': now.toIso8601String(),
          'payload': plainPayload,
        },
      ],
      'sendTime': now.toIso8601String(),
      'sdk': sdk_meta.sdkInfo(),
    });

    try {
      await _httpClient.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: body,
      );
    } catch (_) {
      // Best-effort: swallow errors
    }
  }
}
