# Native migration fixtures

The files in `../../test/fixtures/legacy/{android,swift}` were generated from:

- Android SDK 0.6.9, commit `59be476908ad7c411e2cdca502e974e460a8e50a`.
- Swift SDK commit `162684bfc1695256c84909eccb2a6c4ca5e67c80`.

Inputs are synthetic (`user-a`, `fixture-visitor`, `fixture-token`), with time
fixed to `2023-11-14T22:13:20Z`. No credentials or customer records are included.

Each platform has four artifacts:

| File | Coverage |
| --- | --- |
| `flags.json` | Context, token, variant, reason, apply eligibility, boolean/string/int/double/null, nested structure/list, timestamp |
| `apply.json` | One token with created, sending, and sent entries |
| `events.ready` / `events.READY` | A sealed event with context, values, and original timestamp |
| `events-unfinished` | The same event before sealing; framing is identical |

Android uses the actual `FileDiskStorage` and `EventStorageImpl`, with a mocked
Android Context supplying a temporary event directory. Swift compiles the actual
native models, uses `JSONEncoder` as the native storage does, and reproduces the
newline-before-record framing; it does **not** invoke `EventStorageImpl` or
`DefaultStorage` against an iOS sandbox. Swift object keys are sorted for stable
diffs, without changing the native value/date encoding. Both generators decode
their records with native decoders and assert flag/apply round trips; Swift also
checks that persisted sending state is reset to created.

These are serializer fixtures, not full migration or mobile path tests. Visitor
preference files, older SDK versions, interrupted migration, and corrupt/truncated
multi-record batches are still outstanding. Sealed and unfinished fixtures each
contain one valid record; they do not demonstrate damaged-record recovery.
The Dart queue-reader tests additionally compose these records into multi-record
inputs with corrupt lines and truncated tails, verifying recovery of the valid
records. These are synthetic damage tests, not native crash/upgrade evidence.

## Reproduce

Use disposable checkouts of the exact commits above. Paths below are placeholders
to replace with absolute local paths; generated output may be written to a fresh
directory first for comparison.

Swift (verified with Apple Swift 6.2.4 on macOS; zsh recursive glob):

```sh
cd /path/to/pinned-confidence-sdk-swift
swiftc -o /tmp/confidence-swift-fixtures \
  Sources/Confidence/**/*.swift \
  /path/to/provider/tool/native_fixtures/SwiftFixtures.swift
/tmp/confidence-swift-fixtures /path/to/generated/swift
```

Android (verified with Java 21, Gradle 8.11.1, installed Android SDK platform 33):

Copy `NativeFixturesTest.kt` into the pinned checkout at
`Confidence/src/test/java/com/spotify/confidence/NativeFixturesTest.kt`, then:

```sh
cd /path/to/pinned-confidence-sdk-android
CONFIDENCE_FIXTURE_OUTPUT=/path/to/generated/android \
  ANDROID_HOME=/path/to/android-sdk \
  ./gradlew :Confidence:testDebugUnitTest \
  --tests com.spotify.confidence.NativeFixturesTest --console=plain
```

The native source models/storage files must remain unmodified. The generators
are development tools only; they introduce no native dependency into the provider.
Ordinary provider CI does not build the native SDKs.
