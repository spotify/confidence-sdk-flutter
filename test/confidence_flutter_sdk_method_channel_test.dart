import 'package:confidence_flutter_sdk/confidence_flutter_sdk.dart';
import 'package:confidence_flutter_sdk/confidence_flutter_sdk_method_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannelConfidenceFlutterSdk platform;
  late List<MethodCall> methodCalls;

  setUp(() {
    platform = MethodChannelConfidenceFlutterSdk();
    methodCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform.methodChannel, (methodCall) async {
      methodCalls.add(methodCall);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform.methodChannel, null);
  });

  test('setup passes custom resolve base url to native SDKs', () async {
    await platform.setup(
      'api-key',
      LoggingLevel.DEBUG,
      'http://localhost:8090',
    );

    expect(methodCalls, hasLength(1));
    expect(methodCalls.single.method, 'setup');
    expect(methodCalls.single.arguments, <String, Object>{
      'apiKey': 'api-key',
      'loggingLevel': 'DEBUG',
      'resolveBaseUrl': 'http://localhost:8090',
    });
  });

  test('setup omits resolve base url when none is provided', () async {
    await platform.setup('api-key', LoggingLevel.WARN, null);

    expect(methodCalls, hasLength(1));
    expect(methodCalls.single.method, 'setup');
    expect(methodCalls.single.arguments, <String, Object>{
      'apiKey': 'api-key',
      'loggingLevel': 'WARN',
    });
  });

  test('track forwards the event name and typed data', () async {
    platform.track('my-event', <String, dynamic>{'plan': 'pro', 'seats': 3});

    await pumpEventQueue();

    expect(methodCalls, hasLength(1));
    expect(methodCalls.single.method, 'track');
    expect(methodCalls.single.arguments, <String, Object>{
      'eventName': 'my-event',
      'data': <String, Object>{
        'plan': <String, Object>{'type': 'string', 'value': 'pro'},
        'seats': <String, Object>{'type': 'int', 'value': 3},
      },
    });
  });

  test('flush completes once native replies', () async {
    // Native must reply to every flush call. Without a reply the future below
    // never completes, so this test would time out rather than fail an
    // assertion — which is exactly how the dangling reply went unnoticed.
    await platform.flush().timeout(const Duration(seconds: 5));

    expect(methodCalls, hasLength(1));
    expect(methodCalls.single.method, 'flush');
  });

  test('flush does not raise an unhandled async error when native fails',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform.methodChannel, (methodCall) async {
      methodCalls.add(methodCall);
      throw PlatformException(code: 'FLUSH_FAILED', message: 'boom');
    });

    // The platform interface types flush() as void, so callers discard this
    // future and an unguarded rejection would become an unhandled async error.
    // Awaiting it here asserts the guard directly: it must complete, not throw.
    await expectLater(platform.flush(), completes);

    expect(methodCalls, hasLength(1));
    expect(methodCalls.single.method, 'flush');
  });

  test('track does not raise an unhandled async error when native fails',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform.methodChannel, (methodCall) async {
      methodCalls.add(methodCall);
      throw PlatformException(code: 'TRACK_FAILED', message: 'boom');
    });

    // track() is void, so the future is never awaited by the caller. An
    // unguarded rejection would escape the test zone and fail this test.
    platform.track('my-event', <String, dynamic>{});

    await pumpEventQueue();

    expect(methodCalls, hasLength(1));
    expect(methodCalls.single.method, 'track');
  });

  // Values Confidence has no type for must reach native as a stringified
  // 'unknown', never as a number and never dropped. The native halves of this
  // contract (iOS convertValue, Android convert) cannot be exercised from
  // Dart, so what is pinned here is the wire format they rely on.
  group('unsupported tracking values keep their value', () {
    Map<String, dynamic> trackedData() {
      final args = methodCalls.single.arguments as Map<Object?, Object?>;
      return (args['data'] as Map<Object?, Object?>)
          .map((k, v) => MapEntry(k as String, v));
    }

    test('a DateTime is stringified, not coerced to a number', () {
      final now = DateTime.utc(2026, 9, 7, 12, 34, 56);
      platform.track('my_event', {'ts': now});

      final ts = trackedData()['ts'] as Map<Object?, Object?>;
      expect(ts['type'], 'unknown');
      expect(ts['value'], now.toString());
      expect(ts['value'], isNot(0));
    });

    test('a null keeps a value and the key is not dropped', () {
      platform.track('my_event', {'maybe': null});

      final data = trackedData();
      expect(data.containsKey('maybe'), isTrue,
          reason: 'the key must survive so the caller can see what was sent');
      final maybe = data['maybe'] as Map<Object?, Object?>;
      expect(maybe['type'], 'unknown');
      expect(maybe['value'], isNot(0));
    });

    test('supported types are unaffected', () {
      platform.track('my_event', {'n': 7, 's': 'x', 'b': true, 'd': 1.5});

      final data = trackedData();
      expect((data['n'] as Map<Object?, Object?>)['type'], 'int');
      expect((data['s'] as Map<Object?, Object?>)['type'], 'string');
      expect((data['b'] as Map<Object?, Object?>)['type'], 'bool');
      expect((data['d'] as Map<Object?, Object?>)['type'], 'double');
    });
  });
}
