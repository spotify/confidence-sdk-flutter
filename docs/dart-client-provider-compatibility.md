# Legacy format compatibility

Inventory checked against repository release tags and the pub.dev package index
on 2026-09-18. Untagged releases 0.0.1–0.0.3 and 0.0.9 were inspected directly
from published archives, as was 0.2.4. Tags 0.2.2/0.2.3 exist locally but were
not present in the published package index.

| Flutter versions | Android | Swift source |
| --- | --- | --- |
| 0.0.1–0.0.8 | 0.3.2 (`a91dd135`) | `4be8b1ba`; untagged archive value/client/event/visitor files match this revision |
| 0.0.9–0.1.3 | 0.3.6 (`49ae0963`) | `4be8b1ba` |
| 0.1.4 | 0.3.6 | `53645f3a` |
| 0.2.0–0.2.4 | 0.6.2 (`46812dbc`) | `53645f3a` |
| Current bridge branch | 0.6.9 (`59be4769`) | `162684bf` |

Source comparisons show the same tagged scalar/list/structure/date encodings,
queue record shapes, event framing, file paths, and visitor preference keys.
Android 0.3.2 → 0.3.6 adds a network conversion helper without changing stored
values; 0.6.2 → 0.6.9 has no model-shape changes. Swift's later changes to event
storage and apply delivery do not change the serialized queue schema.

The material cache change is `shouldApply`: Android 0.3.x and early Swift
records omit it. The Dart reader defaults an absent field to true, matching
those SDKs' exposure eligibility. Explicit false is retained; malformed values
are rejected. Swift also treats explicit null as its native decoder does.

## Evidence

- Native-generated `android-old` fixtures use Android 0.3.2's actual serializers,
  file storage, and event storage. The fixture driver uses that version's Mockito
  dependency and storage factory; native production code is unchanged.
- Native-generated `swift-old` fixtures use `4be8b1ba` models with JSONEncoder
  and native decoder round-trip checks. As with the pinned fixtures, event
  newline framing is reproduced by the driver rather than an iOS file store.
- Dart tests read both old and pinned fixture sets. Calendar fixtures include a
  leap day with calendar/time-zone metadata, incomplete DateComponents, and a
  negative fractional timestamp. Storage preserves those values without
  projecting calendar dates through the current device time zone.
- Existing Android/iOS native-seeded probes verify preference keys, missing
  identity, uncached native preference updates, and actual file path access.
- Migration tests cover repeat runs, interrupted commits, relocated sandboxes,
  malformed caches, invalid UTF-8, truncated event lines, and identical batches.

These fixtures also pass retained-sandbox Android/iOS app upgrade probes; see
the [upgrade report](../tool/upgrade_probe/README.md).
Replay against a live backend and broader OS coverage remain release gates. Swift calendar-date replay now uses a Foundation helper matching
the old mapper's current-calendar/time-zone rules. Metadata remains intact until
delivery. Native parity and iOS plugin evidence are in the
[calendar probe](../tool/calendar_probe/README.md).

Reproduction: see the [fixture tools](../tool/native_fixtures/README.md).
