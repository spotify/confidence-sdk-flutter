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

## Native parity inventory (in progress)

Pinned Swift source was inspected remotely: the local submodule checkout is at
a different revision and must not serve as the pinned behavior baseline.

| Area | Verified observation | Remaining evidence |
| --- | --- | --- |
| Swift startup | `fetchAndActivate` catches fetch errors then loads disk; an absent file returns the empty snapshot; corrupt data throws | Compare pinned Android outcomes and specify OpenFeature errors/events |
| Swift context mismatch | Native evaluation can return a cached match with reason `stale` for a different context | The agreed new contract forbids serving another identity's assignment; test rejection in the new runtime |
| Swift identity | Builder injects `visitor_id`; `VisitorUtil` persists `confidence.visitor_id` in standard UserDefaults | Prove Flutter utility access without prefixed-key assumptions; compare Android identity ownership and formats |
| Swift flag storage | JSONEncoder data under Application Support / `com.confidence.cache` / bundle ID; atomic writes | Generate real flags/apply fixtures and access these paths on a device |
| Swift event response | HTTP 200 acknowledges the batch even with per-event errors; 429 retries; other 4xx acknowledge/discard; other statuses retry | Compare Android, batch limits, retry timing, and restart deduplication before choosing shared behavior |
| Android events | The plan records global-only routing in 0.6.9 | Regional routing is an agreed intentional change, not unresolved parity |

Sources for the inspected Swift observations:
[startup, context, builder](https://github.com/spotify/confidence-sdk-swift/blob/162684bfc1695256c84909eccb2a6c4ca5e67c80/Sources/Confidence/Confidence.swift),
[evaluation](https://github.com/spotify/confidence-sdk-swift/blob/162684bfc1695256c84909eccb2a6c4ca5e67c80/Sources/Confidence/FlagEvaluation.swift),
[identity](https://github.com/spotify/confidence-sdk-swift/blob/162684bfc1695256c84909eccb2a6c4ca5e67c80/Sources/Confidence/VisitorUtil.swift),
[storage](https://github.com/spotify/confidence-sdk-swift/blob/162684bfc1695256c84909eccb2a6c4ca5e67c80/Sources/Confidence/DefaultStorage.swift),
[event responses](https://github.com/spotify/confidence-sdk-swift/blob/162684bfc1695256c84909eccb2a6c4ca5e67c80/Sources/Confidence/RemoteConfidenceClient.swift).

## Next increment and gates

1. Complete the pinned Android/Swift outcome matrix, including first launch
   offline, valid cache with fetch failure, corrupt cache, and context mismatch.
   Bring actual platform disagreements back for a decision before coding them.
2. Generate serialized native fixtures for flags, apply state, visitor identity,
   sealed events, and unfinished batches. No real native fixtures are committed
   yet; synthetic JSON must not be presented as migration evidence.
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
