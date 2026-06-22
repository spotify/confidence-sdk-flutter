import 'dart:async';

import 'package:confidence_flutter_sdk/confidence_flutter_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  MyApp({super.key});
  final Completer<void> _initCompleter = Completer<void>();

  Future<void> initDone() async {
    return _initCompleter.future;
  }

  @override
  // ignore: no_logic_in_create_state
  State<MyApp> createState() => _MyAppState(_initCompleter);
}

class _MyAppState extends State<MyApp> {
  String _object = 'Unknown';
  String _message = 'Unknown';
  late final Confidence _confidence;
  final Completer<void> initCompleter;

  _MyAppState(this.initCompleter);

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  Future<void> initPlatformState() async {
    String message;
    String object;
    try {
      await dotenv.load(fileName: ".env");
      _confidence = Confidence.builder(clientSecret: dotenv.env["API_KEY"]!)
          .region(ConfidenceRegion.eu)
          .storage(MemoryStorage())
          .initialContext({
            'visitor_id': ConfidenceValue.string('random'),
            'my_bool': ConfidenceValue.boolean(false),
            'my_int': ConfidenceValue.integer(1),
            'my_double': ConfidenceValue.double_(1.1),
            'my_map': ConfidenceValue.structure({
              'key': ConfidenceValue.string('value'),
            }),
            'my_list': ConfidenceValue.list([
              ConfidenceValue.string('value1'),
              ConfidenceValue.string('value2'),
            ]),
          })
          .build();

      await _confidence.fetchAndActivate();
      object = _confidence.getValue<String>('hawkflag.message', '');
      message = _confidence.getValue<String>('hawkflag.message', '');
      final data = {
        'screen': ConfidenceValue.string('home'),
        'my_bool': ConfidenceValue.boolean(false),
        'my_int': ConfidenceValue.integer(1),
        'my_double': ConfidenceValue.double_(1.1),
        'my_map': ConfidenceValue.structure({
          'key': ConfidenceValue.string('value'),
        }),
        'my_list': ConfidenceValue.list([
          ConfidenceValue.string('value1'),
          ConfidenceValue.string('value2'),
        ]),
      };
      _confidence.track('navigate', data);
      _confidence.flush();
    } catch (e) {
      message = 'Failed: $e';
      object = 'Failed: $e';
    }

    if (!mounted) return;

    setState(() {
      _message = message;
      _object = object;
    });
    initCompleter.complete();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Center(
          child: ListView.builder(
            itemCount: 2,
            itemBuilder: (context, index) {
              var title = "";
              switch (index) {
                case 0:
                  title = _message;
                case 1:
                  title = _object;
              }
              return ListTile(
                title: Text('$title\n'),
              );
            },
          ),
        ),
      ),
    );
  }
}
