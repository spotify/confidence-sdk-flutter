# Native parity and migration evidence

Baseline: Android `59be476908ad7c411e2cdca502e974e460a8e50a` (0.6.9),
Swift `162684bfc1695256c84909eccb2a6c4ca5e67c80`, and Flutter bridge `bff08df`.
This inventory distinguishes observed native behavior from the proposed
OpenFeature mapping. It is not evidence of an in-place mobile upgrade.

## Decisions confirmed during implementation

- Discard corrupt cache data; no recovery copy is required. When there is no
  usable snapshot, continue startup with defaults. A successful fresh fetch
  supplies the active snapshot for `fetchAndActivate`.
- Report exposure only after a successful typed read, including a valid
  backend-directed default. Missing properties, type errors, and other failed
  reads must not enqueue apply work.
- Previously agreed: never serve another identity's assignments; the selected
  region applies to events as well as resolve/apply; background fetching alone
  must not replace active values.

Discarding a corrupt cache does not authorize dropping valid events from another
batch, or unrelated valid records in a partially damaged event file.

## Startup outcome matrix

| Input / operation | Android observation | Swift observation | Dart outcome to implement |
| --- | --- | --- | --- |
| Fetch succeeds, `fetchAndActivate` | Store, then read into active cache | Store, then read into active cache | Persist and activate matching snapshot; emit `ready` |
| First launch, offline | Fetch failure is handled; missing cache becomes `EMPTY` | Fetch failure is swallowed; missing cache becomes `EMPTY` | Initialize with defaults; missing flags return `flagNotFound`; emit `ready` |
| Valid same-context cache, offline | Fetch failure followed by cached activation | Same | Activate cache, retain its token/context; emit `ready`, then `stale` for failed refresh |
| Empty file, offline | Treat as `EMPTY` | JSON decoding fails | Discard unusable file; defaults, `ready` |
| Malformed file, offline | Delete file and return `EMPTY` | Native activation throws; Flutter bridge logs and returns success | Discard corrupt file; defaults, `ready` |
| Cache belongs to another context, offline | Native reads may return old value as `STALE` | Native reads may return old value as `STALE` | Do not activate mismatched snapshot; defaults, `ready` |
| `activateAndFetchAsync`, usable cache | Activate before starting fetch | Activate before starting background task | Activate matching cache, emit `ready`; fetched result is persisted for later activation |
| `activateAndFetchAsync`, corrupt/absent cache | Empty activation then background fetch | Bridge catches activation error then launches fetch | Discard corruption, initialize defaults, emit `ready`; background result stays inactive |
| Context change succeeds | Fetch and activate new snapshot | Fetch and activate new snapshot | Activate matching snapshot, then emit `contextChanged` |
| Context change fails | Old disk cache can be activated under changed native context | Reconciliation fails and attempts old cache activation | Never relabel old assignments; surface reconciliation failure and reject reads with a mismatched context |

The event/error column is the implementation specification, not a claim that the
runtime exists. `ready` plus `stale` must be tested against the upstream lifecycle
contract, which requires a terminal event as well as callback completion.
Never use `providerNotReady` to describe a successfully initialized empty cache.
The future provider must guard direct reads as well as SDK-managed context changes.

