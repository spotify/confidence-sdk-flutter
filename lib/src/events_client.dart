import 'dart:convert';

import 'package:http/http.dart' as http;

import 'confidence_value.dart';
import 'async_gate.dart';
import 'storage.dart';
import 'resolve_client.dart';
import 'sdk_metadata.dart' as sdk_meta;

class EventsClient {
  static const legacyStorageKey = 'confidence.events.migrated';
  final Storage? _storage;
  final AsyncGate _gate = AsyncGate();
  final http.Client _httpClient;
  final String _clientSecret;
  final ConfidenceRegion _region;

  EventsClient({
    required http.Client httpClient,
    required String clientSecret,
    required ConfidenceRegion region,
    Storage? storage,
  })  : _storage = storage,
        _httpClient = httpClient,
        _clientSecret = clientSecret,
        _region = region;

  Future<void> send({
    required String eventName,
    required Map<String, ConfidenceValue> payload,
    Map<String, ConfidenceValue> context = const {},
  }) async {
    final now = DateTime.now().toUtc();

    final plainPayload = payload.map((k, v) => MapEntry(k, v.toPlainJson()));

    if (context.isNotEmpty) {
      plainPayload['context'] =
          context.map((k, v) => MapEntry(k, v.toPlainJson()));
    }

    await _publish([
      {
        'eventDefinition': 'eventDefinitions/$eventName',
        'eventTime': now.toIso8601String(),
        'payload': plainPayload,
      }
    ]);
  }

  Future<void> restore() => _gate.run(() async {
        final storage = _storage;
        if (storage == null) return;
        final saved = await storage.read(legacyStorageKey);
        if (saved == null) return;
        List<Map<String, dynamic>> events;
        try {
          events = (jsonDecode(saved) as List).cast<Map<String, dynamic>>();
        } on FormatException {
          return;
        } on TypeError {
          return;
        }
        if (events.isNotEmpty && await _publish(events)) {
          // Empty is an import receipt; deleting it would replay the native files.
          await storage.write(legacyStorageKey, '[]');
        }
      });

  Future<bool> _publish(List<Map<String, dynamic>> events) async {
    final url = Uri.parse('${_region.eventsBaseUrl}/v1/events:publish');
    final body = jsonEncode({
      'clientSecret': _clientSecret,
      'events': events,
      'sendTime': DateTime.now().toUtc().toIso8601String(),
      'sdk': sdk_meta.sdkInfo(),
    });

    try {
      final response = await _httpClient.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: body,
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
