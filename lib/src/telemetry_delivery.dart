import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'resolver.dart';
import 'calendar_conversion.dart';
import 'storage/outbox.dart';
import 'storage/provider_storage.dart';
import 'telemetry_buffer.dart';

/// Counts for this attempt; concurrent enqueues may remain pending afterwards.
final class ConfidenceFlushResult {
  const ConfidenceFlushResult({
    required this.acceptedRecords,
    required this.droppedRecords,
    required this.pendingRecords,
    required this.retryNeeded,
  });
  final int acceptedRecords;
  final int droppedRecords;
  final int pendingRecords;
  final bool retryNeeded;
}

/// One scheduler for both queues; the storage owner serializes replacement
/// providers' delivery attempts without holding its disk lock over network I/O.
final class TelemetryDelivery {
  TelemetryDelivery(
    this.storage,
    this.buffer,
    this.resolver, {
    required this.onFailure,
    DateTime Function()? now,
    double Function()? random,
    this.interval = const Duration(seconds: 60),
  }) : _now = now ?? DateTime.now,
       _random = random ?? Random().nextDouble;
  final ProviderStorage storage;
  final TelemetryBuffer buffer;
  final ConfidenceResolver resolver;
  final void Function() onFailure;
  final DateTime Function() _now;
  final double Function() _random;
  final Duration interval;
  Timer? _timer;
  bool _closed = false;
  int _failures = 0;
  Future<ConfidenceFlushResult>? _running;

  void start() => _schedule(interval);

  void _schedule(Duration delay) {
    if (_closed) return;
    _timer?.cancel();
    _timer = Timer(delay, () async {
      var retry = true;
      try {
        retry = (await flush()).retryNeeded;
      } catch (_) {
        onFailure();
      }
      if (retry) {
        _failures = min(_failures + 1, 7);
        final seconds = min(60, 1 << (_failures - 1));
        _schedule(
          Duration(
            milliseconds: (seconds * 1000 * (0.5 + _random() * 0.5)).round(),
          ),
        );
      } else {
        _failures = 0;
        _schedule(interval);
      }
    });
  }

  Future<ConfidenceFlushResult> flush() async {
    if (_closed) throw StateError('Delivery is closed.');
    // Each caller's enqueues must be durable, even when joining an active send.
    await buffer.persist();
    if (_closed) throw StateError('Delivery is closed.');
    final running = _running;
    if (running != null) {
      await running;
      return flush();
    }
    final operation = storage.serializeDelivery(_deliver);
    _running = operation;
    try {
      return await operation;
    } finally {
      _running = null;
    }
  }

