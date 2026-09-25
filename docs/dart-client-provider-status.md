# Dart provider implementation status

`confidence_openfeature_provider` is finalized and now lives at the repository
root. The old bridge/runtime packaging has been removed. Native storage migration,
context lifecycle, typed reads, delivery, real mobile upgrades, calendar conversion
and live backend acceptance are implemented and verified. The public-API example,
credential-free CI, migration guide and release preparation are updated.

Publication remains disabled for this development prerelease. Initial release
approval/publisher ownership and broader device/OS coverage are not implied by
these checks. The user's pre-existing Swift checkout was preserved on disk while
its tracked submodule reference was removed.

## Verified baseline

- The published [OpenFeature client package](https://pub.dev/packages/openfeature_dart_client_sdk/versions/0.0.1-beta.1)
  is available at exactly `0.0.1-beta.1`, requiring Dart `^3.12.2`. Its archive
  SHA-256 is `a67d6f2a91f2d243fb9785c0427f50bd0c46de18c27146bf56c27e398188f64f`.
  The package pins that release rather than a floating branch.
- The proposed `confidence_openfeature_provider` package API returned 404 when
  checked. This does not reserve the name or establish publisher ownership.
  `publish_to: none` prevents publishing this unfinished package.
- The package now requires Flutter 3.44.2 / Dart 3.12.2. An isolated Flutter
  checkout was used for Android and iOS storage-access tests; the existing local
  Flutter installation was not upgraded. Utility versions and build limitations
  are recorded in the mobile probe below.
- Configuration defaults: global region, warning logging, fetch-and-activate.
  HTTP(S) resolver overrides preserve proxy path prefixes and trailing slashes
  are normalized. Credentials, query strings, and fragments in the base URL are
  rejected without reproducing their contents in validation errors.
- Resolve and apply use the resolver override when set. Events always use the
  selected regional event service. This follows the pinned Swift
  [base URL mapper](https://github.com/spotify/confidence-sdk-swift/blob/162684bfc1695256c84909eccb2a6c4ca5e67c80/Sources/Confidence/BaseUrlMapper.swift)
  and [event client](https://github.com/spotify/confidence-sdk-swift/blob/162684bfc1695256c84909eccb2a6c4ca5e67c80/Sources/Confidence/RemoteConfidenceClient.swift).

## Upstream contract findings

An initial test-only provider probe was removed during review because it tested
the upstream SDK rather than Confidence behavior. Add lifecycle and domain
isolation tests against the real provider when it is implemented.

The SDK requires both callback completion **and** a terminal provider event:
`ready` for initialization, `contextChanged` for successful reconciliation.
Returning a completed future alone times out. Keep this requirement in the real
provider's lifecycle implementation. Use one provider instance per domain.

## Native parity inventory

The [parity inventory](dart-client-provider-parity.md) now compares the pinned
Android and Swift startup/cache behavior, storage encodings, identity locations,
exposure eligibility, and delivery differences. Separate downloaded source
archives were used; the existing Swift submodule checkout was not modified.

Confirmed decisions: discard corrupt cache data and use defaults when no usable
snapshot exists; report exposure only after successful typed reads (including
valid backend-directed defaults). Failed reads must not enqueue exposure work.

Eight native-generated fixtures cover flags, mixed apply states, and sealed and
unfinished event records. Reproduction tools and evidence limitations are in
[`tool/native_fixtures`](../tool/native_fixtures/README.md).
Swift native-model serialization/decoding and Android storage generation pass;
the pinned Android `FileDiskStorageTest` suite also passes.

## Mobile storage access

`LegacyStorage` now locates the legacy flag/apply files and event directory and
reads the native visitor ID on Android and iOS. It performs no migration, decoding,
deletion, activation, or identity generation. Initialize Flutter bindings before
calling it; keep it off synchronous evaluation paths.

Native-seeded probes pass on Android API 36 and iOS 26.3 with Flutter 3.44.2.
They verify paths, file contents, unprefixed identity reads, native preference
updates, and missing-identity behavior. See the
[mobile storage probe](../tool/mobile_storage_probe/README.md)
for reproduction, exact dependencies, and limitations. This does not replace the
required in-place upgrade tests.

## Snapshot decoding

Immutable snapshot models and pure Android/Swift legacy flag-cache decoders now
preserve context, resolve token, reason, variant, exposure eligibility, recursive
values, integer/double distinctions, and timestamps. Calendar dates remain
distinct and retain Swift DateComponents metadata. Both native flag fixtures
pass, alongside malformed-input and immutability tests. Invalid caches produce
payload-free errors; the storage owner deletes corrupt files.

Import, historical format compatibility, and provider snapshot activation are
implemented below. Native calendar fixtures verify
metadata preservation; the approved iOS calendar helper now handles replay.

SDK attribution is agreed: use Flutter iOS ID 17 / Flutter Android ID 18 from
the resolver proto, with the Dart package version. No new identifier is needed.

## Legacy queue decoding

`LegacyDecoder` now shares native value/date conversion across flag, apply,
and event readers. All eight native fixtures are exercised by Dart tests.
Apply records retain token, flag, timestamp, and created/sending/sent status;
the importer resets sending to pending and retains sent deduplication information.
The pure readers do not replay work or modify files.

Event readers preserve merged context/payload and original timestamps, recover
valid records around malformed or truncated lines, and return rejected line
numbers without payloads. Complete records in unfinished files are accepted.
Physical source positions are retained for repeatable import; identical
events are deliberately not deduplicated by payload. Tests compose native
records into damaged multi-record files. Durable import tracking is implemented;
native crash/upgrade evidence remains outstanding.

## Next increment and gates

### Sequential implementation progress

1. **Durable storage implemented.** `ProviderStorage` serializes reads/updates,
   atomically replaces versioned snapshot/outbox files, retains import metadata
   with queued work, and ignores uncommitted temporary files after restart.
   Native value types survive round trips. Failed writes leave the last commit
   readable and do not prevent subsequent transactions. Corrupt data is removed;
   unsupported future versions are surfaced without overwriting them.
   One storage owner per scope is required; mobile scope selection and runtime
   enqueue coalescing belong to provider integration. Active assignments remain
   in memory and are not changed by writing a fetched snapshot.
   Validation: 80 tests pass, including restart, concurrent update, and
   interrupted-write tests; analysis passes with fatal infos.
2. **Repeatable legacy import implemented.** Identity, flags, apply state, and
   sealed/unfinished events are imported before source cleanup. Queue records
   and source checkpoints commit together; sending becomes pending and sent
   entries retain deduplication. Source IDs survive sandbox relocation and
   distinguish identical events in different files. Invalid UTF-8 is isolated
   per event line. Tests cover failures before/after commit, repeated import,
   corruption, and sandbox relocation. Sources must have no concurrent native
   writer; same-app/same-client ownership remains the documented prerequisite.
   Validation: 88 tests pass; analysis passes with fatal infos.
3. **Historical format compatibility checked.** Published/archive and tag
   inventory, native-generated old fixtures, and calendar preservation tests
   are recorded in [compatibility](dart-client-provider-compatibility.md).
   Fixed Android 0.3.x missing `shouldApply` support. Native Android/Swift fixture
   generation passes; 91 Dart tests and fatal-info analysis pass. Real mobile
   upgrades and calendar conversion during network replay remain later gates.
4. **Resolve transport implemented.** Dart HTTP bulk resolution sends credentials,
   context, `apply: false`, and the agreed platform SDK ID/package version.
   Strict recursive schema decoding preserves integers/doubles and rejects
   mismatches; timestamps in context become UTC strings. Transport has a bounded
   timeout, does not follow credential-bearing redirects, and reports errors
   without request/response payloads. Region/override routing reuses the existing
   endpoint mapper. Validation: 101 tests pass, including local HTTP integration;
   analysis passes with fatal infos. Live backend checks remain a release gate.
5. **Synchronous evaluation implemented.** Typed nested reads, immutable
   structures, backend-directed defaults, reason/variant metadata, and errors
   are resolved entirely from memory. Context mismatches reject assignments;
   failed reads do not invoke the exposure sink. Eligible successful reads
   require a nonempty token. Validation: 112 tests and fatal-info analysis pass.
6. **Public provider/builder integration implemented.** OpenFeature registration,
   both startup modes, typed reads, domain-scoping, tracking persistence, and
   counts-only storage inspection are connected. Mobile initialization locates
   legacy data, persists visitor identity, and scopes new storage by credential,
   region, resolver URL and domain; automatic legacy import is default-domain
   only and assumes the same app/client. Enqueues are coalesced asynchronously;
   the initial 4 MiB UTF-8 outbox budget drops oldest unsent records and persists
   the dropped count. It is an Android-inspired default, not a backend limit.
   Real OpenFeature registration tests exercise
   successful reads and persisted exposure/event records. Validation: 121 tests
   and fatal-info analysis pass.

7. **Lifecycle reconciliation and race guards implemented.** Offline startup
   uses matching cached assignments or defaults. Context changes fetch and
   activate only the latest requested identity; failures reject old-context
   reads. Background startup fetches persist without session activation. Shared
   snapshot writer ownership prevents replaced providers from overwriting new
   assignments, and shutdown rejects late responses with a two-second
   persistence deadline. Tests cover real OpenFeature reconciliation and
   controlled out-of-order, replacement, offline, and shutdown responses.

8. **Telemetry delivery and public flush implemented.** A shared scheduler sends
   regional events and token-grouped applies, with durable acknowledgements,
   bounded shutdown, HTTP retry/permanent-failure handling, and counts-only flush
   results. Replacement workers serialize sends. Tests cover payload fidelity,
   partial rejection, concurrent enqueue, restart after failed acknowledgement,
   automatic retry, and late responses after close. Legacy calendar values use
   the approved Foundation converter, retaining events on conversion failure.

9. **Delivery policies documented.** Retry/drop classification, batching,
   scheduling, request/shutdown deadlines, and flush results are recorded in the
   plan and README. The user selected native iOS calendar conversion for fidelity.
10. **Integrated offline/restart/replay coverage added.** For both native fixture
    formats, tests import queues, initialize the real OpenFeature provider
    offline with cached flags, perform successful/failed typed reads and tracking,
    persist through shutdown, restart, and deliver using public flush. Original
    event context/time and exposure deduplication survive; repeat flush sends
    nothing. These are host integration tests, not real app upgrades.

**Calendar replay implemented.** A small iOS plugin decodes the original Swift
DateComponents and matches native current-calendar/time-zone formatting. It is
packaged for Swift Package Manager and CocoaPods without a Confidence native SDK
dependency. Native parity passes against oldest/pinned SDKs in four time zones;
the real SPM and CocoaPods plugins pass on iOS 26.3. Conversion failures remain durable.
See the [calendar probe](../tool/calendar_probe/README.md).

11. **Retained-sandbox upgrades pass on both platforms.** Published bridge 0.2.4
    reads native-generated fixtures, then the app is replaced without uninstalling.
    The new provider imports offline and persists six pending records; a restart
    replays all six, and another restart sends zero. Native identity, context and
    timestamps survive. Android API 36 and iOS 26.3 pass. Only HTTP is simulated;
    storage and migration use the real mobile path. The new app dependency graph
    contains no Confidence native SDK/bridge. See the
    [upgrade probe](../tool/upgrade_probe/README.md)
    for receipts, fixture adaptations, and reproduction.

**Live backend smoke passes (2026-09-21).** Both Flutter SDK IDs resolve the
configured test flag, decode/persist it, perform successful typed reads, and
receive HTTP 200 for exactly one apply per token/flag despite repeated reads.
The approved `tutorial-event` accepts the configured context plus numeric
`value: 1` with HTTP 200 and no per-event errors. A second flush sends nothing.
Credentials were loaded from the user-approved parent `.env` without printing
or committing values. The management schema lookup was rejected (401); live
publish acceptance verifies this payload without claiming warehouse ingestion.
See the [opt-in smoke runner](../tool/live_smoke/README.md).

The simplified outbox design and its crash/durability trade-offs are agreed and
documented in the [plan](dart-client-provider-plan.md#agreed-outbox-design-and-delivery-trade-offs).
Atomic outbox storage, import, runtime enqueueing, delivery scheduling, retries,
and flush are implemented. Drop-oldest is confirmed;
4 MiB is the initial internal default based on Android's advertised budget,
now measured against actual serialized UTF-8 bytes.

12. **Repository cutover and release preparation completed.** The finalized
    provider is the root package; the example uses its public OpenFeature API.
    Old Dart/Android/Swift bridge files, submodule tracking, native source-copy
    steps and credential-dependent example CI are removed. CI covers unit tests,
    Android, iOS SPM/CocoaPods builds and mobile integration. A staging helper
    preserves the established workaround for SPM Git-identity overrides without
    touching the user's Swift checkout. The SDK version follows the package
    version in Release Please, with a consistency test and package-prefixed tags.
    Publication remains explicitly gated by `publish_to: none`.

The isolated root-package publication dry run succeeds with `--ignore-warnings`.
Its five warnings are the deliberate exact dependency pins; no validation errors
remain. The final Android example build/integration and iOS SPM/CocoaPods builds
pass, as do the two iOS integration cases. Nothing has been uploaded to pub.dev.
See [release preparation](../doc/releasing.md) for the first-release checks and
[application migration](../doc/migration.md) for the supported transition.

Validation: 157 offline tests and two opt-in live scenarios pass; static analysis passes with fatal infos. The
separate CI job now uses Flutter 3.44.2 for the utility dependencies, without
initializing Confidence native submodules. Mobile probe results are listed above.
