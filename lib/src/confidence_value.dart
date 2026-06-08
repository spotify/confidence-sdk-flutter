sealed class ConfidenceValue {
  const ConfidenceValue();

  static ConfidenceValue boolean(bool value) => ConfidenceValueBoolean(value);
  static ConfidenceValue string(String value) => ConfidenceValueString(value);
  static ConfidenceValue integer(int value) => ConfidenceValueInteger(value);
  static ConfidenceValue double_(double value) => ConfidenceValueDouble(value);
  static ConfidenceValue date(DateTime value) => ConfidenceValueDate(value);
  static ConfidenceValue timestamp(DateTime value) =>
      ConfidenceValueTimestamp(value);
  static ConfidenceValue list(List<ConfidenceValue> value) =>
      ConfidenceValueList(value);
  static ConfidenceValue structure(Map<String, ConfidenceValue> value) =>
      ConfidenceValueStructure(value);
  static ConfidenceValue null_() => const ConfidenceValueNull();

  dynamic toJson();

  dynamic toPlainJson() => switch (this) {
    ConfidenceValueBoolean(value: final v) => v,
    ConfidenceValueString(value: final v) => v,
    ConfidenceValueInteger(value: final v) => v,
    ConfidenceValueDouble(value: final v) => v,
    ConfidenceValueDate(value: final v) => v.toIso8601String().split('T')[0],
    ConfidenceValueTimestamp(value: final v) => v.toUtc().toIso8601String(),
    ConfidenceValueList(value: final v) =>
      v.map((e) => e.toPlainJson()).toList(),
    ConfidenceValueStructure(value: final v) =>
      v.map((k, e) => MapEntry(k, e.toPlainJson())),
    ConfidenceValueNull() => null,
  };

  static ConfidenceValue fromJson(dynamic json) {
    if (json == null) return const ConfidenceValueNull();
    if (json is bool) return ConfidenceValueBoolean(json);
    if (json is int) return ConfidenceValueInteger(json);
    if (json is double) return ConfidenceValueDouble(json);
    if (json is String) return ConfidenceValueString(json);
    if (json is List) {
      return ConfidenceValueList(json.map(ConfidenceValue.fromJson).toList());
    }
    if (json is Map<String, dynamic>) {
      return ConfidenceValueStructure(
        json.map((k, v) => MapEntry(k, ConfidenceValue.fromJson(v))),
      );
    }
    return const ConfidenceValueNull();
  }

  static ConfidenceValue fromPlainJson(dynamic json) => fromJson(json);
}

final class ConfidenceValueBoolean extends ConfidenceValue {
  final bool value;
  const ConfidenceValueBoolean(this.value);

  @override
  dynamic toJson() => value;

  @override
  bool operator ==(Object other) =>
      other is ConfidenceValueBoolean && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class ConfidenceValueString extends ConfidenceValue {
  final String value;
  const ConfidenceValueString(this.value);

  @override
  dynamic toJson() => value;

  @override
  bool operator ==(Object other) =>
      other is ConfidenceValueString && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class ConfidenceValueInteger extends ConfidenceValue {
  final int value;
  const ConfidenceValueInteger(this.value);

  @override
  dynamic toJson() => value;

  @override
  bool operator ==(Object other) =>
      other is ConfidenceValueInteger && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class ConfidenceValueDouble extends ConfidenceValue {
  final double value;
  const ConfidenceValueDouble(this.value);

  @override
  dynamic toJson() => value;

  @override
  bool operator ==(Object other) =>
      other is ConfidenceValueDouble && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class ConfidenceValueDate extends ConfidenceValue {
  final DateTime value;
  const ConfidenceValueDate(this.value);

  @override
  dynamic toJson() => value.toIso8601String().split('T')[0];

  @override
  bool operator ==(Object other) =>
      other is ConfidenceValueDate && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class ConfidenceValueTimestamp extends ConfidenceValue {
  final DateTime value;
  const ConfidenceValueTimestamp(this.value);

  @override
  dynamic toJson() => value.toUtc().toIso8601String();

  @override
  bool operator ==(Object other) =>
      other is ConfidenceValueTimestamp && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class ConfidenceValueList extends ConfidenceValue {
  final List<ConfidenceValue> value;
  const ConfidenceValueList(this.value);

  @override
  dynamic toJson() => value.map((e) => e.toJson()).toList();

  @override
  bool operator ==(Object other) =>
      other is ConfidenceValueList &&
      value.length == other.value.length &&
      _listEquals(value, other.value);

  @override
  int get hashCode => Object.hashAll(value);
}

final class ConfidenceValueStructure extends ConfidenceValue {
  final Map<String, ConfidenceValue> value;
  const ConfidenceValueStructure(this.value);

  @override
  dynamic toJson() => value.map((k, v) => MapEntry(k, v.toJson()));

  @override
  bool operator ==(Object other) =>
      other is ConfidenceValueStructure &&
      value.length == other.value.length &&
      value.entries.every(
        (e) => other.value.containsKey(e.key) && other.value[e.key] == e.value,
      );

  @override
  int get hashCode => Object.hashAll(value.entries.map((e) => e.hashCode));
}

final class ConfidenceValueNull extends ConfidenceValue {
  const ConfidenceValueNull();

  @override
  dynamic toJson() => null;

  @override
  bool operator ==(Object other) => other is ConfidenceValueNull;

  @override
  int get hashCode => 0;
}

bool _listEquals(List<ConfidenceValue> a, List<ConfidenceValue> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
