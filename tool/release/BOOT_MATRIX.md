# Boot matrix

This matrix is evidence, not a readiness claim. Run it from the repository root
with the pinned SDK. Every row starts unverified; only an executed command can
make a row pass.

```sh
python3 tool/release/boot_matrix.py --run-host --run-linux --devices
```

The machine-readable result is written to `build/release-boot-matrix.json`.
`--strict` exits non-zero while any required row is unverified.

| Row | Host | Command | What a pass proves |
|---|---|---|---|
| `host-widget-boot` | Flutter host | `./tool/flutterw test --no-pub test/release/boot_smoke_test.dart` | The real app shell boots with isolated synthetic SQLite storage, Today renders and primary navigation works. |
| `linux-native-boot` | Linux desktop | `python3 tool/release/run_linux_boot.py` | A native graphical app boots using a unique real Secret Service key, reopens encrypted synthetic records, checks Settings/data routes, generates an export preview and an embedded-font report, creates/validates a backup and rechecks bootstrap with staging present. Successful runs remove only their own temporary records and key. |
| `linux-packaged-bundle` | Linux bundle | `./tool/package_linux.sh` then `output/linux/true-grit-vital/launch` | The packaged bundle starts with the recorded native libraries and notices. Lead/owner action. |
| `android-emulator-boot` | Disposable emulator | `./tool/flutterw devices` then `./tool/flutterw run -d <id>` | The Android shell starts on a synthetic AVD. Does not prove physical delivery, TalkBack or performance. |
| `android-physical-pilot` | Physical Android | G06 device matrix | Real accessibility, notification, reboot/force-stop/OEM, lifecycle and measured performance. Owner/lead only. |
| `chrome-web-boot` | Chrome/web | Not adopted | Nothing. Web remains unsupported. |

## Boundaries

- No physical Android device is connected in this environment.
- Host widget boot does not replace Linux native launch, Android device evidence,
  TalkBack, measured frame/memory budgets or store submission.
- A green row is not a release authorisation: G01–G08 and owner-supplied signing
  remain separate gates in `tool/release/readiness.py`.
- Only synthetic datasets may be used. Never point the matrix at real records.
