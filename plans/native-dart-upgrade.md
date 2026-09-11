# In-place native → Dart upgrade validation

The behavioral branch comparison is supplemented by a three-install test using
real native-generated data: bridged `bff08df` → current Dart worktree → Dart
restart. Neither the SDK nor its native storage is mocked during seeding.

## Reproduce

```sh
bash scripts/test-upgrade.sh <simulator-or-emulator-id> [baseline-ref]
```

Use an iOS simulator or Android emulator. Set `ANDROID_HOME` for Android.
The runner resets only the example app before seeding, then uses `flutter drive
--keep-app-running` to retain app data across installations. It stops the old
app and snapshots its actual persisted files before installing the rewrite.
Every subsequent phase asserts an unrelated app-data sentinel, so a clean
install cannot accidentally pass as a migration. No branch switching is needed.

Results include pinned revisions, toolchain, contract hash, phase logs, and
base64 snapshots of the native fixture files. The runner prints their directory.
It uses a fake client secret and loopback resolver. The candidate's injectable
HTTP client redirects migrated event delivery to the same local fixture; native
seeding writes events using its ordinary buffering mechanism.

## Scenarios and expected behavior

| Scenario | Assertion | Coverage |
| --- | --- | --- |
| Upgrade an anonymous visitor | Exact native visitor ID, including UUID case, remains the resolver and event context identity | Device + unit |
| First launch after upgrade is offline | Native string, bool, int, integral double and nested object flags remain available | Device + unit |
| Cold blocking fetch fails | `fetchAndActivate()` activates existing disk values instead of returning defaults | Shared branch contract + device restart + unit |
| Resolver recovers | New values replace migrated values and survive another offline restart | Device |
| Exposure interrupted during native send | CREATED/SENDING record retries using its original token and timestamp | Device + unit |
| Exposure already acknowledged | SENT receipt suppresses duplicate evaluation and restart sends | Device + unit |
| Native event buffered at termination | Original event name, values, context and event time survive migration | Device + unit |
| First migrated event upload fails | Queue stays on disk; flush retries identical events; acknowledged events do not return on restart | Device + unit |
| One upload stalls while more flags are read | Later exposures are persisted immediately and survive restart with original times | Unit |
| App owns other persisted files | Sentinel and original native files remain byte-for-byte unchanged | Device + unit |
| Newer Dart data already exists | Existing IDs/caches/empty acknowledgement queues take precedence over native data | Unit + device restart |
| Migration interrupted between writes | Retry imports remaining files without replacing completed/newer data | Unit with injected write failure |
| Missing, empty, malformed, or truncated native files | Startup remains usable; original bytes remain available for recovery | Unit |
| Malformed Dart flag cache | Defaults remain usable; a successful fetch repairs the active cache | Unit |
| Fresh install / concurrent SDK factories | One persistent visitor ID is created and reused | Unit |

## Verified locally on 2026-09-11

Flutter 3.27.3 / Dart 3.6.1:

| Platform | Native seed | In-place Dart upgrade | Dart restart |
| --- | --- | --- | --- |
| iPhone 17 Pro simulator, iOS 26.3 | Passed | Passed | Passed |
| Pixel 9 emulator, Android 16 / API 36 | Passed | Passed | Passed |

The final unit suite passed 152 tests with coverage; `flutter analyze`,
`shellcheck`, shell syntax checks, and `git diff --check` passed. The shared
behavioral contract passed 16 cases on each iOS implementation and 15 on each
Android implementation (one explicit native list-schema limitation skipped).
The iOS/Android CI jobs now run the upgrade gate and retain its evidence.
GitHub Actions results are reported separately on the PR.

Final local evidence directories (under the host's temporary directory):

- iOS upgrade: `confidence-upgrade.n7lKGh`
- Android upgrade: `confidence-upgrade.6ZTwJW`
- iOS branch contract: `confidence-parity.hiGWSY`
- Android branch contract: `confidence-parity.fu8UUX`

## Implementation boundaries

Native originals are preserved. Each atomic destination write is an import
checkpoint. Existing destination files, including empty acknowledgement queues,
prevent re-import; otherwise drained native queues could be resurrected.

Swift reads `confidence.visitor_id` from standard UserDefaults; Android reads
`visitorId` from the `confidence-visitor` SharedPreferences file. The Dart
preference takes precedence once present. Flag and apply formats are converted
from the pinned native SDKs; Swift's 2001 date epoch is converted explicitly.
The migrator reads only SDK event filenames in the SDK's own event directory.

These tests establish the listed upgrade cases, not arbitrary historical SDK
versions, downgrade behavior, or exactly-once delivery across a crash between a
server acknowledgement and its disk write. Retaining original native files does
not mean a downgrade knows about acknowledgements made by Dart. Corrupt source
bytes cannot be reconstructed; malformed native event files defer event import
while leaving flags and source files intact.

Newly tracked Dart events still use the rewrite's immediate best-effort sender.
This work recovers the native backlog and gives flush a retry path for that
backlog and persisted exposures. Native background scheduling, batching, and the
complete event-delivery lifecycle need separate parity validation before making
a blanket release guarantee. See [the parity report](native-dart-parity.md).
