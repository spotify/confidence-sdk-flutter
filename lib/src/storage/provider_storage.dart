import 'dart:convert';
import 'dart:io';

import '../snapshot.dart';
import 'outbox.dart';
import 'storage_codec.dart' as codec;

/// One owner per provider storage scope. All reads and writes are serialized;
/// failed transactions leave the previously committed file readable.
final class ProviderStorage {
  ProviderStorage(this.directory, {Future<void> Function(File, String)? commit})
    : _commit = commit ?? atomicWrite;
  final Directory directory;
  final Future<void> Function(File, String) _commit;
  Future<void> _tail = Future.value();
  Future<void> _deliveryTail = Future.value();

  Future<T> serializeDelivery<T>(Future<T> Function() operation) {
    final result = _deliveryTail.then((_) => operation());
    _deliveryTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  final List<Object> _snapshotOwners = [];

  Object claimSnapshotWriter() {
    final owner = Object();
    _snapshotOwners.add(owner);
    return owner;
  }

  bool isSnapshotWriter(Object owner) =>
      _snapshotOwners.isNotEmpty && identical(_snapshotOwners.last, owner);
  void releaseSnapshotWriter(Object owner) => _snapshotOwners.remove(owner);

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  File _file(String name) => File('${directory.path}/$name.json');

  Future<T?> _read<T>(String name, T Function(Object?) decode) async {
    final file = _file(name);
    List<int> contents;
    try {
      contents = await file.readAsBytes();
    } on PathNotFoundException {
      return null;
    }
    try {
      final envelope = codec.map(jsonDecode(utf8.decode(contents)));
      final version = envelope['version'];
      if (version is! int) codec.invalid();
      if (version != 1) throw UnsupportedError('Unsupported storage version.');
      return decode(envelope['data']);
    } on FormatException {
      await file.delete();
      return null;
    } on ArgumentError {
      await file.delete();
      return null;
    }
  }

  Future<void> _write(String name, Object data) =>
      _commit(_file(name), jsonEncode({'version': 1, 'data': data}));

  Future<FlagSnapshot?> readSnapshot() =>
      _serialized(() => _read('snapshot', codec.decodeSnapshot));
  Future<void> writeSnapshot(
    FlagSnapshot snapshot, {
    bool Function()? shouldWrite,
  }) => _serialized(() async {
    if (shouldWrite != null && !shouldWrite()) return;
    await _write('snapshot', codec.encodeSnapshot(snapshot));
  });
  Future<Outbox> readOutbox() => _serialized(
    () async => await _read('outbox', codec.decodeOutbox) ?? Outbox(),
  );

  /// The transform sees the latest durable state, including earlier queued
  /// updates. Callers can coalesce in-memory enqueues into one transaction.
  Future<Outbox> updateOutbox(Outbox Function(Outbox) transform) => _serialized(
    () async {
      final previous = await _read('outbox', codec.decodeOutbox) ?? Outbox();
      final next = transform(previous);
      final data = codec.encodeOutbox(next);
      codec.decodeOutbox(data); // Reject duplicate IDs/keys before committing.
      await _write('outbox', data);
      return next;
    },
  );

  /// The temporary file lives beside the destination so rename is atomic on
  /// supported mobile filesystems. A stale temporary file is never activated.
  static Future<void> atomicWrite(File destination, String contents) async {
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsString(contents, flush: true);
    await temporary.rename(destination.path);
  }
}
