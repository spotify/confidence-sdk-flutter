import 'package:confidence_openfeature_provider/confidence_openfeature_provider.dart';
import 'package:flutter/material.dart';
import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk.dart';

// Copy into a Flutter app and provide an approved mobile flag-client key:
// flutter run --dart-define=CONFIDENCE_API_KEY=... --dart-define=FLAG_KEY=example.enabled
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const key = String.fromEnvironment('CONFIDENCE_API_KEY');
  const flagKey = String.fromEnvironment(
    'FLAG_KEY',
    defaultValue: 'example.enabled',
  );
  if (key.isEmpty) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Set CONFIDENCE_API_KEY to run this example.'),
          ),
        ),
      ),
    );
    return;
  }

  final provider = ConfidenceProviderBuilder(
    apiKey: key,
  ).withInitializationStrategy(InitializationStrategy.fetchAndActivate).build();
  final api = OpenFeatureAPI.instance;
  await api.setEvaluationContextAndWait(
    EvaluationContext(targetingKey: 'example-user'),
  );
  await api.setProviderAndWait(provider);
  final client = api.getClient();
  runApp(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Confidence + OpenFeature')),
        body: Center(
          child: Text(
            client.getBooleanValue(flagKey, false)
                ? 'The new experience is enabled.'
                : 'The default experience is enabled.',
          ),
        ),
      ),
    ),
  );
}
