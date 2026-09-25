# Migrating from confidence_flutter_sdk

The new package is `confidence_openfeature_provider`, replacing the old bridge
at this repository's root. This is a breaking API migration. The current
development package requires Flutter 3.44.2 / Dart 3.12.2 and pins OpenFeature's
client SDK to `0.0.1-beta.1`. It supports Flutter Android and iOS.

## Replace setup and reads

Initialize Flutter bindings before registering the provider, and set the initial
context before registration so the first fetch uses the right identity:

```dart
import 'package:confidence_openfeature_provider/confidence_openfeature_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk.dart';

Future<void> configureFlags(String flagClientKey, String userId) async {
  WidgetsFlutterBinding.ensureInitialized();
  final provider = ConfidenceProviderBuilder(apiKey: flagClientKey)
      .withRegion(ConfidenceRegion.eu)
      .withInitializationStrategy(InitializationStrategy.fetchAndActivate)
      .build();
  final api = OpenFeatureAPI.instance;
  await api.setEvaluationContextAndWait(EvaluationContext(targetingKey: userId));
  await api.setProviderAndWait(provider);
  final enabled = api.getClient().getBooleanValue('example.enabled', false);
}
```

Use your existing region and flag-client key. A resolver override is configured
with `withResolveBaseUrl(Uri.parse(...))`; it affects resolve and apply only.
Events use the selected region's event service.

| Old bridge | OpenFeature provider |
| --- | --- |
| `setup` then `fetchAndActivate` | Build provider; `setProviderAndWait` |
| `activateAndFetchAsync` startup | Builder strategy `activateAndFetchAsync` |
| `getBool(key, fallback)` | `client.getBooleanValue(key, fallback)` |
| `getInt` / `getDouble` / `getString` | `getIntegerValue` / `getDoubleValue` / `getStringValue` |
| `getObject` | `getStructureValue` for a structured map |
| `putContext` / `putAllContext` | Replace the complete OpenFeature context and await reconciliation |
| `track(name, data)` | `client.track(name, details: TrackingEventDetails(attributes: data))` |
| fire-and-forget `flush` | `await provider.flush()`; inspect its result |
| `isStorageEmpty` | `await provider.inspectStorage()` for queue/cache counts |

Reads are synchronous and typed. Wrong types, missing properties, and wrong
contexts return the caller's fallback with error details; they do not enqueue
exposures. Use `getBooleanDetails` and corresponding typed detail methods to
inspect errors/reasons/variants. Valid backend-directed defaults can report an
exposure. Integers and doubles remain distinct.

## Context and startup

`EvaluationContext.targetingKey` maps to `targeting_key`. The migrated/generated
`visitor_id` is included automatically unless the context explicitly overrides it.
On login, account switch, or sign-out, replace the context rather than retaining
stale user attributes:

```dart
await OpenFeatureAPI.instance.setEvaluationContextAndWait(
  EvaluationContext(targetingKey: nextUserId, attributes: {'country': country}),
);
// For sign-out:
await OpenFeatureAPI.instance.setEvaluationContextAndWait(EvaluationContext.empty);
```

Fetch-and-activate startup uses a fresh fetch when possible; offline it uses a
matching cached snapshot or defaults. Corrupt caches are discarded. Assignments
from a different identity are never served. A failed context change does not
restore reads for the previous identity.

Activate-and-fetch-async starts from matching cached assignments/defaults and
writes a background fetch to disk for a later activation. It does not silently
switch the active assignments during that session. There is no automatic polling
for flags. Use a separate provider instance per OpenFeature domain.

## Preserve the installed app's data

Keep the application ID/bundle ID, signing identity, and sandbox when upgrading.
Do not uninstall the app to perform migration. Stop using the old bridge/native
SDK before starting this provider: migration assumes no concurrent native writer.

Automatic migration runs for the default domain before activation. It reads
native visitor preferences, flags, apply records, and sealed/unfinished event
files. Pending records retain their original context/time; repeated or interrupted
imports do not add duplicates. Native cache formats do not establish credential
or region ownership, so automatic import assumes the same app and Confidence
client. Named domains have separate storage and do not automatically import
native flag/event queues. Changing key, region, resolver URL, or domain selects a
new Dart storage scope.

The Confidence Android/Swift SDKs are no longer runtime dependencies of this
package. Flutter utilities provide storage access. A small iOS Foundation plugin
preserves legacy calendar-only dates using the old calendar/time-zone rules at
replay time; it supports SPM and CocoaPods. Ordinary timestamps remain UTC strings.
A failed calendar conversion keeps the event queued for retry.

## Delivery guarantees

Tracking and exposure recording enqueue in memory, then persist asynchronously.
A hard kill before persistence can lose new records. Once persisted, records
survive restarts; a crash after backend acceptance but before local acknowledgement
can replay them. Exactly-once delivery is not promised.

The initial 4 MiB outbox budget drops the oldest unsent records, with a cumulative
counter in storage inspection. Oversized records are dropped individually.
Identity, import checkpoints and sent-exposure deduplication metadata are retained;
metadata exhaustion causes a visible persistence failure rather than deleting
that information. Snapshots and temporary atomic replacement files are outside
the budget.

One scheduler runs every 60 seconds, batching 10 custom events or 20 exposures
with the same token. Transient failures retry with jittered exponential backoff
up to 60 seconds. HTTP 408, 429, 5xx and transport failures retain records; other
4xx responses discard the batch and count drops. Known per-event rejections also
count as drops. Unknown/malformed responses retain work.

`await provider.flush()` persists queued work and attempts delivery. Its result
reports accepted/dropped/pending counts and whether a retry is needed. Disk
failures throw. Shutdown attempts a two-second flush, but mobile OS termination
may skip shutdown; applications must not rely on it for durability.
