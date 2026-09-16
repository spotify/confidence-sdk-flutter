import 'package:confidence_openfeature_provider/src/configuration.dart';
import 'package:confidence_openfeature_provider/src/endpoints.dart';
import 'package:test/test.dart';

void main() {
  test('defaults match the agreed startup contract', () {
    final configuration = ConfidenceConfiguration(apiKey: 'test-key');
    expect(configuration.region, ConfidenceRegion.global);
    expect(configuration.loggingLevel, ConfidenceLoggingLevel.warn);
    expect(
      configuration.initializationStrategy,
      InitializationStrategy.fetchAndActivate,
    );
    expect(configuration.resolveBaseUrl, isNull);
  });

  test('explicit startup and disabled logging are retained', () {
    final configuration = ConfidenceConfiguration(
      apiKey: 'test-key',
      loggingLevel: ConfidenceLoggingLevel.none,
      initializationStrategy: InitializationStrategy.activateAndFetchAsync,
    );
    expect(configuration.loggingLevel, ConfidenceLoggingLevel.none);
    expect(
      configuration.initializationStrategy,
      InitializationStrategy.activateAndFetchAsync,
    );
  });

  for (final key in ['', ' \n\t']) {
    test('rejects an empty credential', () {
      expect(() => ConfidenceConfiguration(apiKey: key), throwsArgumentError);
    });
  }

  for (final entry in {
    ConfidenceRegion.global: '',
    ConfidenceRegion.eu: '.eu',
    ConfidenceRegion.us: '.us',
  }.entries) {
    test('${entry.key.name} routes all three services', () {
      final endpoints = ConfidenceEndpoints(
        ConfidenceConfiguration(apiKey: 'test-key', region: entry.key),
      );
      final resolver = 'https://resolver${entry.value}.confidence.dev';
      expect(endpoints.resolve.toString(), '$resolver/v1/flags:resolve');
      expect(endpoints.apply.toString(), '$resolver/v1/flags:apply');
      expect(
        endpoints.publish.toString(),
        'https://events${entry.value}.confidence.dev/v1/events:publish',
      );
    });

    for (final suffix in ['', '/', '///']) {
      test('${entry.key.name} resolver override with suffix "$suffix"', () {
        final endpoints = ConfidenceEndpoints(
          ConfidenceConfiguration(
            apiKey: 'test-key',
            region: entry.key,
            resolveBaseUrl: Uri.parse('http://localhost:8080/proxy$suffix'),
          ),
        );
        expect(
          endpoints.resolve.toString(),
          'http://localhost:8080/proxy/v1/flags:resolve',
        );
        expect(
          endpoints.apply.toString(),
          'http://localhost:8080/proxy/v1/flags:apply',
        );
        expect(
          endpoints.publish.toString(),
          'https://events${entry.value}.confidence.dev/v1/events:publish',
        );
      });
    }
  }

  for (final url in [
    '/relative',
    'file:///tmp/resolver',
    'https://',
    'https://user:secret@example.com',
    'https://example.com?token=secret',
    'https://example.com#fragment',
  ]) {
    test('rejects invalid resolver URL without including its contents', () {
      expect(
        () => ConfidenceConfiguration(
          apiKey: 'private-key',
          resolveBaseUrl: Uri.parse(url),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'message',
            allOf(isNot(contains('secret')), isNot(contains('private-key'))),
          ),
        ),
      );
    });
  }
}
