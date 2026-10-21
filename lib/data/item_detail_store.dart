part of 'record_store.dart';

/// Schema 22 adds user-authored substance details and the durable progress
/// marker for the optional steps after identity creation. The draft table is
/// rebuilt only to widen its closed kind CHECK for the details form.
const itemDetailSchemaV22 = [
  '''CREATE TABLE item_detail(item TEXT PRIMARY KEY,person TEXT NOT NULL,instructions TEXT NOT NULL DEFAULT '',notes TEXT NOT NULL DEFAULT '',revision INTEGER NOT NULL DEFAULT 1 CHECK(revision>0),updated_at INTEGER NOT NULL,FOREIGN KEY(item,person) REFERENCES item(id,person) ON DELETE CASCADE) STRICT''',
  '''CREATE TABLE item_setup(item TEXT PRIMARY KEY,person TEXT NOT NULL,generation TEXT NOT NULL,schedule_skipped INTEGER NOT NULL DEFAULT 0 CHECK(schedule_skipped IN (0,1)),stock_skipped INTEGER NOT NULL DEFAULT 0 CHECK(stock_skipped IN (0,1)),details_skipped INTEGER NOT NULL DEFAULT 0 CHECK(details_skipped IN (0,1)),created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL,completed_at INTEGER,FOREIGN KEY(item,person) REFERENCES item(id,person) ON DELETE CASCADE) STRICT''',
  'CREATE INDEX item_setup_generation ON item_setup(generation,item)',
];

const itemDetailDraftSchemaV22 =
    "CREATE TABLE ordinary_draft(id TEXT PRIMARY KEY,generation TEXT NOT NULL,operation TEXT NOT NULL UNIQUE,kind TEXT NOT NULL CHECK(kind IN ('item','dose','correction','profile','dailyPlan','pausePlan','phasePlan','itemType','stockContainer','stockAdjustment','productLabel','combinedDose','combinedCorrection','siteEdit','event','usePeriod','eventReview','attachmentRename','labPanel','supportingObservation','supportingVoid','itemDetails')),person TEXT REFERENCES person(id),person_revision INTEGER,target TEXT,target_revision INTEGER,snapshot TEXT NOT NULL) STRICT";

/// Applies the additive schema and the one bounded draft-kind widening.
Future<void> _migrateItemDetailV22(_Database db) async {
  final collision = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE name='ordinary_draft_v21'",
      )
      .get();
  if (collision.isNotEmpty) {
    throw StateError('item_detail_migration_collision');
  }
  for (final sql in itemDetailSchemaV22) {
    await db.customStatement(sql);
  }
  final before =
      (await db
              .customSelect('SELECT COUNT(*) AS count FROM ordinary_draft')
              .get())
          .single
          .read<int>('count');
  await db.customStatement(
    'ALTER TABLE ordinary_draft RENAME TO ordinary_draft_v21',
  );
  await db.customStatement(itemDetailDraftSchemaV22);
  await db.customStatement(
    'INSERT INTO ordinary_draft SELECT * FROM ordinary_draft_v21',
  );
  final copied =
      (await db
              .customSelect('SELECT COUNT(*) AS count FROM ordinary_draft')
              .get())
          .single
          .read<int>('count');
  if (copied != before) {
    throw StateError('item_detail_migration_rows');
  }
  await db.customStatement('DROP TABLE ordinary_draft_v21');
  await db.customStatement(
    "CREATE INDEX ordinary_draft_supporting_void ON ordinary_draft(person,target) WHERE kind='supportingVoid'",
  );
  if ((await db.customSelect('PRAGMA foreign_key_check').get()).isNotEmpty) {
    throw StateError('item_detail_migration_integrity');
  }
}

SubstanceDetail _itemDetail(Map<String, Object?> row) => SubstanceDetail(
  itemId: row['item'] as String,
  personId: row['person'] as String,
  instructions: row['instructions'] as String,
  notes: row['notes'] as String,
  revision: row['revision'] as int,
  updatedAt: DateTime.fromMicrosecondsSinceEpoch(
    row['updated_at'] as int,
    isUtc: true,
  ),
);

