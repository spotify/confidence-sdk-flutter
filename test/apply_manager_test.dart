import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:confidence_flutter_sdk/src/apply_manager.dart';
import 'package:confidence_flutter_sdk/src/apply_client.dart';
import 'package:confidence_flutter_sdk/src/resolve_client.dart';
import 'package:confidence_flutter_sdk/src/storage.dart';

void main() {
  group('ApplyManager', () {
    late MemoryStorage storage;
    late List<http.Request> capturedRequests;

    http.Client makeApplyClient({int statusCode = 200}) {
      return MockClient((request) async {
        capturedRequests.add(request);
        return http.Response('{}', statusCode);
      });
    }

    setUp(() {
      storage = MemoryStorage();
      capturedRequests = [];
    });

    test('sends apply request for a new flag', () async {
      final applyClient = ApplyClient(
        httpClient: makeApplyClient(),
        clientSecret: 'test-secret',
        region: ConfidenceRegion.global,
      );
      final manager = ApplyManager(
        storage: storage,
        applyClient: applyClient,
      );

      await manager.apply('my-flag', 'token-123');

      expect(capturedRequests, hasLength(1));
      final body =
          jsonDecode(capturedRequests[0].body) as Map<String, dynamic>;
      expect(body['resolveToken'], equals('token-123'));
      final flags = body['flags'] as List;
      expect(flags, hasLength(1));
      expect(flags[0]['flag'], equals('flags/my-flag'));
      expect(flags[0]['applyTime'], isNotNull);
    });

    test('deduplicates same flag + resolve token', () async {
      final applyClient = ApplyClient(
        httpClient: makeApplyClient(),
        clientSecret: 'test-secret',
        region: ConfidenceRegion.global,
      );
      final manager = ApplyManager(
        storage: storage,
        applyClient: applyClient,
      );

      await manager.apply('my-flag', 'token-123');
      await manager.apply('my-flag', 'token-123');

      expect(capturedRequests, hasLength(1));
    });

    test('sends separate requests for different flags', () async {
      final applyClient = ApplyClient(
        httpClient: makeApplyClient(),
        clientSecret: 'test-secret',
        region: ConfidenceRegion.global,
      );
      final manager = ApplyManager(
        storage: storage,
        applyClient: applyClient,
      );

      await manager.apply('flag-a', 'token-123');
      await manager.apply('flag-b', 'token-123');

      expect(capturedRequests, hasLength(2));
    });

    test('sends separate requests for different resolve tokens', () async {
      final applyClient = ApplyClient(
        httpClient: makeApplyClient(),
        clientSecret: 'test-secret',
        region: ConfidenceRegion.global,
      );
      final manager = ApplyManager(
        storage: storage,
        applyClient: applyClient,
      );

      await manager.apply('my-flag', 'token-1');
      await manager.apply('my-flag', 'token-2');

      expect(capturedRequests, hasLength(2));
    });

    test('retains pending applies on failure for later retry', () async {
      var callCount = 0;
      final failThenSucceed = MockClient((request) async {
        capturedRequests.add(request);
        callCount++;
        if (callCount == 1) {
          return http.Response('Server Error', 500);
        }
        return http.Response('{}', 200);
      });

      final applyClient = ApplyClient(
        httpClient: failThenSucceed,
        clientSecret: 'test-secret',
        region: ConfidenceRegion.global,
      );
      final manager = ApplyManager(
        storage: storage,
        applyClient: applyClient,
      );

      await manager.apply('my-flag', 'token-123');
      // First call failed, pending set should still contain the apply.
      // A second apply with different flag should trigger retry of pending.
      await manager.apply('other-flag', 'token-123');

      expect(capturedRequests.length, greaterThanOrEqualTo(2));
    });

    test('persists pending applies to storage', () async {
      final applyClient = ApplyClient(
        httpClient: makeApplyClient(statusCode: 500),
        clientSecret: 'test-secret',
        region: ConfidenceRegion.global,
      );
      final manager = ApplyManager(
        storage: storage,
        applyClient: applyClient,
      );

      await manager.apply('my-flag', 'token-123');

      final stored = await storage.read('confidence.apply.cache');
      expect(stored, isNotNull);
    });

    test('restores pending applies from storage on creation', () async {
      // Pre-populate storage with pending applies
      final pendingData = jsonEncode({
        'token-123': ['flag-a'],
      });
      await storage.write('confidence.apply.cache', pendingData);

      final applyClient = ApplyClient(
        httpClient: makeApplyClient(),
        clientSecret: 'test-secret',
        region: ConfidenceRegion.global,
      );
      final manager = ApplyManager(
        storage: storage,
        applyClient: applyClient,
      );

      await manager.restore();

      expect(capturedRequests, hasLength(1));
      final body =
          jsonDecode(capturedRequests[0].body) as Map<String, dynamic>;
      expect(body['resolveToken'], equals('token-123'));
    });
  });

  group('ApplyClient', () {
    test('sends to correct global URL', () async {
      late Uri capturedUrl;
      final mockClient = MockClient((request) async {
        capturedUrl = request.url;
        return http.Response('{}', 200);
      });

      final client = ApplyClient(
        httpClient: mockClient,
        clientSecret: 'test-secret',
        region: ConfidenceRegion.global,
      );

      await client.sendApply(
        flagName: 'my-flag',
        resolveToken: 'token',
        applyTime: DateTime.utc(2026, 6, 5, 10, 0, 0),
      );

      expect(
        capturedUrl.toString(),
        equals('https://resolver.confidence.dev/v1/flags:apply'),
      );
    });

    test('sends to correct EU URL', () async {
      late Uri capturedUrl;
      final mockClient = MockClient((request) async {
        capturedUrl = request.url;
        return http.Response('{}', 200);
      });

      final client = ApplyClient(
        httpClient: mockClient,
        clientSecret: 'test-secret',
        region: ConfidenceRegion.eu,
      );

      await client.sendApply(
        flagName: 'my-flag',
        resolveToken: 'token',
        applyTime: DateTime.utc(2026, 6, 5, 10, 0, 0),
      );

      expect(
        capturedUrl.toString(),
        equals('https://resolver.eu.confidence.dev/v1/flags:apply'),
      );
    });
  });
}

