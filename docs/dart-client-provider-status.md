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
- The foundation analyzes and runs on a separate Dart 3.12.2 toolchain. The local
  Flutter installation's Dart 3.6.1 is insufficient. A supported minimum Flutter
  version remains a mobile integration gate; it has not been tested here.
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

## Next increment and gates

1. Implement the documented startup outcome matrix when adding lifecycle support.
   Resolve remaining batching/scheduling, storage-budget, and apply HTTP-policy
   differences before implementing delivery.
2. Extend the native fixtures with visitor stores, older shipped formats, and
   damaged multi-record batches; test interrupted/repeated import.
3. Verify mobile utility access to the legacy files and identity stores. Android
   `getDir("events")` is not its documents directory. Test both mobile platforms
   before selecting dependencies or claiming a minimum Flutter version.
4. Define transport/storage contracts from those verified models, then add the
   functional provider and builder, resolve transport, and local evaluation.
   Backend support for the new SDK telemetry identifier remains unverified.
5. Continue the remaining persistence, migration, lifecycle, telemetry, and
   mobile cutover steps in the plan. In-place upgrades, live smoke tests,
   publication dry run, and removal of the bridge have not been performed.

Validation after review: 22 tests pass with Dart 3.12.2; static analysis
passes with fatal infos. The separate CI job performs these checks without
initializing native submodules or installing Flutter.
