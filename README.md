# Flutter Confidence SDK

Flutter implementation of the [Confidence](https://confidence.spotify.com/) SDK.

This SDK uses the [Android](https://github.com/spotify/confidence-sdk-android) and [iOS](https://github.com/spotify/confidence-sdk-swift) respectively under the hood.

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

### Running the example iOS app in xcode
to run the iOS example app in xcode, first fetch the submodules:

```bash
git submodule update --init --recursive
```

then you can drag and drop the `ios/Classes/confidence_sdk/Sources/Confidence` folder into your xcode project next to the `ConfidenceFlutterSDkPlugin.swift` file.

then we can run flutter on iOS given your iOS simulator is running using:

```bash
flutter run
```

or simply run the app from XCode.

