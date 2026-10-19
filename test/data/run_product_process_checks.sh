#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
product_fixture_dir=$(mktemp -d -t vital-product-process-XXXXXX)
trap 'rm -rf "$product_fixture_dir"' EXIT
run_fixture() { dart run test/data/product_store_process.dart "$product_fixture_dir" "$1"; }
run_fixture init
set +e
run_fixture before
product_before_status=$?
set -e
[[ "$product_before_status" == 71 ]]
run_fixture verify-empty
set +e
run_fixture after
product_after_status=$?
set -e
[[ "$product_after_status" == 72 ]]
run_fixture verify-retry
