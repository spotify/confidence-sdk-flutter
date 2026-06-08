import 'confidence_value.dart';
import 'evaluation.dart';

class ResolvedFlag {
  final String flag;
  final String variant;
  final ConfidenceValueStructure? value;
  final ResolveReason reason;
  final bool shouldApply;

  const ResolvedFlag({
    required this.flag,
    required this.variant,
    required this.value,
    required this.reason,
    required this.shouldApply,
  });

  Map<String, dynamic> toJson() => {
    'flag': flag,
    'variant': variant,
    'value': value?.toJson(),
    'reason': reason.toJson(),
    'shouldApply': shouldApply,
  };

  factory ResolvedFlag.fromJson(Map<String, dynamic> json) {
    final valueJson = json['value'];
    ConfidenceValueStructure? value;
    if (valueJson != null && valueJson is Map<String, dynamic>) {
      value = ConfidenceValue.fromJson(valueJson) as ConfidenceValueStructure;
    }
    return ResolvedFlag(
      flag: json['flag'] as String,
      variant: json['variant'] as String? ?? '',
      value: value,
      reason: ResolveReason.fromString(json['reason'] as String? ?? ''),
      shouldApply: json['shouldApply'] as bool? ?? true,
    );
  }
}

class FlagResolution {
  final List<ResolvedFlag> flags;
  final String resolveToken;

  const FlagResolution({
    required this.flags,
    required this.resolveToken,
  });

  Evaluation<T> evaluate<T>(String flagPath, T defaultValue) {
    final parts = flagPath.split('.');
    if (parts.length < 2) {
      return Evaluation(
        value: defaultValue,
        reason: ResolveReason.error,
        errorCode: 'INVALID_FLAG_PATH',
        errorMessage: 'Flag path must contain at least flag name and property',
      );
    }

    final flagName = parts[0];
    final propertyPath = parts.sublist(1);

    final resolvedFlag = _findFlag(flagName);
    if (resolvedFlag == null) {
      return Evaluation(
        value: defaultValue,
        reason: ResolveReason.error,
        errorCode: 'FLAG_NOT_FOUND',
        errorMessage: 'Flag "$flagName" not found',
      );
    }

    if (resolvedFlag.value == null) {
      return Evaluation(
        value: defaultValue,
        variant: resolvedFlag.variant,
        reason: resolvedFlag.reason,
      );
    }

    final extracted = _walkPath(resolvedFlag.value!, propertyPath);
    if (extracted == null) {
      return Evaluation(
        value: defaultValue,
        variant: resolvedFlag.variant,
        reason: ResolveReason.error,
        errorCode: 'VALUE_NOT_FOUND',
        errorMessage: 'Property path "${propertyPath.join('.')}" not found',
      );
    }

    final typed = _castValue<T>(extracted);
    if (typed == null) {
      return Evaluation(
        value: defaultValue,
        variant: resolvedFlag.variant,
        reason: ResolveReason.error,
        errorCode: 'TYPE_MISMATCH',
        errorMessage:
            'Expected $T but got ${extracted.runtimeType}',
      );
    }

    return Evaluation(
      value: typed,
      variant: resolvedFlag.variant,
      reason: resolvedFlag.reason,
    );
  }

  ResolvedFlag? _findFlag(String flagName) {
    for (final flag in flags) {
      if (flag.flag == flagName) return flag;
    }
    return null;
  }

  ConfidenceValue? _walkPath(
    ConfidenceValueStructure struct,
    List<String> path,
  ) {
    ConfidenceValue current = struct;
    for (final key in path) {
      if (current is! ConfidenceValueStructure) return null;
      final next = current.value[key];
      if (next == null) return null;
      current = next;
    }
    return current;
  }

  T? _castValue<T>(ConfidenceValue value) {
    if (T == String && value is ConfidenceValueString) {
      return value.value as T;
    }
    if (T == int && value is ConfidenceValueInteger) {
      return value.value as T;
    }
    if (T == bool && value is ConfidenceValueBoolean) {
      return value.value as T;
    }
    if (T == double && value is ConfidenceValueDouble) {
      return value.value as T;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'resolvedFlags': flags.map((f) => f.toJson()).toList(),
    'resolveToken': resolveToken,
  };

  factory FlagResolution.fromJson(Map<String, dynamic> json) {
    final flagsList = (json['resolvedFlags'] as List?)
            ?.map((f) => ResolvedFlag.fromJson(f as Map<String, dynamic>))
            .toList() ??
        [];
    return FlagResolution(
      flags: flagsList,
      resolveToken: json['resolveToken'] as String? ?? '',
    );
  }
}
