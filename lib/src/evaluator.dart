import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk.dart';

import 'snapshot.dart';

/// Entirely synchronous. The exposure sink must only enqueue in memory.
final class FlagEvaluator {
  FlagEvaluator({required this.onExposure});
  final void Function(String token, String flag) onExposure;
  FlagSnapshot? active;
  bool ready = false;
  bool stale = false;

  ResolutionDetails<T> evaluate<T>(
    String key,
    T fallback,
    Map<String, Object?> context,
  ) {
    ResolutionDetails<T> error(ErrorCode code, String message) =>
        ResolutionDetails(
          value: fallback,
          reason: 'ERROR',
          errorCode: code,
          errorMessage: message,
        );
    if (!ready) {
      return error(ErrorCode.providerNotReady, 'Provider is not ready.');
    }
    final snapshot = active;
    if (snapshot == null) {
      return error(ErrorCode.flagNotFound, 'No flag snapshot.');
    }
    if (!sameValue(snapshot.context, context)) {
      return error(
        ErrorCode.invalidContext,
        'Snapshot context does not match.',
      );
    }
    final parts = key.split('.');
    if (parts.any((part) => part.isEmpty)) {
      return error(ErrorCode.parseError, 'Invalid flag property path.');
    }
    final flag = snapshot.flags[parts.first];
    if (flag == null) return error(ErrorCode.flagNotFound, 'Flag not found.');
    final backendError = switch (flag.reason) {
      'RESOLVE_REASON_TARGETING_KEY_ERROR' => ErrorCode.invalidContext,
      'RESOLVE_REASON_TYPE_MISMATCH' => ErrorCode.typeMismatch,
      'RESOLVE_REASON_FLAG_NOT_FOUND' => ErrorCode.flagNotFound,
      'RESOLVE_REASON_MATCH' ||
      'RESOLVE_REASON_BUNDLE' ||
      'RESOLVE_REASON_STALE' ||
      'RESOLVE_REASON_NO_SEGMENT_MATCH' ||
      'RESOLVE_REASON_NO_TREATMENT_MATCH' ||
      'RESOLVE_REASON_FLAG_ARCHIVED' => null,
      _ => ErrorCode.general,
    };
    if (backendError != null) {
      return error(backendError, 'Backend could not resolve flag.');
    }
    final defaultReason = switch (flag.reason) {
      'RESOLVE_REASON_FLAG_ARCHIVED' => 'DISABLED',
      'RESOLVE_REASON_NO_SEGMENT_MATCH' ||
      'RESOLVE_REASON_NO_TREATMENT_MATCH' => 'DEFAULT',
      _ => null,
    };
    Object? value = flag.value;
    if (defaultReason == null && value != null) {
      for (final part in parts.skip(1)) {
        if (value is! Map<String, Object?> || !value.containsKey(part)) {
          return error(ErrorCode.flagNotFound, 'Flag property not found.');
        }
        value = value[part];
      }
      if (value != null && value is! T) {
        return error(
          ErrorCode.typeMismatch,
          'Flag property has a different type.',
        );
      }
    }
    final result = defaultReason != null || value == null
        ? fallback
        : value as T;
    if (flag.shouldApply && snapshot.resolveToken.isNotEmpty) {
      onExposure(snapshot.resolveToken, flag.name);
    }
    return ResolutionDetails(
      value: result,
      variant: flag.variant,
      reason: stale || flag.reason == 'RESOLVE_REASON_STALE'
          ? 'STALE'
          : defaultReason ?? (value == null ? 'DEFAULT' : 'TARGETING_MATCH'),
      flagMetadata: {'confidence.resolveReason': flag.reason},
    );
  }
}

/// Context equality ignores map insertion order, but preserves list order and
/// native date metadata. Never relabel another context's assignments as stale.
bool sameValue(Object? a, Object? b) {
  if (a is Map<String, Object?> && b is Map<String, Object?>) {
    return a.length == b.length &&
        a.entries.every(
          (entry) =>
              b.containsKey(entry.key) && sameValue(entry.value, b[entry.key]),
        );
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(a.length, (i) => i).every((i) => sameValue(a[i], b[i]));
  }
  if (a is CalendarDate && b is CalendarDate) {
    return sameValue(a.components, b.components);
  }
  return a == b;
}
