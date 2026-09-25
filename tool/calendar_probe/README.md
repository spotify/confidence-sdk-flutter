# Legacy calendar conversion probe

The iOS plugin is a small Foundation-only compatibility helper, not a dependency
on a native Confidence SDK. Dart sends only encoded DateComponents (batched per
event); payloads, identity, network I/O, queue persistence and retries stay in Dart.
Conversion occurs at delivery time using `Calendar.current` and `TimeZone.current`,
matching the old mapper, including its empty-string fallback for unresolvable
components. Failed decoding/channel calls leave the original event pending.

Verified on 2026-09-18:

- The Foundation helper matches both Swift `162684bf` and the oldest shipped
  `4be8b1ba` mapper for seven cases in UTC, Europe/Stockholm,
  America/Los_Angeles, and Asia/Bangkok. Cases include leap day, partial/empty
  components, DST, a Buddhist calendar, overflowed fields, and week-based dates.
- The actual Flutter plugin registers through Swift Package Manager and CocoaPods and passes
  `calendar_test.dart` on iPhone 17 Pro / iOS 26.3, Flutter 3.44.2 / Dart 3.12.2.
  The test covers nested conversion, malformed input and recovery afterwards.
- Dart tests verify metadata transfer without flattening, unchanged ordinary
  timestamps, preserved events on conversion failure, and successful replay.

To reproduce mapper parity, compile `../native_fixtures/CalendarParity.swift`
with the selected native SDK's `Sources/Confidence/**/*.swift` and this package's
`ios/confidence_openfeature_provider/Sources/confidence_openfeature_provider/LegacyCalendar.swift`.
Run the executable with `TZ=UTC`, `TZ=Europe/Stockholm`,
`TZ=America/Los_Angeles`, and `TZ=Asia/Bangkok`. The SDK sources are test-only;
they are not linked into the provider.

For the channel test, generate a disposable Flutter iOS app, add a path
dependency on this package and the `integration_test` SDK dev dependency, then
copy `calendar_test.dart` to its `integration_test` directory. Run:

```sh
flutter pub get
flutter test integration_test/calendar_test.dart -d <ios-simulator-id> --verbose
```

The simulator test expects its default Gregorian calendar. Mapper parity covers
components with additional calendar metadata separately. For CocoaPods, add `flutter.config.enable-swift-package-manager: false` in
the disposable app pubspec and run the same test. The retained-sandbox upgrade and live-backend checks have separate reports in
`../upgrade_probe` and `../live_smoke`.
