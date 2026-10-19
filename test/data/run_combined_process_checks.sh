#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
combined_fixture_dir=$(mktemp -d -t vital-combined-process-XXXXXX)
trap 'rm -rf "$combined_fixture_dir"' EXIT
sdk_root="${VITAL_FLUTTER_SDK:-${XDG_DATA_HOME:-$HOME/.local/share}/flutter-$(<.flutter-version)}"
run_fixture() { "$sdk_root/bin/dart" run test/data/combined_store_process.dart "$combined_fixture_dir" "$1"; }
run_fixture init
set +e
run_fixture before
combined_before_status=$?
set -e
[[ "$combined_before_status" == 71 ]]
run_fixture verify-empty
set +e
run_fixture after
combined_after_status=$?
set -e
[[ "$combined_after_status" == 72 ]]
run_fixture verify-retry
set +e
run_fixture correction-before
combined_correction_before_status=$?
set -e
[[ "$combined_correction_before_status" == 73 ]]
run_fixture correction-verify-empty
set +e
run_fixture correction-after
combined_correction_after_status=$?
set -e
[[ "$combined_correction_after_status" == 74 ]]
run_fixture correction-verify-retry
