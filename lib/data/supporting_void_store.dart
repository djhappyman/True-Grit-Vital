part of 'record_store.dart';

/// Recovery schema 21. It only widens the closed draft-kind CHECK and adds the
/// lookup index used by a fixed-person supporting detail page. Earlier
/// migrations stay untouched; schema 20 runs before this recovery migration.
const supportingVoidDraftSchemaV21 =
    "CREATE TABLE ordinary_draft(id TEXT PRIMARY KEY,generation TEXT NOT NULL,operation TEXT NOT NULL UNIQUE,kind TEXT NOT NULL CHECK(kind IN ('item','dose','correction','profile','dailyPlan','pausePlan','phasePlan','itemType','stockContainer','stockAdjustment','productLabel','combinedDose','combinedCorrection','siteEdit','event','usePeriod','eventReview','attachmentRename','labPanel','supportingObservation','supportingVoid')),person TEXT REFERENCES person(id),person_revision INTEGER,target TEXT,target_revision INTEGER,snapshot TEXT NOT NULL) STRICT";

/// Rebuilds the draft table in place so every old row, operation and foreign
/// key survives with foreign keys enabled. A damaged database that already
/// contains the intermediate name aborts before any DDL.
Future<void> _migrateSupportingVoidV21(_Database db) async {
  final collision = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE name='ordinary_draft_v20'",
      )
      .get();
  if (collision.isNotEmpty) {
    throw StateError('supporting_void_migration_collision');
  }
  final before =
      (await db
              .customSelect('SELECT COUNT(*) AS count FROM ordinary_draft')
              .get())
          .single
          .read<int>('count');
  await db.customStatement(
    'ALTER TABLE ordinary_draft RENAME TO ordinary_draft_v20',
  );
  await db.customStatement(supportingVoidDraftSchemaV21);
  await db.customStatement(
    'INSERT INTO ordinary_draft SELECT * FROM ordinary_draft_v20',
  );
  final copied =
      (await db
              .customSelect('SELECT COUNT(*) AS count FROM ordinary_draft')
              .get())
          .single
          .read<int>('count');
  if (copied != before) {
    throw StateError('supporting_void_migration_rows');
  }
  await db.customStatement('DROP TABLE ordinary_draft_v20');
  await db.customStatement(
    "CREATE INDEX ordinary_draft_supporting_void ON ordinary_draft(person,target) WHERE kind='supportingVoid'",
  );
  if ((await db.customSelect('PRAGMA foreign_key_check').get()).isNotEmpty) {
    throw StateError('supporting_void_migration_integrity');
  }
}

/// Reconstructs the one confirmed command from its closed draft snapshot.
/// The intended state comes from the saved intent, never from the live record.
VoidSupportingRecordCommand _supportingVoidCommand(OrdinaryDraft draft) {
  if (draft.kind != DraftKind.supportingVoid ||
      draft.personId == null ||
      draft.personRevision == null ||
      draft.targetId == null ||
      draft.targetRevision == null ||
      draft.fields.length != 1 ||
      (draft.fields['isVoided'] != 'true' &&
          draft.fields['isVoided'] != 'false')) {
    throw const CommandConflict('draft_identity');
  }
  return VoidSupportingRecordCommand(
    commandId: draft.operationId,
    generation: draft.generation,
    personId: draft.personId!,
    id: draft.targetId!,
    expectedPersonRevision: draft.personRevision!,
    expectedRevision: draft.targetRevision!,
    isVoided: draft.fields['isVoided'] == 'true',
  );
}

extension SupportingVoidRecovery on RecordStore {
  /// Resumes one durably saved void or restore intent.
  ///
  /// `_command` resolves the exact operation receipt before its body validates
  /// the captured revision, so a committed request whose reply was lost is
  /// replayed once instead of being reported as stale. A changed owner, record
  /// or dataset generation throws without writing, leaving the intent for an
  /// explicit retry or discard.
  Future<SupportingRevision> resumeSupportingVoidDraft(
    OrdinaryDraft draft,
  ) async {
    final command = _supportingVoidCommand(draft);
    _requireWritable();
    if (draft.generation != generation) {
      throw const CommandConflict('generation');
    }
    return voidSupportingRecord(command);
  }
}
