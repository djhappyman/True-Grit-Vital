# Captured dose strengths

D26b adds the numerical strength saved with each recorded dose to all three
report templates and their text alternatives. Exact mg/ml and mg/item values
produce exact volume/mass/count equivalents. Recurring values stay fractions;
unknown or unresolved replacements never acquire an invented equivalent.

Vial preparation facts are copied from the recorded dose, only when the existing
stock-details option is selected. Later substance defaults and stock metadata
cannot rewrite the captured preparation or an already reviewed report. Raw
container labels are not copied into the new strength projection. The existing
stock source section retains its separate capture-time meaning.

Verification: 38 focused report domain/store/PDF/text checks passed. They cover
all three templates, stock consent on/off, unknown strength, repeating ratios,
count strengths, an unresolved replacement, projection guards and later default
changes. All four rendered pages were visually inspected: readable quantities,
matching text/PDF, repeated identity and no clipping/overlap. R03's closing
scope notice continues on page 2. Current report pagination bounds remain.

Skills: Flutter expert, architecture, Dart unit testing, static analysis,
verification-before-completion, codebase memory, better-writing, repository
vital-mobile-copy and read-only PDF review. No package or schema change.
Physical Android and production release checks remain separate.
