#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <device-id> [baseline-ref]" >&2
  exit 2
fi

device=$1
# Last bridged main revision, including the tracking-value and reply fixes.
baseline_ref=${2:-bff08df}
repo=$(git rev-parse --show-toplevel)
baseline_sha=$(git -C "$repo" rev-parse "$baseline_ref^{commit}")
results=$(mktemp -d "${TMPDIR:-/tmp}/confidence-parity.XXXXXX")
if [[ -n ${GITHUB_OUTPUT:-} ]]; then
  echo "parity_results=$results" >> "$GITHUB_OUTPUT"
fi
baseline="$results/baseline"
flutter_bin=${FLUTTER_BIN:-flutter}
created_env=false

cleanup() {
  git -C "$repo" worktree remove --force --force "$baseline" >/dev/null 2>&1 || true
  if [[ $created_env == true ]]; then
    rm -f "$repo/example/.env"
  fi
  echo "Parity logs: $results"
}
trap cleanup EXIT

# shellcheck source=scripts/prepare-native-baseline.sh
source "$repo/scripts/prepare-native-baseline.sh"
prepare_native_baseline
cp "$repo/example/integration_test/parity_test.dart" \
  "$baseline/example/integration_test/parity_test.dart"

{
  echo "Baseline: $baseline_sha"
  echo "Candidate: $(git -C "$repo" rev-parse HEAD) plus working-tree changes"
  echo "Device: $device"
  "$flutter_bin" --version
  shasum -a 256 "$repo/example/integration_test/parity_test.dart"
} | tee "$results/revisions.txt"

run_suite() {
  local checkout=$1
  local label=$2
  (
    cd "$checkout/example"
    "$flutter_bin" test -d "$device" integration_test/parity_test.dart \
      --reporter expanded
  ) 2>&1 | tee "$results/$label.log"
}

# Run both even if one fails, so the logs expose baseline limitations too.
baseline_status=0
candidate_status=0
run_suite "$baseline" baseline || baseline_status=$?
run_suite "$repo" candidate || candidate_status=$?
echo "Baseline exit: $baseline_status; candidate exit: $candidate_status" \
  | tee "$results/result.txt"
[[ $baseline_status -eq 0 && $candidate_status -eq 0 ]]
