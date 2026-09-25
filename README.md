# Confidence OpenFeature provider (in development)

`confidence_openfeature_provider` replaces the old Confidence Flutter bridge with
an OpenFeature client provider. Networking, evaluation, persistence, migration,
and telemetry run in Dart; a small iOS helper preserves legacy calendar values.

Typed reads, context reconciliation, durable queues, native data migration and
live resolve/apply/event acceptance are validated. The repository and example now
use the new package. This is a development prerelease: publication remains disabled
until the initial release is approved. See [release preparation](doc/releasing.md).

Requires Flutter 3.44.2 / Dart 3.12.2 or newer. The OpenFeature client dependency
is pinned to the published `0.0.1-beta.1` release. General-purpose Flutter
utilities locate legacy files and read native visitor preferences; there is no
dependency on the Confidence Android/Swift SDKs or the old Flutter bridge. A small
iOS Foundation helper preserves legacy calendar-date conversion during replay.
See the [mobile storage probe](tool/mobile_storage_probe/README.md) for the
verified dependency set and platform checks.

### Toolchain and application setup

The Dart 3.12.2 minimum comes from the published
`openfeature_dart_client_sdk` 0.0.1-beta.1 SDK constraint. Flutter 3.44.2 is the
verified toolchain used for our mobile builds and CI; we have not established a
lower compatible Flutter version. Lowering our Dart constraint alone would not
make the pinned OpenFeature dependency work on older Dart SDKs.

Use a Confidence **client secret**, matching the terminology of the
[Android](https://github.com/spotify/confidence-sdk-android#usage) and
[Swift](https://github.com/spotify/confidence-sdk-swift#create-and-set-the-provider)
SDKs. Pass the client secret for your application's Confidence flag client to
`ConfidenceProviderBuilder(clientSecret: clientSecret)`. This is not a Confidence
management API/OAuth credential.
This mobile SDK uses that client secret in the app. Values supplied through
`--dart-define` are compiled into the binary and can be extracted; this is not a
way to keep a credential confidential.

Flag reads use dot notation: `example.enabled` reads the `enabled` property of
the `example` flag; `example.banner.title` reads a nested property. The first
component is the flag name, followed by the property path. Choose the typed read
that matches the property's type.

To read the complete flag object, pass just the flag name:

```dart
final details = client.getStructureDetails('example', {});
// For a matching variant with {"enabled": true}:
// details.value == {'enabled': true}
// details.variant == 'flags/example/variants/enabled'
// details.reason == 'TARGETING_MATCH'
// details.errorCode == null
```

Use `get*Details` to inspect `errorCode`, `reason`, `variant`, and `flagMetadata`.
A missing flag or type mismatch returns the caller's fallback with error details
rather than throwing. `get*Value` returns only the value, so it cannot distinguish
an evaluation error from a successful assignment equal to the fallback.

`EvaluationContext(targetingKey: userId)` sends `targeting_key`; it does **not**
populate `user_id`. If your Confidence rules use `User(user_id)`, also supply
`attributes: {'user_id': userId}`. Attribute names must match your flag's targeting
configuration.

On Android, add network permission to your application's
`android/app/src/main/AndroidManifest.xml`, inside `<manifest>` and outside
`<application>`, so release builds can connect too:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

Flutter's debug/profile manifest permissions alone do not cover release builds.
The example already includes this permission. See Flutter's
[networking instructions](https://docs.flutter.dev/data-and-backend/networking).

See the [migration guide](doc/migration.md) and [public-API example](example/lib/main.dart)
for application setup and the breaking changes from the old bridge.

Run independently of the bridge and native Confidence SDKs:

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test tool/mobile_storage_probe
flutter analyze --fatal-infos
flutter test
```

### Delivery guarantees

The provider uses a bounded, atomically written JSON outbox with asynchronous
persistence and one delivery scheduler for exposures and custom events.

- Unsent records survive restarts once persisted. A hard kill before persistence
  completes can lose newly queued exposures or custom events.
- Events retain their original context and timestamp. Successful flag reads
  enqueue eligible exposures without doing disk or network I/O on the read path.
- A crash after server acceptance but before saving the acknowledgement can cause
  duplicate delivery. Exactly-once delivery is not guaranteed.
- Explicit `flush()` waits for persistence of already queued work and attempts
  delivery; it cannot guarantee server acceptance while offline. Shutdown only
  attempts a bounded flush and may not run when the OS terminates the app.

The initial outbox-file budget is 4 MiB, inspired by Android's advertised budget
rather than a backend limit. When full, oldest unsent events/exposures are dropped
by timestamp; `inspectStorage()` reports the durable dropped-record count.
An individually oversized record is dropped without evicting smaller records.
Identity/import/deduplication metadata is retained; metadata exhaustion causes a
visible persistence failure. Snapshots, temporary files and in-memory work are
outside this file-size budget.

Delivery runs every 60 seconds while the provider is alive, with up to 10 events
per request or 20 exposures sharing a resolve token. Failed attempts retry with
exponential backoff starting at one second, capped at 60 seconds, and jitter of
50–100% of that delay. Each request times out after 10 seconds. Explicit flush
bypasses the scheduling delay; shutdown allows two seconds for persistence and
delivery before closing the transport. Mobile background suspension may delay
timers; no background execution guarantee is made.

HTTP 200 acknowledges a batch. HTTP 408, 429, 5xx, transport failures and
unexpected statuses retain work. Other HTTP 4xx responses discard the batch and
increment the durable dropped-record count, including authentication failures.
Known per-event schema/missing-definition errors in a 200 response count as
permanent rejections. Malformed responses and unknown error reasons retain the
batch; accepted siblings may therefore be replayed.

```dart
final result = await provider.flush();
// acceptedRecords / droppedRecords describe this attempt.
// pendingRecords includes work still queued; retryNeeded reports a transient
// delivery failure. A disk failure throws instead of claiming persistence.
final storage = await provider.inspectStorage();
// storage.droppedRecords is cumulative (overflow and permanent rejections).
```

Legacy Swift calendar-only values are retained and converted by an iOS helper
using the native mapper's current-calendar/time-zone rules at delivery time.
Failed conversion retains the event for retry while other events keep flowing.
Ordinary timestamps use the Dart UTC conversion and require no platform call.
See the [calendar probe](tool/calendar_probe/README.md) for parity and simulator
evidence. Both Swift Package Manager and CocoaPods packaging are provided.
See the [outbox design](https://github.com/spotify/confidence-sdk-flutter/blob/main/docs/dart-client-provider-plan.md#agreed-outbox-design-and-delivery-trade-offs)
for the full contract and validation requirements. Legacy queue migration remains
required.

The package name is finalized as `confidence_openfeature_provider`. The current
version is a development prerelease; publication remains disabled.
See [implementation status](https://github.com/spotify/confidence-sdk-flutter/blob/main/docs/dart-client-provider-status.md) for
verified facts, unresolved parity questions, and the next increment. The
[upgrade probe](tool/upgrade_probe/README.md) records real Android/iOS binary
replacement, offline migration, and replay after process restarts.

Live checks are opt-in and create exposure/event traffic. See the
[live smoke runner](tool/live_smoke/README.md) for safe local credential loading
and the verified test coverage. They are not part of credential-free CI.
