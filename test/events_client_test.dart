import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:confidence_flutter_sdk/src/confidence_value.dart';
import 'package:confidence_flutter_sdk/src/events_client.dart';
import 'package:confidence_flutter_sdk/src/resolve_client.dart';

void main() {
  group('EventsClient', () {
    const clientSecret = 'test-secret';

    test('sends event to correct global URL', () async {
      late Uri capturedUrl;
      final mockClient = MockClient((request) async {
        capturedUrl = request.url;
        return http.Response('{}', 200);
      });

      final client = EventsClient(
        httpClient: mockClient,
        clientSecret: clientSecret,
        region: ConfidenceRegion.global,
      );

      await client.send(
        eventName: 'purchase',
        payload: {},
      );

      expect(
        capturedUrl.toString(),
        equals('https://events.confidence.dev/v1/events:publish'),
      );
    });

    test('sends event to correct EU URL', () async {
      late Uri capturedUrl;
      final mockClient = MockClient((request) async {
        capturedUrl = request.url;
        return http.Response('{}', 200);
      });

      final client = EventsClient(
        httpClient: mockClient,
        clientSecret: clientSecret,
        region: ConfidenceRegion.eu,
      );

      await client.send(
        eventName: 'purchase',
        payload: {},
      );

      expect(
        capturedUrl.toString(),
        equals('https://events.eu.confidence.dev/v1/events:publish'),
      );
    });

    test('sends correct request format', () async {
      late Map<String, dynamic> capturedBody;
      final mockClient = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{}', 200);
      });

      final client = EventsClient(
        httpClient: mockClient,
        clientSecret: clientSecret,
        region: ConfidenceRegion.global,
      );

      await client.send(
        eventName: 'purchase',
        payload: {
          'amount': ConfidenceValue.double_(99.99),
          'currency': ConfidenceValue.string('USD'),
        },
      );

      expect(capturedBody['clientSecret'], equals(clientSecret));
      expect(capturedBody['sendTime'], isNotNull);
      expect(capturedBody['sdk'], isA<Map>());

      final events = capturedBody['events'] as List;
      expect(events, hasLength(1));

      final event = events[0] as Map<String, dynamic>;
      expect(
        event['eventDefinition'],
        equals('eventDefinitions/purchase'),
      );
      expect(event['eventTime'], isNotNull);
      expect(event['payload'], isA<Map>());
      expect(event['payload']['amount'], equals(99.99));
      expect(event['payload']['currency'], equals('USD'));
    });

    test('merges context into payload', () async {
      late Map<String, dynamic> capturedBody;
      final mockClient = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{}', 200);
      });

      final client = EventsClient(
        httpClient: mockClient,
        clientSecret: clientSecret,
        region: ConfidenceRegion.global,
      );

      await client.send(
        eventName: 'navigate',
        payload: {
          'screen': ConfidenceValue.string('home'),
        },
        context: {
          'targeting_key': ConfidenceValue.string('user-123'),
          'country': ConfidenceValue.string('SE'),
        },
      );

      final events = capturedBody['events'] as List;
      final payload = events[0]['payload'] as Map<String, dynamic>;
      expect(payload['screen'], equals('home'));
      expect(payload['context'], isA<Map>());
      expect(
        (payload['context'] as Map)['targeting_key'],
        equals('user-123'),
      );
    });

    test('does not throw on HTTP 500 (best-effort)', () async {
      final mockClient = MockClient((_) async {
        return http.Response('Server Error', 500);
      });

      final client = EventsClient(
        httpClient: mockClient,
        clientSecret: clientSecret,
        region: ConfidenceRegion.global,
      );

      // Should not throw — best-effort fire-and-forget
      await client.send(
        eventName: 'purchase',
        payload: {},
      );
    });

    test('sends event with empty payload', () async {
      late Map<String, dynamic> capturedBody;
      final mockClient = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{}', 200);
      });

      final client = EventsClient(
        httpClient: mockClient,
        clientSecret: clientSecret,
        region: ConfidenceRegion.global,
      );

      await client.send(eventName: 'page_view', payload: {});

      final events = capturedBody['events'] as List;
      expect(events[0]['payload'], isA<Map>());
    });
  });
}