ItemSetupState _itemSetup(Map<String, Object?> row) => ItemSetupState(
  itemId: row['item'] as String,
  personId: row['person'] as String,
  generation: row['generation'] as String,
  scheduleSkipped: row['schedule_skipped'] == 1,
  stockSkipped: row['stock_skipped'] == 1,
  detailsSkipped: row['details_skipped'] == 1,
  completedAt: row['completed_at'] == null
      ? null
      : DateTime.fromMicrosecondsSinceEpoch(
          row['completed_at'] as int,
          isUtc: true,
        ),
);

extension ItemDetailRecords on RecordStore {
  /// Resolves a committed identity command's item ID when the reply was lost
  /// or the form is retrying an already committed save.
  Future<String?> itemIdForOperation(String commandId) async {
    final rows = await _rows('SELECT result FROM operation WHERE id=?', [
      commandId,
    ]);
    if (rows.isEmpty) return null;
    final result = jsonDecode(rows.single['result'] as String);
    if (result is! Map || result['invalidated'] == true) return null;
    return result['id'] as String?;
  }

  Future<SubstanceDetail?> itemDetail(String itemId, {String? personId}) async {
    final rows = await _rows(
      'SELECT * FROM item_detail WHERE item=?${personId == null ? '' : ' AND person=?'}',
      [itemId, ?personId],
    );
    return rows.isEmpty ? null : _itemDetail(rows.single);
  }

  Stream<SubstanceDetail?> watchItemDetail(String itemId) =>
      _watch(() => itemDetail(itemId));

  /// Saves the exact text entered. A null [expectedRevision] creates the row;
  /// any existing row is a stale write rather than an implicit overwrite.
  Future<SubstanceDetail> saveItemDetail({
    required String commandId,
    String? expectedGeneration,
    required String itemId,
    required String instructions,
    required String notes,
    required int? expectedRevision,
    String personId = meId,
    int? expectedPersonRevision,
  }) async {
    if (expectedGeneration != null && expectedGeneration != generation) {
      throw const CommandConflict('generation');
    }
    if (instructions.length > 8000 || notes.length > 8000) {
      throw const FormatException('item_detail_fields');
    }
    final r = await _command(
      commandId,
      [
        'item_detail',
        personId,
        itemId,
        instructions,
        notes,
        ?expectedRevision,
        ?expectedPersonRevision,
      ],
      () async {
        await _activeOwner(personId, expectedPersonRevision ?? 1);
        final item = await _rows(
          'SELECT id FROM item WHERE id=? AND person=?',
          [itemId, personId],
        );
        if (item.isEmpty) throw const CommandConflict('item');
        final current = await _rows(
          'SELECT revision FROM item_detail WHERE item=? AND person=?',
          [itemId, personId],
        );
        final currentRevision = current.isEmpty
            ? null
            : current.single['revision'] as int;
        if (expectedRevision == null) {
          if (currentRevision != null) {
            throw const CommandConflict('revision');
          }
        } else if (currentRevision != expectedRevision) {
          throw const CommandConflict('revision');
        }
        final revision = (currentRevision ?? 0) + 1;
        final updatedAt = DateTime.now().toUtc().microsecondsSinceEpoch;
        if (currentRevision == null) {
          await _db.customStatement(
            'INSERT INTO item_detail(item,person,instructions,notes,revision,updated_at) VALUES (?,?,?,?,?,?)',
            [itemId, personId, instructions, notes, revision, updatedAt],
          );
        } else {
          await _db.customStatement(
            'UPDATE item_detail SET instructions=?,notes=?,revision=?,updated_at=? WHERE item=? AND person=?',
            [instructions, notes, revision, updatedAt, itemId, personId],
          );
        }
        return {
          'item': itemId,
          'person': personId,
          'instructions': instructions,
          'notes': notes,
          'revision': revision,
          'updated_at': updatedAt,
        };
      },
    );
    return _itemDetail(r);
  }

