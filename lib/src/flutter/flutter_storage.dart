import 'package:path_provider/path_provider.dart';

import '../storage.dart';

class FlutterStorage {
  FlutterStorage._();

  static Future<DiskStorage> create() async {
    final dir = await getApplicationSupportDirectory();
    return DiskStorage('${dir.path}/confidence');
  }
}
