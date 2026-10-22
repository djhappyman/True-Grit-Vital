# Substance properties

Owner approved 22 October 2026. These capabilities precede further feature work.

## User flow

Create keeps the existing name/category/catalogue controls. Taken as reveals
Injectable (oil-based, water-based, powder to mix, other), Oral (tablet, capsule,
liquid, powder, other), or Other with original labelled wording. Category,
route and formulation are separate facts. Existing unclassified records remain
usable; the app never classifies them by name. Original catalogue wording is
retained separately from these personal choices.

A known liquid strength is entered per ml; tablet/capsule strength is entered per
item. Both accept mg or micrograms explicitly. Blank means unknown. A name such
as Test 400 is never parsed into a strength or ingredient composition.

Powder to mix points to the existing Stock container editor after identity save.
Each vial saves its own original powder amount/unit and **confirmed final total
volume**, plus optional mixing liquid, amount added and preparation date. The
amount added is descriptive and never substituted for final volume. The live
preview derives strength by exact rational division. No mixing liquid,
compatibility, preparation instructions or dose is recommended.

Record shows the selected strength and the live equivalent beside the amount.
Source choice still uses the existing container picker and guard. A tablet or
capsule can convert between count and mg using its entered strength. Liquid
sources convert between mg and ml. Original entered quantities and units remain
separate from equivalents; rounded display values never return to bookkeeping.
Dose entries retain the existing mg/ml/count units; micrograms are accepted for
labelled strength and powder amount and converted exactly to mg internally.

The optional Half-life disclosure stores a positive value in hours/days,
original ingredient/ester/formulation/route context and optional source.
Ready-mixed products use separate half-life controls for each ingredient in the
existing product editor. The app infers nothing from a carrier and does not
calculate estimated levels, treatment schedules or duration of action.

## Storage and history

Record schema 25 adds a nullable profile JSON column to existing substance
details. Profile creation is atomic with substance creation; existing Details
uses its optimistic revision and command guards. Legacy records and drafts do
not acquire invented classifications. An omitted profile in an older details
command preserves the current profile rather than clearing it.

Strength snapshots gain optional exact mg-per-count and original vial
preparation fields. Existing strength JSON remains readable and unchanged when
those fields are absent. Container identity and strength remain immutable: a
new preparation uses a new vial. Stock metadata edits never rewrite strength.
Dose corrections carry the captured strength through the existing revision
engine. Structured dose exports include the captured preparation and exact
mg-per-count where present; these are additive optional provenance fields.
Protected backups retain profiles, preparations and ingredient half-lives, with
bounded validation of structured facts before validation/restore acceptance.

## Presentation

Use the shared controls, disclosures and motion adapters, full safe areas and
one scroll owner. Full editors remain full pages, recording remains the guarded
modal sheet, and optional information stays in disclosures. The existing
interaction blueprint applies, including reduced motion, draft dismissal,
privacy, keyboard and large-text behaviour. Half-life and preparation details
are capabilities, not placeholders for a later calculator.

## Verification

Evidence and remaining limits are recorded in
[the implementation review](reviews/2026-10-22-substance-properties/README.md).
