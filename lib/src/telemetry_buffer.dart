import 'dart:async';
import 'dart:convert';

import 'storage/outbox.dart';
import 'storage/provider_storage.dart';
import 'storage/storage_codec.dart' as codec;

/// In-memory enqueue followed by coalesced durable commits. Delivery is separate.
final class TelemetryBuffer {
  TelemetryBuffer(
    this.storage,
    Outbox initial, {
    this.maxBytes = 4 * 1024 * 1024,
    required this.onPersistenceError,
  }) : _seen = initial.apply.map((a) => a.key).toSet() {
    if (maxBytes <= 0) throw ArgumentError('Outbox budget must be positive.');
    _schedule();
  }

  final ProviderStorage storage;
  final int maxBytes;
  final void Function() onPersistenceError;
  final Set<(String, String)> _seen;
  final List<ApplyRecord> _apply = [];
  final List<EventRecord> _events = [];
  Future<void> _tail = Future.value();
  bool _scheduled = false;
  bool _needsBound = true;

  void apply(ApplyRecord record) {
    if (!_seen.add(record.key)) return;
    _apply.add(record);
    _schedule();
  }

  void track(EventRecord record) {
    _events.add(record);
    _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      unawaited(persist().catchError((Object _) => onPersistenceError()));
    });
  }

  /// Captures calls made before this operation. Later enqueues use another
  /// commit, and acknowledgements use the same serialized storage writer.
  Future<void> persist() {
    final result = _tail.then((_) async {
      final apply = List<ApplyRecord>.of(_apply);
      final events = List<EventRecord>.of(_events);
      _apply.clear();
      _events.clear();
      if (apply.isEmpty && events.isEmpty && !_needsBound) return;
      try {
        await storage.updateOutbox((box) {
          final existing = {for (final a in box.apply) a.key: a};
          for (final a in apply) {
            existing.putIfAbsent(a.key, () => a);
          }
          return _bounded(
            box.copyWith(
              apply: existing.values,
              events: [...box.events, ...events],
            ),
          );
        });
        _needsBound = false;
      } catch (_) {
        _apply.insertAll(0, apply);
        _events.insertAll(0, events);
        rethrow;
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Outbox _bounded(Outbox box) {
    final apply = box.apply.toList();
    final events = box.events.toList();
    final encoded = codec.encodeOutbox(box);
    final encodedApply = codec.list(encoded['apply']);
    final encodedEvents = codec.list(encoded['events']);
    final candidates =
        <({DateTime time, int index, bool event, int bytes})>[
          for (var i = 0; i < apply.length; i++)
            if (!apply[i].sent)
              (
                time: apply[i].time,
                index: i,
                event: false,
                bytes: utf8.encode(jsonEncode(encodedApply[i])).length,
              ),
          for (var i = 0; i < events.length; i++)
            (
              time: events[i].time,
              index: i,
              event: true,
              bytes: utf8.encode(jsonEncode(encodedEvents[i])).length,
            ),
        ]..sort((a, b) {
          final byTime = a.time.compareTo(b.time);
          if (byTime != 0) return byTime;
          if (a.event != b.event) return a.event ? 1 : -1;
          return a.index.compareTo(b.index);
        });
    final droppedApply = <int>{};
    final droppedEvents = <int>{};
    var count = 0;
    Outbox candidate() => box.copyWith(
      apply: [
        for (var i = 0; i < apply.length; i++)
          if (!droppedApply.contains(i)) apply[i],
      ],
      events: [
        for (var i = 0; i < events.length; i++)
          if (!droppedEvents.contains(i)) events[i],
      ],
      droppedRecords: box.droppedRecords + count,
    );
    var size = _size(box);
    void remove(({DateTime time, int index, bool event, int bytes}) record) {
      final remaining = record.event
          ? events.length - droppedEvents.length
          : apply.length - droppedApply.length;
      size -= record.bytes + (remaining > 1 ? 1 : 0);
      (record.event ? droppedEvents : droppedApply).add(record.index);
      final previousDigits = (box.droppedRecords + count).toString().length;
      count++;
      size += (box.droppedRecords + count).toString().length - previousDigits;
    }

    // An individually oversized record cannot fit even in an otherwise empty
    // queue. Reject it without first sacrificing every smaller queued record.
    final metadataSize = _size(
      box.copyWith(apply: apply.where((a) => a.sent), events: []),
    );
    for (final record in candidates) {
      if (metadataSize + record.bytes > maxBytes) remove(record);
    }
    for (final record in candidates) {
      if (size <= maxBytes) break;
      if ((record.event ? droppedEvents : droppedApply).contains(
        record.index,
      )) {
        continue;
      }
      remove(record);
    }
    final result = candidate();
    if (_size(result) > maxBytes) {
      // Never silently remove identity or import checkpoints to satisfy a cap.
      throw StateError('Outbox metadata exceeds its storage budget.');
    }
    return result;
  }

  int _size(Outbox box) => utf8
      .encode(jsonEncode({'version': 1, 'data': codec.encodeOutbox(box)}))
      .length;
}
