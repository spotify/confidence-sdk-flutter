import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(responseDataCallback: (data) async {
      final path = Platform.environment['UPGRADE_REPORT'];
      if (path != null) {
        await File(path)
            .writeAsString(jsonEncode({'UPGRADE_EXPECTED': jsonEncode(data)}));
      }
    });
