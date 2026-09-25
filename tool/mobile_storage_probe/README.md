# Legacy mobile storage access probe

Verified on 2026-09-16 with Flutter 3.44.2 / Dart 3.12.2:

| Platform | Environment | Result |
| --- | --- | --- |
| Android | ARM64 emulator, API 36; generated AGP 9.0.1 / Gradle 9.1.0 project | Passed |
| iOS | iPhone 17 Pro simulator, iOS 26.3; Xcode 26.3; Swift Package Manager | Passed |

The native harness writes sentinel files using the same location APIs as the
pinned SDKs. The Dart test calls `LegacyStorage.locate()` and checks canonical
paths and contents for flags, apply data, sealed events, and unfinished events.
It also verifies the native visitor ID, ignores a decoy Flutter-prefixed value,
observes a native identity change without a preferences cache, and reads a missing
identity twice without generating one. No Confidence credentials are needed.

The test channel exists only in the disposable app. The provider uses only
`path_provider`, `package_info_plus`, and `shared_preferences` utilities.

## Verified dependency set

Direct utility versions are pinned while this package is in development:
`path_provider` 2.1.5, `package_info_plus` 8.3.1, `shared_preferences` 2.5.3,
and `shared_preferences_android` 2.4.11. The platform implementations resolved to
`path_provider_android` 2.3.1, `path_provider_foundation` 2.6.0, and
`shared_preferences_foundation` 2.5.7. `path` resolved to 1.9.1.

Android explicitly uses `SharedPreferencesAsyncAndroidOptions` with the
SharedPreferences backend and file name `confidence-visitor`, not the default
DataStore backend. iOS uses the unprefixed `confidence.visitor_id` key with the
async API. Android's event directory is `app_events`, a sibling of `filesDir`;
iOS uses Application Support plus the actual bundle ID.

Newer Android utility releases were also checked: `package_info_plus` 10.2.1
with `shared_preferences_android` 2.4.28 did not build under the generated
Flutter 3.44.2 project's `android.builtInKotlin=false` configuration. Enabling
built-in Kotlin then conflicted with that Flutter release's integration-test
plugin. Keep these upgrades coupled to a verified Flutter/Gradle migration.
The selected versions build with the unmodified template but emit a future
Kotlin-plugin compatibility warning. Newer Flutter releases are not yet tested.

## Reproduce against the provider

1. Use Flutter 3.44.2 and generate a disposable app with its own ID:

   ```sh
   flutter create --platforms android,ios --org dev.confidence.probe \
     --project-name storage_probe /path/to/disposable/storage_probe
   ```

2. Add a path dependency on this provider package and the integration-test SDK
   to the generated app's `pubspec.yaml`:

   ```yaml
   dependencies:
     confidence_openfeature_provider:
       path: /absolute/path/to/packages/confidence_openfeature_provider
   dev_dependencies:
     integration_test:
       sdk: flutter
   ```

   Retain the generated Flutter and flutter_test dependencies.

3. Replace the generated Android activity at
   `android/app/src/main/kotlin/dev/confidence/probe/storage_probe/MainActivity.kt`
   with this directory's `MainActivity.kt`. Replace `ios/Runner/AppDelegate.swift`
   with this directory's `AppDelegate.swift`. Copy `storage_test.dart` to the
   app's `integration_test/storage_test.dart`.

4. From the disposable app, run `flutter pub get`, then run each platform:

   ```sh
   flutter test integration_test/storage_test.dart -d <android-device-id>
   flutter test integration_test/storage_test.dart -d <ios-simulator-id> --verbose
   ```

   Ensure the Android SDK path points to the installed SDK. In this environment,
   the inherited `ANDROID_SDK_ROOT` pointed to a missing directory; unsetting it
   and providing the correct `ANDROID_HOME` fixed device discovery. The iOS test
   runner stalled awaiting VM-service discovery in non-verbose mode; verbose
   retries completed. These are host-tool observations, not storage failures.
   After switching Android utility versions, a `flutter clean` in the disposable
   app was needed to remove stale generated plugin classes before the final pass.

Only the disposable app's sandbox is seeded or modified. Flutter integration
testing may uninstall that probe app on completion. The sentinels are synthetic
and reproducible from these sources.

## Limits

This proves storage and preference access on these two simulator/emulator
configurations. It is not an in-place upgrade from the old bridge, a check of
all supported OS versions, or a migration/replay test. Native serialized formats
are covered separately by `../native_fixtures`. Older shipped formats, damaged
records, app sandbox retention across upgrades, and durable import remain gates.
The provider's normal CI runs analysis and unit tests; this probe is a manual
mobile integration check.
