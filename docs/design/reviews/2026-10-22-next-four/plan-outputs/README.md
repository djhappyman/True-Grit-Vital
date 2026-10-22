# Saved plan outputs

Lead implementation of D11b, 22 October 2026.

- Optional report instructions come from the immutable plan audit version
  explicitly referenced by a dose's saved action and frozen occurrence.
  Standalone doses inherit nothing. Changing a dose time or editing a future
  plan cannot replace its original words.
- All three PDF/text templates include the same selected instruction facts.
  Repeated instructions are grouped by item and exact plan version, with the
  contributing dose identities retained. This context does not establish that
  the instruction was followed.
- Structured export schema 3 adds `provenance.planInstruction` for dose
  revisions and `planInstruction` for skip actions. Each carries `planId`,
  `versionId` and exact `text`, or null. CSV appends `plan_id`,
  `plan_version_id` and `plan_instructions`; existing columns retain their
  positions. Formula escaping and existing byte limits apply.
- Private text remains default-off. Report/export capture and domain boundary
  checks enforce the existing notes consent. The report switch now works
  independently of supporting records, because dose/substance instructions do
  not require lab context. Source files keep their separate consent.
- Reports cover instructions linked to recorded doses. Export also covers
  explicit skips. Unrecorded future plans and unrelated current instructions
  are not inferred into either artifact.
- A long-text PDF check exposed a nested context container that could repeat
  pages indefinitely. The shared report context now supplies pageable children
  directly, with spanning text. The original end marker survives in all three
  templates.

## Verification

The focused data/export/report run passed 74 checks. The PDF/text run passed
14 checks, including on/off consent and long multiline instructions in R01,
R02 and R03. Export UI passed 9 checks; the earlier combined controller/motion
run passed its 16 remaining checks (its sole failure was the intentionally
changed export help string, updated and rerun in the 9-check export run).
Two additional app tests verify report consent without lab context, preserved
selection under reduced motion, both themes and 320/390/430 layouts with 2x
text. Analysis passed. Batch integration evidence is recorded separately.

The export privacy fixture now checks the actual projected note and its quoted
JSON value, rather than mistaking the public phrase “Private notes” in schema
documentation for leaked content.

`r01.png`, `r02.png` and `r03.png` show synthetic generated PDF first pages.
The light/dark app captures show the inclusion choice and updated help. Reports
remain white print documents regardless of app theme. Narrow captures show a
scrollable viewport, not a full-page screenshot. No new dialog or route was
introduced. Existing report preview, handoff, cancellation and lock tests
remain applicable. Physical-device and tagged-PDF accessibility are unverified.

## Sources and skills

Read installed `/home/mike/.codex/skills/` files for `flutter-expert`,
`codebase-memory`, `flutter-apply-architecture-best-practices`,
`dart-add-unit-test`, `flutter-add-widget-test`,
`flutter-build-responsive-layout`, `ui-ux-pro-max`,
`dart-run-static-analysis`, `better-writing` and
`verification-before-completion`, plus the repository
`.agents/skills/vital-mobile-copy/SKILL.md`. The expert's state/widget references
and the shared specification, copy contract and interaction documents were
used. Existing Riverpod/shadcn patterns take precedence over generic examples.

Primary references checked: [SQLite JSON functions](https://www.sqlite.org/json1.html)
for exact saved-version lookup and [Drift transactions](https://drift.simonbinder.eu/dart_api/transactions/)
for coherent capture reads. Graph-first discovery and coverage checks reported
no recorded issue for the relied-on existing source paths; private Dart edges
were source-read. New files were read directly while indexing refreshed.
