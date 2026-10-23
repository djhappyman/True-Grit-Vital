# Canonical picker provenance

Owner-directed adaptation from True Grit Workout Tracker, 23 October 2026. Source checkout HEAD: `726e69526c63ce022c6055668182eda548e20bc3`. The hashes below identify the actual source bytes read, including any local source changes. The sibling checkout was read only.

| Source | SHA-256 | Vital adaptation |
| --- | --- | --- |
| `lib/shared/widgets/date_pickers/app_date_picker.dart` | `1f2363a30f847a9844a177f16e99363444b664638eafebd52201f32bb99689f2` | `lib/ui/pickers/vital_date_picker.dart` |
| `lib/shared/widgets/date_pickers/app_date_picker_math.dart` | `aeaab1dfa27cad5c43e3cc5491250d2dcd1e31221848ae245e49b39de6ecfb62` | `lib/ui/pickers/vital_date_picker_math.dart` |
| `lib/shared/widgets/date_pickers/app_date_picker_models.dart` | `0ad477593bdb96620b146158f49e62eb0422da34d803e66c14a0e8b5eeb091f9` | `lib/ui/pickers/vital_date_picker_models.dart` |
| `lib/shared/widgets/date_pickers/app_date_picker_navigation_views.dart` | `fd4b58eacf863081830197d9e2f59c4338ff9db739e3309916f8bd500c837b6c` | `lib/ui/pickers/vital_date_picker_navigation_views.dart` |
| `lib/shared/widgets/date_pickers/app_date_picker_selection_summary.dart` | `82ac522fe35dc59f534ffa769cf9727cc0f6c31c2ed5da7e726dfa79b19d70df` | `lib/ui/pickers/vital_date_picker_selection_summary.dart` |
| `lib/shared/widgets/date_pickers/app_time_picker.dart` | `3ba8a6fdd3a79826dbc4fe5592298c20ccd78040819540e6886c04a286e19894` | `lib/ui/pickers/vital_time_picker.dart` |
| `lib/shared/widgets/date_pickers/app_week_picker_math.dart` | `4f6ab432a96afb12807a623d999f58eae500dec32cc79cbb3b11ae35c9166e6d` | `lib/ui/pickers/vital_week_picker_math.dart` |

Repeat composition reference: `lib/features/calendar/widgets/calendar_repeat_editor_sheet.dart`, SHA-256 `419b4e6184d38f3a7f991b1f218b691430917af36ea5ae8e441cbc4cd654eafc`. Vital adapts its dropdown/weekday/stepper/month-rule/end-selection composition through `CalendarEditor`, `CalendarRepeatDetails` and `lib/ui/vital_repeat.dart`, retaining Vital's own calendar, clock, pause and recorded-use semantics. This is not a second copied planner domain.

The date/clock implementation retains single date, month/year granularity, required/optional date-time, range selection, week selection, endpoint editing modes, metadata/selectability hooks, navigation, range summary, clock interaction and geometry. Adaptations replace Workout's Material overlay and interactive controls with shared Vital/shadcn adapters, centralise palette/typography and reduced motion, localise authored copy and apply lock/dataset invalidation. `picker_adapters.dart` uses Material types/localisation/painter primitives only; surfaces and controls remain Vital-owned.

Range consumers explicitly bridge inclusive selected days to existing exclusive filter bounds using civil-day arithmetic. No timezone or clinical content is inferred from a selected calendar value. See the [blueprint](interaction-blueprint.md#dates-and-repeats) for the mandatory future-screen contract and the [rollout record](interaction-implementation-plan.md#canonical-pickers-and-schedule-23-october) for verification limits.
