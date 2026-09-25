import 'package:confidence_openfeature_provider/confidence_openfeature_provider.dart';
import 'package:flutter/material.dart';
import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk.dart';

// Copy into a Flutter app and provide a Confidence client secret:
// flutter run --dart-define=CONFIDENCE_CLIENT_SECRET=... --dart-define=FLAG_KEY=example.enabled
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const key = String.fromEnvironment('CONFIDENCE_CLIENT_SECRET');
  const flagKey = String.fromEnvironment(
    'FLAG_KEY',
    defaultValue: 'example.enabled',
  );
  if (key.isEmpty) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Set CONFIDENCE_CLIENT_SECRET to run this example.'),
          ),
        ),
      ),
    );
    return;
  }

  // Create the future once, outside build, so rebuilding never re-registers.
  runApp(
    MaterialApp(home: FlagExample(initialization: initializeFlags(flagKey))),
  );
}

Future<bool> initializeFlags(String flagKey) async {
  const clientSecret = String.fromEnvironment('CONFIDENCE_CLIENT_SECRET');
  final provider = ConfidenceProviderBuilder(
    clientSecret: clientSecret,
  ).withInitializationStrategy(InitializationStrategy.fetchAndActivate).build();
  final api = OpenFeatureAPI.instance;
  // This Dart SDK has no initialContext parameter on provider registration.
  await api.setEvaluationContextAndWait(
    EvaluationContext(
      targetingKey: 'example-user',
      attributes: {'user_id': 'example-user'},
    ),
  );
  await api.setProviderAndWait(provider);
  return api.getClient().getBooleanValue(flagKey, false);
}

class FlagExample extends StatelessWidget {
  const FlagExample({required this.initialization, super.key});

  final Future<bool> initialization;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Confidence + OpenFeature')),
    body: Center(
      child: FutureBuilder<bool>(
        future: initialization,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const CircularProgressIndicator();
          }
          if (snapshot.hasError) {
            // Do not display raw exceptions or credential-bearing diagnostics.
            return const Text(
              'Unable to initialize flags. Please restart the app.',
            );
          }
          return Text(
            snapshot.data == true
                ? 'The new experience is enabled.'
                : 'The default experience is enabled.',
          );
        },
      ),
    ),
  );
}
