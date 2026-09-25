import '../snapshot.dart';

enum LegacyApplyStatus { created, sending, sent }

/// Retains sent entries in mixed native groups for migration-time deduplication.
/// Sending entries must become pending again when imported into the outbox.
final class LegacyApply {
  const LegacyApply({
    required this.resolveToken,
    required this.flag,
    required this.time,
    required this.status,
  });

  final String resolveToken;
  final String flag;
  final DateTime time;
  final LegacyApplyStatus status;
}

final class LegacyEvent {
  LegacyEvent({
    required this.sourceLine,
    required this.name,
    required this.time,
    required Map<String, Object?> payload,
  }) : payload = freezeValue(payload) as Map<String, Object?>;

  /// One-based physical line number; combine with source file identity during
  /// import. Never deduplicate by payload: identical events can be legitimate.
  final int sourceLine;
  final String name;
  final DateTime time;

  /// Native SDKs have already merged the event's original context into payload.
  final Map<String, Object?> payload;
}

/// A damaged record does not prevent importing other records from the file.
/// Diagnostics contain positions only, never payloads or credentials.
final class LegacyEventBatch {
  LegacyEventBatch(Iterable<LegacyEvent> events, Iterable<int> rejectedLines)
    : events = List.unmodifiable(events),
      rejectedLines = List.unmodifiable(rejectedLines);

  final List<LegacyEvent> events;
  final List<int> rejectedLines;
}
