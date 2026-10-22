# Selected week

D19a reuses the canonical History calendar and day selection. The locale week
follows the selected date, with indexed counts across all seven days rather
than the loaded 25-record page. Existing substance, type, event and status
filters flow into the same aggregate; only selected statuses are displayed or
announced. The date range, mixed-status markers and day targets remain explicit.
Locked, loading and failed reads never imply empty or successful counts.

Lead review fixed retained AsyncValue data being presented as current during a
refresh or after a failed refresh. The focused regression fails without the fix
and passes with it. Its selected-day fixture now uses a fixed Wednesday, avoiding
Monday/midnight-dependent totals. The existing date-boundary, full indexed count,
status semantics, retry, lock, narrow layout and calendar navigation checks pass.
The selected-day heading now stacks its Today action at narrow widths or large
text sizes, preserving whole date words. The updated narrow capture and focused
layout assertion cover this arrangement.

Verification: 39 focused history/calendar/motion checks passed, followed by the
11-test weekly-summary run after stabilising its date fixture. Counts overlap.
Project analysis was clean. The worker loaded Flutter expert (state/widgets)
and both copy skills from the shared OpenCode catalogue. Lead review applied the
repository copy skill, architecture, unit/widget testing, responsive/UI guidance,
codebase-memory and verification skills, the interaction blueprint and History
rollout row. Graph coverage was checked on the exact source/test evidence paths;
source was read for the bounded feature and private-edge gaps.

- [Light](light-history-week.png)
- [Dark](dark-history-week.png)
- [Dark, 320 px and double text](dark-history-week-narrow-double-text.png)

Captures use synthetic data in the actual History route, fixed dock and device
safe insets. D11 timing rules remain open: no planned/unrecorded totals,
on-time/late classification, adherence percentage or treatment inference is
introduced. Physical screen-reader and performance acceptance remain open.
