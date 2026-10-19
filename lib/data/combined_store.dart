part of 'record_store.dart';

const combinedSchemaV14 = [
  '''CREATE TABLE combined_action(id TEXT PRIMARY KEY,person TEXT NOT NULL REFERENCES person(id),actual INTEGER NOT NULL,UNIQUE(id,person)) STRICT''',
  '''CREATE TABLE combined_member(action TEXT NOT NULL,person TEXT NOT NULL,record TEXT NOT NULL UNIQUE,position INTEGER NOT NULL CHECK(position>=0 AND position<16),PRIMARY KEY(action,position),FOREIGN KEY(action,person) REFERENCES combined_action(id,person) ON DELETE CASCADE,FOREIGN KEY(record,person) REFERENCES administration(id,person) ON DELETE CASCADE) STRICT''',
  '''CREATE TABLE combined_audit(action TEXT NOT NULL,person TEXT NOT NULL,sequence INTEGER NOT NULL CHECK(sequence>0),operation TEXT NOT NULL UNIQUE,snapshot TEXT NOT NULL CHECK(json_valid(snapshot)),PRIMARY KEY(action,sequence),FOREIGN KEY(action,person) REFERENCES combined_action(id,person) ON DELETE CASCADE) STRICT''',
  "CREATE TRIGGER combined_member_immutable BEFORE UPDATE ON combined_member BEGIN SELECT RAISE(ABORT,'immutable_combined_member'); END",
  "CREATE TRIGGER combined_audit_immutable BEFORE UPDATE ON combined_audit BEGIN SELECT RAISE(ABORT,'immutable_combined_audit'); END",
  '''CREATE TABLE site_event(record TEXT NOT NULL,person TEXT NOT NULL,sequence INTEGER NOT NULL CHECK(sequence>0),label TEXT CHECK(label IS NULL OR (length(label) BETWEEN 1 AND 500)),record_revision INTEGER NOT NULL,operation TEXT NOT NULL,recorded_at INTEGER NOT NULL,PRIMARY KEY(record,sequence),FOREIGN KEY(record,person) REFERENCES administration(id,person) ON DELETE CASCADE,FOREIGN KEY(record,record_revision) REFERENCES revision(record,revision) ON DELETE CASCADE) STRICT''',
  'CREATE INDEX site_person_history ON site_event(person,recorded_at DESC,record,sequence)',
  "CREATE TRIGGER site_event_immutable BEFORE UPDATE ON site_event BEGIN SELECT RAISE(ABORT,'immutable_site_event'); END",
  'ALTER TABLE ordinary_draft RENAME TO ordinary_draft_v13',
  "CREATE TABLE ordinary_draft(id TEXT PRIMARY KEY,generation TEXT NOT NULL,operation TEXT NOT NULL UNIQUE,kind TEXT NOT NULL CHECK(kind IN ('item','dose','correction','profile','dailyPlan','pausePlan','phasePlan','itemType','stockContainer','stockAdjustment','productLabel','combinedDose','combinedCorrection','siteEdit')),person TEXT REFERENCES person(id),person_revision INTEGER,target TEXT,target_revision INTEGER,snapshot TEXT NOT NULL) STRICT",
  'INSERT INTO ordinary_draft SELECT * FROM ordinary_draft_v13',
  'DROP TABLE ordinary_draft_v13',
];

void _validateSite(String? label) {
  if (label != null && (label.trim().isEmpty || label.length > 500)) {
    throw const FormatException('site_label');
  }
}

extension CombinedRecordStore on RecordStore {
  Future<void> _setSite(
    String operation,
    String person,
    String record,
    String? label,
  ) async {
    _validateSite(label);
    final current = (await _rows(
      'SELECT revision FROM administration WHERE id=? AND person=?',
      [record, person],
    ));
    if (current.isEmpty) throw const CommandConflict('ownership');
    final old = await _rows(
      'SELECT sequence,label FROM site_event WHERE record=? AND person=? ORDER BY sequence DESC LIMIT 1',
      [record, person],
    );
    if (old.isEmpty && label == null ||
        old.isNotEmpty && old.single['label'] == label) {
      return;
    }
    await _db.customStatement('INSERT INTO site_event VALUES (?,?,?,?,?,?,?)', [
      record,
      person,
      old.isEmpty ? 1 : (old.single['sequence'] as int) + 1,
      label,
      current.single['revision'],
      operation,
      DateTime.now().microsecondsSinceEpoch,
    ]);
  }

