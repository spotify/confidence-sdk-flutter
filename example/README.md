# Confidence OpenFeature example

From this directory run `flutter pub get`, then `flutter run` with an approved
mobile flag-client key and boolean property path:

```sh
flutter run --dart-define=CONFIDENCE_API_KEY=... --dart-define=FLAG_KEY=example.enabled
```

Without a key, the app displays setup instructions and makes no network requests.
The example retains its old Android/iOS application IDs to allow same-app upgrade
checks. It uses only the new provider and Flutter utilities; no old bridge or native
Confidence SDK is linked. See [migration](../doc/migration.md) for the full contract.