  Future<ConfidenceFlushResult> _deliver() async {
    var accepted = 0;
    var dropped = 0;
    var retry = false;
    final initial = await storage.readOutbox();
    final groups = <String, List<ApplyRecord>>{};
    for (final record in initial.apply.where((a) => !a.sent)) {
      groups.putIfAbsent(record.token, () => []).add(record);
    }
    for (final group in groups.values) {
      for (var offset = 0; offset < group.length && !_closed; offset += 20) {
        final queued = (await storage.readOutbox()).apply
            .where((a) => !a.sent)
            .map((a) => a.key)
            .toSet();
        final batch = group
            .skip(offset)
            .take(20)
            .where((a) => queued.contains(a.key))
            .toList();
        if (batch.isEmpty) continue;
        final outcome = await _send(
          resolver.endpoints.apply,
          {
            'resolveToken': batch.first.token,
            'flags': [
              for (final a in batch)
                {
                  'flag': 'flags/${a.flag}',
                  'applyTime': a.time.toUtc().toIso8601String(),
                },
            ],
          },
          batch.length,
          events: false,
        );
        if (_closed) break;
        if (outcome == null) {
          retry = true;
          break;
        }
        final keys = batch.map((a) => a.key).toSet();
        await storage.updateOutbox((box) {
          final present = box.apply
              .where((a) => !a.sent && keys.contains(a.key))
              .length;
          dropped += outcome.isEmpty ? 0 : present;
          accepted += outcome.isEmpty ? present : 0;
          return box.copyWith(
            apply: [
              for (final a in box.apply)
                if (keys.contains(a.key))
                  ApplyRecord(
                    token: a.token,
                    flag: a.flag,
                    time: a.time,
                    sent: true,
                  )
                else
                  a,
            ],
            droppedRecords:
                box.droppedRecords + (outcome.isEmpty ? 0 : present),
          );
        });
      }
      if (retry) break;
    }
    for (
      var offset = 0;
      offset < initial.events.length && !_closed;
      offset += 10
    ) {
      final queued = (await storage.readOutbox()).events
          .map((e) => e.id)
          .toSet();
      final batch = <EventRecord>[];
      final wire = <Map<String, Object?>>[];
      for (final event in initial.events.skip(offset).take(10)) {
        if (!queued.contains(event.id)) continue;
        try {
          wire.add({
            'eventDefinition': 'eventDefinitions/${event.name}',
            'eventTime': event.time.toUtc().toIso8601String(),
            'payload': await eventWireValue(event.payload),
          });
          batch.add(event);
        } on FormatException {
          // Failed native conversion stays durable; it must not poison other
          // events or discard the original calendar metadata.
          retry = true;
        }
      }
      if (_closed) break;
      if (batch.isEmpty) continue;
      final outcome = await _send(
        resolver.endpoints.publish,
        {'events': wire},
        batch.length,
        events: true,
      );
      if (_closed) break;
      if (outcome == null) {
        retry = true;
        break;
      }
      final ids = batch.map((e) => e.id).toSet();
      final rejected = {for (final i in outcome) batch[i].id};
      await storage.updateOutbox((box) {
        final present = box.events.where((e) => ids.contains(e.id)).toList();
        final lost = present.where((e) => rejected.contains(e.id)).length;
        dropped += lost;
        accepted += present.length - lost;
        return box.copyWith(
          events: box.events.where((e) => !ids.contains(e.id)),
          droppedRecords: box.droppedRecords + lost,
        );
      });
    }
    final remaining = await storage.readOutbox();
    final pending =
        remaining.events.length + remaining.apply.where((a) => !a.sent).length;
    return ConfidenceFlushResult(
      acceptedRecords: accepted,
      droppedRecords: dropped,
      pendingRecords: pending,
      retryNeeded: retry || _closed,
    );
  }

  /// Null retries the batch; otherwise these indices are permanent rejections.
  Future<Set<int>?> _send(
    Uri uri,
    Map<String, Object?> fields,
    int count, {
    required bool events,
  }) async {
    try {
      final response = await resolver.transport.post(uri, {
        'clientSecret': resolver.configuration.clientSecret,
        'sdk': resolver.sdk,
        'sendTime': _now().toUtc().toIso8601String(),
        ...fields,
      });
      final status = response.status;
      if (status >= 400 && status < 500 && status != 408 && status != 429) {
        return {for (var i = 0; i < count; i++) i};
      }
      if (status != 200) return null;
      if (!events) return <int>{};
      final data = jsonDecode(response.body);
      if (data is! Map<String, Object?>) return null;
      final errors = data['errors'] ?? <Object?>[];
      if (errors is! List) return null;
      final rejected = <int>{};
      for (final error in errors) {
        if (error is! Map<String, Object?>) return null;
        final index = error['index'] ?? 0; // Protobuf's default integer value.
        if (index is! int ||
            index < 0 ||
            index >= count ||
            !rejected.add(index)) {
          return null;
        }
        if (error['reason'] != 'EVENT_DEFINITION_NOT_FOUND' &&
            error['reason'] != 'EVENT_SCHEMA_VALIDATION_FAILED') {
          return null;
        }
      }
      return rejected;
    } catch (_) {
      return null;
    }
  }

  void close() {
    _closed = true;
    _timer?.cancel();
  }
}
