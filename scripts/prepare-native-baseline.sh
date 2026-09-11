#!/usr/bin/env bash
# Variables are provided/consumed by the sourcing runner.
# shellcheck disable=SC2154,SC2034
# Shared preparation for parity and upgrade tests; source from the runners.
prepare_native_baseline() {
  git -C "$repo" worktree add --detach "$baseline" "$baseline_sha"
  cp "$repo/example/android/app/src/debug/AndroidManifest.xml" \
    "$baseline/example/android/app/src/debug/AndroidManifest.xml"
  echo 'API_KEY=unused-by-parity-suite' > "$baseline/example/.env"
  if [[ ! -e "$repo/example/.env" ]]; then
    echo 'API_KEY=unused-by-parity-suite' > "$repo/example/.env"
    created_env=true
  fi
  if [[ -f "$baseline/ios/confidence_flutter_sdk.podspec" ]]; then
    git -C "$baseline" submodule update --init --recursive
    cp -R "$baseline/ios/Classes/confidence-sdk/Sources/Confidence" \
      "$baseline/ios/Classes/Confidence"
  fi
}
