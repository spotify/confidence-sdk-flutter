# Opt-in live smoke test

Verified 2026-09-21 against Confidence's global resolve/apply/events endpoints,
using the user-approved parent `.env` and `tutorial-event`. Both Flutter SDK IDs
(Android and iOS) pass these real HTTP checks:

- Resolve HTTP 200, strict response decoding and durable snapshot persistence.
- Successful typed reads of the configured flag/property.
- Two reads enqueue only one exposure; apply receives HTTP 200.
- One event per SDK ID, with the configured targeting key, synthetic visitor
  `dart-provider-smoke`, and numeric `value: 1`, receives HTTP 200 **and no
  per-event rejections**. The flush result reports acceptance, zero drops,
  and no pending records.
- Another read/flush does not resend acknowledged telemetry.

Run from the repository root:

```sh
python3 tool/live_smoke/run.py \
  --env-file ../.env --flutter /path/to/flutter --event tutorial-event
```

The env file must contain `CONFIDENCE_FLAG_CLIENT_SECRET`,
`CONFIDENCE_TEST_FLAG` (flag name or typed property path), and
`CONFIDENCE_TARGETING_KEY`. The runner parses these values as data, not shell
code, and passes only these selected credentials/configuration through the child
environment. It does not print secrets, send them as process arguments, or copy
them into source files. Only status codes and aggregate acceptance are asserted;
request/response bodies, flag values, and resolve tokens are not logged. Temporary
snapshot/outbox files are removed by teardown. Use an approved test client:
this check intentionally creates exposure/event traffic.

Omit `--event` to run only flag/exposure checks. The runner is outside `test/`
and never runs as part of the normal offline test suite or CI. Each invocation
can send one new apply and optional event for each SDK ID; it is not a load test.

The management schema lookup with the approved API credentials returned 401.
The chosen synthetic event payload was instead verified by actual publish
acceptance. These tests establish endpoint acceptance, not warehouse arrival or
metric ingestion. Mobile installation, migration, and Foundation calendar
conversion are covered by the separate upgrade/calendar probes.
