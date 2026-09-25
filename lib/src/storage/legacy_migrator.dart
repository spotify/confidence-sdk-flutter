import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'legacy_decoder.dart';
import 'legacy_queue.dart';
import 'outbox.dart';
import 'provider_storage.dart';

final class MigrationReport {
  int importedEvents = 0;
  int importedApply = 0;
  int rejectedEvents = 0;
  int corruptCaches = 0;
}

/// Run before native startup, provider activation, or delivery. Legacy files
/// must not have a concurrent writer. Ownership cannot be inferred from native
/// files: this supports a same-app, same-Confidence-client upgrade.
final class LegacyMigrator {
  LegacyMigrator({
    required LegacyPlatform platform,
    required this.flags,
    required this.apply,
    required this.events,
    required this.readVisitorId,
    required this.destination,
  }) : _decoder = LegacyDecoder(platform);
  final File flags;
  final File apply;
  final Directory events;
  final Future<String?> Function() readVisitorId;
  final ProviderStorage destination;
  final LegacyDecoder _decoder;
  Future<MigrationReport>? _running;

  Future<MigrationReport> run() async {
    final running = _running;
    if (running != null) return running;
    final future = _run();
    _running = future;
    try {
      return await future;
    } finally {
      _running = null;
    }
  }

  Future<MigrationReport> _run() async {
    final report = MigrationReport();
    final initial = await destination.readOutbox();
    if (!initial.importedSources.contains('legacy:identity')) {
      final visitor = await readVisitorId();
      await destination.updateOutbox(
        (box) => box.copyWith(
          visitorId: box.visitorId ?? visitor,
          importedSources: {...box.importedSources, 'legacy:identity'},
        ),
      );
    }
    await _import(flags, 'flags', (bytes, key) async {
      try {
        final snapshot = _decoder.decodeFlags(utf8.decode(bytes));
        // Never replace a newer Dart snapshot on a repeated or interrupted run.
        if (await destination.readSnapshot() == null) {
          await destination.writeSnapshot(snapshot);
        }
      } on FormatException {
        report.corruptCaches++;
      }
      await _checkpoint(key);
    });
    await _import(apply, 'apply', (bytes, key) async {
      List<LegacyApply> records;
      try {
        records = _decoder.decodeApply(utf8.decode(bytes));
      } on FormatException {
        report.corruptCaches++;
        await _checkpoint(key);
        return;
      }
      await destination.updateOutbox((box) {
        final existing = {for (final record in box.apply) record.key: record};
        for (final record in records) {
          final id = (record.resolveToken, record.flag);
          existing.putIfAbsent(
            id,
            () => ApplyRecord(
              token: record.resolveToken,
              flag: record.flag,
              time: record.time,
              sent: record.status == LegacyApplyStatus.sent,
            ),
          );
        }
        return box.copyWith(
          apply: existing.values,
          importedSources: {...box.importedSources, key},
        );
      });
      report.importedApply += records.length;
    });
    if (await events.exists()) {
      final files = await events
          .list(followLinks: false)
          .where((f) => f is File)
          .cast<File>()
          .toList();
      files.sort((a, b) => a.path.compareTo(b.path));
      for (final file in files) {
        await _import(file, 'events', (bytes, key) async {
          final batch = _decoder.decodeEventBytes(bytes);
          await destination.updateOutbox(
            (box) => box.copyWith(
              events: [
                ...box.events,
                for (final e in batch.events)
                  EventRecord(
                    id: '$key:${e.sourceLine}',
                    name: e.name,
                    time: e.time,
                    payload: e.payload,
                  ),
              ],
              importedSources: {...box.importedSources, key},
            ),
          );
          report.importedEvents += batch.events.length;
          report.rejectedEvents += batch.rejectedLines.length;
        });
      }
    }
    return report;
  }

  Future<void> _checkpoint(String key) => destination
      .updateOutbox(
        (box) => box.copyWith(importedSources: {...box.importedSources, key}),
      )
      .then((_) {});

  Future<void> _import(
    File file,
    String kind,
    Future<void> Function(List<int>, String) import,
  ) async {
    List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } on PathNotFoundException {
      return;
    }
    // File identity distinguishes legitimate identical batches. Content binds
    // checkpoints to the source generation. Do not include the sandbox prefix,
    // which iOS may relocate. Source files are immutable during migration.
    final key =
        'legacy:$kind:${sha256.convert([...utf8.encode(file.uri.pathSegments.last), 0, ...bytes])}';
    if (!(await destination.readOutbox()).importedSources.contains(key)) {
      await import(bytes, key);
    }
    // Cleanup only after the destination commit; a failed cleanup is retryable.
    await file.delete();
  }
}