  /// A site edit is context only: it creates neither a dose revision nor stock.
  Future<void> updateSite({
    required String commandId,
    required String personId,
    required int expectedPersonRevision,
    required String expectedGeneration,
    required String recordId,
    required int expectedRevision,
    required String? siteLabel,
  }) async {
    _stockGeneration(expectedGeneration);
    _validateSite(siteLabel);
    await _command(
      commandId,
      [
        'site_edit',
        personId,
        recordId,
        expectedRevision,
        expectedPersonRevision,
        siteLabel,
      ],
      () async {
        await _activeOwner(personId, expectedPersonRevision);
        final current = await recordById(recordId, personId: personId);
        if (current == null ||
            current.revision != expectedRevision ||
            current.isVoided) {
          throw const CommandConflict('revision');
        }
        await _setSite(commandId, personId, recordId, siteLabel);
        return {'person': personId, 'record': recordId};
      },
    );
  }

  Future<List<String>> siteHistory({
    required String personId,
    int limit = 100,
    int offset = 0,
  }) async {
    _pageBounds(limit, offset);
    return (await _rows(
      'SELECT label,MAX(recorded_at) AS latest FROM site_event WHERE person=? AND label IS NOT NULL GROUP BY label ORDER BY latest DESC,label LIMIT ? OFFSET ?',
      [personId, limit, offset],
    )).map((r) => r['label'] as String).toList();
  }

  Future<CombinedUseResult?> combinedById({
    required String actionId,
    required String personId,
  }) async => _db.transaction(() async {
    final head = await _rows(
      'SELECT id FROM combined_action WHERE id=? AND person=?',
      [actionId, personId],
    );
    if (head.isEmpty) return null;
    return CombinedUseResult(
      actionId: actionId,
      personId: personId,
      records: (await _combinedRows(actionId, personId)).map(_record),
    );
  });
  Future<CombinedUseResult?> combinedForRecord({
    required String recordId,
    required String personId,
  }) async {
    final rows = await _rows(
      'SELECT action FROM combined_member WHERE record=? AND person=?',
      [recordId, personId],
    );
    return rows.isEmpty
        ? null
        : combinedById(
            actionId: rows.single['action'] as String,
            personId: personId,
          );
  }

  Future<List<Map<String, Object?>>> _combinedRows(
    String action,
    String person,
  ) => _rows(
    '${RecordStore._current} JOIN combined_member m ON m.record=a.id AND m.person=a.person WHERE m.action=? AND m.person=? ORDER BY m.position',
    [action, person],
  );
  Future<List<Map<String, Object?>>> combinedHistory({
    required String actionId,
    required String personId,
  }) => _rows(
    'SELECT sequence,operation,snapshot FROM combined_audit WHERE action=? AND person=? ORDER BY sequence',
    [actionId, personId],
  );

  CombinedUseResult _combinedResult(Map<String, Object?> result) =>
      CombinedUseResult(
        actionId: result['action'] as String,
        personId: result['person'] as String,
        alreadyCommitted: result['replay'] == true,
        records: (result['records'] as List).map(
          (r) => _record({
            ...Map<String, Object?>.from(r as Map),
            'replay': result['replay'] == true,
          }),
        ),
      );

  Future<Map<String, Object?>> _auditCombined(
    String action,
    String person,
    String command,
  ) async {
    final rows = await _combinedRows(action, person);
    final seq = (await _rows(
      'SELECT COALESCE(MAX(sequence),0)+1 AS next FROM combined_audit WHERE action=?',
      [action],
    )).single['next'];
    final result = <String, Object?>{
      'action': action,
      'person': person,
      'records': rows,
    };
    await _db.customStatement('INSERT INTO combined_audit VALUES (?,?,?,?,?)', [
      action,
      person,
      seq,
      command,
      jsonEncode(result),
    ]);
    return result;
  }

