import 'package:confidence_flutter_sdk/confidence_flutter_sdk.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'confidence_flutter_sdk_method_channel.dart';

abstract class ConfidenceFlutterSdkPlatform extends PlatformInterface {
  /// Constructs a ConfidenceFlutterSdkPlatform.
  ConfidenceFlutterSdkPlatform() : super(token: _token);

  static final Object _token = Object();

  static ConfidenceFlutterSdkPlatform _instance = MethodChannelConfidenceFlutterSdk();

  /// The default instance of [ConfidenceFlutterSdkPlatform] to use.
  ///
  /// Defaults to [MethodChannelConfidenceFlutterSdk].
  static ConfidenceFlutterSdkPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [ConfidenceFlutterSdkPlatform] when
  /// they register themselves.
  static set instance(ConfidenceFlutterSdkPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<void> setup(String apiKey, LoggingLevel loggingLevel) {
    throw UnimplementedError('setup() has not been implemented.');
  }

  Future<void> fetchAndActivate() {
    throw UnimplementedError('fetchAndActivate() has not been implemented.');
  }

  Future<void> activateAndFetchAsync() {
    throw UnimplementedError('activateAndFetchAsync() has not been implemented.');
  }

  Future<String> getString(String key, String defaultValue) {
    throw UnimplementedError('getString() has not been implemented.');
  }

  Future<void> putContext(String key, dynamic value) async {
    throw UnimplementedError('putContext() has not been implemented.');
  }

  Future<void> putAllContext(Map<String, dynamic> context) async {
    throw UnimplementedError('putAllContext() has not been implemented.');
  }

  Future<bool> isStorageEmpty() {
    throw UnimplementedError('isStorageEmpty() has not been implemented.');
  }

  Future<bool> getBool(String key, bool defaultValue) {
    throw UnimplementedError('getBool() has not been implemented.');
  }

  void track(String eventName, Map<String, dynamic> data) {
    throw UnimplementedError('track has not been implemented.');
  }

  void flush() {
    throw UnimplementedError('flush has not been implemented.');
  }

  Future<double> getDouble(String key, double defaultValue) async {
    throw UnimplementedError('getDouble() has not been implemented.');
  }

  Future<Map<String, dynamic>> getObject(String key, Map<String, dynamic> defaultValue) async {
    throw UnimplementedError('getObject() has not been implemented.');
  }

  Future<int> getInt(String key, int defaultValue) async {
    throw UnimplementedError('getInt() has not been implemented.');
  }

  Future<Map<String, dynamic>> readAllFlags() {
    throw UnimplementedError('readAllFlags() has not been implemented.');
  }
}
