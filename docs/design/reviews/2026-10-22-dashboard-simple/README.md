# Today functional baseline

22 October 2026. The owner accepted the functional direction and explicitly
rejected the current visual composition. These captures document the working
baseline, not an approved visual design.

- Left profile control and local-time greeting with the saved name.
- Week browsing retains the selected day; a date tap changes its actual records.
- One daypart timeline, quiet empty groups and the existing planned-dose commands.
- Unplanned medication chooser, minimal creation and guarded dose recording.
- Editable medicine details preserve historical dose snapshots and exact units.
- Observations stays a disabled Coming soon preview by explicit owner choice.

Verification: 62 targeted store/draft/calendar tests and seven current dashboard
flow tests passed. The schedule/dashboard run passed 18 checks, including home
zone fallback, skip/Undo, draft locking and narrow/large-text layouts. Shared
motion, substance-property and setup regressions passed their cases. Project
analysis reported no issues. Native Linux boot, encrypted persistence,
navigation, reports, export and backup passed with real Secret Service storage;
its isolated test data and key were removed. No physical Android performance or
screen-reader acceptance is claimed. No new APK/release was requested.

The light/dark PNGs show empty, populated, unplanned, chooser and dose-sheet
states using real Flutter widgets and synthetic records. The saved design
references remain authoritative; a further visual pass is required.

Skills read: flutter-expert, codebase-memory, vital-mobile-copy, better-writing,
interaction-design, responsive layout, UI/UX guidance, Dart/Flutter testing,
static analysis and verification-before-completion. Flutter PageView and app
lifecycle APIs were checked against official documentation and the pinned SDK.
