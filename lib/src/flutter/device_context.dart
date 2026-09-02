import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../confidence_value.dart';

class DeviceContextProvider {
  Future<Map<String, ConfidenceValue>> getDeviceContext() async {
    final context = <String, ConfidenceValue>{};

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      context['app'] = ConfidenceValue.structure({
        'version': ConfidenceValue.string(packageInfo.version),
        'build': ConfidenceValue.string(packageInfo.buildNumber),
        'package': ConfidenceValue.string(packageInfo.packageName),
      });
    } catch (_) {}

    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        context['device'] = ConfidenceValue.structure({
          'manufacturer': ConfidenceValue.string(android.manufacturer),
          'model': ConfidenceValue.string(android.model),
          'type': ConfidenceValue.string('android'),
        });
        context['os'] = ConfidenceValue.structure({
          'name': ConfidenceValue.string('android'),
          'version': ConfidenceValue.string(android.version.release),
        });
      } else if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        context['device'] = ConfidenceValue.structure({
          'manufacturer': ConfidenceValue.string('Apple'),
          'model': ConfidenceValue.string(ios.model),
          'type': ConfidenceValue.string('ios'),
        });
        context['os'] = ConfidenceValue.structure({
          'name': ConfidenceValue.string('ios'),
          'version': ConfidenceValue.string(ios.systemVersion),
        });
      }
    } catch (_) {}

    try {
      context['locale'] = ConfidenceValue.string(Platform.localeName);
    } catch (_) {}

    return context;
  }
}
