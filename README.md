# Flutter Confidence SDK

Flutter implementation of the [Confidence](https://confidence.spotify.com/).

## Usage

### Instantiating the Confidence

first, we need to setup the api config which contains a `api_key`:

```dart
await _confidenceFlutterSdkPlugin.setup("API_KEY");
```

after this initial setup we can start fetching and accessing the flags. 

```dart
await _confidenceFlutterSdkPlugin.fetchAndActivate();
await _confidenceFlutterSdkPlugin.getString("[FLAG]", "Default"))
```

The schema of the property plays a crucial role in resolving the property, if the schema type matches the asked type, the value will be returned otherwise
we expect default value to be returned.

### Send custom Events
we can send custom events to the confidence sdk like following:

```dart
_confidenceFlutterSdkPlugin.track("[EVENT-NAME]", <String, dynamic>{});
```