Evidence:
[Android activation/fetch](https://github.com/spotify/confidence-sdk-android/blob/59be476908ad7c411e2cdca502e974e460a8e50a/Confidence/src/main/java/com/spotify/confidence/Confidence.kt),
[Android disk storage](https://github.com/spotify/confidence-sdk-android/blob/59be476908ad7c411e2cdca502e974e460a8e50a/Confidence/src/main/java/com/spotify/confidence/cache/FileDiskStorage.kt),
[Swift activation/fetch](https://github.com/spotify/confidence-sdk-swift/blob/162684bfc1695256c84909eccb2a6c4ca5e67c80/Sources/Confidence/Confidence.swift),
[Swift disk storage](https://github.com/spotify/confidence-sdk-swift/blob/162684bfc1695256c84909eccb2a6c4ca5e67c80/Sources/Confidence/DefaultStorage.swift),
[Swift bridge error handling](https://github.com/spotify/confidence-sdk-flutter/blob/bff08df/ios/confidence_flutter_sdk/Sources/confidence_flutter_sdk/ConfidenceFlutterSdkPlugin.swift).

## Storage and identity

| Data | Android | Swift |
| --- | --- | --- |
| Flags | `filesDir/confidence_flags_cache.json`; `context`, `flags`, `resolveToken` | Application Support / `com.confidence.cache` / bundle ID / `confidence.flags.resolve`; same outer fields |
| Values | Tagged objects such as `{"integer":7}`, `{"map":{...}}`, null as `{}` | Synthesized enum encoding such as `{"integer":{"_0":7}}`, `{"structure":{"_0":{...}}}`, null as `{"null":{}}` |
| Flag metadata | `reason`, `variant`, `shouldApply` | `resolveReason`, optional `variant`, `shouldApply` (missing defaults to true on decode) |
| Apply | `filesDir/confidence_apply_cache.json`; token → flag → `{time,eventStatus}` | Same cache directory / `confidence.flags.apply`; `{resolveEvents:[{resolveToken,events:[{name,applyTime,status}]}]}` |
| Apply date / status | UTC ISO-8601 string; `CREATED`, `SENDING`, `SENT` | Seconds since 2001-01-01; `{"created":{}}`, `{"sending":{}}`, `{"sent":{}}` |
| Event location | `context.getDir("events", MODE_PRIVATE)` | Application Support / `com.confidence.events.storage` / bundle ID / `events` |
| Event framing | JSON followed by `,\n`; sealed suffix `.ready` | `\n` before JSON; sealed suffix `.READY` |
| Event name/time | `eventDefinition`, ISO-8601 `eventTime` | `name`, reference-date numeric `eventTime` |
| Visitor ID | SharedPreferences file `confidence-visitor`, key `visitorId`; inject `visitor_id` only if absent | Standard UserDefaults key `confidence.visitor_id`; builder passes ID into initial context |

Stored values carry their native types rather than the original wire schema.
Do not assume native caches retain a separate schema object. Preserve integer
versus double and recursive list/structure types when creating the new snapshot.
Neither format associates the snapshot with a credential or region: support the
same-app, same-client upgrade first; do not infer ownership from filenames.

Evidence:
[Android identity](https://github.com/spotify/confidence-sdk-android/blob/59be476908ad7c411e2cdca502e974e460a8e50a/Confidence/src/main/java/com/spotify/confidence/VisitorUtil.kt),
[Android serializers](https://github.com/spotify/confidence-sdk-android/blob/59be476908ad7c411e2cdca502e974e460a8e50a/Confidence/src/main/java/com/spotify/confidence/serializers/Serializers.kt),
[Android event storage](https://github.com/spotify/confidence-sdk-android/blob/59be476908ad7c411e2cdca502e974e460a8e50a/Confidence/src/main/java/com/spotify/confidence/EventStorage.kt),
[Swift identity](https://github.com/spotify/confidence-sdk-swift/blob/162684bfc1695256c84909eccb2a6c4ca5e67c80/Sources/Confidence/VisitorUtil.swift),
[Swift value encoding](https://github.com/spotify/confidence-sdk-swift/blob/162684bfc1695256c84909eccb2a6c4ca5e67c80/Sources/Confidence/ConfidenceValue.swift),
[Swift event storage](https://github.com/spotify/confidence-sdk-swift/blob/162684bfc1695256c84909eccb2a6c4ca5e67c80/Sources/Confidence/EventStorage.swift).

## Exposure, durability, and remaining delivery differences

- Android queues eligible apply before property lookup/type checking. Swift
  queues after successful evaluation or a valid default outcome. Use the
  successful-read policy confirmed above. Swift's resolver currently constructs
  `shouldApply: true`; Android reads the response field. The new transport must
  preserve backend eligibility rather than copy that Swift assumption.
- Both deduplicate by resolve token plus flag name, batch apply in groups of 20,
  and reset persisted sending state to created on restart. Both omit wholly sent
  token groups from disk, so deduplication is not guaranteed across every restart.
  Migration must retain mixed created/sending/sent groups without claiming
  exactly-once delivery.
- Event HTTP policy agrees: 200 removes a batch, 429 retains it, other 4xx remove
  it, and other statuses retain it. Swift also logs per-event errors from a 200
  response; Android does not parse that response body. Network/decode failures
  need separate tests from HTTP response classification.
- Android flushes at five events or explicit flush. Swift flushes at ten events,
  every 60 seconds, on startup, and during bounded shutdown. The agreed Dart
  design uses one shared scheduler with startup, interval, threshold, explicit
  flush, and bounded shutdown triggers. Numeric defaults remain to be selected.
- Android advertises a 4 MiB event budget with a 90% threshold, but the inspected
  size check reads a directory's length, not aggregate event bytes. Swift's
  inspected file store has no equivalent cap. A reliable common storage budget
  remains to be specified.
- Android reopens unfinished files with `outputStream()`, which truncates them;
  Swift opens for writing and seeks to end on each write. Read unfinished files
  before invoking any legacy startup. The new provider must preserve the valid
  records rather than reproduce the truncation behavior.
- Apply response classification also needs an explicit policy: Swift treats an
  HTTP-client success result as sent without checking HTTP status in its applier.
  Do not copy that behavior as the Dart retry contract.

Evidence:
[Android evaluation](https://github.com/spotify/confidence-sdk-android/blob/59be476908ad7c411e2cdca502e974e460a8e50a/Confidence/src/main/java/com/spotify/confidence/ConfidenceFlagEvaluation.kt),
[Swift evaluation](https://github.com/spotify/confidence-sdk-swift/blob/162684bfc1695256c84909eccb2a6c4ca5e67c80/Sources/Confidence/FlagEvaluation.swift),
[Android apply](https://github.com/spotify/confidence-sdk-android/blob/59be476908ad7c411e2cdca502e974e460a8e50a/Confidence/src/main/java/com/spotify/confidence/apply/FlagApplierWithRetries.kt),
[Swift apply](https://github.com/spotify/confidence-sdk-swift/blob/162684bfc1695256c84909eccb2a6c4ca5e67c80/Sources/Confidence/Apply/FlagApplierWithRetries.swift),
[Android uploader](https://github.com/spotify/confidence-sdk-android/blob/59be476908ad7c411e2cdca502e974e460a8e50a/Confidence/src/main/java/com/spotify/confidence/EventSenderUploader.kt),
[Swift uploader](https://github.com/spotify/confidence-sdk-swift/blob/162684bfc1695256c84909eccb2a6c4ca5e67c80/Sources/Confidence/RemoteConfidenceClient.swift),
[Android event engine](https://github.com/spotify/confidence-sdk-android/blob/59be476908ad7c411e2cdca502e974e460a8e50a/Confidence/src/main/java/com/spotify/confidence/EventSenderEngine.kt),
[Swift event engine](https://github.com/spotify/confidence-sdk-swift/blob/162684bfc1695256c84909eccb2a6c4ca5e67c80/Sources/Confidence/EventSenderEngine.swift).

## Evidence limits and next work

The [agreed outbox design](dart-client-provider-plan.md#agreed-outbox-design-and-delivery-trade-offs)
replaces native queue internals with atomic JSON persistence and shared scheduling.
The user accepts possible loss before asynchronous persistence and duplicate
delivery after server acceptance but before durable acknowledgement, provided
these limits are documented. This does not relax repeatable legacy import.

Native-generated fixtures and reproduction instructions are in
[`tool/native_fixtures`](../tool/native_fixtures/README.md).
They cover flags, apply states, and sealed/unfinished events with synthetic
identities and timestamps. They are actual native serialization output, not real
customer data or proof of mobile sandbox access.

Initial preference/path access is now verified on both mobile platforms; see the
[mobile storage probe](../tool/mobile_storage_probe/README.md).
Still required: older shipped-format inventory,
visitor-store fixtures, crash-safe import tracking, damaged-batch recovery,
in-place Android/iOS upgrade tests, and the
delivery-policy decisions above. No legacy mobile data was modified by this work.
