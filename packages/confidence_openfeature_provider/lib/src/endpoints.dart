import 'configuration.dart';

/// Central routing for all Confidence requests.
final class ConfidenceEndpoints {
  ConfidenceEndpoints(ConfidenceConfiguration configuration)
    : _resolverBase =
          (configuration.resolveBaseUrl ??
                  Uri.https(_host('resolver', configuration.region)))
              .toString()
              .replaceFirst(RegExp(r'/+$'), ''),
      publish = Uri.https(
        _host('events', configuration.region),
        '/v1/events:publish',
      );

  final String _resolverBase;
  Uri get resolve => Uri.parse('$_resolverBase/v1/flags:resolve');
  Uri get apply => Uri.parse('$_resolverBase/v1/flags:apply');
  final Uri publish;

  static String _host(String service, ConfidenceRegion region) =>
      switch (region) {
        ConfidenceRegion.global => '$service.confidence.dev',
        ConfidenceRegion.eu => '$service.eu.confidence.dev',
        ConfidenceRegion.us => '$service.us.confidence.dev',
      };
}
