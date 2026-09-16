# Confidence OpenFeature provider (in development)

This independent package is the first implementation increment of the
[Dart provider plan](../../docs/dart-client-provider-plan.md). It currently
contains configuration, endpoint routing, and read-only legacy storage access.
It does **not** yet provide a usable Confidence provider or migrate device data.
Publication is disabled until the migration and mobile release gates pass.

Requires Flutter 3.44.2 / Dart 3.12.2 or newer. The OpenFeature client dependency
is pinned to the published `0.0.1-beta.1` release. General-purpose Flutter
utilities locate legacy files and read native visitor preferences; there is no
dependency on the Confidence Android/Swift SDKs or the old Flutter bridge.
See the [mobile storage probe](tool/mobile_storage_probe/README.md) for the
verified dependency set and platform checks.

Run independently of the bridge and native Confidence SDKs:

```sh
cd packages/confidence_openfeature_provider
flutter pub get
dart format --output=none --set-exit-if-changed lib test tool/mobile_storage_probe
flutter analyze --fatal-infos
flutter test
```

The working package name and initial release version remain provisional.
See [implementation status](../../docs/dart-client-provider-status.md) for
verified facts, unresolved parity questions, and the next increment.
