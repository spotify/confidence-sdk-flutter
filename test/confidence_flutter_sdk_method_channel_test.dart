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
}
