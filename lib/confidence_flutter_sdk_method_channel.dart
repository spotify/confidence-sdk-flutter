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
  Future<void> setup(
    String apiKey,
    LoggingLevel loggingLevel, [
    String? resolveBaseUrl,
  ]) async {
    return await methodChannel.invokeMethod<void>('setup', {
      'apiKey': apiKey,
      'loggingLevel': loggingLevel.name,
      if (resolveBaseUrl != null) 'resolveBaseUrl': resolveBaseUrl,
    });
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
    // track() is intentionally fire-and-forget, so the returned future is not
    // awaited. Without this handler a native error reply would surface as an
    // unhandled async error in the host app.
    methodChannel
        .invokeMethod<void>(
        'track',
        {'eventName': eventName, 'data': wrappedData}
    ).catchError((Object error) {
      if (kDebugMode) {
        print('Confidence SDK: failed to track "$eventName": $error');
      }
    });
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
    // The platform interface declares flush() as void, so callers discard this
    // future. Now that native replies with an error on failure, an unguarded
    // rejection would surface as an unhandled async error in the host app.
    try {
      await methodChannel.invokeMethod<void>('flush');
    } catch (error) {
      if (kDebugMode) {
        print('Confidence SDK: failed to flush: $error');
      }
    }
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

  /// Wraps [value] in the `{'type': ..., 'value': ...}` envelope the native
  /// plugins decode.
  ///
  /// Anything Confidence has no type for — a `DateTime`, a `null`, a custom
  /// object — is sent as `type: 'unknown'` carrying `value.toString()`. Both
  /// native sides publish that as a string. They must not coerce it to a
  /// number or drop it: the caller's data would be silently wrong with
  /// nothing to indicate it.
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
