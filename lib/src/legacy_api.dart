import 'confidence.dart';

extension ConfidenceLegacyApi on Confidence {
  bool getBool(String key, bool defaultValue) =>
      getValue<bool>(key, defaultValue);

  String getString(String key, String defaultValue) =>
      getValue<String>(key, defaultValue);

  int getInt(String key, int defaultValue) =>
      getValue<int>(key, defaultValue);

  double getDouble(String key, double defaultValue) =>
      getValue<double>(key, defaultValue);
}
