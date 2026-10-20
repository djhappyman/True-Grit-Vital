#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
sdk_root="${VITAL_FLUTTER_SDK:-${XDG_DATA_HOME:-$HOME/.local/share}/flutter-$(cat .flutter-version)}"
fixture_dir=$(mktemp -d -t vital-supporting-void-process-XXXXXX)
trap 'rm -rf "$fixture_dir"' EXIT
run_fixture() { "$sdk_root/bin/dart" run test/data/supporting_void_recovery_process.dart "$fixture_dir" "$1"; }
run_fixture init
run_fixture verify-pending
set +e
run_fixture resume
resume_status=$?
set -e
[[ "$resume_status" == 81 ]]
run_fixture verify-committed
run_fixture verify-replay
