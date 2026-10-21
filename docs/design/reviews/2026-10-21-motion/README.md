# Interaction rollout review

The [blueprint](../../interaction-blueprint.md) defines the current and future-screen standard. The [rollout matrix](../../interaction-implementation-plan.md) records each canonical screen presentation. This batch builds on the separately pushed D06/D07/D09 feature checkpoint `760eb4e`.

- Shared timings/curves now drive route, sheet, dialog, press, bounds, progress and theme motion. Native shadcn controls remain the primary controls. System/app reduced motion removes decorative travel; unmeasured glass stays disabled.
- Root destinations, substance sections and Settings sections use retained PageViews. History months and Today weeks page real queries. Hidden pages exclude focus/semantics and suspend tickers. Tab strips remain on one row with a scrolling large-text fallback.
- Recording/correction/combined, stock adjustment and pause routes use guarded modal tasks. Optional content is disclosed, dose actions stay above the keyboard, and existing exact-value, stock, revision, draft and idempotency logic remains connected. Short decisions use dialogs; filters use live anchored options or an adaptive sheet; secondary commands use shadcn menus.
- Rapid dock changes exposed a stale animation callback overriding the final destination. The shared pager now fences callbacks immediately and stops an old activity even when already at the requested pixel. The regression test passes.
- Unsupported dashboard/recording/Settings advertisements were removed. Provenance and saved sources remain reachable under Source details; exact results/ranges/flags stay visible.

## Captures

Synthetic data, actual bundled fonts, 390 × 844 px with device safe areas. Light canvas is white; dark uses the established green-black/mint palette.

| Screen | Light | Dark |
| --- | --- | --- |
| Today | [Image](light-today.png) | [Image](dark-today.png) |
| History | [Image](light-history.png) | [Image](dark-history.png) |
| Dose sheet | [Image](light-record.png) | [Image](dark-record.png) |
| Combined sheet | [Image](light-combined.png) | [Image](dark-combined.png) |
| Substance sections | [Image](light-substance-overview.png) | [Image](dark-substance-overview.png) |
| Settings sections | [Image](light-settings.png) | [Image](dark-settings.png) |

The saved-amount editor has additional [light](light-dose-presets.png) and [dark](dark-dose-presets.png) views, plus 320 px double-text captures: [light](light-dose-presets-narrow-2x.png), [dark](dark-dose-presets-narrow-2x.png). Full names/units remain available through deliberate scrolling; sticky dose actions remain at the bottom. The capture test also checks 390/430 px at double text.

## Verification

Whole-project analysis is clean. The 66 updated design/schedule/event checks, seven focused motion checks, light/dark captures and narrow preset captures passed. The final whole-suite run was stopped at the owner’s request to publish immediately; no complete full-suite pass is claimed for this batch. Native Linux boot has passed with real Secret Service, encrypted persistence, navigation, report/export and backup/restore. Android debug APK builds and its package metadata/signature verify. Seven focused motion checks cover retained navigation, rapid interruption, nested month gestures, guarded scrim/handle/Escape/system Back, pending single-dispatch writes, reduced motion and 320 px double-text keyboard clearance.

Physical Android installation, native delivery, assistive-technology acceptance and measured frame timing remain open. No physical Android device is attached. The debug prerelease does not configure production signing or close G01–G08 acceptance gates.

## Published build

[First development prerelease](https://github.com/djhappyman/True-Grit-Vital/releases/tag/v0.1.0-alpha.1), source `c10a62e`. The universal Android debug APK is version 0.1.0+1 (`dev.truegrit.vital`), minimum Android API 24, with arm64-v8a/armeabi-v7a/x86_64 support. Its uploaded size and server SHA-256 digest match the staged, signature-verified build.

SHA-256: `4f69af4fec23a00ecaa2dd35c35d01647f7ffa83c51421a13381504c8fdd0ee8`. The APK and `SHA256SUMS` are attached to the release.
