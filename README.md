# Flutter Confidence SDK

Flutter implementation of the [Confidence](https://confidence.spotify.com/) SDK.

This package provides a pure Dart Confidence SDK for Flutter apps, plus a legacy `ConfidenceFlutterSdk` wrapper for existing integrations.

## Usage
Add the confidence sdk to your flutter app using the following command:

```bash
flutter pub add confidence_flutter_sdk
```

### Instantiating the Confidence

first, we need to setup the api config which contains a `api_key`:

```dart
import 'package:confidence_flutter_sdk/confidence_flutter_sdk.dart';

final confidence = ConfidenceFlutterSdk();
await confidence.setup("API_KEY");
```

To use a self-hosted local resolver SDK or sidecar resolver for flag resolve and apply requests, pass a custom resolve base URL:

```dart
await confidence.setup("API_KEY", LoggingLevel.WARN, "http://localhost:8090");
```

The pure Dart resolve and apply clients append `/v1/flags:resolve` and `/v1/flags:apply` to this URL. Event tracking continues to use the Confidence events endpoint.

Context could be passed to the sdk as follows:
```dart
await confidence.putContext(key, value)
```

Multiple context elements could be send to the sdk as follows:
```dart
await confidence.putAllContext(map)
```

after this initial setup we can start fetching and accessing the flags. 

```dart
await confidence.fetchAndActivate();
await confidence.getString("[FLAG]", "Default"))
```

The schema of the property plays a crucial role in resolving the property, if the schema type matches the asked type, the value will be returned otherwise
we expect default value to be returned.

### Send custom Events
we can send custom events to the confidence sdk like following:

```dart
confidence.track("[EVENT-NAME]", <String, dynamic>{});
```

### Running the example iOS app in Xcode
Run the app on iOS with a simulator already running:

```bash
flutter run
```

or open the example app in Xcode and run it from there.
