import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_android/shared_preferences_android.dart';

import 'package:uuid/uuid.dart';

import '../async_gate.dart';

import '../confidence_value.dart';

class VisitorIdManager {
  static const _key = 'confidence.visitor_id';
  static final _gate = AsyncGate();
  String? _cachedId;
  final Future<String?> Function()? nativeIdReader;

  VisitorIdManager({this.nativeIdReader});

  Future<String> getOrCreate() => _gate.run(() async {
        if (_cachedId != null) return _cachedId!;

        final prefs = await SharedPreferences.getInstance();
        var id = prefs.getString(_key);
        if (id == null || id.isEmpty) {
          id = await (nativeIdReader ?? _nativeId)() ?? const Uuid().v4();
          await prefs.setString(_key, id);
        }
        _cachedId = id;
        return id;
      });

  Future<String?> _nativeId() async {
    String? id;
    if (Platform.isIOS) {
      // Async preferences use the original, unprefixed UserDefaults key.
      id = await SharedPreferencesAsync().getString(_key);
    } else if (Platform.isAndroid) {
      id = await SharedPreferencesAsync(
          options: const SharedPreferencesAsyncAndroidOptions(
        backend: SharedPreferencesAndroidBackendLibrary.SharedPreferences,
        originalSharedPreferencesOptions: AndroidSharedPreferencesStoreOptions(
            fileName: 'confidence-visitor'),
      )).getString('visitorId');
    }
    return id == null || id.isEmpty ? null : id;
  }

  Future<Map<String, ConfidenceValue>> asContext() async {
    final id = await getOrCreate();
    return {'visitor_id': ConfidenceValue.string(id)};
  }
}
