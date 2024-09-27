import 'dart:async';

import 'confidence_flutter_sdk_platform_interface.dart';

class ConfidenceFlutterSdk {
  Map<String, dynamic> _flags = {};
  bool isInitialized = false;
  Future<bool> isStorageEmpty() async {
    return ConfidenceFlutterSdkPlatform.instance.isStorageEmpty();
  }

  Future<void> putContext(String key, dynamic value) async {
    await ConfidenceFlutterSdkPlatform.instance.putContext(key, value);
    if(isInitialized) {
      await fetchAndActivate();
    }
  }

  void track(String eventName, Map<String, dynamic> data) {
    ConfidenceFlutterSdkPlatform.instance.track(eventName, data);
  }

  void flush() {
    ConfidenceFlutterSdkPlatform.instance.flush();
  }

  bool getBool(String key, bool defaultValue) {
    unawaited(ConfidenceFlutterSdkPlatform.instance.getBool(key, defaultValue));
    return resolveKey(key) ?? defaultValue;
  }

  T? resolveKey<T>(String key) {
    List<String> keys = key.split(".");
    Map<String, dynamic> flags = _flags;
    for(int i = 0; i < keys.length; i++) {
      String element = keys[i];
      if (flags.containsKey(element)) {
        if(flags[element] is Map<String, dynamic>) {
          flags = flags[element];
        } else {
          return parse<T>(flags[element]);
        }
      } else {
        return null;
      }
    }
    return parse<T>(flags);
  }

  T parse<T>(dynamic value) {
    if(T == String) {
      return value.toString() as T;
    } else if(T == int) {
      return int.parse(value.toString()) as T;
    }  else if(T == bool) {
      return bool.parse(value.toString()) as T;
    } else if(T == double) {
      return double.parse(value.toString()) as T;
    } else if(T == Map<String, dynamic>) {
      return value as T;
    } else {
      return value as T;
    }
  }

    int getInt(String key, int defaultValue) {
    unawaited(ConfidenceFlutterSdkPlatform.instance.getInt(key, defaultValue));
    return resolveKey<int>(key) ?? defaultValue;
  }

    String getString(String key, String defaultValue) {
    unawaited(ConfidenceFlutterSdkPlatform.instance.getString(key, defaultValue));
    return resolveKey(key) ?? defaultValue;
  }

  Map<String, dynamic> getObject(String key, Map<String, dynamic> defaultValue) {
    unawaited(ConfidenceFlutterSdkPlatform.instance.getObject(key, defaultValue));
    return resolveKey(key) ?? defaultValue;
  }

  double getDouble(String key, double defaultValue) {
    unawaited(ConfidenceFlutterSdkPlatform.instance.getDouble(key, defaultValue));
    return resolveKey(key) ?? defaultValue;
  }

  Future<void> setup(String apiKey) async {
    return await ConfidenceFlutterSdkPlatform.instance.setup(apiKey);
  }

  Future<void> fetchAndActivate() async {
    await ConfidenceFlutterSdkPlatform.instance.fetchAndActivate();
    await fillAllFlags();
  }

  Future<void> fillAllFlags() async {
    _flags = await ConfidenceFlutterSdkPlatform.instance.readAllFlags();
    isInitialized = true;
  }

  Future<void> activateAndFetchAsync() async {
    await ConfidenceFlutterSdkPlatform.instance.activateAndFetchAsync();
    await fillAllFlags();
  }
}
