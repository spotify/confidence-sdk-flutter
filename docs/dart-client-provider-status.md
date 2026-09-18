# Dart provider implementation status

The first increment adds an independent package under
`packages/confidence_openfeature_provider`. The existing bridge remains in place.
This is groundwork for delivery steps 1–2, not completion of either step or a
usable provider. The public builder is deferred until it can return a functional
provider; no placeholder runtime reports successful initialization.

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
[`tool/native_fixtures`](../packages/confidence_openfeature_provider/tool/native_fixtures/README.md).
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
[mobile storage probe](../packages/confidence_openfeature_provider/tool/mobile_storage_probe/README.md)
for reproduction, exact dependencies, and limitations. This does not replace the
required in-place upgrade tests.

## Snapshot decoding

Immutable snapshot models and pure Android/Swift legacy flag-cache decoders now
preserve context, resolve token, reason, variant, exposure eligibility, recursive
values, integer/double distinctions, and timestamps. Calendar dates remain
distinct and retain Swift DateComponents metadata. Both native flag fixtures
pass, alongside malformed-input and immutability tests. Invalid caches produce
payload-free errors; file deletion remains the future storage owner's job.

This does not yet import files, activate snapshots,
or establish compatibility with older shipped formats. Calendar date edge cases
(including Swift calendar/time-zone conversion) still need native fixture coverage.

SDK attribution is agreed: use Flutter iOS ID 17 / Flutter Android ID 18 from
the resolver proto, with the Dart package version. No new identifier is needed.

## Legacy queue decoding

`LegacyDecoder` now shares native value/date conversion across flag, apply,
and event readers. All eight native fixtures are exercised by Dart tests.
Apply records retain token, flag, timestamp, and created/sending/sent status;
the future importer must reset sending to pending and retain sent deduplication
information. The readers do not replay work or modify files.

Event readers preserve merged context/payload and original timestamps, recover
valid records around malformed or truncated lines, and return rejected line
numbers without payloads. Complete records in unfinished files are accepted.
Physical source positions are retained for future repeatable import; identical
events are deliberately not deduplicated by payload. Tests compose native
records into damaged multi-record files; native crash/upgrade evidence and
durable import tracking are still outstanding.

## Next increment and gates

The simplified outbox design and its crash/durability trade-offs are agreed and
documented in the [plan](dart-client-provider-plan.md#agreed-outbox-design-and-delivery-trade-offs).
This is a design decision, not implemented queue behavior: one atomic JSON
outbox, serialized writes, one flush in flight, and shared fixed scheduling.

1. Implement the documented startup outcome matrix when adding lifecycle support.
   Specify numeric scheduling/batching/backoff defaults, storage cap/overflow,
   and apply HTTP failure policy before implementing delivery.
2. Extend the native fixtures with visitor stores, older shipped formats, and
   damaged multi-record batches; test interrupted/repeated import.
3. Extend the mobile path/identity checks to retained app sandboxes during actual
   upgrades and the final supported OS matrix. Initial access is verified on
   both platforms; the utility dependencies have been selected.
4. Implement the atomic outbox and repeatable migration using the legacy readers;
   add the functional provider and builder, resolve transport, and local evaluation.
5. Continue the remaining persistence, migration, lifecycle, telemetry, and
   mobile cutover steps in the plan. In-place upgrades, live smoke tests,
   publication dry run, and removal of the bridge have not been performed.

Validation: 71 unit tests pass; static analysis passes with fatal infos. The
separate CI job now uses Flutter 3.44.2 for the utility dependencies, without
initializing Confidence native submodules. Mobile probe results are listed above.
