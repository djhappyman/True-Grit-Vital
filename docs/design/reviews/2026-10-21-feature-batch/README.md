# Feature batch review

Three roadmap features: D06 weekly browsing/favourites and D07 status filtering by DeepSeek; D09 exact dose presets by the lead. All use existing shared components and canonical routes.

## Dose presets

- [Light](light-dose-presets.png), [dark](dark-dose-presets.png), [narrow light](light-dose-presets-narrow-2x.png) and [narrow dark](dark-dose-presets-narrow-2x.png) use synthetic saved amounts. Narrow captures are 320 px with double text and show intentional stacking/scrolling.
- Latest saved schedule amounts and up to eight explicitly saved quantities fill the existing form with exact units. Manual entry, strength/stock previews and final Save stay connected. Choosing or configuring an amount does not record a dose.
- Preferences are stored inside the encrypted database and retained in its backup snapshot. Failed writes preserve the previous values; lock cycles and dataset replacement retire delayed writes. Unsupported cross-unit amounts remain unavailable until a compatible source or explicit labelled strength is chosen.
- Focused unit, interaction and existing recording checks passed: 18 tests. A subsequent capture/layout check passed in both themes at 320/390/430 px with double text; semantics preserve one labelled selected control. Whole-project analysis is clean. An additional 31 stock, product, combined-use and private-draft regression checks passed. Final combined-batch verification follows the two remaining integrations.
- Physical-device accessibility and measured performance remain open.
