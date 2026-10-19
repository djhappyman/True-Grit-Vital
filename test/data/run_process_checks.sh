#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
fixture_dir=$(mktemp -d -t vital-process-check-XXXXXX)
trap 'rm -rf "$fixture_dir"' EXIT
run_fixture() { dart run test/data/record_store_process.dart "$fixture_dir" "$1"; }
run_fixture init
set +e
run_fixture before
before_status=$?
set -e
[[ "$before_status" == 71 ]]
run_fixture verify-empty
set +e
run_fixture after
after_status=$?
set -e
[[ "$after_status" == 72 ]]
run_fixture verify-retry
