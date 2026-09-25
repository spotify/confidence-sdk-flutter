/// Region used for flag resolution, exposure reporting, and custom events.
enum ConfidenceRegion { global, eu, us }

/// Logging verbosity. [none] disables logging entirely.
enum ConfidenceLoggingLevel { verbose, debug, warn, error, none }

/// Determines when persisted assignments become active for a session.
enum InitializationStrategy { fetchAndActivate, activateAndFetchAsync }

/// Immutable configuration shared by the provider's private components.
///
/// Construction validates inputs without performing I/O. Keep this internal
/// until the builder can construct a functional provider.
final class ConfidenceConfiguration {
  ConfidenceConfiguration({
    required this.clientSecret,
    this.region = ConfidenceRegion.global,
    this.loggingLevel = ConfidenceLoggingLevel.warn,
    this.initializationStrategy = InitializationStrategy.fetchAndActivate,
    Uri? resolveBaseUrl,
  }) : resolveBaseUrl = _validateBaseUrl(resolveBaseUrl) {
    if (clientSecret.trim().isEmpty) {
      // Do not include credential values in validation messages.
      throw ArgumentError('A non-empty client secret is required.');
    }
  }

  final String clientSecret;
  final ConfidenceRegion region;
  final ConfidenceLoggingLevel loggingLevel;
  final InitializationStrategy initializationStrategy;
  final Uri? resolveBaseUrl;

  static Uri? _validateBaseUrl(Uri? url) {
    if (url == null) return null;
    if ((url.scheme != 'https' && url.scheme != 'http') ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.hasQuery ||
        url.hasFragment) {
      throw ArgumentError(
        'Resolver base URL must be an absolute HTTP(S) URL without '
        'credentials, query, or fragment.',
      );
    }
    return url;
  }
}
