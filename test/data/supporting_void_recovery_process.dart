// Separate-process fixture. Synthetic key, person and supporting record only.
//
// The script proves that a confirmed void intent survives a process death
// before execution, then a second death after the durable commit but before any
// acknowledgement. Reopening resolves the operation receipt instead of
// reporting the captured revision as stale.
import 'dart:io';

import 'package:true_grit_vital/data/record_store.dart';

const operation = 'process-void';

Future<void> main(List<String> args) async {
  final directory = args[0];
  final mode = args[1];
  final store = await RecordStore.open(
    path: '$directory/records.db',
    key: List.generate(32, (i) => i + 1),
    isNew: mode == 'init',
  );
  OrdinaryDraft intent() => OrdinaryDraft.supportingVoid(
    id: operation,
    operationId: operation,
    generation: store.generation,
    personId: meId,
    personRevision: 1,
    recordId: 'report',
    recordRevision: 1,
    isVoided: true,
  );
  if (mode == 'init') {
    await store.saveLabPanel(
      SaveLabPanelCommand(
        commandId: 'process-seed',
        generation: store.generation,
        expectedPersonRevision: 1,
        panel: LabPanelSnapshot(
          id: SupportingRecordId(id: 'report', personId: meId),
          title: 'Synthetic process report',
          collectionDate: SupportingDate.day(CivilDate(2026, 10, 19)),
          reportDate: SupportingDate.day(CivilDate(2026, 10, 20)),
          provenance: SupportingProvenance(
            mode: SupportingProvenanceMode.manualTranscription,
            laboratoryId: 'process-lab',
            laboratoryName: 'Synthetic laboratory',
            methodId: 'process-method',
            specimenId: 'process-specimen',
          ),
          results: [
            LabResultSnapshot(
              id: 'process-result',
              metricId: 'process-metric',
              markerName: 'Synthetic marker',
              value: SupportingValue.numeric('1'),
              unit: 'mg/L',
            ),
          ],
        ),
      ),
    );
    await store.saveDraft(intent());
    // Process death after the durable intent, before the domain command.
    exit(0);
  } else if (mode == 'verify-pending') {
    final draft = (await store.drafts()).single;
    final record = (await store.supportingRecord(meId, 'report'))!;
    if (draft.operationId != operation ||
        draft.kind != DraftKind.supportingVoid ||
        draft.targetId != 'report' ||
        draft.targetRevision != 1 ||
        record.revision != 1 ||
        record.isVoided) {
      throw StateError('pending_intent_lost');
    }
    await store.close();
    exit(0);
  } else if (mode == 'resume') {
    final draft = (await store.drafts()).single;
    await store.resumeSupportingVoidDraft(draft);
    // Process death after the durable commit and its atomic draft removal.
    exit(81);
  } else if (mode == 'verify-committed') {
    final record = (await store.supportingRecord(meId, 'report'))!;
    if ((await store.drafts()).isNotEmpty ||
        !await store.operationCommitted(operation) ||
        record.revision != 2 ||
        !record.isVoided ||
        (await store.supportingRevisions(meId, 'report')).length != 2) {
      throw StateError('void_not_committed_once');
    }
    await store.close();
    exit(0);
  } else if (mode == 'verify-replay') {
    final record = await store.resumeSupportingVoidDraft(intent());
    if (record.revision != 2 ||
        (await store.supportingRevisions(meId, 'report')).length != 2) {
      throw StateError('replay_created_another_revision');
    }
    await store.close();
    exit(0);
  } else {
    throw StateError('unknown_mode');
  }
}