  Future<CombinedUseResult> recordCombined(
    CombinedUseCommand command, {
    bool failBeforeCommit = false,
    Future<void> Function()? beforeCommit,
  }) async {
    _stockGeneration(command.expectedGeneration);
    final result = await _command(
      command.commandId,
      ['combined_record', command.personId, encodeCombinedUse(command)],
      () async {
        await _activeOwner(command.personId, command.expectedPersonRevision);
        // Capture every caller's original source revision before any component mutates it.
        for (final c in command.components) {
          final item = await itemById(c.itemId, personId: command.personId);
          if (item == null || item.revision != c.expectedItemRevision) {
            throw const CommandConflict('item_revision');
          }
          final cid = c.containerId;
          if (cid != null) {
            final row = await _stockContext(
              command.personId,
              cid,
              (c.stockUse?.expectedContainerRevision ??
                  c.productUse?.expectedContainerRevision)!,
            );
            if (row['item'] != c.itemId) {
              throw const CommandConflict('stock_item');
            }
          }
          if (c.intendedRow case final row?) {
            if (row.expectation.identity.personId != command.personId ||
                row.expectation.itemId != c.itemId ||
                row.expectation.amount.enteredText != c.enteredAmount) {
              throw const CommandConflict('combined_occurrence');
            }
            await _validateDailyRow(row);
          }
        }
        final action = newCommandId();
        await _db.customStatement(
          'INSERT INTO combined_action VALUES (?,?,?)',
          [action, command.personId, command.actualAt.microsecondsSinceEpoch],
        );
        for (var index = 0; index < command.components.length; index++) {
          final c = command.components[index];
          // The original revision was validated above. Subsequent same-container
          // draws use the current transaction checkpoint, so totals accumulate.
          final container = c.containerId == null
              ? null
              : await stockContainerById(
                  personId: command.personId,
                  containerId: c.containerId!,
                );
          final stock = c.stockUse;
          final use = stock == null
              ? null
              : StockUseInput(
                  expectedGeneration: stock.expectedGeneration,
                  entered: stock.entered,
                  containerId: stock.containerId,
                  expectedContainerRevision: container?.revision,
                  replacement: stock.replacement,
                  strength: stock.strength,
                );
          final product = c.productUse;
          final productUse = product == null
              ? null
              : ProductUseInput.fromJson({
                  ...product.toJson(),
                  'containerRevision': container?.revision,
                });
          String record;
          if (c.intendedRow case final row?) {
            final result = await _actDailyInTransaction(
              commandId: '${command.commandId}/$index',
              row: row,
              kind: DailyActionKind.taken,
              actualAt: command.actualAt,
              stockUse: use,
              capturedProductUse: productUse,
              intervalClockSample: c.intervalClockSample,
            );
            record = result['record'] as String;
            await _setSite(
              command.commandId,
              command.personId,
              record,
              c.siteLabel,
            );
          } else {
            final result = await _recordInTransaction(
              commandId: '${command.commandId}/$index',
              personId: command.personId,
              expectedPersonRevision: command.expectedPersonRevision,
              itemId: c.itemId,
              amount: c.enteredAmount,
              actualAt: command.actualAt,
              stockUse: use,
              productUse: productUse,
              siteLabel: c.siteLabel,
            );
            record = result['id'] as String;
          }
          await _db.customStatement(
            'INSERT INTO combined_member VALUES (?,?,?,?)',
            [action, command.personId, record, index],
          );
        }
        return _auditCombined(action, command.personId, command.commandId);
      },
      failBeforeCommit: failBeforeCommit,
      beforeCommit: beforeCommit,
    );
    return _combinedResult(result);
  }

