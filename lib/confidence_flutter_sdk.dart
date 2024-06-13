import 'confidence_flutter_sdk_platform_interface.dart';

class ConfidenceFlutterSdk {
  Future<bool> isStorageEmpty() async {
    return ConfidenceFlutterSdkPlatform.instance.isStorageEmpty();
  }

  Future<void> putContext(String key, dynamic value) async {
    ConfidenceFlutterSdkPlatform.instance.putContext(key, value);
  }

  void track(String eventName, Map<String, dynamic> data) {
    ConfidenceFlutterSdkPlatform.instance.track(eventName, data);
  }

  Future<bool> getBool(String key, bool defaultValue) {
    return ConfidenceFlutterSdkPlatform.instance.getBool(key, defaultValue);
  }

  Future<int> getInt(String key, int defaultValue) {
    return ConfidenceFlutterSdkPlatform.instance.getInt(key, defaultValue);
  }

  Future<String> getString(String key, String defaultValue) {
    return ConfidenceFlutterSdkPlatform.instance.getString(key, defaultValue);
  }

  Future<Map<String, dynamic>> getObject(String key, Map<String, dynamic> defaultValue) {
    return ConfidenceFlutterSdkPlatform.instance.getObject(key, defaultValue);
  }

  Future<double> getDouble(String key, double defaultValue) {
    return ConfidenceFlutterSdkPlatform.instance.getDouble(key, defaultValue);
  }

  Future<void> setup(String apiKey) async {
    return await ConfidenceFlutterSdkPlatform.instance.setup(apiKey);
  }

  Future<void> fetchAndActivate() async {
    return await ConfidenceFlutterSdkPlatform.instance.fetchAndActivate();
  }

  Future<void> activateAndFetchAsync() async {
    return ConfidenceFlutterSdkPlatform.instance.activateAndFetchAsync();
  }
}
