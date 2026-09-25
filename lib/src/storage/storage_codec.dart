import '../snapshot.dart';
import 'outbox.dart';

/// Every value is tagged, so user maps cannot collide with date/type markers.
Object encodeValue(Object? value) => switch (value) {
  null => ['null'],
  bool() => ['bool', value],
  String() => ['string', value],
  int() => ['int', value],
  double() when value.isFinite => ['double', value],
  DateTime() => ['timestamp', value.toUtc().toIso8601String()],
  CalendarDate() => ['date', encodeValue(value.components)],
  List<Object?>() => ['list', value.map(encodeValue).toList()],
  Map<String, Object?>() => [
    'map',
    value.map((k, v) => MapEntry(k, encodeValue(v))),
  ],
  _ => throw const FormatException('Unsupported storage value.'),
};

Object? decodeValue(Object? input) {
  final parts = list(input);
  if (parts.length == 1 && parts[0] == 'null') return null;
  if (parts.length != 2) invalid();
  final value = parts[1];
  return switch (parts[0]) {
    'bool' => boolean(value),
    'string' => string(value),
    'int' => value is int ? value : invalid(),
    'double' => value is num && value.isFinite ? value.toDouble() : invalid(),
    'timestamp' => timestamp(value),
    'date' => CalendarDate(map(decodeValue(value))),
    'list' => List<Object?>.unmodifiable(list(value).map(decodeValue)),
    'map' => Map<String, Object?>.unmodifiable(
      map(value).map((k, v) => MapEntry(k, decodeValue(v))),
    ),
    _ => invalid(),
  };
}

Map<String, Object?> encodeSnapshot(FlagSnapshot snapshot) => {
  'context': encodeValue(snapshot.context),
  'token': snapshot.resolveToken,
  'flags': snapshot.flags.values
      .map(
        (f) => {
          'name': f.name,
          'value': encodeValue(f.value),
          'reason': f.reason,
          'variant': f.variant,
          'shouldApply': f.shouldApply,
        },
      )
      .toList(),
};

FlagSnapshot decodeSnapshot(Object? input) {
  final root = map(input);
  final flags = <String, ResolvedFlag>{};
  for (final entry in list(root['flags'])) {
    final f = map(entry);
    final name = string(f['name']);
    if (flags.containsKey(name)) invalid();
    flags[name] = ResolvedFlag(
      name: name,
      value: decodeValue(f['value']),
      reason: string(f['reason']),
      variant: f['variant'] == null ? null : string(f['variant']),
      shouldApply: boolean(f['shouldApply']),
    );
  }
  return FlagSnapshot(
    context: map(decodeValue(root['context'])),
    flags: flags,
    resolveToken: string(root['token']),
  );
}

Map<String, Object?> encodeOutbox(Outbox box) => {
  'droppedRecords': box.droppedRecords,
  'visitorId': box.visitorId,
  'importedSources': box.importedSources.toList(),
  'apply': box.apply
      .map(
        (a) => {
          'token': a.token,
          'flag': a.flag,
          'time': a.time.toUtc().toIso8601String(),
          'sent': a.sent,
        },
      )
      .toList(),
  'events': box.events
      .map(
        (e) => {
          'id': e.id,
          'name': e.name,
          'time': e.time.toUtc().toIso8601String(),
          'payload': encodeValue(e.payload),
        },
      )
      .toList(),
};

Outbox decodeOutbox(Object? input) {
  final root = map(input);
  final dropped = root['droppedRecords'] ?? 0;
  if (dropped is! int || dropped < 0) invalid();
  final applyKeys = <(String, String)>{};
  final eventIds = <String>{};
  return Outbox(
    droppedRecords: dropped,
    visitorId: root['visitorId'] == null ? null : string(root['visitorId']),
    importedSources: list(root['importedSources']).map(string),
    apply: list(root['apply']).map((input) {
      final a = map(input);
      final record = ApplyRecord(
        token: string(a['token']),
        flag: string(a['flag']),
        time: timestamp(a['time']),
        sent: boolean(a['sent']),
      );
      if (!applyKeys.add(record.key)) invalid();
      return record;
    }),
    events: list(root['events']).map((input) {
      final e = map(input);
      final id = string(e['id']);
      if (!eventIds.add(id)) invalid();
      return EventRecord(
        id: id,
        name: string(e['name']),
        time: timestamp(e['time']),
        payload: map(decodeValue(e['payload'])),
      );
    }),
  );
}

Map<String, Object?> map(Object? value) =>
    value is Map<String, Object?> ? value : invalid();
List<Object?> list(Object? value) => value is List<Object?> ? value : invalid();
String string(Object? value) => value is String ? value : invalid();
bool boolean(Object? value) => value is bool ? value : invalid();
DateTime timestamp(Object? value) {
  final date = DateTime.parse(string(value));
  if (!date.isUtc || date.toIso8601String() != value) invalid();
  return date;
}

Never invalid() => throw const FormatException('Invalid persisted data.');
