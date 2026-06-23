import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../confidence_value.dart';

class VisitorIdManager {
  static const _key = 'confidence.visitor_id';
  String? _cachedId;

  Future<String> getOrCreate() async {
    if (_cachedId != null) return _cachedId!;

    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_key);
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString(_key, id);
    }
    _cachedId = id;
    return id;
  }

  Future<Map<String, ConfidenceValue>> asContext() async {
    final id = await getOrCreate();
    return {'visitor_id': ConfidenceValue.string(id)};
  }
}
