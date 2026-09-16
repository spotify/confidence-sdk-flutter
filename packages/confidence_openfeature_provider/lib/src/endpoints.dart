import 'configuration.dart';

/// Central routing for all Confidence requests.
final class ConfidenceEndpoints {
  ConfidenceEndpoints(ConfidenceConfiguration configuration)
    : resolve = _flagEndpoint(configuration, 'resolve'),
      apply = _flagEndpoint(configuration, 'apply'),
      publish = Uri.https(
        _host('events', configuration.region),
        '/v1/events:publish',
      );

  final Uri resolve;
  final Uri apply;
  final Uri publish;

  static Uri _flagEndpoint(
    ConfidenceConfiguration configuration,
    String operation,
  ) {
    final base =
        configuration.resolveBaseUrl ??
        Uri.https(_host('resolver', configuration.region));
    // Preserve proxy path prefixes and append the API path exactly once here.
    final prefix = base.path.replaceFirst(RegExp(r'/+$'), '');
    return base.replace(path: '$prefix/v1/flags:$operation');
  }

  static String _host(String service, ConfidenceRegion region) =>
      switch (region) {
        ConfidenceRegion.global => '$service.confidence.dev',
        ConfidenceRegion.eu => '$service.eu.confidence.dev',
        ConfidenceRegion.us => '$service.us.confidence.dev',
      };
}
