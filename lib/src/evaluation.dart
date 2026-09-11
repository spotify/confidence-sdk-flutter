class Evaluation<T> {
  final T value;
  final String? variant;
  final ResolveReason reason;
  final String? errorCode;
  final String? errorMessage;

  const Evaluation({
    required this.value,
    this.variant,
    required this.reason,
    this.errorCode,
    this.errorMessage,
  });
}

enum ResolveReason {
  match,
  unspecified,
  noSegmentMatch,
  noTreatmentMatch,
  flagArchived,
  targetingKeyError,
  error,
  stale;

  static ResolveReason fromString(String value) => switch (value) {
    'RESOLVE_REASON_MATCH' => ResolveReason.match,
    'RESOLVE_REASON_NO_SEGMENT_MATCH' => ResolveReason.noSegmentMatch,
    'RESOLVE_REASON_NO_TREATMENT_MATCH' => ResolveReason.noTreatmentMatch,
    'RESOLVE_REASON_FLAG_ARCHIVED' => ResolveReason.flagArchived,
    'RESOLVE_REASON_TARGETING_KEY_ERROR' => ResolveReason.targetingKeyError,
    'RESOLVE_REASON_ERROR' => ResolveReason.error,
    'RESOLVE_REASON_STALE' => ResolveReason.stale,
    _ => ResolveReason.unspecified,
  };

  String toJson() => switch (this) {
    ResolveReason.match => 'RESOLVE_REASON_MATCH',
    ResolveReason.noSegmentMatch => 'RESOLVE_REASON_NO_SEGMENT_MATCH',
    ResolveReason.noTreatmentMatch => 'RESOLVE_REASON_NO_TREATMENT_MATCH',
    ResolveReason.flagArchived => 'RESOLVE_REASON_FLAG_ARCHIVED',
    ResolveReason.targetingKeyError => 'RESOLVE_REASON_TARGETING_KEY_ERROR',
    ResolveReason.error => 'RESOLVE_REASON_ERROR',
    ResolveReason.stale => 'RESOLVE_REASON_STALE',
    ResolveReason.unspecified => 'RESOLVE_REASON_UNSPECIFIED',
  };
}
