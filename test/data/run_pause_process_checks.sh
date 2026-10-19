#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
pause_fixture_dir=$(mktemp -d -t vital-pause-process-XXXXXX)
trap 'rm -rf "$pause_fixture_dir"' EXIT
sdk_root="${VITAL_FLUTTER_SDK:-${XDG_DATA_HOME:-$HOME/.local/share}/flutter-$(<.flutter-version)}"
run_fixture() { "$sdk_root/bin/dart" run test/data/pause_store_process.dart "$pause_fixture_dir" "$1"; }
run_fixture init
set +e
run_fixture before
pause_before_status=$?
set -e
[[ "$pause_before_status" == 71 ]]
run_fixture verify-empty
set +e
run_fixture after
pause_after_status=$?
set -e
[[ "$pause_after_status" == 72 ]]
run_fixture verify-retry
