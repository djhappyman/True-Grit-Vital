#!/usr/bin/env bash
# Focused T10 release-readiness checks. The lead runs the complete suite separately.
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd -- "$project_root"

python3 tool/release/readiness.py
python3 -m unittest discover -s tool/release/tests
python3 tool/release/boot_matrix.py --run-host --devices
