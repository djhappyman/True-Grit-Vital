#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
interval_fixture_dir=$(mktemp -d -t vital-interval-process-XXXXXX)
trap 'rm -rf "$interval_fixture_dir"' EXIT
sdk_root="${VITAL_FLUTTER_SDK:-${XDG_DATA_HOME:-$HOME/.local/share}/flutter-$(<.flutter-version)}"
run_fixture() { "$sdk_root/bin/dart" run test/data/interval_store_process.dart "$interval_fixture_dir" "$1"; }
run_fixture init
set +e
run_fixture before
interval_before_status=$?
set -e
[[ "$interval_before_status" == 71 ]]
run_fixture verify-empty
set +e
run_fixture after
interval_after_status=$?
set -e
[[ "$interval_after_status" == 72 ]]
run_fixture verify-retry
