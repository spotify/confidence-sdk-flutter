import 'dart:io';

abstract class Storage {
  Future<String?> read(String key);
  Future<void> write(String key, String data);
  Future<void> delete(String key);
  Future<bool> exists(String key);
}

class MemoryStorage implements Storage {
  final Map<String, String> _store = {};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String data) async => _store[key] = data;

  @override
  Future<void> delete(String key) async => _store.remove(key);

  @override
  Future<bool> exists(String key) async => _store.containsKey(key);
}

class DiskStorage implements Storage {
  final String _directoryPath;

  DiskStorage(this._directoryPath);

  String _filePath(String key) =>
      '$_directoryPath/${key.replaceAll('/', '_')}';

  @override
  Future<String?> read(String key) async {
    final file = File(_filePath(key));
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> write(String key, String data) async {
    final file = File(_filePath(key));
    await file.parent.create(recursive: true);
    await file.writeAsString(data);
  }

  @override
  Future<void> delete(String key) async {
    final file = File(_filePath(key));
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<bool> exists(String key) async => File(_filePath(key)).exists();
}
