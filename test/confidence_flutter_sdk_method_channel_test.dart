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
}
