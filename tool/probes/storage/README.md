# Storage probe

An isolated G02 experiment, not the Vital app schema. Only synthetic values and a public fixture passphrase are used. See [storage gate](../../../docs/implementation/02-storage-gate.md) for provenance, results, proposed choices and remaining Android gates.

Run from the repository root:

```bash
./tool/probes/storage/run.sh
```

The script verifies the pinned Flutter 3.47.7/Dart 3.13.5 pair, restores this probe's exact lock, checks formatting/static analysis and executes 15 native Linux tests. It writes reproducible logs under `docs/implementation/evidence/02-storage/`. Set `VITAL_FLUTTER_SDK` to the same pinned SDK elsewhere. Root analysis excludes this independent package; `tool/verify` does not test it. Run this separate runner when probe sources change. No global tool/configuration or main manifest edits are made. Pub/hook caches are regenerated normally.

`test/generate_fractions.py` uses Python's standard-library Fraction as an independent exact oracle; the committed `fractions.json` allows ordinary Dart test execution without Python. Tests create and remove their own temporary encrypted datasets. The subprocess interruption fixture intentionally exits before or after COMMIT and uses the same synthetic key.

The probe is for native Linux execution. Android ABI packaging, Keystore, backup/transfer and physical-device lifecycle checks remain required before clearing G02. The SQL command fixture, minimal Drift roundtrip class and migration fixture are deliberately bounded experiments, not a complete persistence implementation.
