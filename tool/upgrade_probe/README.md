# Retained-sandbox upgrade probe

Verified 2026-09-18 with Flutter 3.44.2 / Dart 3.12.2:

| Platform | Environment | Result |
| --- | --- | --- |
| Android | ARM64 Pixel 9 emulator, API 36 | Passed |
| iOS | iPhone 17 Pro simulator, iOS 26.3 / Xcode 26.3 | Passed |

The baseline is the published `confidence_flutter_sdk` 0.2.4 archive (SHA-256
`3345ae558b438dc9a76363b73b1b284fa1c75189f48ccf71d7d2aa9b802c0acb`).
The legacy app installs native-generated flag/apply/event fixtures using native
path/preference APIs, then calls the actual published bridge's `readAllFlags`.
It never initializes the native network clients or contacts a live service.

The replacement app has the same app ID and signing key. It removes the bridge
and the fixture-seeding channel. Provider startup uses the actual mobile
storage, preferences, identity, import and persistence code. Only the internal
HTTP transport is replaced with a deterministic offline/online implementation.
This seam is not exported by the public provider library.

Three provider launches verify:

1. The old app's marker and native visitor survive replacement. Cached flags
   work offline. Two native events and two pending native exposures import;
   one typed read and one tracked event bring the pending count to six. The
   provider persists them and shuts down while offline.
2. After process termination/relaunch, all six records replay. Both original
   events retain their identity/context and original 2023 timestamp. Repeated
   flush sends nothing.
3. After another process termination/relaunch, the queue remains empty and the
   same typed read does not recreate an acknowledged exposure.

Both platforms produced these reports, in sequence:

```json
{"ok":true,"phase":"offline","pending":6}
{"ok":true,"phase":"complete","accepted":6,"historicalEvents":2}
{"ok":true,"phase":"complete","accepted":0,"historicalEvents":0}
```

## Reproduce

Use two disposable copies of an app generated with:

```sh
flutter create --no-pub --platforms android,ios --org dev.confidence.probe \
  --project-name upgrade_probe /path/to/legacy-app
```

For the legacy copy:

- Add path dependencies on the extracted published 0.2.4 package and
  `path_provider: 2.1.5`. Use `legacy_main.dart.template` as `lib/main.dart`.
- Copy this directory's `AppDelegate.swift` and `MainActivity.kt` to the generated
  platform application files (Kotlin package `dev.confidence.probe.upgrade_probe`).
- Copy `../../test/fixtures/legacy/android` and `swift` into `assets/android`
  and `assets/swift`; declare both directories under `flutter.assets`.
- Set the app's iOS deployment target to 14.0. The published Swift package
  manifest refers to a sibling `FlutterFramework` that current Flutter no longer
  generates. In the **disposable archive copy only**, replace its dependencies
  with `[]` and target with `.target(name: "confidence_flutter_sdk")`. No native
  SDK implementation is changed.
- The Dart seeder removes only the Android flag fixture's synthetic timestamp
  field: the published bridge's value serializer crashes on timestamp-valued
  flags, which backend flag schemas do not produce. Event timestamp fixtures
  remain unchanged and are verified during replay.

For the provider copy, retain the generated application IDs and signing setup,
replace the bridge dependency with a path dependency on this package, and use
`provider_main.dart` as `lib/main.dart`. Restore the generated default Android
activity and iOS app delegate so the old seeding channel is absent. Remove the
fixture asset declarations. Run `flutter pub get` and build each copy:

```sh
flutter build apk --debug
flutter build ios --simulator --debug
```

Install and launch the **legacy** binary first. Its `legacy-result.json` in
Application Support must say `ok: true`. Then terminate the app, install the
provider binary **without uninstalling**, and launch it three times, reading
`provider-result.json` after each launch:

```sh
# Android; repeat force-stop/start for each later phase.
adb install -r /path/to/provider-app/build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n dev.confidence.probe.upgrade_probe/.MainActivity
adb shell run-as dev.confidence.probe.upgrade_probe cat files/provider-result.json
adb shell am force-stop dev.confidence.probe.upgrade_probe

# iOS; repeat terminate/launch for each later phase.
xcrun simctl install <device> /path/to/provider-app/build/ios/iphonesimulator/Runner.app
xcrun simctl launch <device> dev.confidence.probe.upgradeProbe
xcrun simctl get_app_container <device> dev.confidence.probe.upgradeProbe data
# Read Library/Application Support/provider-result.json in that data container.
xcrun simctl terminate <device> dev.confidence.probe.upgradeProbe
```

Wait for each report to reach its expected phase before terminating. Do not use
`flutter test` to install the two upgrade versions: its cleanup can uninstall the
app and erase the very sandbox retention being tested. A fresh app ID or cleared
**disposable probe only** is needed to repeat the entire sequence.

## Limits

These are real binary replacements and process restarts using native-generated
fixtures, not an exhaustive OS matrix or a production-network test. The baseline
reads actual native cache data; it does not generate events from live app traffic.
The event transport simulates outages and acceptance without credentials. The
separate [calendar probe](../calendar_probe/README.md) verifies actual iOS calendar
conversion, including both Swift Package Manager and CocoaPods registration.
Live-backend verification and the root-package cutover are now complete; see the
[live smoke report](../live_smoke/README.md) and [release preparation](../../doc/releasing.md).
