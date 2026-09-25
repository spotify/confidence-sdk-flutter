# Release preparation

`confidence_openfeature_provider` is the finalized package name. The repository
root now contains that package; the old bridge changelog is retained in GitHub's
`docs/legacy-bridge-changelog.md`. The example retains its old app IDs but depends
only on this provider. `publish_to: none` intentionally prevents publication until
a release is explicitly approved and publisher ownership is confirmed.

Use Flutter 3.44.2 / Dart 3.12.2. Before releasing:

1. Run `flutter pub get`, `flutter analyze --fatal-infos`, and `flutter test`.
2. Build the example on Android and iOS (SPM and CocoaPods). CI covers both
   packaging paths and credential-free emulator/simulator integration tests.
3. Review the upgrade/calendar reports and opt-in live smoke results. The tested
   mobile configurations are Android API 36 and iOS 26.3; this is not exhaustive
   device/OS coverage. The live checks establish HTTP acceptance, not warehouse
   ingestion.
4. Review the archive in an isolated copy. Keep credentials and the preserved
   local Swift checkout out of it:

   ```sh
   python3 tool/stage_package.py /tmp/release-review/confidence_openfeature_provider --publishable
   cd /tmp/release-review/confidence_openfeature_provider
   flutter pub get
   flutter pub publish --dry-run --ignore-warnings
   ```

   The five expected warnings concern exact dependency pins: OpenFeature,
   package_info_plus, path_provider, shared_preferences, and
   shared_preferences_android. These preserve the verified beta/toolchain matrix.
   Review all warnings; do not broaden constraints solely to silence them.
   `--dry-run` uploads nothing. The real repository remains non-publishable.
5. For an approved release, confirm the pub.dev publisher and version, then remove
   `publish_to: none` in the release change. Release Please uses package-prefixed
   tags, creates draft release PRs, and updates the SDK attribution constant with
   the pubspec version. A test prevents version drift. Its annotation follows
   [Release Please's extra-file mechanism](https://github.com/googleapis/release-please/blob/main/docs/customizing.md#updating-arbitrary-files).
   The publish workflow skips credential setup and upload while publication is
   disabled; after approval it runs validation before publishing.

## Local SPM builds

Flutter/SPM can infer this checkout's Git repository identity
(`confidence-sdk-flutter`) instead of the package identity, causing an override
error. CI stages the tree without Git metadata under the finalized package name:

```sh
python3 tool/stage_package.py /tmp/mobile-check/confidence_openfeature_provider
cd /tmp/mobile-check/confidence_openfeature_provider/example
flutter pub get
flutter build ios --simulator --debug
```

This matches the published-package layout. The staging tool copies tracked and
non-ignored reviewable files, skips deleted files/submodule directories, and
requires a new destination outside the repository. It does not modify the checkout
or remove the user's preserved `ios/Classes/confidence-sdk` directory.
