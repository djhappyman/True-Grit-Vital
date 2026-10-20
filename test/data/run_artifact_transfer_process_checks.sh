#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
orphan_dir=$(mktemp -d -t vital-artifact-orphan-XXXXXX)
partial_dir=$(mktemp -d -t vital-artifact-partial-XXXXXX)
trap 'rm -rf "$orphan_dir" "$partial_dir"' EXIT
dart run test/data/artifact_transfer_process.dart "$orphan_dir" stage orphan
dart run test/data/artifact_transfer_process.dart "$orphan_dir" cleanup orphan
dart run test/data/artifact_transfer_process.dart "$partial_dir" stage partial
dart run test/data/artifact_transfer_process.dart "$partial_dir" cleanup partial
