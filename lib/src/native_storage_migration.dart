import 'dart:convert';
import 'dart:io';

import 'apply_manager.dart';
import 'async_gate.dart';
import 'confidence_value.dart';
import 'evaluation.dart';
import 'events_client.dart';
import 'flag_resolution.dart';
import 'storage.dart';

enum NativeStorageFormat { ios, android }

/// Imports the files written by Swift 0.6.x and Android 0.6.9. Each atomic
/// destination write is a checkpoint; native files are never changed/deleted.
class NativeStorageMigration {
  static final _gate = AsyncGate();
  final Storage source;
  final Storage destination;
  final NativeStorageFormat format;
  final Storage? eventSource;
  final List<String> eventFiles;

  NativeStorageMigration(
      {required this.source,
      required this.destination,
      required this.format,
      this.eventSource,
      this.eventFiles = const []});

  Future<void> migrate() => _gate.run(() async {
        await _import(
            format == NativeStorageFormat.ios
                ? 'confidence.flags.resolve'
                : 'confidence_flags_cache.json',
            'confidence.flags.resolve',
            _flags);
        await _import(
            format == NativeStorageFormat.ios
                ? 'confidence.flags.apply'
                : 'confidence_apply_cache.json',
            ApplyManager.storageKey,
            _applies);
        await _importEvents();
      });

  Future<void> _importEvents() async {
    final source = eventSource;
    if (source == null ||
        eventFiles.isEmpty ||
        await destination.exists(EventsClient.legacyStorageKey)) return;
    final events = <Map<String, dynamic>>[];
    try {
      for (final file in eventFiles) {
        final data = await source.read(file);
        if (data == null) continue;
        for (final line in data.split('\n')) {
          final text = line.trim().replaceFirst(RegExp(r',$'), '');
          if (text.isEmpty) continue;
          final event = jsonDecode(text) as Map<String, dynamic>;
          final name = event[format == NativeStorageFormat.ios
              ? 'name'
              : 'eventDefinition'] as String;
          final time = format == NativeStorageFormat.ios
              ? swiftDate(event['eventTime'] as num)
              : DateTime.parse(event['eventTime'] as String);
          events.add({
            'eventDefinition': name.startsWith('eventDefinitions/')
                ? name
                : 'eventDefinitions/$name',
            'eventTime': time.toUtc().toIso8601String(),
            'payload': (event['payload'] as Map<String, dynamic>).map(
                (key, value) =>
                    MapEntry(key, decodeValue(value).toPlainJson())),
          });
        }
      }
    } on FormatException {
      return;
    } on TypeError {
      return;
    } on StateError {
      return;
    } on FileSystemException {
      return;
    }
    if (events.isNotEmpty) {
      await destination.write(
          EventsClient.legacyStorageKey, jsonEncode(events));
    }
  }

  Future<void> _import(String from, String to,
      Object Function(Map<String, dynamic>) convert) async {
    // Even an empty destination is a completed import (e.g. drained applies).
    // Reimporting an old native file would resurrect stale assignments/events.
    if (await destination.exists(to)) return;
    String? data;
    try {
      data = await source.read(from);
    } on FileSystemException {
      return;
    }
    if (data == null || data.isEmpty) return;
    Object converted;
    try {
      converted = convert(jsonDecode(data) as Map<String, dynamic>);
    } on FormatException {
      return;
    } on TypeError {
      return;
    } on StateError {
      return;
    }
    // Do not suppress write failures: callers can retry with originals intact.
    await destination.write(to, jsonEncode(converted));
  }

  Map<String, dynamic> _flags(Map<String, dynamic> json) {
    final flags = (json['flags'] as List).map((item) {
      final flag = item as Map<String, dynamic>;
      final rawValue = flag['value'];
      final value = rawValue == null
          ? null
          : format == NativeStorageFormat.ios
              ? decodeValue(rawValue)
              : ConfidenceValue.structure((rawValue as Map<String, dynamic>)
                  .map((k, v) => MapEntry(k, decodeValue(v))));
      return ResolvedFlag(
        flag: flag['flag'] as String,
        variant: flag['variant'] as String? ?? '',
        value: value as ConfidenceValueStructure?,
        reason: ResolveReason.fromString(
            flag[format == NativeStorageFormat.ios ? 'resolveReason' : 'reason']
                as String),
        shouldApply: flag['shouldApply'] as bool? ?? true,
      );
    }).toList();
    return FlagResolution(
            flags: flags, resolveToken: json['resolveToken'] as String)
        .toJson();
  }

  Map<String, dynamic> _applies(Map<String, dynamic> json) {
    final records = <String, Map<String, dynamic>>{};
    void add(String token, String name, DateTime time, String status) {
      if (!['created', 'sending', 'sent'].contains(status)) {
        throw const FormatException('Unknown native exposure state');
      }
      (records[token] ??= {})[name] =
          ApplyRecord(time, sent: status == 'sent').toJson();
    }

    if (format == NativeStorageFormat.ios) {
      for (final resolve in json['resolveEvents'] as List) {
        for (final event in resolve['events'] as List) {
          add(
              resolve['resolveToken'] as String,
              event['name'] as String,
              swiftDate(event['applyTime'] as num),
              (event['status'] as Map<String, dynamic>).keys.single);
        }
      }
    } else {
      for (final token in json.entries) {
        for (final flag in (token.value as Map<String, dynamic>).entries) {
          add(token.key, flag.key, DateTime.parse(flag.value['time'] as String),
              (flag.value['eventStatus'] as String).toLowerCase());
        }
      }
    }
    return records;
  }

  /// Swift's synthesized enum Codable representation differs from Kotlin's
  /// tagged values. Preserve the declared numeric type, not JSON's type.
  ConfidenceValue decodeValue(dynamic json) {
    final map = json as Map<String, dynamic>;
    if (map.isEmpty || map.containsKey('null')) return ConfidenceValue.null_();
    final type = map.keys.single;
    final value =
        format == NativeStorageFormat.ios ? map[type]['_0'] : map[type];
    return switch (type) {
      'string' => ConfidenceValue.string(value as String),
      'boolean' => ConfidenceValue.boolean(value as bool),
      'integer' => ConfidenceValue.integer(value as int),
      'double' => ConfidenceValue.double_((value as num).toDouble()),
      'structure' || 'map' => ConfidenceValue.structure(
          (value as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, decodeValue(v)))),
      'list' => ConfidenceValue.list((value as List).map(decodeValue).toList()),
      'timestamp' => ConfidenceValue.timestamp(swiftDate(value as num)),
      'dateTime' => ConfidenceValue.timestamp(DateTime.parse(value as String)),
      'date' => ConfidenceValue.date(format == NativeStorageFormat.ios
          ? DateTime.utc(
              value['year'] as int, value['month'] as int, value['day'] as int)
          : DateTime.parse(value as String)),
      _ => throw FormatException('Unsupported native value type: $type'),
    };
  }

  static DateTime swiftDate(num seconds) => DateTime.utc(2001).add(Duration(
      microseconds: (seconds * Duration.microsecondsPerSecond).round()));
}
