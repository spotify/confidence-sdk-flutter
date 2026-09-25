/// A fetched snapshot. Activation and context matching are separate concerns.
final class FlagSnapshot {
  FlagSnapshot({
    required Map<String, Object?> context,
    required Map<String, ResolvedFlag> flags,
    required this.resolveToken,
  }) : context = freezeValue(context) as Map<String, Object?>,
       flags = Map.unmodifiable(flags);

  final Map<String, Object?> context;
  final Map<String, ResolvedFlag> flags;
  final String resolveToken;
}

final class ResolvedFlag {
  ResolvedFlag({
    required this.name,
    required Object? value,
    required this.reason,
    required this.variant,
    required this.shouldApply,
  }) : value = freezeValue(value);

  final String name;
  final Object? value;
  final String reason;
  final String? variant;
  final bool shouldApply;
}

/// A calendar date, distinct from a timestamp. Retains Swift DateComponents
/// metadata (including calendar/time zone) until conversion is needed.
final class CalendarDate {
  CalendarDate(Map<String, Object?> components)
    : components = freezeValue(components) as Map<String, Object?>;

  final Map<String, Object?> components;
}

/// Keep native scalar types (especially int/double) and freeze nested containers.
Object? freezeValue(Object? value) => switch (value) {
  null ||
  bool() ||
  String() ||
  int() ||
  double() ||
  DateTime() ||
  CalendarDate() => value,
  Map<String, Object?>() => Map<String, Object?>.unmodifiable(
    value.map((key, value) => MapEntry(key, freezeValue(value))),
  ),
  List<Object?>() => List<Object?>.unmodifiable(value.map(freezeValue)),
  _ => throw ArgumentError('Unsupported snapshot value type.'),
};
