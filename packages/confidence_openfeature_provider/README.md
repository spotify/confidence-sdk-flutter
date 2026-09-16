# Confidence OpenFeature provider (in development)

This independent package is the first implementation increment of the
[Dart provider plan](../../docs/dart-client-provider-plan.md). It currently
contains configuration, endpoint routing, and an upstream contract probe.
It does **not** yet provide a usable Confidence provider or migrate device data.
Publication is disabled until the migration and mobile release gates pass.

Requires Dart 3.12.2 or newer. The OpenFeature client dependency is pinned to
the published `0.0.1-beta.1` release. The foundation is pure Dart; mobile storage
utility dependencies will be selected after legacy path access is verified.
No Flutter minimum is claimed until that integration is tested.

Run independently of the bridge and native Confidence SDKs:

```sh
cd packages/confidence_openfeature_provider
dart pub get
dart format --output=none --set-exit-if-changed lib test
dart analyze --fatal-infos
dart test
```

The working package name and initial release version remain provisional.
See [implementation status](../../docs/dart-client-provider-status.md) for
verified facts, unresolved parity questions, and the next increment.
