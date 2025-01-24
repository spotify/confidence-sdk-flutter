import 'dart:async';

import 'package:confidence_flutter_sdk/confidence_flutter_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _confidenceFlutterSdkPlugin = ConfidenceFlutterSdk();
  final Completer<void> initCompleter;

  _MyAppState(this.initCompleter);

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    String message;
    String object;
    // Platform messages may fail, so we use a try/catch PlatformException.
    // We also handle the message potentially returning null.
    try {
      await dotenv.load(fileName: ".env");
      await _confidenceFlutterSdkPlugin.setup(dotenv.env["API_KEY"]!, LoggingLevel.VERBOSE);
      await _confidenceFlutterSdkPlugin.putAllContext({
        "targeting_key": "random",
        "my_bool": false,
        "my_int": 1,
        "my_double": 1.1,
        "my_map": {"key": "value"},
        "my_list": ["value1", "value2"]
      });
      await _confidenceFlutterSdkPlugin.fetchAndActivate();
      object =
      (_confidenceFlutterSdkPlugin.getObject("hawkflag", <String, dynamic>{})).toString();
      message =
          (_confidenceFlutterSdkPlugin.getString("ludwigs-new-test-flag.struct-key.string-key", "0"));
      final data = {
        'screen': 'home',
        "my_bool": false,
        "my_int": 1,
        "my_double": 1.1,
        "my_map": {"key": "value"},
        "my_list": ["value1", "value2"]
      };
      _confidenceFlutterSdkPlugin.track("navigate", data);
      _confidenceFlutterSdkPlugin.flush();
    } on PlatformException {
      message = 'Failed to get platform version.';
      object = 'Failed to get object.';
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
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
