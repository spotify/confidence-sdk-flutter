import 'dart:io';

import 'package:confidence_openfeature_provider/src/resolver.dart';
import 'package:test/test.dart';

void main() {
  test('wire SDK version matches the published package version', () {
    final version = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1);
    expect(providerVersion, version);
  });
}
