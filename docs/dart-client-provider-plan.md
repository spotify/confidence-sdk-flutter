# Dart-native Confidence OpenFeature client provider

Status: implementation started. See [implementation status](dart-client-provider-status.md)
for completed groundwork and outstanding gates. The design below remains the
agreed plan; it is not a claim of implementation completeness.

## Agreed scope

- Replace the current Confidence Flutter bridge with a newly named provider package in this repository. A breaking application API migration is acceptable.
- Support Flutter mobile on iOS and Android. Flutter and general-purpose Flutter plugins are allowed dependencies. Implement Confidence networking, evaluation, persistence, and telemetry in Dart, with no dependency on the existing bridge or the Confidence Android/Swift SDKs.
- Expose an OpenFeature provider, not a public standalone Confidence client.
- Preserve current Flutter capabilities and their underlying behavior: typed/nested evaluation, context changes, initialization strategies, offline cache, exposure reporting, custom events, explicit flushing, and storage inspection.
- Migrate existing on-device flags and queued events. Include persisted apply state and identity data needed to preserve those behaviors.
- Provide a builder with an API key, logging level, custom resolver base URL, region, and initialization strategy. Regions are `eu`, `us`, and `global`; default to `global`. The selected region governs flag resolution, exposure/apply reporting, and custom events, subject to the resolve/apply URL override below.
- Default initialization to `fetchAndActivate`. Also support explicit `activateAndFetchAsync`. Do not choose a strategy automatically.
- Preserve strategy-driven startup and context-triggered refresh. Do not introduce polling, resume-triggered flag refresh, or a separate configurable refresh policy.
- Raise the minimum Flutter/Dart version as needed for the upstream client SDK.

The user selected `confidence_openfeature_provider` as the final new package name.
Publisher ownership and initial publication remain release-time checks.

## Evidence and upstream baseline

This repo currently publishes `confidence_flutter_sdk` 0.2.4. Its Dart API caches flag values, while method channels delegate networking, persistence, apply reporting, and tracking to native SDKs. Android is pinned to 0.6.9; the Swift submodule is pinned to `162684bfc1695256c84909eccb2a6c4ca5e67c80`.

