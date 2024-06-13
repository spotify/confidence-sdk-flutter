import 'dart:async';

import 'package:confidence_flutter_sdk/confidence_flutter_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _object = 'Unknown';
  String _message = 'Unknown';
  bool _enabled = false;
  final _confidenceFlutterSdkPlugin = ConfidenceFlutterSdk();

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    String message;
    bool enabled;
    String object;
    // Platform messages may fail, so we use a try/catch PlatformException.
    // We also handle the message potentially returning null.
    try {
      await _confidenceFlutterSdkPlugin.setup("API_KEY");
      if(await _confidenceFlutterSdkPlugin.isStorageEmpty()) {
        await _confidenceFlutterSdkPlugin.fetchAndActivate();
      } else {
        await _confidenceFlutterSdkPlugin.activateAndFetchAsync();
      }
      await _confidenceFlutterSdkPlugin.putContext("Yo", "Hello");
      object =
      (await _confidenceFlutterSdkPlugin.getObject("hawkflag", <String, dynamic>{})).toString();
      message =
          (await _confidenceFlutterSdkPlugin.getString("hawkflag.message", "default")).toString();
      enabled = await _confidenceFlutterSdkPlugin.getBool("hawkflag.enabled", false);
      final data = {
        'screen': 'home',
        "my_bool": false,
        "my_int": 1,
        "my_double": 1.1,
        "my_map": {"key": "value"},
        "my_list": ["value1", "value2"]
      };
      _confidenceFlutterSdkPlugin.track("navigate", data);
    } on PlatformException {
      message = 'Failed to get platform version.';
      enabled = false;
      object = 'Failed to get object.';
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;

    setState(() {
      _enabled = enabled;
      _message = message;
      _object = object;
    });
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
            itemCount: 3,
            itemBuilder: (context, index) {
              var title = "";
              switch (index) {
                case 0:
                  title = 'Message: $_message\n';
                case 1:
                  title = 'Enabled: $_enabled\n';
                case 2:
                  title = 'Object: \n$_object\n';
              }
              return ListTile(
                title: Text('Evaluation -> $title\n'),
              );
            },
          ),
        ),
      ),
    );
  }
}
