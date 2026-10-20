#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
sdk_root="${VITAL_FLUTTER_SDK:-${XDG_DATA_HOME:-$HOME/.local/share}/flutter-$(cat .flutter-version)}"
run_fixture() { "$sdk_root/bin/dart" run test/restore/restore_activation_process.dart "$@"; }
for phase in ready replaced committed; do
  fixture_dir=$(mktemp -d -t vital-restore-process-XXXXXX)
  trap 'rm -rf "$fixture_dir"' EXIT
  set +e
  run_fixture init "$fixture_dir" "$phase"
  status=$?
  set -e
  [[ "$status" == 81 ]]
  if [[ "$phase" == ready ]]; then
    run_fixture wrong-key "$fixture_dir"
    run_fixture old "$fixture_dir"
  else
    run_fixture new "$fixture_dir"
  fi
  rm -rf "$fixture_dir"
  trap - EXIT
done
