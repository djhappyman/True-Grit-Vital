# Whole collection overview

D16 replaces loaded-page totals on Events with whole-collection status counts
and filters the saved collection before slicing one deterministic 50-event page.
Counts, cards and paging share one captured instant, so a boundary status cannot
disagree with the card or the chip that led to it. The existing status rules are
unchanged: a completed event wins, a future resolved start is upcoming, a missing
elapsed value needs date review, and everything else is active. Saved zones,
date precision, actual/planned boundaries, membership and combined selection
are untouched.

`All` stays a plain reset target; the status chips carry whole-collection counts.
Changing status resets the page, a filtered page reports its range, and
Previous/Next use the page actually shown. A stale offset clamps against the
filtered total rather than the whole collection, so unrelated statuses cannot
leave the chosen filter beyond its last page. An empty filtered page keeps the
status row, the selected zero state and the Clear recovery action.

Live saves and completions refresh the counts and page through the existing store
watch. Loading, failures, stale offsets and the app lock never present the prior
page as current. Watches stop publishing while writes are suspended, and the
collection read re-checks the lock and dataset generation before returning.

Lead review fixed the stale-page clamp reading the all-status total and added the
regression where 60 completed events keep the all count high while only three
active events must clamp to the first filtered page. The same review added the
store lock/generation checks, the watch publishing guard and the single captured
instant used by counts and cards.

Verification: all 46 focused Events, timing and summary checks passed, including
six new collection-store checks and four new Events UI checks. Project analysis
was clean. Captures ran through the actual Events route with synthetic data and
real fonts at a 390 px viewport and 320 px with double text.

- [Light overview](light-events-overview.png)
- [Dark overview](dark-events-overview.png)
- [Dark overview, 320 px and double text](dark-events-overview-narrow-double-text.png)
- [Light, empty status filter](light-events-review-empty.png)
- [Dark, empty status filter](dark-events-review-empty.png)
- [Dark empty status filter, 320 px and double text](dark-events-review-empty-narrow-double-text.png)

The narrow captures show the scroll viewport shared with the fixed dock; the
status row and Clear action remain reachable there. Physical screen-reader,
device and performance acceptance remain open. This slice adds no clinical
inference, adherence percentage, planned-total inference or new status meaning.