  Future<CombinedUseResult> correctCombined(
    CombinedCorrectionCommand command, {
    bool failBeforeCommit = false,
    Future<void> Function()? beforeCommit,
  }) async {
    _stockGeneration(command.expectedGeneration);
    final result = await _command(
      command.commandId,
      ['combined_correct', command.personId, encodeCombinedCorrection(command)],
      () async {
        await _activeOwner(command.personId, command.expectedPersonRevision);
        final members = await _combinedRows(command.actionId, command.personId);
        final ids = members.map((m) => m['id']).toSet();
        if (members.length != command.components.length ||
            command.components.any((c) => !ids.contains(c.recordId))) {
          throw const CommandConflict('combined_membership');
        }
        for (final c in command.components) {
          final old = members.singleWhere((m) => m['id'] == c.recordId);
          if (old['revision'] != c.expectedRevision || old['voided'] == 1) {
            throw const CommandConflict('revision');
          }
          await _validateIntervalRevisionReviews(
            c.recordId,
            command.personId,
            c.expectedRevision,
            command.actualAt,
            command.voided,
            c.intervalReviews,
          );
        }
        for (var index = 0; index < command.components.length; index++) {
          final c = command.components[index];
          await _reviseInTransaction(
            '${command.commandId}/$index',
            c.recordId,
            c.expectedRevision,
            command.personId,
            c.enteredAmount,
            command.actualAt,
            command.voided,
            command.expectedPersonRevision,
            c.physicalCorrection,
            c.intervalReviews,
            allowCombined: true,
            intervalReviewsValidated: true,
          );
          await _setSite(
            command.commandId,
            command.personId,
            c.recordId,
            c.siteLabel,
          );
        }
        if (command.actualAt != null) {
          await _db.customStatement(
            'UPDATE combined_action SET actual=? WHERE id=? AND person=?',
            [
              command.actualAt!.microsecondsSinceEpoch,
              command.actionId,
              command.personId,
            ],
          );
        }
        return _auditCombined(
          command.actionId,
          command.personId,
          command.commandId,
        );
      },
      failBeforeCommit: failBeforeCommit,
      beforeCommit: beforeCommit,
    );
    return _combinedResult(result);
  }
}

Map<String, Object?> encodeCombinedUse(CombinedUseCommand c) => {
  'commandId': c.commandId,
  'expectedGeneration': c.expectedGeneration,
  'personId': c.personId,
  'expectedPersonRevision': c.expectedPersonRevision,
  'actualAt': c.actualAt.microsecondsSinceEpoch,
  'components': [
    for (final s in c.components)
      {
        'itemId': s.itemId,
        'expectedItemRevision': s.expectedItemRevision,
        'enteredAmount': s.enteredAmount,
        'stockUse': _stockUsePayload(s.stockUse),
        'productUse': s.productUse?.toJson(),
        'intendedRow': s.intendedRow == null
            ? null
            : {
                ..._targetJson(
                  ReminderTarget(
                    row: s.intendedRow!,
                    snoozeRevision: 0,
                    configRevision: 0,
                  ),
                ),
                'item_revision': s.intendedRow!.itemRevision,
              },
        'clock': s.intervalClockSample == null
            ? null
            : _sampleJson(s.intervalClockSample!),
        'siteLabel': s.siteLabel,
      },
  ],
};
StockUseInput? _readCombinedStock(dynamic s) => s == null
    ? null
    : StockUseInput(
        expectedGeneration: s[0] as String,
        containerId: s[1] as String?,
        expectedContainerRevision: s[2] as int?,
        entered: EnteredStockAmount(s[3] as String, s[4] as String),
        replacement: s[5] == null ? null : _replacementDecode(jsonEncode(s[5])),
        strength: s[6] == null ? null : _strengthDecode(s[6] as Object),
      );
CombinedUseCommand decodeCombinedUse(Map<String, dynamic> m) =>
    CombinedUseCommand(
      commandId: m['commandId'] as String,
      expectedGeneration: m['expectedGeneration'] as String,
      personId: m['personId'] as String,
      expectedPersonRevision: m['expectedPersonRevision'] as int,
      actualAt: DateTime.fromMicrosecondsSinceEpoch(
        m['actualAt'] as int,
        isUtc: true,
      ),
      components: [
        for (final dynamic s in m['components'] as List)
          CombinedUseComponent(
            itemId: s['itemId'] as String,
            expectedItemRevision: s['expectedItemRevision'] as int,
            enteredAmount: s['enteredAmount'] as String,
            stockUse: _readCombinedStock(s['stockUse']),
            productUse: s['productUse'] == null
                ? null
                : ProductUseInput.fromJson(
                    Map<String, dynamic>.from(s['productUse'] as Map),
                  ),
            intendedRow: s['intendedRow'] == null
                ? null
                : _targetRead(s['intendedRow']).row,
            intervalClockSample: s['clock'] == null
                ? null
                : _sampleRead(s['clock']),
            siteLabel: s['siteLabel'] as String?,
          ),
      ],
    );

