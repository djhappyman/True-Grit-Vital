# Stitch screen rebuild

Native Flutter captures of Dashboard and Substances, rebuilt directly against the [20 October Stitch batch](../../stitch/2026-10-20/README.md). Dashboard follows `dashboard-timeline-velocity-dark-mode--42445af1`; Substances follows `substances-dark-mode--1ecd8e65`. Saved light variants supply the white-theme treatment. The four original font weights are bundled unchanged; see [font provenance](../../../../assets/fonts/STITCH.md).

The fixture contains synthetic records only. Captures use real app fonts, loaded SQLite data and 390 px width with 28 px top / 24 px bottom safe areas. Full images expand the capture viewport to show the entire composition; the actual app keeps its navigation dock fixed.

| Screen | Light viewport | Dark viewport | Full composition |
| --- | --- | --- | --- |
| Dashboard | [Light](light-today.png) | [Dark](dark-today.png) | [Light](light-today-full.png) · [Dark](dark-today-full.png) |
| Substances | [Light](light-substances.png) | [Dark](dark-substances.png) | [Light](light-substances-full.png) · [Dark](dark-substances-full.png) |

Taken, Skip, Undo, eligible snooze, PRN recording, search/type filters, paging and overview navigation use existing app commands. The activity icon opens dose Details, including Source, Extra and editing. Manage retains stock notices and schedule controls; Recorded expands the real history list. Stock and supporting-record buttons open their existing pages. Weekly browsing and shortcut configuration explain that they are unavailable. The pressure chart is labelled Design preview; stock quantities are real balances, with no invented days-of-stock forecast.

Regenerate with:

```sh
./tool/flutterw test --no-pub test/stitch_reference_screens_test.dart \
  --dart-define=VITAL_STITCH_CAPTURES=output/stitch-review
```

The four screen checks passed, including exact Taken/Undo record identity, no placeholder writes, 320 px width and double text. Static analysis, the Linux debug build and native Linux boot/report/backup check passed. Physical-device accessibility, performance and glass gates remain open.

The full regression run recorded 1,753 passes and one skip, with one profile-fixture race. The fixture now waits for the saved profile revision before opening its form; that case passed on rerun, and the complete 15-test supporting-record file also passed. No production record or profile guards were relaxed.
