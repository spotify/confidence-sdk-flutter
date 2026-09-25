/// Dart-native Confidence OpenFeature provider (in development).
///
/// Mobile upgrade validation and release preparation are still in progress.
library;

export 'src/configuration.dart'
    show ConfidenceRegion, ConfidenceLoggingLevel, InitializationStrategy;
export 'src/provider.dart'
    show
        ConfidenceProvider,
        ConfidenceProviderBuilder,
        ConfidenceStorageInspection;

export 'src/telemetry_delivery.dart' show ConfidenceFlushResult;