  Future<ItemSetupState?> itemSetup(String itemId, {String? personId}) async {
    final rows = await _rows(
      'SELECT * FROM item_setup WHERE item=?${personId == null ? '' : ' AND person=?'}',
      [itemId, ?personId],
    );
    if (rows.isEmpty || rows.single['generation'] != generation) return null;
    return _itemSetup(rows.single);
  }

  Stream<ItemSetupState?> watchItemSetup(String itemId) =>
      _watch(() => itemSetup(itemId));

  /// Records an explicit skip or completion without creating a plan, stock
  /// container or other clinical record. Skipped steps stay skipped unless the
  /// caller completes setup; a saved real record is read separately.
  Future<ItemSetupState> updateItemSetup({
    required String commandId,
    String? expectedGeneration,
    required String itemId,
    String personId = meId,
    int? expectedPersonRevision,
    bool skipSchedule = false,
    bool skipStock = false,
    bool skipDetails = false,
    bool complete = false,
  }) async {
    if (expectedGeneration != null && expectedGeneration != generation) {
      throw const CommandConflict('generation');
    }
    final r = await _command(
      commandId,
      [
        'item_setup',
        personId,
        itemId,
        skipSchedule,
        skipStock,
        skipDetails,
        complete,
        ?expectedPersonRevision,
      ],
      () async {
        await _activeOwner(personId, expectedPersonRevision ?? 1);
        final item = await _rows(
          'SELECT id FROM item WHERE id=? AND person=?',
          [itemId, personId],
        );
        if (item.isEmpty) throw const CommandConflict('item');
        final current = await _rows(
          'SELECT * FROM item_setup WHERE item=? AND person=?',
          [itemId, personId],
        );
        final existing =
            current.isEmpty || current.single['generation'] != generation
            ? null
            : current.single;
        final now = DateTime.now().toUtc().microsecondsSinceEpoch;
        final schedule = skipSchedule || existing?['schedule_skipped'] == 1;
        final stock = skipStock || existing?['stock_skipped'] == 1;
        final details = skipDetails || existing?['details_skipped'] == 1;
        final completedAt = complete ? now : existing?['completed_at'] as int?;
        final createdAt = existing?['created_at'] as int? ?? now;
        await _db.customStatement(
          'INSERT INTO item_setup(item,person,generation,schedule_skipped,stock_skipped,details_skipped,created_at,updated_at,completed_at) VALUES (?,?,?,?,?,?,?,?,?) ON CONFLICT(item) DO UPDATE SET generation=excluded.generation,schedule_skipped=excluded.schedule_skipped,stock_skipped=excluded.stock_skipped,details_skipped=excluded.details_skipped,updated_at=excluded.updated_at,completed_at=excluded.completed_at',
          [
            itemId,
            personId,
            generation,
            schedule ? 1 : 0,
            stock ? 1 : 0,
            details ? 1 : 0,
            createdAt,
            now,
            completedAt,
          ],
        );
        return {
          'item': itemId,
          'person': personId,
          'generation': generation,
          'schedule_skipped': schedule ? 1 : 0,
          'stock_skipped': stock ? 1 : 0,
          'details_skipped': details ? 1 : 0,
          'created_at': createdAt,
          'updated_at': now,
          'completed_at': completedAt,
        };
      },
    );
    return _itemSetup(r);
  }

  /// Bounded lookup used by reports and structured exports. Missing metadata is
  /// simply absent; an empty row is not treated as authored content.
  Future<Map<String, SubstanceDetail>> _itemDetailsFor(
    Iterable<String> itemIds,
    String personId,
  ) async {
    final ids = itemIds.toSet().toList();
    final result = <String, SubstanceDetail>{};
    for (var offset = 0; offset < ids.length; offset += 200) {
      final chunk = ids.skip(offset).take(200).toList();
      if (chunk.isEmpty) break;
      final marks = List.filled(chunk.length, '?').join(',');
      final rows = await _rows(
        'SELECT * FROM item_detail WHERE person=? AND item IN ($marks)',
        [personId, ...chunk],
      );
      for (final row in rows) {
        final detail = _itemDetail(row);
        if (!detail.isEmpty) result[detail.itemId] = detail;
      }
    }
    return result;
  }
}
