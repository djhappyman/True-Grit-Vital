# Quick-entry context

Quick entry validates exact civil dates and suggested plan times. Impossible or
duplicate options show a concise recovery; conflicting Create/Plan/Record tasks
require a choice. No malformed day silently normalises to another calendar day.
Absent dates retain the existing default. Valid days/times survive medicine
selection and minimal creation into the canonical record or schedule editor.

Lead review added captured store/lock guards to navigation callbacks and keyed
the dose editor by its whole location. Existing save/draft/lock paths remain.
The recording test explicitly expects the established return to Today after Save.

`test/quick_entry_context_test.dart` and `test/quick_entry_flow_test.dart` cover
leap/impossible/final-year dates, invalid/competing flags, creation/planning,
actual saved use, retained search, duplicate taps, lock and narrow large text.
Five PNGs capture recovery and explicit choices in both themes, including a
narrow 2x-text recovery, with bundled
fonts and synthetic records. Physical-device validation is not claimed.
