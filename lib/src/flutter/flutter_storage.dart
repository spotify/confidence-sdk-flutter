import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../native_storage_migration.dart';
import '../storage.dart';

class FlutterStorage {
  FlutterStorage._();

  static Future<DiskStorage> create() async {
    final dir = await getApplicationSupportDirectory();
    final storage = DiskStorage('${dir.path}/confidence');
    if (Platform.isIOS || Platform.isAndroid) {
      final bundleId = Platform.isIOS
          ? (await PackageInfo.fromPlatform()).packageName
          : null;
      final legacyPath = Platform.isIOS
          ? '${dir.path}/com.confidence.cache/$bundleId'
          : dir.path;
      final eventPath = Platform.isIOS
          ? '${dir.path}/com.confidence.events.storage/$bundleId/events'
          : '${dir.parent.path}/app_events';
      try {
        final eventDir = Directory(eventPath);
        final eventFiles = await eventDir.exists()
            ? await eventDir
                .list(followLinks: false)
                .where((entry) => entry is File)
                .map((entry) => entry.uri.pathSegments.last)
                .where((name) => Platform.isIOS
                    ? RegExp(r'^[0-9a-fA-F-]{36}(\.READY)?$').hasMatch(name)
                    : RegExp(r'^events-[0-9]+(\.ready)?$').hasMatch(name))
                .toList()
            : <String>[];
        await NativeStorageMigration(
          source: DiskStorage(legacyPath),
          eventSource: DiskStorage(eventPath),
          eventFiles: eventFiles,
          destination: storage,
          format: Platform.isIOS
              ? NativeStorageFormat.ios
              : NativeStorageFormat.android,
        ).migrate();
      } on FileSystemException {
        // Leave the originals/checkpoints for a retry on the next launch.
      }
    }
    return storage;
  }
}
