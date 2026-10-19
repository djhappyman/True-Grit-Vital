#!/usr/bin/env bash
set -euo pipefail
probe_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd -- "$probe_root/../../.." && pwd)"
sdk_root="${VITAL_FLUTTER_SDK:-${XDG_DATA_HOME:-$HOME/.local/share}/flutter-3.47.7}"
evidence="$project_root/docs/implementation/evidence/02-storage"
"$project_root/tool/flutterw" --version --machine > "$evidence/sdk.json"
cd -- "$probe_root"
"$sdk_root/bin/dart" pub get --enforce-lockfile > "$evidence/pub-get.txt" 2>&1
"$sdk_root/bin/dart" format --output=none --set-exit-if-changed lib test bin > "$evidence/format.txt" 2>&1
"$sdk_root/bin/dart" analyze --fatal-infos > "$evidence/analysis.txt" 2>&1
"$sdk_root/bin/dart" test --reporter expanded > "$evidence/tests.txt" 2>&1
sha256sum .dart_tool/lib/libsqlite3mc.so > "$evidence/native-sha256.txt"
printf 'Storage probe passed; evidence: %s\n' "$evidence"
