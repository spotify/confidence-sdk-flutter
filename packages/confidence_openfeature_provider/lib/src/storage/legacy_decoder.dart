import 'dart:convert';

import '../snapshot.dart';
import 'legacy_queue.dart';

enum LegacyPlatform { android, swift }

/// Pure decoders for the pinned native caches. No activation or file I/O.
/// Invalid flag/apply caches throw payload-free errors. Event batches report
/// rejected line numbers and preserve other records. The owner handles removal.
final class LegacyDecoder {
  const LegacyDecoder(this.platform);

  final LegacyPlatform platform;
  bool get _swift => platform == LegacyPlatform.swift;

  /// Decode apply state without dropping sent entries or replaying anything.
  List<LegacyApply> decodeApply(String source) {
    try {
      final root = _map(jsonDecode(source));
      final records = <LegacyApply>[];
      final seen = <(String, String)>{};
      void add(String token, String flag, Object? time, String status) {
        if (!seen.add((token, flag))) _invalid();
        records.add(
          LegacyApply(
            resolveToken: token,
            flag: flag,
            time: _timestamp(time),
            status: switch (status) {
              'created' => LegacyApplyStatus.created,
              'sending' => LegacyApplyStatus.sending,
              'sent' => LegacyApplyStatus.sent,
              _ => _invalid(),
            },
          ),
        );
      }

      if (_swift) {
        for (final input in _list(root['resolveEvents'])) {
          final group = _map(input);
          final token = _string(group['resolveToken']);
          for (final input in _list(group['events'])) {
            final event = _map(input);
            final status = _map(event['status']);
            if (status.length != 1 || _map(status.values.single).isNotEmpty) {
              _invalid();
            }
            add(
              token,
              _string(event['name']),
              event['applyTime'],
              status.keys.single,
            );
          }
        }
      } else {
        for (final group in root.entries) {
          for (final entry in _map(group.value).entries) {
            final event = _map(entry.value);
            final status = switch (event['eventStatus']) {
              'CREATED' => 'created',
              'SENDING' => 'sending',
              'SENT' => 'sent',
              _ => _invalid(),
            };
            add(group.key, entry.key, event['time'], status);
          }
        }
      }
      return List.unmodifiable(records);
    } on FormatException {
      throw const FormatException('Invalid legacy apply cache.');
    } on ArgumentError {
      throw const FormatException('Invalid legacy apply cache.');
    }
  }

  /// Both native writers store one compact JSON object per line, with escaped
  /// newlines inside strings. Android appends a comma; Swift prefixes a newline.
  /// This also accepts complete final records in unfinished files.
  LegacyEventBatch decodeEvents(String source) {
    final events = <LegacyEvent>[];
    final rejected = <int>[];
    final lines = const LineSplitter().convert(source);
    for (var index = 0; index < lines.length; index++) {
      var line = lines[index].trim();
      if (line.isEmpty) continue;
      if (!_swift && line.endsWith(',')) {
        line = line.substring(0, line.length - 1);
      }
      try {
        final event = _map(jsonDecode(line));
        events.add(
          LegacyEvent(
            sourceLine: index + 1,
            name: _string(event[_swift ? 'name' : 'eventDefinition']),
            time: _timestamp(event['eventTime']),
            payload: _values(event['payload']),
          ),
        );
      } on FormatException {
        rejected.add(index + 1);
      } on ArgumentError {
        rejected.add(index + 1);
      }
    }
    return LegacyEventBatch(events, rejected);
  }

  DateTime _timestamp(Object? value) =>
      _swift ? _swiftTimestamp(value) : _androidTimestamp(value);

  FlagSnapshot decodeFlags(String source) {
    try {
      final root = _map(jsonDecode(source));
      final flags = <String, ResolvedFlag>{};
      for (final entry in _list(root['flags'])) {
        final flag = _map(entry);
        final name = _string(flag['flag']);
        if (flags.containsKey(name)) _invalid();
        final variant = flag['variant'];
        flags[name] = ResolvedFlag(
          name: name,
          value: _swift
              ? (flag['value'] == null ? null : _value(flag['value']))
              : _values(
                  flag.containsKey('value')
                      ? flag['value']
                      : <String, Object?>{},
                ),
          reason: _string(flag[_swift ? 'resolveReason' : 'reason']),
          variant: _swift && variant == null ? null : _string(variant),
          shouldApply: _bool(
            _swift ? flag['shouldApply'] ?? true : flag['shouldApply'],
          ),
        );
      }
      return FlagSnapshot(
        context: _values(root['context']),
        flags: flags,
        resolveToken: _string(root['resolveToken']),
      );
    } on FormatException {
      // jsonDecode/date parsing errors can include the source payload.
      _invalid();
    } on ArgumentError {
      _invalid();
    }
  }

  Map<String, Object?> _values(Object? input) =>
      _map(input).map((key, value) => MapEntry(key, _value(value)));

  Object? _value(Object? input) {
    final tagged = _map(input);
    if (!_swift && tagged.isEmpty) return null;
    if (tagged.length != 1) _invalid();
    final tag = tagged.keys.single;
    Object? payload = tagged[tag];
    if (_swift) {
      final wrapper = _map(payload);
      if (tag == 'null' && wrapper.isEmpty) return null;
      if (wrapper.length != 1 || !wrapper.containsKey('_0')) _invalid();
      payload = wrapper['_0'];
    }
    return switch (tag) {
      'boolean' => _bool(payload),
      'string' => _string(payload),
      'integer' => payload is int ? payload : _invalid(),
      'double' =>
        payload is num && payload.isFinite ? payload.toDouble() : _invalid(),
      'list' => _list(payload).map(_value).toList(),
      'structure' when _swift => _values(payload),
      'map' when !_swift => _values(payload),
      'timestamp' when _swift => _swiftTimestamp(payload),
      'dateTime' when !_swift => _androidTimestamp(payload),
      'date' => _date(payload),
      _ => _invalid(),
    };
  }

  CalendarDate _date(Object? payload) {
    if (_swift) return CalendarDate(_map(payload));
    final text = _string(payload);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) _invalid();
    final date = DateTime.parse('${text}T00:00:00Z');
    if (date.toIso8601String().substring(0, 10) != text) _invalid();
    return CalendarDate({
      'year': date.year,
      'month': date.month,
      'day': date.day,
    });
  }

  DateTime _androidTimestamp(Object? payload) {
    final text = _string(payload);
    if (!RegExp(
      r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{3})?Z$',
    ).hasMatch(text)) {
      _invalid();
    }
    final date = DateTime.parse(text);
    final canonical = text.contains('.')
        ? text
        : text.replaceFirst('Z', '.000Z');
    if (date.toIso8601String() != canonical) _invalid();
    return date;
  }

  DateTime _swiftTimestamp(Object? payload) {
    if (payload is! num || !payload.isFinite) _invalid();
    final micros = payload * Duration.microsecondsPerSecond;
    if (!micros.isFinite || micros.abs() > 8000000000000000000) _invalid();
    return DateTime.utc(2001).add(Duration(microseconds: micros.round()));
  }
}

Map<String, Object?> _map(Object? value) =>
    value is Map<String, Object?> ? value : _invalid();
List<Object?> _list(Object? value) =>
    value is List<Object?> ? value : _invalid();
String _string(Object? value) => value is String ? value : _invalid();
bool _bool(Object? value) => value is bool ? value : _invalid();
Never _invalid() => throw const FormatException('Invalid legacy flag cache.');
