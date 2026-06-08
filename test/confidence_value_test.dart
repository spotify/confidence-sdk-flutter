import 'package:flutter_test/flutter_test.dart';
import 'package:confidence_flutter_sdk/src/confidence_value.dart';

void main() {
  group('ConfidenceValue constructors', () {
    test('boolean value', () {
      final value = ConfidenceValue.boolean(true);
      expect(value, isA<ConfidenceValueBoolean>());
      expect((value as ConfidenceValueBoolean).value, isTrue);
    });

    test('string value', () {
      final value = ConfidenceValue.string('hello');
      expect(value, isA<ConfidenceValueString>());
      expect((value as ConfidenceValueString).value, equals('hello'));
    });

    test('integer value', () {
      final value = ConfidenceValue.integer(42);
      expect(value, isA<ConfidenceValueInteger>());
      expect((value as ConfidenceValueInteger).value, equals(42));
    });

    test('double value', () {
      final value = ConfidenceValue.double_(3.14);
      expect(value, isA<ConfidenceValueDouble>());
      expect((value as ConfidenceValueDouble).value, equals(3.14));
    });

    test('null value', () {
      final value = ConfidenceValue.null_();
      expect(value, isA<ConfidenceValueNull>());
    });

    test('list value', () {
      final value = ConfidenceValue.list([
        ConfidenceValue.string('a'),
        ConfidenceValue.integer(1),
      ]);
      expect(value, isA<ConfidenceValueList>());
      final list = (value as ConfidenceValueList).value;
      expect(list, hasLength(2));
      expect(list[0], isA<ConfidenceValueString>());
      expect(list[1], isA<ConfidenceValueInteger>());
    });

    test('structure value', () {
      final value = ConfidenceValue.structure({
        'name': ConfidenceValue.string('test'),
        'count': ConfidenceValue.integer(5),
      });
      expect(value, isA<ConfidenceValueStructure>());
      final struct = (value as ConfidenceValueStructure).value;
      expect(struct['name'], isA<ConfidenceValueString>());
      expect(struct['count'], isA<ConfidenceValueInteger>());
    });

    test('deeply nested structure', () {
      final value = ConfidenceValue.structure({
        'outer': ConfidenceValue.structure({
          'inner': ConfidenceValue.structure({
            'deep': ConfidenceValue.string('found'),
          }),
        }),
      });
      expect(value, isA<ConfidenceValueStructure>());
      final outer =
          (value as ConfidenceValueStructure).value['outer']
              as ConfidenceValueStructure;
      final inner = outer.value['inner'] as ConfidenceValueStructure;
      final deep = inner.value['deep'] as ConfidenceValueString;
      expect(deep.value, equals('found'));
    });
  });

  group('ConfidenceValue JSON serialization', () {
    test('boolean round-trips through JSON', () {
      final original = ConfidenceValue.boolean(true);
      final json = original.toJson();
      final restored = ConfidenceValue.fromJson(json);
      expect(restored, isA<ConfidenceValueBoolean>());
      expect((restored as ConfidenceValueBoolean).value, isTrue);
    });

    test('string round-trips through JSON', () {
      final original = ConfidenceValue.string('hello');
      final json = original.toJson();
      final restored = ConfidenceValue.fromJson(json);
      expect((restored as ConfidenceValueString).value, equals('hello'));
    });

    test('integer round-trips through JSON', () {
      final original = ConfidenceValue.integer(42);
      final json = original.toJson();
      final restored = ConfidenceValue.fromJson(json);
      expect((restored as ConfidenceValueInteger).value, equals(42));
    });

    test('double round-trips through JSON', () {
      final original = ConfidenceValue.double_(3.14);
      final json = original.toJson();
      final restored = ConfidenceValue.fromJson(json);
      expect((restored as ConfidenceValueDouble).value, equals(3.14));
    });

    test('null round-trips through JSON', () {
      final original = ConfidenceValue.null_();
      final json = original.toJson();
      final restored = ConfidenceValue.fromJson(json);
      expect(restored, isA<ConfidenceValueNull>());
    });

    test('list round-trips through JSON', () {
      final original = ConfidenceValue.list([
        ConfidenceValue.string('a'),
        ConfidenceValue.integer(1),
        ConfidenceValue.boolean(false),
      ]);
      final json = original.toJson();
      final restored = ConfidenceValue.fromJson(json);
      expect(restored, isA<ConfidenceValueList>());
      final list = (restored as ConfidenceValueList).value;
      expect(list, hasLength(3));
      expect((list[0] as ConfidenceValueString).value, equals('a'));
      expect((list[1] as ConfidenceValueInteger).value, equals(1));
      expect((list[2] as ConfidenceValueBoolean).value, isFalse);
    });

    test('structure round-trips through JSON', () {
      final original = ConfidenceValue.structure({
        'color': ConfidenceValue.string('red'),
        'size': ConfidenceValue.integer(42),
        'enabled': ConfidenceValue.boolean(true),
      });
      final json = original.toJson();
      final restored = ConfidenceValue.fromJson(json);
      expect(restored, isA<ConfidenceValueStructure>());
      final struct = (restored as ConfidenceValueStructure).value;
      expect(
        (struct['color'] as ConfidenceValueString).value,
        equals('red'),
      );
      expect((struct['size'] as ConfidenceValueInteger).value, equals(42));
      expect((struct['enabled'] as ConfidenceValueBoolean).value, isTrue);
    });

    test('nested structure round-trips through JSON', () {
      final original = ConfidenceValue.structure({
        'outer': ConfidenceValue.structure({
          'inner': ConfidenceValue.string('deep'),
        }),
        'list': ConfidenceValue.list([
          ConfidenceValue.structure({
            'item': ConfidenceValue.integer(1),
          }),
        ]),
      });
      final json = original.toJson();
      final restored = ConfidenceValue.fromJson(json);
      expect(restored, isA<ConfidenceValueStructure>());
      final struct = (restored as ConfidenceValueStructure).value;
      final outer = struct['outer'] as ConfidenceValueStructure;
      expect(
        (outer.value['inner'] as ConfidenceValueString).value,
        equals('deep'),
      );
    });
  });

  group('ConfidenceValue equality', () {
    test('same boolean values are equal', () {
      expect(ConfidenceValue.boolean(true), equals(ConfidenceValue.boolean(true)));
    });

    test('different boolean values are not equal', () {
      expect(
        ConfidenceValue.boolean(true),
        isNot(equals(ConfidenceValue.boolean(false))),
      );
    });

    test('same string values are equal', () {
      expect(
        ConfidenceValue.string('hello'),
        equals(ConfidenceValue.string('hello')),
      );
    });

    test('null values are equal', () {
      expect(ConfidenceValue.null_(), equals(ConfidenceValue.null_()));
    });
  });

  group('ConfidenceValue toPlainJson', () {
    test('converts primitives to plain JSON', () {
      expect(ConfidenceValue.string('hello').toPlainJson(), equals('hello'));
      expect(ConfidenceValue.integer(42).toPlainJson(), equals(42));
      expect(ConfidenceValue.double_(3.14).toPlainJson(), equals(3.14));
      expect(ConfidenceValue.boolean(true).toPlainJson(), equals(true));
      expect(ConfidenceValue.null_().toPlainJson(), isNull);
    });

    test('converts structure to plain JSON map', () {
      final value = ConfidenceValue.structure({
        'name': ConfidenceValue.string('test'),
        'count': ConfidenceValue.integer(5),
      });
      final plain = value.toPlainJson();
      expect(plain, isA<Map<String, dynamic>>());
      expect((plain as Map)['name'], equals('test'));
      expect(plain['count'], equals(5));
    });

    test('converts list to plain JSON list', () {
      final value = ConfidenceValue.list([
        ConfidenceValue.string('a'),
        ConfidenceValue.integer(1),
      ]);
      final plain = value.toPlainJson();
      expect(plain, isA<List>());
      expect((plain as List)[0], equals('a'));
      expect(plain[1], equals(1));
    });
  });

  group('ConfidenceValue fromPlainJson', () {
    test('converts plain JSON primitives', () {
      expect(
        ConfidenceValue.fromPlainJson('hello'),
        isA<ConfidenceValueString>(),
      );
      expect(ConfidenceValue.fromPlainJson(42), isA<ConfidenceValueInteger>());
      expect(ConfidenceValue.fromPlainJson(3.14), isA<ConfidenceValueDouble>());
      expect(ConfidenceValue.fromPlainJson(true), isA<ConfidenceValueBoolean>());
      expect(ConfidenceValue.fromPlainJson(null), isA<ConfidenceValueNull>());
    });

    test('converts plain JSON map to structure', () {
      final value = ConfidenceValue.fromPlainJson({
        'name': 'test',
        'count': 5,
      });
      expect(value, isA<ConfidenceValueStructure>());
    });

    test('converts plain JSON list', () {
      final value = ConfidenceValue.fromPlainJson(['a', 1, true]);
      expect(value, isA<ConfidenceValueList>());
    });
  });
}
