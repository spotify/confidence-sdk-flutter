# Native Dart migration: parity validation

## Revisions and worktrees

Inspected on 2026-09-11 after fetching origin:

| Worktree | Branch / revision | Purpose |
| --- | --- | --- |
| `confidence-sdk-flutter-worktree-session-bewildered-lark-h8of` | `session/bewildered-lark-h8of`, `02a510e` plus these changes | Dart rewrite; draft PR #62 |
| `confidence-sdk-flutter-worktree-session-tetchy-starling-1xkw` | `session/tetchy-starling-1xkw`, `bff08df` | Current bridged `origin/main`; untouched |
| `confidence-sdk-flutter` | `nicklasl/fix-release-workflow`, `d8eebe0` | Other work; untouched |
| `confidence-sdk-flutter-worktree-nicklasl-flutter-custom-resolve-base-url-run` | `nicklasl/flutter-custom-resolve-base-url-run`, `f69d1d6` | Other work; untouched |

The rewrite has 14 unique commits; main has three since their common ancestor.
The test baseline includes main's recent tracking-value and asynchronous-reply
fixes. It uses Swift submodule revision
`162684bfc1695256c84909eccb2a6c4ca5e67c80` and Android SDK `0.6.9`.
No branch merge, rebase, rename, commit, or push was needed for this validation.

The original plan and draft PR description say the bridge is retained for
side-by-side comparison. That is stale: commit `1b55dfa` removed it. Separate
checkouts provide the comparison instead.

## Run the same contract against both implementations

From the repository root, with an emulator/simulator running:

```sh
flutter test --coverage
flutter analyze
bash scripts/test-parity.sh <device-id>
bash scripts/test-upgrade.sh <device-id>
```

The runner pins baseline `bff08df`, creates a temporary detached worktree,
copies the candidate's exact `example/integration_test/parity_test.dart` into it,
prepares the pinned native sources, and runs both apps on the same device. It
does not switch or reset the working branch. An optional second argument
selects another baseline revision; `FLUTTER_BIN` selects a Flutter executable.

The suite runs a real HTTP server on the device's loopback interface and uses
the public legacy API in both implementations. It exercises actual method
channels/native libraries in the baseline, actual Dart HTTP in the candidate,
real Flutter plugins, and filesystem caching. Fake client secrets are used;
the local parity suite needs no backend credentials. Debug-only Android
configuration allows localhost HTTP; release configuration is unchanged.

The runner records revisions, the test-file SHA-256, toolchain, device, both
logs, and both exit statuses in a printed temporary results directory. It runs
the candidate even if the baseline fails and returns failure if either fails.
Both existing device CI jobs run this comparison before their live-backend
example smoke test. Root CI also collects unit-test coverage.

## Local validation

Toolchain: Flutter 3.27.3 / Dart 3.6.1. Devices: iPhone 17 Pro simulator
(iOS 26.3) and Pixel 9 emulator (Android 16 / API 36).

- Dart unit suite: 152 passing tests, with LCOV output.
- `flutter analyze`: no issues.
- Existing real-backend iOS example smoke test: passed before the native-storage
  follow-up (one test). This confirms
  the rendered live flag values, not event ingestion or flush guarantees.
- Runner: `shellcheck`, `bash -n`, and `git diff --check` pass.

| Shared device contract | Bridged `bff08df` | Dart rewrite |
| --- | --- | --- |
| iOS | 16 passed | 16 passed |
| Android | 15 passed, 1 documented skip | 15 passed, 1 documented skip |

Both final runner invocations exited successfully for both revisions. Each
compared byte-identical copies of the same contract test file. These are local
results; GitHub Actions results are reported separately on the PR.

## Contract coverage

- Defaults before fetching; missing flags/properties and unmatched flags.
- Resolve URL, request shape, client secret, context, and SDK metadata.
- String, boolean, integer, double, root object, and nested object values.
- Integral doubles and JSON doubles declared as integers, including nested
  numeric fields; numeric types survive cache persistence.
- Null object fields; list-valued flags on iOS.
- Context updates, preserved context keys, nested maps/lists, and automatic
  refetch after initialization.
- Legacy unsupported values (including dates and null) remain strings, matching
  the current bridge rather than silently becoming null or zero.
- Scalar/root-object/nested-object exposure delivery, deduplication after the
  initial send, and a fresh exposure for a new resolve token.
- Cached startup with an unavailable resolver, cold blocking fetch fallback,
  failed-refresh cache retention,
  and repeated setup with a new endpoint/client secret.

The unit suite additionally covers new core APIs, stale responses, staged
activation, region routing, apply failure/recovery, event payloads, type
serialization, concurrent first-read deduplication, tracking before any flag
fetch, fire-and-forget serialization failures, and complete disk reads during
overlapping writes. Device coverage is separate from the unit LCOV report.

## Regressions fixed

The native iOS baseline passed scenarios that originally failed on the rewrite:
schema-driven numeric types, object exposure tracking, unsupported legacy value
conversion, cached integral doubles, legacy refresh error containment, and
reconfiguration. Additional checks exposed early tracking being dropped and
readers observing partially written cache files. In-place upgrade checks also
required explicit native ID/cache/event import, persisted exposure timestamps
and acknowledgements, and offline cold-fetch activation. The fixes retain the legacy
surface while routing object evaluation through the shared core path, initializing
the SDK during setup without resolving flags, and publishing disk writes atomically.

## Limits and release follow-up

Passing this suite proves the listed scenarios, not universal migration parity.

- Android SDK 0.6.9 rejects `listSchema`. The shared list-valued-flag case is
  explicitly skipped on Android for both revisions. Lists in context are tested
  on both platforms. The unsupported schema is isolated so it cannot invalidate
  every flag in the common fixture.
- A burst of first reads occasionally produced duplicate exposures in the
  native iOS baseline. The shared test checks deduplication after the first send;
  a separate strict concurrent-first-read regression test covers the Dart manager.
  The native defect was not copied into the rewrite.
- In-place upgrades now have a separate [three-install suite](native-dart-upgrade.md)
  covering native visitor IDs, flag caches, pending/sent exposures, buffered
  native events, and unrelated user files. The behavioral contract above still
  uses fresh installations; the upgrade runner explicitly preserves app data.
- Migrated native events persist until upload succeeds; flush retries that
  backlog and persisted exposures. Newly tracked events still use immediate
  best-effort sends. Native event batching, background scheduling, and complete
  event-delivery guarantees are not established by these migration tests.
- Logging levels and telemetry equivalence are not established. The wrapper
  accepts the logging level without implementing native logging behavior; Dart
  SDK metadata also still reports version `1.0.0` while the package is `0.2.4`.
- The new core-only APIs, web/desktop support, and all possible concurrent
  context/fetch schedules are outside the shared legacy contract. In particular,
  the package still imports `dart:io`; this does not prove web support.

Keep PR #62 in draft until these remaining migration differences are resolved or
explicitly accepted. The suite supplies a repeatable gate, not a blanket claim
that replacing the bridge cannot change behavior.
