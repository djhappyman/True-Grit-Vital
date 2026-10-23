# FHIR export

The paid OpenCode DeepSeek lane stopped at its usage limit. The lead recovered,
reviewed and completed the export, including privacy and exact-value fixes.

The existing Export flow now offers a FHIR R4 4.0.1 collection Bundle. Preview
shows mapping limits and the JSON that explicit Save will write. The same
captured bytes are reused; existing lock, dataset, route, cancellation and
protected-file guards remain active. No automatic transfer is added.

Reported medicine use becomes MedicationStatement, skipped use becomes
not-taken, and voided/superseded revisions become entered-in-error. Patient
identity is local; panels group Observation members and quick observations use
components. Known instants use UTC, uncertain/date-only values remain dates.
Exact decimals are written without a double conversion; non-terminating
quantities remain exact text. Recorded labelled strength is factual text,
never a guessed ingredient. User-authored plan requirements follow the existing
notes choice. No clinical/UCUM codes or unrecorded patient facts are invented.
Files, attachment references, stock and several local-only labels are omitted;
the review explains these limits.

## Verification

- Initial combined export/controller/file-handoff/UI and JSON/CSV regressions:
  76 passing checks. Fifteen final FHIR checks cover exact quantities, source
  meaning, date uncertainty, privacy and the root integration changes.
- Six capture checks cover 390/430 and 320px with double text in both themes.
  The fixture seeds persisted appearance before launch and asserts actual
  rendered brightness; the lead visually inspected dark and white light views.
- The synthetic `fhir-r4-sample.json` was checked by official HL7 validator CLI
  7.0.3 against `hl7.fhir.r4.core#4.0.1`, with `-tx n/a`. `validation.json`
  contains **zero errors/fatal issues and 11 warnings**: ten missing narrative
  best-practice warnings and one uncoded source interpretation warning.
  `validator.log` records the integrated root run.

Terminology lookup was disabled. No national profile, EHR import contract or
clinical certification is claimed. Other healthcare systems may need their
own agreed mapping. Detailed logs remain in the local batch tracker.
