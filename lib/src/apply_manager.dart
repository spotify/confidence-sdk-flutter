import 'dart:convert';

import 'apply_client.dart';
import 'storage.dart';

class ApplyManager {
  final Storage _storage;
  final ApplyClient _applyClient;
  final Set<String> _appliedKeys = {};
  final Set<String> _inFlightKeys = {};

  static const _storageKey = 'confidence.apply.cache';

  ApplyManager({
    required Storage storage,
    required ApplyClient applyClient,
  })  : _storage = storage,
        _applyClient = applyClient;

  Future<void> apply(String flagName, String resolveToken) async {
    final key = _appliedKey(resolveToken, flagName);

    await _restore(skipKey: key);

    if (_appliedKeys.contains(key) || _inFlightKeys.contains(key)) return;
    _inFlightKeys.add(key);

    final applyTime = DateTime.now().toUtc();

    try {
      final success = await _applyClient.sendApply(
        flagName: flagName,
        resolveToken: resolveToken,
        applyTime: applyTime,
      );

      if (success) {
        _appliedKeys.add(key);
        await _removePending(resolveToken, flagName);
      } else {
        await _addPending(resolveToken, flagName);
      }
    } catch (_) {
      await _addPending(resolveToken, flagName);
    } finally {
      _inFlightKeys.remove(key);
    }
  }

  Future<void> restore() => _restore();

  Future<void> _restore({String? skipKey}) async {
    final pending = await _loadPending();
    if (pending.isEmpty) return;

    for (final entry in pending.entries) {
      final resolveToken = entry.key;
      for (final flagName in List<String>.of(entry.value)) {
        final key = _appliedKey(resolveToken, flagName);
        if (key == skipKey ||
            _appliedKeys.contains(key) ||
            _inFlightKeys.contains(key)) {
          continue;
        }
        _inFlightKeys.add(key);

        try {
          final success = await _applyClient.sendApply(
            flagName: flagName,
            resolveToken: resolveToken,
            applyTime: DateTime.now().toUtc(),
          );
          if (success) {
            _appliedKeys.add(key);
            await _removePending(resolveToken, flagName);
          }
        } catch (_) {
          // Keep in pending for next retry
        } finally {
          _inFlightKeys.remove(key);
        }
      }
    }
  }

  String _appliedKey(String resolveToken, String flagName) =>
      '$resolveToken:$flagName';

  Future<void> _addPending(String resolveToken, String flagName) async {
    final pending = await _loadPending();
    final flags = pending[resolveToken] ?? [];
    if (!flags.contains(flagName)) {
      flags.add(flagName);
    }
    pending[resolveToken] = flags;
    await _storage.write(_storageKey, jsonEncode(pending));
  }

  Future<void> _removePending(String resolveToken, String flagName) async {
    final pending = await _loadPending();
    final flags = pending[resolveToken];
    if (flags != null) {
      flags.remove(flagName);
      if (flags.isEmpty) {
        pending.remove(resolveToken);
      }
    }
    await _storage.write(_storageKey, jsonEncode(pending));
  }

  Future<Map<String, List<String>>> _loadPending() async {
    final stored = await _storage.read(_storageKey);
    if (stored == null) return {};
    final json = jsonDecode(stored) as Map<String, dynamic>;
    return json.map(
      (k, v) => MapEntry(k, (v as List).cast<String>()),
    );
  }
}
