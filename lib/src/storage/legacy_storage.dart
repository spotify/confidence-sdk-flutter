import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_android/shared_preferences_android.dart';

/// Read-only access to the native SDK's legacy storage.
///
/// Call during initialization, after Flutter bindings are initialized. This
/// does not activate, migrate, remove, or rewrite any legacy records.
final class LegacyStorage {
  LegacyStorage._(
    this.flags,
    this.apply,
    this.events,
    this._preferences,
    this._visitorKey,
  );

  final File flags;
  final File apply;
  final Directory events;
  final SharedPreferencesAsync _preferences;
  final String _visitorKey;

  static Future<LegacyStorage> locate() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw UnsupportedError(
        'Legacy storage is supported only on Android and iOS.',
      );
    }
    final support = await getApplicationSupportDirectory();
    if (Platform.isAndroid) {
      return LegacyStorage._(
        File(p.join(support.path, 'confidence_flags_cache.json')),
        File(p.join(support.path, 'confidence_apply_cache.json')),
        // path_provider returns filesDir; getDir("events") is its sibling.
        Directory(p.join(support.parent.path, 'app_events')),
        SharedPreferencesAsync(
          options: const SharedPreferencesAsyncAndroidOptions(
            backend: SharedPreferencesAndroidBackendLibrary.SharedPreferences,
            originalSharedPreferencesOptions:
                AndroidSharedPreferencesStoreOptions(
                  fileName: 'confidence-visitor',
                ),
          ),
        ),
        'visitorId',
      );
    }
    final bundleId = (await PackageInfo.fromPlatform()).packageName;
    final cache = p.join(support.path, 'com.confidence.cache', bundleId);
    return LegacyStorage._(
      File(p.join(cache, 'confidence.flags.resolve')),
      File(p.join(cache, 'confidence.flags.apply')),
      Directory(
        p.join(
          support.path,
          'com.confidence.events.storage',
          bundleId,
          'events',
        ),
      ),
      SharedPreferencesAsync(),
      'confidence.visitor_id',
    );
  }

  /// Reads the existing native identity without generating or persisting one.
  Future<String?> readVisitorId() => _preferences.getString(_visitorKey);
}