Map<String, Object?> _encodeCombinedReview(IntervalChangeReview r) => {
  'plan': encodeDailyPlan(r.plan.plan),
  'revision': r.plan.revision,
  'record': r.recordId,
  'recordRevision': r.expectedRecordRevision,
  'guard': r.sourceGuard,
  'generation': r.generation,
  'personRevision': r.personRevision,
  'now': r.now.microsecondsSinceEpoch,
  'observedZone': r.observedZone,
  'actual': r.actualAt?.microsecondsSinceEpoch,
  'qualifies': r.qualifies,
  'voided': r.voided,
  'before': r.before == null ? null : encodeDailyExpectation(r.before!),
  'after': r.after == null ? null : encodeDailyExpectation(r.after!),
  'clock': r.intervalClockSample == null
      ? null
      : _sampleJson(r.intervalClockSample!),
};
IntervalChangeReview _decodeCombinedReview(dynamic r) => IntervalChangeReview(
  plan: SavedDailyPlan(
    plan: decodeDailyPlan(Map<String, dynamic>.from(r['plan'] as Map)),
    revision: r['revision'] as int,
  ),
  recordId: r['record'] as String,
  expectedRecordRevision: r['recordRevision'] as int,
  sourceGuard: r['guard'] as String,
  generation: r['generation'] as String,
  personRevision: r['personRevision'] as int,
  now: DateTime.fromMicrosecondsSinceEpoch(r['now'] as int, isUtc: true),
  observedZone: r['observedZone'] as String,
  actualAt: r['actual'] == null
      ? null
      : DateTime.fromMicrosecondsSinceEpoch(r['actual'] as int, isUtc: true),
  qualifies: r['qualifies'] as bool?,
  voided: r['voided'] as bool,
  before: r['before'] == null
      ? null
      : decodeDailyExpectation(Map<String, dynamic>.from(r['before'] as Map)),
  after: r['after'] == null
      ? null
      : decodeDailyExpectation(Map<String, dynamic>.from(r['after'] as Map)),
  intervalClockSample: r['clock'] == null ? null : _sampleRead(r['clock']),
);
Map<String, Object?> encodeCombinedCorrection(CombinedCorrectionCommand c) => {
  'commandId': c.commandId,
  'actionId': c.actionId,
  'personId': c.personId,
  'expectedPersonRevision': c.expectedPersonRevision,
  'expectedGeneration': c.expectedGeneration,
  'actualAt': c.actualAt?.microsecondsSinceEpoch,
  'voided': c.voided,
  'components': [
    for (final s in c.components)
      {
        'recordId': s.recordId,
        'expectedRevision': s.expectedRevision,
        'enteredAmount': s.enteredAmount,
        'physicalCorrection': s.physicalCorrection?.name,
        'siteLabel': s.siteLabel,
        'intervalReviews': [
          for (final r in s.intervalReviews) _encodeCombinedReview(r),
        ],
      },
  ],
};
CombinedCorrectionCommand decodeCombinedCorrection(Map<String, dynamic> m) =>
    CombinedCorrectionCommand(
      commandId: m['commandId'] as String,
      actionId: m['actionId'] as String,
      personId: m['personId'] as String,
      expectedPersonRevision: m['expectedPersonRevision'] as int,
      expectedGeneration: m['expectedGeneration'] as String,
      actualAt: m['actualAt'] == null
          ? null
          : DateTime.fromMicrosecondsSinceEpoch(
              m['actualAt'] as int,
              isUtc: true,
            ),
      voided: m['voided'] as bool,
      components: [
        for (final dynamic s in m['components'] as List)
          CombinedCorrectionComponent(
            recordId: s['recordId'] as String,
            expectedRevision: s['expectedRevision'] as int,
            enteredAmount: s['enteredAmount'] as String?,
            physicalCorrection: s['physicalCorrection'] == null
                ? null
                : PhysicalCorrection.values.byName(
                    s['physicalCorrection'] as String,
                  ),
            siteLabel: s['siteLabel'] as String?,
            intervalReviews: [
              for (final dynamic r in s['intervalReviews'] as List)
                _decodeCombinedReview(r),
            ],
          ),
      ],
    );

Map<String, Object?> encodeCombinedRow(DailyRow row) => {
  ..._targetJson(
    ReminderTarget(row: row, snoozeRevision: 0, configRevision: 0),
  ),
  'item_revision': row.itemRevision,
};
DailyRow decodeCombinedRow(Map<String, dynamic> value) =>
    _targetRead(value).row;
