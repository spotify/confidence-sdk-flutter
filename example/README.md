# Confidence OpenFeature example

From this directory run `flutter pub get`, then `flutter run` with an Confidence
client secret and boolean property path:

```sh
flutter run --dart-define=CONFIDENCE_CLIENT_SECRET=... --dart-define=FLAG_KEY=example.enabled
```

`CONFIDENCE_CLIENT_SECRET` supplies the client secret to the builder's `clientSecret`
argument. It is compiled into the application, not kept confidential. Use the
client secret for the app's Confidence flag client, not a management credential.
`example.enabled` means flag `example`, property `enabled`.

The UI shows loading during registration and a generic message on initialization
failure. The initial context includes both `targeting_key` (via `targetingKey`)
and an explicit `user_id` attribute; use the fields your targeting rules expect.
The pinned Dart SDK does not accept an initial context in `setProviderAndWait`,
so this example sets it first. The Android main manifest includes `INTERNET`
permission for release builds, as described in [setup](../README.md#toolchain-and-application-setup).

Without a key, the app displays setup instructions and makes no network requests.
The example retains its old Android/iOS application IDs to allow same-app upgrade
checks. It uses only the new provider and Flutter utilities; no old bridge or native
Confidence SDK is linked. See [migration](../doc/migration.md) for the full contract.
