import 'dart:async';

class AsyncGate {
  Completer<void>? _pending;

  Future<T> run<T>(Future<T> Function() operation) async {
    while (_pending != null) {
      await _pending!.future;
    }
    _pending = Completer<void>();
    try {
      return await operation();
    } finally {
      final p = _pending!;
      _pending = null;
      p.complete();
    }
  }
}
