import 'package:confidence_flutter_sdk/confidence_flutter_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _status = 'Initializing...';
  String _flagValue = '';
  String _variant = '';
  String _reason = '';
  String _context = '';

  @override
  void initState() {
    super.initState();
    _initConfidence();
  }

  Future<void> _initConfidence() async {
    try {
      await dotenv.load(fileName: ".env");
      final apiKey = dotenv.env["API_KEY"]!;

      final confidence = Confidence.builder(clientSecret: apiKey)
          .region(ConfidenceRegion.eu)
          .storage(MemoryStorage())
          .initialContext({
            'targeting_key': ConfidenceValue.string('flutter-dart-sdk-test'),
          })
          .build();

      setState(() => _status = 'Fetching flags...');

      await confidence.fetchAndActivate();

      final eval = confidence.getFlag<String>('hawkflag.message', 'no value');

      confidence.track('example_app_loaded', {
        'sdk': ConfidenceValue.string('dart'),
        'screen': ConfidenceValue.string('home'),
      });

      final ctx = confidence.getContext();
      final ctxDisplay = ctx.entries
          .map((e) => '  ${e.key}: ${e.value.toPlainJson()}')
          .join('\n');

      setState(() {
        _status = 'Ready';
        _flagValue = eval.value;
        _variant = eval.variant ?? 'none';
        _reason = eval.reason.name;
        _context = ctxDisplay;
      });
    } catch (e) {
      setState(() => _status = 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Confidence Dart SDK Example')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('Status', _status),
              const Divider(),
              _row('hawkflag.message', _flagValue),
              _row('Variant', _variant),
              _row('Reason', _reason),
              const Divider(),
              const Text('Context:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(_context, style: const TextStyle(fontFamily: 'monospace')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text('$label:',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
