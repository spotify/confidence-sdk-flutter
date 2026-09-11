#!/usr/bin/env bash
set -euo pipefail
if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <simulator-or-emulator-id> [baseline-ref]" >&2
  exit 2
fi
device=$1
repo=$(git rev-parse --show-toplevel)
baseline_sha=$(git -C "$repo" rev-parse "${2:-bff08df}^{commit}")
results=$(mktemp -d "${TMPDIR:-/tmp}/confidence-upgrade.XXXXXX")
if [[ -n ${GITHUB_OUTPUT:-} ]]; then
  echo "upgrade_results=$results" >> "$GITHUB_OUTPUT"
fi
baseline="$results/baseline"
flutter_bin=${FLUTTER_BIN:-flutter}
created_env=false
if [[ $device == emulator-* ]]; then
  platform=android
  app=com.example.confidence_flutter_sdk_example
  adb_bin=${ADB_BIN:-${ANDROID_HOME:?Set ANDROID_HOME}/platform-tools/adb}
else
  platform=ios
  app=com.example.confidenceFlutterSdkExample
  xcrun simctl list devices available -j | python3 -c \
    'import json,sys; assert any(d["udid"] == sys.argv[1] for group in json.load(sys.stdin)["devices"].values() for d in group), "Expected an iOS simulator"' "$device"
fi
stop_app() {
  if [[ $platform == ios ]]; then
    xcrun simctl terminate "$device" "$app" 2>/dev/null || true
  else
    "$adb_bin" -s "$device" shell am force-stop "$app"
  fi
}
cleanup() {
  stop_app
  git -C "$repo" worktree remove --force --force "$baseline" >/dev/null 2>&1 || true
  if [[ $created_env == true ]]; then rm -f "$repo/example/.env"; fi
  echo "Upgrade logs and native snapshots: $results"
}
trap cleanup EXIT
# shellcheck source=scripts/prepare-native-baseline.sh
source "$repo/scripts/prepare-native-baseline.sh"
prepare_native_baseline
cp "$repo/example/integration_test/upgrade_test.dart" "$baseline/example/integration_test/"
cp "$repo/example/test_drive/upgrade_driver.dart" "$baseline/example/test_drive/"
cat > "$baseline/example/integration_test/upgrade_sdk.dart" <<'DART'
import 'package:confidence_flutter_sdk/confidence_flutter_sdk.dart';
ConfidenceFlutterSdk createUpgradeSdk(Uri server) => ConfidenceFlutterSdk();
DART
python3 - "$baseline/example/pubspec.yaml" <<'PYTHON'
from pathlib import Path
import sys
p = Path(sys.argv[1])
p.write_text(p.read_text().replace('dev_dependencies:', 'dev_dependencies:\n  path_provider: ^2.1.0'))
PYTHON
{
  echo "Baseline: $baseline_sha"
  echo "Candidate: $(git -C "$repo" rev-parse HEAD) plus working-tree changes"
  echo "Device: $device"
  "$flutter_bin" --version
  shasum -a 256 "$repo/example/integration_test/upgrade_test.dart"
} | tee "$results/revisions.txt"
# Reset only the disposable example application BEFORE seeding. Never reset
# between installations: the sentinel assertion detects any lost app data.
if [[ $platform == ios ]]; then
  xcrun simctl uninstall "$device" "$app" || true
else
  "$adb_bin" -s "$device" uninstall "$app" || true
fi
run_phase() {
  local checkout=$1 phase=$2
  local defines=(--dart-define="UPGRADE_PHASE=$phase")
  if [[ $phase != seed ]]; then
    defines+=(--dart-define-from-file="$results/seed.json")
  fi
  (
    cd "$checkout/example"
    UPGRADE_REPORT="$results/$phase.json" "$flutter_bin" drive -d "$device" \
      --driver=test_drive/upgrade_driver.dart --target=integration_test/upgrade_test.dart \
      --keep-app-running "${defines[@]}"
  ) 2>&1 | tee "$results/$phase.log"
  stop_app
}
run_phase "$baseline" seed
# Capture the stable native bytes AFTER process termination. Native request
# timeouts can update exposure state between reporting and termination.
ADB_BIN=${adb_bin:-adb} python3 "$repo/scripts/snapshot-upgrade.py" "$device" "$results/seed.json"
run_phase "$repo" verify
run_phase "$repo" restart
echo "PASS: native install → Dart upgrade → Dart restart" | tee "$results/result.txt"
