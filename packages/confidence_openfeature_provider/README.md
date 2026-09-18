# Confidence OpenFeature provider (in development)

This independent package is the first implementation increment of the
[Dart provider plan](../../docs/dart-client-provider-plan.md). It currently
contains configuration, endpoint routing, read-only legacy storage access,
and immutable snapshots with native flag-cache decoders.
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

### Planned delivery guarantees

The outbox is not implemented yet. The agreed design uses a bounded, atomically
written JSON outbox with asynchronous persistence and shared delivery scheduling.

- Unsent records survive restarts once persisted. A hard kill before persistence
  completes can lose newly queued exposures or custom events.
- Events retain their original context and timestamp. Successful flag reads
  enqueue eligible exposures without doing disk or network I/O on the read path.
- A crash after server acceptance but before saving the acknowledgement can cause
  duplicate delivery. Exactly-once delivery is not guaranteed.
- Explicit `flush()` waits for persistence of already queued work and attempts
  delivery; it cannot guarantee server acceptance while offline. Shutdown only
  attempts a bounded flush and may not run when the OS terminates the app.

Exact limits, overflow behavior, and retry defaults remain to be specified.
See the [outbox design](../../docs/dart-client-provider-plan.md#agreed-outbox-design-and-delivery-trade-offs)
for the full contract and validation requirements. Legacy queue migration remains
required.

The working package name and initial release version remain provisional.
See [implementation status](../../docs/dart-client-provider-status.md) for
verified facts, unresolved parity questions, and the next increment.