The upstream client source inspected at `5de0dd42b2d76094e3feef1760a29c0d6bddb9f1` contains `openfeature_dart_client_sdk` 0.0.1-beta.1 and requires Dart `^3.12.2`. Its conformance matrix says the initial beta contract is implemented and full conformance remains in progress. Source version does not establish that this version has been published. [Package](https://github.com/open-feature/dart-server-sdk/blob/5de0dd42b2d76094e3feef1760a29c0d6bddb9f1/packages/openfeature_dart_client_sdk/pubspec.yaml), [matrix](https://github.com/open-feature/dart-server-sdk/blob/5de0dd42b2d76094e3feef1760a29c0d6bddb9f1/doc/client-sdk-conformance-matrix.md)

Follow its static-context provider contract: synchronous typed evaluation from memory; asynchronous initialization, context reconciliation, and shutdown; provider-emitted lifecycle events; non-blocking tracking; and cache state associated with the correct active context. The core owns OpenFeature APIs, hooks, defaults, domain binding, and reconciliation scheduling. This provider owns Confidence transport, persisted state, and telemetry. [Architecture](https://github.com/open-feature/dart-server-sdk/blob/5de0dd42b2d76094e3feef1760a29c0d6bddb9f1/doc/client-sdk-architecture.md)

Develop against an exact upstream commit until a suitable immutable release is available. Before publishing this provider, verify a compatible published dependency and rerun contract tests. Do not ship a floating branch dependency.

## Proposed implementation

### Public API

Use a small builder that produces immutable provider configuration. `build()` constructs the provider; OpenFeature registration performs asynchronous initialization. Do not perform network or storage work in the builder.

Illustrative provider API, with names subject to implementation review:

```dart
final provider = ConfidenceProviderBuilder(apiKey: apiKey)
    .withRegion(ConfidenceRegion.eu)
    .withLoggingLevel(ConfidenceLoggingLevel.warn)
    .withInitializationStrategy(
      InitializationStrategy.activateAndFetchAsync,
    )
    .build();
```

| Setting | Contract |
| --- | --- |
| API key | Required; use the existing Confidence client credential protocol |
| Region | `global` by default; `eu` and `us` selectable; applies to flags, exposures, and custom events |
| Logging | Preserve existing levels and warning-level default; ensure disabling logs works |
| Resolver URL | Optional override for resolve and apply requests; custom events use Confidence's event service in the selected region |
| Initialization | `fetchAndActivate` by default; explicit `activateAndFetchAsync` alternative |

Application evaluation context, flag reads/details, events, and custom tracking go through OpenFeature. Keep provider-specific utility methods only where OpenFeature has no equivalent, notably explicit flush and storage inspection. Do not recreate the old standalone SDK surface.

### Internal boundaries

Keep one published provider package with private reusable components under `lib/src/`:

- Provider and immutable configuration/builder.
- Confidence protocol models, context/value conversion, and region/endpoint resolution.
- HTTP transport for resolve, apply, and event publishing.
- Active in-memory flag snapshot and typed/schema-aware property evaluation.
- Persistent storage for fetched snapshots, apply work, event queues, and migration metadata.
- Apply/exposure processor and custom-event delivery, sharing scheduling and transport utilities where semantics match.
- Platform storage location lookup and legacy migration readers.

Implement the upstream `FeatureProvider`, `InitializableProvider`, `ContextReconciliationProvider`, `ProviderEventSource`, `TrackingProvider`, and `ShutdownProvider` capabilities. Follow its domain-scoping rules for a provider with one active context. Reuse upstream context/details/error types instead of maintaining parallel public OpenFeature types. [Provider interfaces](https://github.com/open-feature/dart-server-sdk/blob/5de0dd42b2d76094e3feef1760a29c0d6bddb9f1/packages/openfeature_dart_client_sdk/lib/src/provider.dart)

Use dependency injection internally for transport, storage, and time so tests need no live backend. Select Flutter utility packages only after proving they can locate the legacy storage paths on both platforms. A utility plugin does not justify delegating Confidence behavior to native code.
Explicitly approved exception: a small iOS Foundation helper converts legacy
calendar-only DateComponents at replay time, preserving the native mapper's
calendar/time-zone rules. It adds no Confidence native SDK dependency.

### Initialization and context behavior

| Trigger | Required behavior |
| --- | --- |
| `fetchAndActivate` startup | Complete migration, fetch and persist flags, then activate the resulting usable snapshot before successful initialization completes |
| `activateAndFetchAsync` startup | Complete migration, activate usable cached flags, and fetch updates asynchronously into persistent storage for a later activation |
| Background fetch completion | Do not replace the active session snapshot solely because this fetch completed |
| Context change | Reconcile through OpenFeature, fetch for the new context, and activate the corresponding snapshot on success |
| Typed flag read | Resolve synchronously from the active snapshot; enqueue eligible exposure work in memory; perform no network, disk, or plugin I/O on the read path |
| Shutdown | Stop accepting/scheduling work, attempt a bounded flush, preserve unsent durable work, and prevent late callbacks from restoring state |

Keep fetched and active snapshots separate. Preserve the context, resolve token, schema, reason, variant, and other metadata needed for correct evaluation and apply behavior; migrating only the bridge's flattened value map is insufficient.

Define and test an outcome table for empty cache, first launch offline, usable cache with network failure, corrupt cache, and context mismatch. Derive behavior from the pinned implementations and the upstream client contract. Record any platform disagreement rather than silently choosing one. In particular, stored assignments cannot be served as belonging to a different identity merely to preserve a legacy stale-cache behavior.

The old bridge/native error handling does not map one-to-one to OpenFeature. Specify provider events and resolution error details for each outcome, while retaining offline functionality where the cached context is valid. Guard late network completions during context changes, provider replacement, and shutdown.

Implementation decisions: discard corrupt cache data rather than preserving it;
initialize with defaults when no usable snapshot exists. Report exposure only
after a successful typed read, including a valid backend-directed default, never
for missing properties or type errors. See the [parity inventory](dart-client-provider-parity.md).

### Confidence transport and telemetry

- Implement Confidence bulk resolve, apply, and event publishing directly in Dart. Preserve request/response schemas, client credential handling, context mapping, and SDK metadata.
- Preserve dot-separated flag/property paths, schema-aware booleans/strings/integers/doubles/objects, nested structures/lists, defaults, reasons, variants, and errors. Share the path walker and schema validation across typed resolvers.
- Record exposure when a value is actually consumed, using the matching flag and resolve token. Preserve native eligibility and deduplication behavior, including repeated property reads, retries, and restarts. Fetching flags alone must not report exposure.
- Capture the event's applicable context and timestamp when tracking is called. A later context change must not relabel queued events.
- Preserve pending work across restarts once persisted, with batching, retries, and explicit flush as specified below. Native queue architecture and scheduling need not be reproduced.
- Resolve custom-base-URL precedence centrally: override resolve/apply only; event delivery retains its endpoint in the selected region. Test all three regions across resolve, apply, and event publishing, including custom resolver overrides.
- Use `SDK_ID_FLUTTER_IOS_CONFIDENCE` (17) on iOS and `SDK_ID_FLUTTER_ANDROID_CONFIDENCE` (18) on Android, with the Dart package version. These IDs exist in the resolver's `confidence/flags/resolver/v1/types.proto`; retaining the platform-specific Flutter identity is explicitly agreed. OpenFeature telemetry mapping remains part of runtime implementation.

Region routing is explicitly agreed: use the selected region for flags, exposures, and custom events on both platforms. This follows Swift's routing behavior and intentionally changes Android 0.6.9's global-only custom-event routing. [Swift builder](https://github.com/spotify/confidence-sdk-swift/blob/162684bfc1695256c84909eccb2a6c4ca5e67c80/Sources/Confidence/Confidence.swift), [Android uploader](https://github.com/spotify/confidence-sdk-android/blob/59be476908ad7c411e2cdca502e974e460a8e50a/Confidence/src/main/java/com/spotify/confidence/EventSenderUploader.kt)

### Agreed outbox design and delivery trade-offs

Use one versioned JSON outbox per provider storage scope, separate from the flag
cache. Atomically replace it through one serialized writer, batching writes to
limit disk work. Use one flush in flight and one shared scheduler for exposure
and custom-event delivery. Trigger delivery on startup, a fixed interval, a
batch threshold, explicit flush, and bounded shutdown. Keep defaults internal;
no public queue-tuning API is planned initially.

Persist pending records before sending them. Keep in-flight state only in
memory, and durably remove acknowledged records after delivery. Share storage
and scheduling machinery while keeping apply/event payloads and response
handling distinct. Retry transient failures with capped backoff and jitter,
without per-record timers. Exact intervals, thresholds, backoff bounds, storage
cap details, and apply HTTP failure classification still need to be
specified before delivery implementation.

Overflow decision: discard oldest unsent records across custom events and
exposures, ordered by their recorded timestamps, and persist a dropped-record
counter exposed through storage inspection. The initial internal budget is
4 MiB (4 × 1024 × 1024 bytes), taken from Android 0.6.9's advertised event
budget; it is not a backend constraint. The user approved drop-oldest; this size
is an implementation default, not a separately requested product requirement.
Measure actual UTF-8 serialized outbox bytes, including the envelope and metadata.
Reject an individually oversized record without evicting smaller records that
already fit. Identity, migration checkpoints, and sent deduplication metadata
are not evicted: if metadata alone exceeds the budget, persistence fails visibly
and leaves the last durable commit intact. Snapshot and temporary replacement
files are outside this outbox-file budget; peak disk use can exceed 4 MiB.

Delivery policy and initial internal defaults:

- One scheduler handles both channels every 60 seconds while the app runs.
  Each pass attempts the records present at its start, in batches of 10 custom
  events or 20 exposures sharing a resolve token. Explicit flush skips the delay.
- Retry transport failures, HTTP 408, 429 and 5xx. Unexpected statuses also retain
  work. Other 4xx responses permanently discard that batch, including 401/403,
  and increment the persisted dropped count. The user approved proceeding with
  this policy. HTTP 200 acknowledges delivery; known event-level missing-schema
  or validation rejections count as drops. Malformed or unknown response errors
  retain the batch, potentially replaying already accepted siblings.
- Automatic retries use exponential backoff from one second to a 60-second cap,
  with a uniformly random 50–100% multiplier. Each HTTP request has a 10-second
  timeout. Shutdown has a two-second total flush deadline. Timers do not promise
  background execution while a mobile OS suspends the app.
- `flush()` returns accepted/dropped counts for that attempt, a current pending
  count, and `retryNeeded`. Disk failures throw. A nonempty queue can also contain
  concurrent enqueues; flush does not wait indefinitely for all future work.
- Preserve Swift calendar-only event values through an iOS Foundation converter,
  as explicitly chosen by the user. Decode the original DateComponents and use
  the current calendar/time zone at replay time. Retain and retry events when
  conversion fails; do not drop or flatten them during migration.

Accepted guarantees and limits:

- Events retain their original context and timestamp. Exposures are queued only
  after successful typed reads and deduplicated by resolve token plus flag.
  This local deduplication does not guarantee exactly-once network delivery.
- Reads and non-blocking tracking enqueue in memory; persistence is asynchronous.
  A hard kill before persistence completes can lose those new records. Disk
  work must not block synchronous flag evaluation.
- Once persisted, pending records survive process restarts, subject to the
  eventual documented storage-cap and permanent-failure policies. Atomic file
  replacement avoids partial JSON writes; it is not an unconditional guarantee
  against storage failure or power loss.
- A crash after server acceptance but before durable acknowledgement can cause
  replay and duplicate delivery. Exactly-once delivery would require backend
  support; it is not promised by this provider.
- Explicit `flush()` waits for persistence of work queued before the call and
  attempts delivery. It does not guarantee server acceptance or an empty queue
  during an outage. Persistence/delivery failures must be observable to callers;
  the precise result API will be defined with the provider utilities.
- Shutdown attempts a bounded flush. Mobile termination may skip shutdown or
  interrupt it, so shutdown cannot close the asynchronous persistence window.
- Legacy queues are still imported. Simplifying runtime storage does not remove
  crash-safe, repeatable import or preservation of unrelated valid records.

Validate these boundaries with tests for termination before persistence,
restart after persistence, acknowledgement-write failure, concurrent enqueue
during flush, and interrupted/repeated migration. Publish these limits in the
package and application migration documentation before release.

## On-device migration

Migration runs before cache activation and before replaying queued work. It must work on the first upgraded launch while offline and must not require the old bridge package to be installed.

| Platform | Confirmed legacy storage |
| --- | --- |
| Android | `context.filesDir/confidence_flags_cache.json` and `confidence_apply_cache.json`; events in `context.getDir("events", MODE_PRIVATE)`, with `,\n`-delimited records and `.ready` batches |
| iOS | Application Support / `com.confidence.cache` / bundle identifier / `confidence.flags.resolve` and `confidence.flags.apply`; events under Application Support / `com.confidence.events.storage` / bundle identifier / `events`, with newline-delimited records and `.READY` batches |

Sources: [Android cache](https://github.com/spotify/confidence-sdk-android/blob/59be476908ad7c411e2cdca502e974e460a8e50a/Confidence/src/main/java/com/spotify/confidence/cache/FileDiskStorage.kt), [Android events](https://github.com/spotify/confidence-sdk-android/blob/59be476908ad7c411e2cdca502e974e460a8e50a/Confidence/src/main/java/com/spotify/confidence/EventStorage.kt), [Swift cache](https://github.com/spotify/confidence-sdk-swift/blob/162684bfc1695256c84909eccb2a6c4ca5e67c80/Sources/Confidence/DefaultStorage.swift), [Swift events](https://github.com/spotify/confidence-sdk-swift/blob/162684bfc1695256c84909eccb2a6c4ca5e67c80/Sources/Confidence/EventStorage.swift).

Migration work:

1. Obtain real serialized fixtures from the pinned native SDKs for flag resolutions, apply state, sealed event batches, and unfinished batches. Inventory earlier formats shipped through this Flutter package and identify which need additional readers.
2. Inventory generated identity/context state. Android's factory adds a persisted visitor ID when absent; preserving assignments may require migrating that ID as well. Verify the corresponding Swift behavior and both storage locations.
3. Prove access to the exact paths and bundle identifier through Flutter utilities. Do not assume an Android documents/support directory is the same as `getDir("events")`.
4. Implement Dart readers for native type encodings, date formats, and both event delimiters. Preserve original event context/timestamps and any existing identifiers or deduplication metadata.
5. Write a versioned destination format atomically and track imported source records/batches. Mark import complete only after durable writes; rerunning an interrupted import must not duplicate imported work.
6. Retain recoverable source data until successful import is established. Handle corrupt/truncated records without silently discarding unrelated valid batches. Keep migration diagnostics useful without logging credentials or payloads.
7. Validate an actual in-place app upgrade on each platform, keeping the app ID and sandbox. A unit test of JSON conversion alone is insufficient.

Migration must not promise exactly-once network delivery where legacy records/backend acknowledgements cannot establish it. Test that migration itself does not add duplicate imports, and retain pending work under the documented outbox guarantees above. Legacy caches and queues may lack credential/region ownership metadata; document that limit and validate the normal same-application, same-Confidence-client upgrade before claiming broader compatibility.

## Delivery plan

Each step is a small reviewable change or a short sequence of changes. The old bridge can remain in the working tree during development, but the new package must build independently from the first step. Development used a temporary nested package; the finalized provider now occupies the repository root and release automation has been updated.

| Step | Work | Completion evidence |
| --- | --- | --- |
| 1. Contract and parity inventory | Pin upstream client; record native behavior/serialization fixtures; resolve platform differences; confirm new package name and supported Flutter version | Traceable capability/outcome matrix; minimal provider contract compiles; fixture inventory and migration-path access verified |
| 2. Independent package and builder | Scaffold new provider package, configuration defaults, endpoint mapping, private transport/storage seams, and package-specific CI | Package analyzes/builds without the bridge or native Confidence SDKs; builder/region/URL tests; publication dry run |
| 3. Resolve and local evaluation | Protocol conversion, resolve transport, fetched/active snapshots, typed nested evaluation, reasons/errors/metadata | Deterministic protocol/evaluation tests; network and storage spies confirm reads perform no I/O |
| 4. Persistence and migration | New durable format, legacy readers, identity/apply/event import, crash-safe import tracking | Golden fixtures pass; interrupted/repeated migrations preserve records; offline upgraded startup works on both platforms |
| 5. Initialization and reconciliation | Both strategies, provider events, context reconciliation, stale/error handling, shutdown coordination | Startup outcome matrix; context/replacement/shutdown race tests; upstream client integration tests |
| 6. Exposure and custom events | Eligible apply reporting, durable queues, batching/retries, explicit flush, bounded shutdown | Read-to-apply tests; timestamp/context fidelity; outage/restart/retry tests; migrated queues successfully delivered |
| 7. Mobile integration and cutover | Update example to OpenFeature; perform upgrade tests; remove bridge/native packaging; publish/migration documentation | Android and iOS builds/integration tests; clean dependency/archive checks; reproducible upgrade report and release checklist |

Steps 3 and 4 can progress independently after their shared model/storage contracts are defined. Full lifecycle validation depends on both; event delivery depends on durable storage. Remove the bridge only after the new provider passes the parity and upgrade gates.

## Verification and release gates

- Run unit/contract tests for provider behavior, protocol conversion, value types, schema mismatches, nested missing properties, exposure eligibility, and event serialization.
- Test both initialization strategies with fresh/empty/corrupt/migrated caches and failed/slow requests. Prove background fetch preserves session values until activation.
- Exercise anonymous/user A/user B/sign-out transitions, rapid updates, late responses, context-change failure, provider replacement, and shutdown. Test domain isolation according to upstream capabilities without duplicating its scheduler.
- Verify migrated flags remain usable offline with their correct context, pending apply work is retained, and sealed/unfinished event batches survive repeated or interrupted import.
- Test actual Flutter iOS and Android app upgrades from the bridge implementation, including force-stop/relaunch and offline-to-online event replay. Any reliance on mobile lifecycle callbacks for flushing needs platform tests; flag refresh policy remains strategy/context-driven.
- Run focused live smoke tests for resolve, apply, and custom events using approved test credentials, including each region and a custom resolver URL. Keep the main automated test suite independent of live services.
- Check the final dependency graph and published archive for absence of the bridge, its method-channel classes (except the approved calendar helper), Confidence native SDK artifacts, and Swift submodule content.
- Update CI and publishing for the new package and Dart requirement. Remove native Confidence source-copy, submodule, CocoaPods/SPM, and Gradle dependency steps that become obsolete; retain the platform build checks required by Flutter utility plugins.
- Confirm pub.dev name availability, uploader/publisher ownership, initial publication procedure, versioning, and package-specific release routing. Bootstrap publishing and old-package deprecation are release tasks, not actions performed by this plan.
- Document migration from old setup/context/getters/track/flush calls to OpenFeature registration, context setters, typed evaluation, tracking, and provider utilities. Explain both startup modes, defaults, region/URL precedence, upgrade behavior, and supported minimum versions.

## Remaining decisions and technical checks

- Final new package name and initial release version; working proposal is `confidence_openfeature_provider`.
- Verify an appropriate upstream published version, upstream contract stability, and the exact Flutter release satisfying Dart 3.12.2+.
- Complete the parity outcome matrix and bring concrete native-platform conflicts back for a decision; do not silently encode a preferred platform's behavior.
- Verify legacy visitor identity, older shipped storage formats, path access, and ownership metadata. These are migration release gates, not reasons to drop data preservation from scope.

No runtime implementation, dependency changes, branch, commit, or pull request is part of this planning change.
