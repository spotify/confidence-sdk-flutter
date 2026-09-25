import '../snapshot.dart';

final class ApplyRecord {
  const ApplyRecord({
    required this.token,
    required this.flag,
    required this.time,
    this.sent = false,
  });
  final String token;
  final String flag;
  final DateTime time;
  final bool sent;
  (String, String) get key => (token, flag);
}

final class EventRecord {
  EventRecord({
    required this.id,
    required this.name,
    required this.time,
    required Map<String, Object?> payload,
  }) : payload = freezeValue(payload) as Map<String, Object?>;
  final String id;
  final String name;
  final DateTime time;
  final Map<String, Object?> payload;
}

/// Durable work and import checkpoints share a commit boundary. In-flight
/// delivery is deliberately not persisted. Sent apply entries retain dedupe.
final class Outbox {
  Outbox({
    Iterable<ApplyRecord> apply = const [],
    Iterable<EventRecord> events = const [],
    Iterable<String> importedSources = const [],
    this.visitorId,
    this.droppedRecords = 0,
  }) : apply = List.unmodifiable(apply),
       events = List.unmodifiable(events),
       importedSources = Set.unmodifiable(importedSources);
  final List<ApplyRecord> apply;
  final List<EventRecord> events;
  final Set<String> importedSources;
  final String? visitorId;
  final int droppedRecords;

  Outbox copyWith({
    Iterable<ApplyRecord>? apply,
    Iterable<EventRecord>? events,
    Iterable<String>? importedSources,
    String? visitorId,
    int? droppedRecords,
  }) => Outbox(
    apply: apply ?? this.apply,
    events: events ?? this.events,
    importedSources: importedSources ?? this.importedSources,
    visitorId: visitorId ?? this.visitorId,
    droppedRecords: droppedRecords ?? this.droppedRecords,
  );
}
