import 'dart:convert';

import 'apply_client.dart';
import 'async_gate.dart';
import 'storage.dart';

class ApplyRecord {
  final DateTime time;
  bool sent;
  ApplyRecord(this.time, {this.sent = false});

  Map<String, dynamic> toJson() =>
      {'time': time.toUtc().toIso8601String(), 'sent': sent};
  factory ApplyRecord.fromJson(Map<String, dynamic> json) =>
      ApplyRecord(DateTime.parse(json['time'] as String),
          sent: json['sent'] as bool);
}

class ApplyManager {
  static const storageKey = 'confidence.apply.cache';
  final Storage _storage;
  final ApplyClient _applyClient;
  final AsyncGate _gate = AsyncGate();
  final AsyncGate _sendGate = AsyncGate();

  ApplyManager({required Storage storage, required ApplyClient applyClient})
      : _storage = storage,
        _applyClient = applyClient;

  Future<void> apply(String flagName, String resolveToken) async {
    final time = DateTime.now().toUtc();
    await _gate.run(() async {
      final records = await _load();
      final flags = records[resolveToken] ??= {};
      if (!flags.containsKey(flagName)) {
        flags[flagName] = ApplyRecord(time);
        // Persist before sending, even while another request is stalled.
        await _save(records);
      }
    });
    await restore();
  }

  Future<void> restore() => _sendGate.run(() async {
        final records = await _gate.run(() async {
          final records = await _load();
          if (records.isNotEmpty) await _save(records);
          return records;
        });
        await _sendPending(records);
      });

  Future<void> _sendPending(
      Map<String, Map<String, ApplyRecord>> records) async {
    for (final token in records.entries) {
      for (final flag in token.value.entries) {
        if (flag.value.sent) continue;
        bool success;
        try {
          success = await _applyClient.sendApply(
              flagName: flag.key,
              resolveToken: token.key,
              applyTime: flag.value.time);
        } catch (_) {
          continue;
        }
        if (success) {
          await _gate.run(() async {
            // Merge the acknowledgement with exposures queued during the send.
            final latest = await _load();
            final record = latest[token.key]?[flag.key];
            if (record != null) {
              record.sent = true;
              await _save(latest);
            }
          });
        }
      }
    }
  }

  Future<void> _save(Map<String, Map<String, ApplyRecord>> records) =>
      _storage.write(
          storageKey,
          jsonEncode(records.map((token, flags) => MapEntry(token,
              flags.map((name, record) => MapEntry(name, record.toJson()))))));

  Future<Map<String, Map<String, ApplyRecord>>> _load() async {
    final stored = await _storage.read(storageKey);
    if (stored == null) return {};
    try {
      final json = jsonDecode(stored) as Map<String, dynamic>;
      return json.map((token, value) => MapEntry(
          token,
          value is List
              // Compatibility with pre-migration Dart caches (which had no times).
              ? {
                  for (final flag in value)
                    flag as String: ApplyRecord(DateTime.now().toUtc())
                }
              : (value as Map<String, dynamic>).map((name, record) => MapEntry(
                  name,
                  ApplyRecord.fromJson(record as Map<String, dynamic>)))));
    } on FormatException {
      return {};
    } on TypeError {
      return {};
    }
  }
}
