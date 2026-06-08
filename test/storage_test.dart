import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:confidence_flutter_sdk/src/storage.dart';

void main() {
  group('MemoryStorage', () {
    late MemoryStorage storage;

    setUp(() {
      storage = MemoryStorage();
    });

    test('read returns null for non-existent key', () async {
      final result = await storage.read('nonexistent');
      expect(result, isNull);
    });

    test('write and read round-trip', () async {
      await storage.write('key1', 'value1');
      final result = await storage.read('key1');
      expect(result, equals('value1'));
    });

    test('write overwrites existing value', () async {
      await storage.write('key1', 'value1');
      await storage.write('key1', 'value2');
      final result = await storage.read('key1');
      expect(result, equals('value2'));
    });

    test('delete removes the key', () async {
      await storage.write('key1', 'value1');
      await storage.delete('key1');
      final result = await storage.read('key1');
      expect(result, isNull);
    });

    test('delete non-existent key does not throw', () async {
      await storage.delete('nonexistent');
    });

    test('exists returns false for non-existent key', () async {
      final result = await storage.exists('nonexistent');
      expect(result, isFalse);
    });

    test('exists returns true after write', () async {
      await storage.write('key1', 'value1');
      final result = await storage.exists('key1');
      expect(result, isTrue);
    });

    test('exists returns false after delete', () async {
      await storage.write('key1', 'value1');
      await storage.delete('key1');
      final result = await storage.exists('key1');
      expect(result, isFalse);
    });

    test('multiple keys are independent', () async {
      await storage.write('key1', 'value1');
      await storage.write('key2', 'value2');
      expect(await storage.read('key1'), equals('value1'));
      expect(await storage.read('key2'), equals('value2'));
      await storage.delete('key1');
      expect(await storage.read('key1'), isNull);
      expect(await storage.read('key2'), equals('value2'));
    });
  });

  group('DiskStorage', () {
    late Directory tempDir;
    late DiskStorage storage;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('confidence_test_');
      storage = DiskStorage(tempDir.path);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('read returns null for non-existent key', () async {
      final result = await storage.read('nonexistent');
      expect(result, isNull);
    });

    test('write and read round-trip', () async {
      await storage.write('flags', '{"data": "test"}');
      final result = await storage.read('flags');
      expect(result, equals('{"data": "test"}'));
    });

    test('write creates the directory if needed', () async {
      final nested = DiskStorage('${tempDir.path}/sub/dir');
      await nested.write('key', 'value');
      final result = await nested.read('key');
      expect(result, equals('value'));
    });

    test('write overwrites existing value', () async {
      await storage.write('key', 'v1');
      await storage.write('key', 'v2');
      expect(await storage.read('key'), equals('v2'));
    });

    test('delete removes the file', () async {
      await storage.write('key', 'value');
      await storage.delete('key');
      expect(await storage.read('key'), isNull);
    });

    test('delete non-existent key does not throw', () async {
      await storage.delete('nonexistent');
    });

    test('exists returns correct values', () async {
      expect(await storage.exists('key'), isFalse);
      await storage.write('key', 'value');
      expect(await storage.exists('key'), isTrue);
      await storage.delete('key');
      expect(await storage.exists('key'), isFalse);
    });

    test('handles special characters in data', () async {
      final data = '{"emoji": "\\u{1F600}", "newline": "line1\\nline2"}';
      await storage.write('special', data);
      expect(await storage.read('special'), equals(data));
    });
  });
}
