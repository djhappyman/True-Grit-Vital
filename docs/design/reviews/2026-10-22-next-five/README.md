# Five roadmap features

Integrated on 22 October 2026 from baseline `bbf7360`:

- [History](history/README.md): exact selected-week totals with calendar selection,
  status filters and honest pending/error states.
- [Schedule instructions](plan-instructions/README.md): exact authored text through
  immutable versions, drafts, pause/restart, phases and shared summaries.
- [Reminder alerts](alerts/README.md): saved sound/vibration choices, real Android
  channels, OS-mute protection and separate saved/applied states.
- [Stock reports](report-stock/README.md): default-off chosen-container details in
  all three PDF/text reports, with exact quantities and capture-time meaning.
- [Backup history](backup-history/README.md): bounded encrypted receipts separating
  archive validation from confirmed saves, with restored-generation fencing.

One free DeepSeek Flash worker implemented History. Three paid workers used
OpenCode's direct DeepSeek API model `deepseek/deepseek-flash` (V4.1 Flash 1017).
The lead implemented backup history and reviewed/fixed all integrations. No rate
limit takeover was needed. Root task/delegation evidence is retained locally in
`.scratch/vital-implementation/next-five-2026-10-22/`.

Final host verification passed 113 combined feature/framework/motion checks and
clean whole-project analysis. The earlier scoped runs are documented per feature;
their counts overlap. All 37 native reminder engine checks passed, and the actual
Android `:app:compileDebugKotlin` completed successfully. The reported summary
fixture hang was fixed; all 14 summary checks then passed. Light/dark and narrow,
large-text captures are committed beside each review.

The [native Linux result](native-boot.json) confirms a real Secret Service boot,
encrypted persistence, navigation, export and protected-backup flow. The Linux
debug bundle built successfully. The isolated test key and temporary dataset were
removed successfully. No dependencies, SDK pins or SQL schema versions changed.

This is host evidence. Physical-device alert output, screen readers, measured
performance/glass and production signing retain their existing gates. Timing
tolerances, reminder follow-up timing and automatic backup lifecycle remain open.
Plan instructions stay out of report/export and notification outputs; adding
them to optional private-note outputs requires its own mapping work.
