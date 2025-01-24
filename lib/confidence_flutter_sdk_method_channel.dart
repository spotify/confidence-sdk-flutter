import 'package:confidence_flutter_sdk/confidence_flutter_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:convert';

import 'confidence_flutter_sdk_platform_interface.dart';

/// An implementation of [ConfidenceFlutterSdkPlatform] that uses method channels.
class MethodChannelConfidenceFlutterSdk extends ConfidenceFlutterSdkPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('confidence_flutter_sdk');

  @override
  Future<void> setup(String apiKey, LoggingLevel loggingLevel) async {
    return await methodChannel.invokeMethod<void>('setup', {'apiKey': apiKey, 'loggingLevel': loggingLevel.name});
  }

  @override
  Future<void> fetchAndActivate() async {
    return await methodChannel.invokeMethod<void>('fetchAndActivate');
  }

  @override
  Future<void> activateAndFetchAsync() async {
    return await methodChannel.invokeMethod<void>('activateAndFetchAsync');
  }

  @override
  Future<void> putContext(String key, dynamic value) async {
    final wrappedValue = toTypedValue(value);
    await methodChannel
        .invokeMethod<void>(
        'putContext',
        {'key': key, 'value': wrappedValue}
    );
  }

  @override
  Future<void> putAllContext(Map<String, dynamic> context) async {
    final wrappedContext = context.map((key, value) {
      return MapEntry(key, toTypedValue(value));
    });
    await methodChannel
        .invokeMethod<void>(
        'putAllContext',
        {'context': wrappedContext}
    );
  }

  @override
  void track(String eventName, Map<String, dynamic> data) {
    final wrappedData = data.map((key, value) {
      return MapEntry(key, toTypedValue(value));
    });
    if (kDebugMode) {
      print(wrappedData);
    }
    methodChannel
        .invokeMethod<void>(
        'track',
        {'eventName': eventName, 'data': wrappedData}
    );
  }

  @override
  Future<bool> isStorageEmpty() async {
    final value = await methodChannel.invokeMethod<bool>('isStorageEmpty');
    return value!;
  }

  @override
  Future<Map<String, dynamic>> readAllFlags() async {
    final value = await methodChannel.invokeMethod<String>('readAllFlags');
    return value != null ? jsonDecode(value) : {};
  }

  @override
  Future<Map<String, dynamic>> getObject(String key, Map<String, dynamic> defaultValue) async {
    final wrappedDefaultValue = defaultValue.map((key, value) {
      return MapEntry(key, toTypedValue(value));
    });

    final value = await methodChannel
        .invokeMethod<String>(
        'getObject',
        {'key': key, 'defaultValue': wrappedDefaultValue}
    );
    return value != null ? jsonDecode(value) : {};
  }

  @override
  Future<bool> getBool(String key, bool defaultValue) async {
    final value = await methodChannel
        .invokeMethod<bool>(
        'getBool',
        {'key': key, 'defaultValue': defaultValue}
    );
    return value!;
  }

  @override
  Future<String> getString(String key, String defaultValue) async {
    final value = await methodChannel
        .invokeMethod<String>(
        'getString',
        {'key': key, 'defaultValue': defaultValue}
    );
    return value!;
  }

  @override
  Future<double> getDouble(String key, double defaultValue) async {
    final value = await methodChannel
        .invokeMethod<double>(
        'getDouble',
        {'key': key, 'defaultValue': defaultValue}
    );
    return value!;
  }

  @override
  Future<void> flush() async {
    await methodChannel
        .invokeMethod<void>('flush');
  }



  @override
  Future<int> getInt(String key, int defaultValue) async {
    final value = await methodChannel
        .invokeMethod<int>(
        'getInt',
        {'key': key, 'defaultValue': defaultValue}
    );
    return value!;
  }

  Map<String, dynamic> toTypedValue(dynamic value) {
    if (value is int) {
      return {'type': 'int', 'value': value};
    } else if (value is String) {
      return {'type': 'string', 'value': value};
    } else if (value is bool) {
      return {'type': 'bool', 'value': value};
    } else if (value is double) {
      return {'type': 'double', 'value': value};
    } else if (value is Map) {
      return {'type': 'map', 'value': value.map((key, value) {
        return MapEntry(key, toTypedValue(value));
      })};
    }
    else if (value is List) {
      return {'type': 'list', 'value': value.map((value) {
        return toTypedValue(value);
      }).toList()};
    }
    else {
      return {'type': 'unknown', 'value': value.toString()};
    }
  }
}
