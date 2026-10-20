part of 'record_store.dart';

// Identifier columns are validated text, never display names. A supporting
// metric ID is globally unique and is never reused across adults; the app
// creates a fresh ID for each new marker, so equal marker names stay separate.
const supportingSchemaV19 = [
  '''CREATE TABLE supporting_record(id TEXT PRIMARY KEY,person TEXT NOT NULL REFERENCES person(id),kind TEXT NOT NULL CHECK(kind IN ('labPanel','observation')),revision INTEGER NOT NULL CHECK(revision>0),entered_at INTEGER NOT NULL,entry_day TEXT NOT NULL,voided INTEGER NOT NULL CHECK(voided IN (0,1)),collection_day TEXT,collection_at INTEGER,report_day TEXT,report_at INTEGER,UNIQUE(id,person),FOREIGN KEY(id,person,revision) REFERENCES supporting_revision(record,person,revision) DEFERRABLE INITIALLY DEFERRED) STRICT''',
  '''CREATE TABLE supporting_revision(record TEXT NOT NULL,person TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),operation TEXT NOT NULL UNIQUE,entered_at INTEGER NOT NULL,snapshot TEXT NOT NULL CHECK(json_valid(snapshot)),header TEXT NOT NULL CHECK(json_valid(header)),PRIMARY KEY(record,person,revision),FOREIGN KEY(record,person) REFERENCES supporting_record(id,person) ON DELETE CASCADE) STRICT''',
  "CREATE TRIGGER supporting_revision_immutable BEFORE UPDATE ON supporting_revision BEGIN SELECT RAISE(ABORT,'immutable_supporting_revision'); END",
  "CREATE TABLE supporting_metric(id TEXT PRIMARY KEY,person TEXT NOT NULL REFERENCES person(id),kind TEXT NOT NULL CHECK(kind IN ('lab','observation')),name TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),UNIQUE(id,person)) STRICT",
  '''CREATE TABLE supporting_result(record TEXT NOT NULL,person TEXT NOT NULL,revision INTEGER NOT NULL,id TEXT NOT NULL,position INTEGER NOT NULL,metric TEXT NOT NULL,unit TEXT,value_kind TEXT NOT NULL CHECK(value_kind IN ('numeric','qualitative','missing')),numerator TEXT,denominator TEXT,snapshot TEXT NOT NULL CHECK(json_valid(snapshot)),PRIMARY KEY(record,person,revision,id),UNIQUE(record,person,revision,position),CHECK((value_kind='numeric' AND numerator IS NOT NULL AND denominator IS NOT NULL) OR (value_kind!='numeric' AND numerator IS NULL AND denominator IS NULL)),FOREIGN KEY(record,person,revision) REFERENCES supporting_revision(record,person,revision) ON DELETE CASCADE,FOREIGN KEY(metric,person) REFERENCES supporting_metric(id,person)) STRICT''',
  "CREATE TRIGGER supporting_result_immutable BEFORE UPDATE ON supporting_result BEGIN SELECT RAISE(ABORT,'immutable_supporting_result'); END",
  '''CREATE TABLE supporting_context(record TEXT NOT NULL,person TEXT NOT NULL,revision INTEGER NOT NULL,item TEXT,event TEXT,CHECK((item IS NOT NULL)+(event IS NOT NULL)=1),FOREIGN KEY(record,person,revision) REFERENCES supporting_revision(record,person,revision) ON DELETE CASCADE,FOREIGN KEY(item,person) REFERENCES item(id,person),FOREIGN KEY(event,person) REFERENCES event_record(id,person)) STRICT''',
  '''CREATE TABLE supporting_source(record TEXT NOT NULL,person TEXT NOT NULL,revision INTEGER NOT NULL,attachment TEXT NOT NULL,content_version TEXT NOT NULL,metadata_revision INTEGER NOT NULL,FOREIGN KEY(record,person,revision) REFERENCES supporting_revision(record,person,revision) ON DELETE CASCADE,FOREIGN KEY(attachment,person) REFERENCES attachment_record(id,person) ON DELETE CASCADE) STRICT''',
  'CREATE INDEX supporting_collection_feed ON supporting_record(person,collection_day DESC,collection_at DESC,id)',
  'CREATE INDEX supporting_report_feed ON supporting_record(person,report_day DESC,report_at DESC,id)',
  'CREATE INDEX supporting_entry_feed ON supporting_record(person,entered_at DESC,id)',
  'CREATE INDEX supporting_result_metric ON supporting_result(person,metric,record,revision)',
  'CREATE INDEX supporting_metric_search ON supporting_metric(person,kind,name,id)',
  'CREATE INDEX supporting_context_item ON supporting_context(person,item,record,revision)',
  'CREATE INDEX supporting_context_event ON supporting_context(person,event,record,revision)',
  'CREATE TABLE supporting_manifest_v18 AS SELECT * FROM attachment_record',
  'CREATE TABLE supporting_links_v18 AS SELECT * FROM attachment_link',
  'DROP TABLE attachment_link',
  'DROP TABLE attachment_record',
  "CREATE TABLE attachment_record(id TEXT PRIMARY KEY,person TEXT NOT NULL,target_kind TEXT NOT NULL CHECK(target_kind IN ('item','record','supporting')),target TEXT NOT NULL,version TEXT NOT NULL UNIQUE,revision INTEGER NOT NULL CHECK(revision>0),state TEXT NOT NULL CHECK(state IN ('staging','ready','deleting')),created_at INTEGER NOT NULL,snapshot TEXT NOT NULL CHECK(json_valid(snapshot)),UNIQUE(id,person)) STRICT",
  'INSERT INTO attachment_record SELECT * FROM supporting_manifest_v18',
  '''CREATE TABLE attachment_link(attachment TEXT PRIMARY KEY,person TEXT NOT NULL REFERENCES person(id),item TEXT,record TEXT,supporting TEXT,CHECK((item IS NOT NULL)+(record IS NOT NULL)+(supporting IS NOT NULL)=1),FOREIGN KEY(attachment,person) REFERENCES attachment_record(id,person) ON DELETE CASCADE,FOREIGN KEY(item,person) REFERENCES item(id,person),FOREIGN KEY(record,person) REFERENCES administration(id,person),FOREIGN KEY(supporting,person) REFERENCES supporting_record(id,person)) STRICT''',
  'INSERT INTO attachment_link SELECT attachment,person,item,record,NULL FROM supporting_links_v18',
  'CREATE INDEX attachment_link_person ON attachment_link(person,attachment)',
  'CREATE INDEX attachment_target ON attachment_record(person,target_kind,target,state,created_at,id)',
  "CREATE INDEX attachment_deleting ON attachment_record(id) WHERE state='deleting'",
  'DROP TABLE supporting_links_v18',
  'DROP TABLE supporting_manifest_v18',
  'ALTER TABLE ordinary_draft RENAME TO ordinary_draft_v18',
  "CREATE TABLE ordinary_draft(id TEXT PRIMARY KEY,generation TEXT NOT NULL,operation TEXT NOT NULL UNIQUE,kind TEXT NOT NULL CHECK(kind IN ('item','dose','correction','profile','dailyPlan','pausePlan','phasePlan','itemType','stockContainer','stockAdjustment','productLabel','combinedDose','combinedCorrection','siteEdit','event','usePeriod','eventReview','attachmentRename','labPanel','supportingObservation')),person TEXT REFERENCES person(id),person_revision INTEGER,target TEXT,target_revision INTEGER,snapshot TEXT NOT NULL) STRICT",
  'INSERT INTO ordinary_draft SELECT * FROM ordinary_draft_v18',
  'DROP TABLE ordinary_draft_v18',
];

/// Schema 20 adds only the bounded chronology access paths. Prior tables,
/// rows, triggers and indexes from v19 remain untouched.
const supportingSchemaV20 = [
  // Exact instants: display-zone day ranges become instant ranges.
  'CREATE INDEX supporting_collection_instant ON supporting_record(person,collection_at DESC,id) WHERE collection_at IS NOT NULL',
  'CREATE INDEX supporting_report_instant ON supporting_record(person,report_at DESC,id) WHERE report_at IS NOT NULL',
  // Supplied civil days, never converted between zones.
  'CREATE INDEX supporting_collection_civil ON supporting_record(person,collection_day DESC,id) WHERE collection_at IS NULL AND collection_day IS NOT NULL',
  'CREATE INDEX supporting_report_civil ON supporting_record(person,report_day DESC,id) WHERE report_at IS NULL AND report_day IS NOT NULL',
  // Unknown and partial dates remain an explicit, separately bounded section.
  'CREATE INDEX supporting_collection_unpositioned ON supporting_record(person,id) WHERE collection_at IS NULL AND collection_day IS NULL',
  'CREATE INDEX supporting_report_unpositioned ON supporting_record(person,id) WHERE report_at IS NULL AND report_day IS NULL',
];

Future<void> _migrateSupportingV20(_Database db) async {
  for (final sql in supportingSchemaV20) {
    await db.customStatement(sql);
  }
}

Future<void> _migrateSupportingV19(_Database db) async {
  // Rebuild only the known child before its parent, without disabling FKs.
  // A future unexpected child must receive an explicit migration design.
  final tables = await db
      .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
      .get();
  for (final table in tables) {
    final name = table.read<String>('name');
    final foreignKeys = await db
        .customSelect(
          'PRAGMA foreign_key_list("${name.replaceAll('"', '""')}")',
        )
        .get();
    if (name != 'attachment_link' &&
        foreignKeys.any((r) => r.data['table'] == 'attachment_record')) {
      throw StateError('supporting_attachment_migration_review');
    }
  }
  for (final sql in supportingSchemaV19) {
    await db.customStatement(sql);
  }
  if ((await db.customSelect('PRAGMA foreign_key_check').get()).isNotEmpty) {
    throw StateError('supporting_migration_integrity');
  }
}

Map<String, dynamic> _supportingObject(Object? value) =>
    Map<String, dynamic>.from(value as Map);

/// One row of the merged collection/report chronology.
///
/// [day] is the display-zone day for exact instants and the supplied civil day
/// for day-only records. Unknown and partial dates have no day and sort last.
final class _SupportingFeedRow {
  const _SupportingFeedRow(this.id, this.day, this.at);
  final String id;
  final String? day;
  final int? at;
}

int _supportingFeedCompare(_SupportingFeedRow a, _SupportingFeedRow b) {
  final aDay = a.day, bDay = b.day;
  if (aDay == null && bDay != null) return 1;
  if (aDay != null && bDay == null) return -1;
  if (aDay != null && bDay != null) {
    final order = bDay.compareTo(aDay);
    if (order != 0) return order;
  }
  final aAt = a.at, bAt = b.at;
  if (aAt == null && bAt != null) return 1;
  if (aAt != null && bAt == null) return -1;
  if (aAt != null && bAt != null) {
    final order = bAt.compareTo(aAt);
    if (order != 0) return order;
  }
  return a.id.compareTo(b.id);
}

final class SaveLabPanelCommand {
  const SaveLabPanelCommand({
    required this.commandId,
    required this.generation,
    required this.expectedPersonRevision,
    required this.panel,
    this.expectedRevision,
  });
  final String commandId, generation;
  final int expectedPersonRevision;
  final int? expectedRevision;
  final LabPanelSnapshot panel;
  Map<String, Object?> toJson() => {
    'commandId': commandId,
    'generation': generation,
    'expectedPersonRevision': expectedPersonRevision,
    'expectedRevision': expectedRevision,
    'panel': panel.toJson(),
  };
  factory SaveLabPanelCommand.fromJson(Map<String, dynamic> j) =>
      SaveLabPanelCommand(
        commandId: j['commandId'] as String,
        generation: j['generation'] as String,
        expectedPersonRevision: j['expectedPersonRevision'] as int,
        expectedRevision: j['expectedRevision'] as int?,
        panel: LabPanelSnapshot.fromJson(_supportingObject(j['panel'])),
      );
}

final class SaveObservationCommand {
  const SaveObservationCommand({
    required this.commandId,
    required this.generation,
    required this.expectedPersonRevision,
    required this.observation,
    this.expectedRevision,
  });
  final String commandId, generation;
  final int expectedPersonRevision;
  final int? expectedRevision;
  final ObservationSnapshot observation;
  Map<String, Object?> toJson() => {
    'commandId': commandId,
    'generation': generation,
    'expectedPersonRevision': expectedPersonRevision,
    'expectedRevision': expectedRevision,
    'observation': observation.toJson(),
  };
  factory SaveObservationCommand.fromJson(Map<String, dynamic> j) =>
      SaveObservationCommand(
        commandId: j['commandId'] as String,
        generation: j['generation'] as String,
        expectedPersonRevision: j['expectedPersonRevision'] as int,
        expectedRevision: j['expectedRevision'] as int?,
        observation: ObservationSnapshot.fromJson(
          _supportingObject(j['observation']),
        ),
      );
}

final class VoidSupportingRecordCommand {
  const VoidSupportingRecordCommand({
    required this.commandId,
    required this.generation,
    required this.personId,
    required this.id,
    required this.expectedPersonRevision,
    required this.expectedRevision,
    this.isVoided = true,
  });
  final String commandId, generation, personId, id;
  final int expectedPersonRevision, expectedRevision;
  final bool isVoided;
  Map<String, Object?> toJson() => {
    'commandId': commandId,
    'generation': generation,
    'personId': personId,
    'id': id,
    'expectedPersonRevision': expectedPersonRevision,
    'expectedRevision': expectedRevision,
    'isVoided': isVoided,
  };
  factory VoidSupportingRecordCommand.fromJson(Map<String, dynamic> j) =>
      VoidSupportingRecordCommand(
        commandId: j['commandId'] as String,
        generation: j['generation'] as String,
        personId: j['personId'] as String,
        id: j['id'] as String,
        expectedPersonRevision: j['expectedPersonRevision'] as int,
        expectedRevision: j['expectedRevision'] as int,
        isVoided: j['isVoided'] as bool,
      );
}

final class SupportingQuery {
  SupportingQuery({
    required this.personId,
    this.kind,
    this.dateBasis = SupportingDateBasis.collection,
    this.fromDate,
    this.beforeDate,
    this.includeUnknownDates = true,
    this.itemId,
    this.eventId,
    this.includeVoided = false,
    this.limit = 25,
    this.displayZone = 'UTC',
  }) {
    attachmentIdentity(personId);
    if (limit < 1 || limit > 50) {
      throw const SupportingLimitException('page_limit');
    }
    if (fromDate != null &&
        beforeDate != null &&
        beforeDate!.compareTo(fromDate!) <= 0) {
      throw ArgumentError('supporting_range');
    }
  }
  final String personId, displayZone;
  final SupportingRecordKind? kind;
  final SupportingDateBasis dateBasis;
  final CivilDate? fromDate, beforeDate;
  final bool includeUnknownDates, includeVoided;
  final String? itemId, eventId;
  final int limit;
  String get identity => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            personId,
            kind?.name,
            dateBasis.name,
            fromDate?.toString(),
            beforeDate?.toString(),
            includeUnknownDates,
            itemId,
            eventId,
            includeVoided,
            displayZone,
            limit,
          ]),
        ),
      )
      .toString();
}

final class SupportingCursor {
  SupportingCursor._(
    this.identity,
    this.schemaVersion,
    this.datasetGeneration,
    this.day,
    this.at,
    this.id,
  );
  final String identity, datasetGeneration, id;
  final int schemaVersion;
  final String? day;
  final int? at;
  String encode() => base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'v': 1,
            'query': identity,
            'schema': schemaVersion,
            'dataset': datasetGeneration,
            'day': day,
            'at': at,
            'id': id,
          }),
        ),
      )
      .replaceAll('=', '');
  factory SupportingCursor.decode(String text) {
    try {
      if (text.length > 8192) throw const FormatException();
      final j = _supportingObject(
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(text)))),
      );
      if (j['v'] != 1 ||
          j['query'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(j['query'] as String) ||
          j['schema'] is! int ||
          j['dataset'] is! String ||
          j['id'] is! String ||
          (j['day'] != null && j['day'] is! String) ||
          (j['at'] != null && j['at'] is! int)) {
        throw const FormatException();
      }
      return SupportingCursor._(
        j['query'] as String,
        j['schema'] as int,
        j['dataset'] as String,
        j['day'] as String?,
        j['at'] as int?,
        j['id'] as String,
      );
    } on Object {
      throw const TimelineCursorException('cursor_malformed');
    }
  }
}

final class SupportingPage {
  SupportingPage._({
    required this.queryIdentity,
    required this.schemaVersion,
    required this.datasetGeneration,
    required Iterable<SupportingRevision> entries,
    required this.next,
  }) : entries = List.unmodifiable(entries);
  final String queryIdentity, datasetGeneration;
  final int schemaVersion;
  final List<SupportingRevision> entries;
  final SupportingCursor? next;
  bool get hasMore => next != null;
}

extension SupportingRecordStore on RecordStore {
  SupportingRevision _supportingRead(Map<String, Object?> row) =>
      SupportingRevision.fromJson(
        _supportingObject(jsonDecode(row['snapshot'] as String)),
      );

  Future<SupportingRevision?> supportingRecord(
    String personId,
    String id, {
    int? revision,
  }) async {
    _requireWritable();
    final rows = await _rows(
      'SELECT v.snapshot FROM supporting_record s JOIN supporting_revision v ON v.record=s.id AND v.person=s.person AND v.revision=${revision == null ? 's.revision' : '?'} WHERE s.person=? AND s.id=?',
      [?revision, personId, id],
    );
    return rows.isEmpty ? null : _supportingRead(rows.single);
  }

  Future<List<SupportingRevision>> supportingRevisions(
    String personId,
    String id, {
    int? beforeRevision,
    int limit = 25,
  }) async {
    _requireWritable();
    if (limit < 1 || limit > 50) {
      throw const SupportingLimitException('page_limit');
    }
    return (await _rows(
      'SELECT snapshot FROM supporting_revision WHERE person=? AND record=? ${beforeRevision == null ? '' : 'AND revision<?'} ORDER BY revision DESC LIMIT ?',
      [personId, id, ?beforeRevision, limit],
    )).map(_supportingRead).toList();
  }

  Stream<SupportingRevision?> watchSupportingRecord(
    String personId,
    String id,
  ) => _watch(() => supportingRecord(personId, id));
  Future<List<SupportingMetric>> supportingMetrics({
    required String personId,
    required SupportingMetricKind kind,
    String search = '',
    int limit = 50,
    int offset = 0,
  }) async {
    _requireWritable();
    if (limit < 1 || limit > 50 || offset < 0) {
      throw const SupportingLimitException('page_limit');
    }
    return (await _rows(
          'SELECT * FROM supporting_metric WHERE person=? AND kind=? AND instr(lower(name),lower(?))>0 ORDER BY name,id LIMIT ? OFFSET ?',
          [personId, kind.name, search, limit, offset],
        ))
        .map(
          (r) => SupportingMetric(
            id: r['id'] as String,
            personId: r['person'] as String,
            kind: SupportingMetricKind.values.byName(r['kind'] as String),
            name: r['name'] as String,
            revision: r['revision'] as int,
          ),
        )
        .toList();
  }

  Future<SupportingRevision> saveLabPanel(
    SaveLabPanelCommand command, {
    bool failBeforeCommit = false,
    Future<void> Function()? beforeCommit,
  }) => _saveSupporting(
    command.commandId,
    command.generation,
    command.expectedPersonRevision,
    command.expectedRevision,
    command.panel,
    failBeforeCommit: failBeforeCommit,
    beforeCommit: beforeCommit,
  );
  Future<SupportingRevision> saveObservation(
    SaveObservationCommand command, {
    bool failBeforeCommit = false,
    Future<void> Function()? beforeCommit,
  }) => _saveSupporting(
    command.commandId,
    command.generation,
    command.expectedPersonRevision,
    command.expectedRevision,
    command.observation,
    failBeforeCommit: failBeforeCommit,
    beforeCommit: beforeCommit,
  );

  Future<SupportingRevision> _saveSupporting(
    String commandId,
    String dataset,
    int ownerRevision,
    int? expectedRevision,
    SupportingSnapshot snapshot, {
    bool failBeforeCommit = false,
    Future<void> Function()? beforeCommit,
  }) async {
    _dailyGeneration(dataset);
    final encoded = jsonEncode(snapshot.toJson());
    if (encoded.length > 2000000) {
      throw const SupportingLimitException('snapshot_size');
    }
    final result = await _command(
      commandId,
      [
        'supporting_save',
        snapshot.id.personId,
        ownerRevision,
        expectedRevision,
        snapshot.toJson(),
      ],
      () async {
        await _activeOwner(snapshot.id.personId, ownerRevision);
        final existing = await _rows(
          'SELECT person,kind,revision FROM supporting_record WHERE id=?',
          [snapshot.id.id],
        );
        if (existing.isNotEmpty &&
            existing.single['person'] != snapshot.id.personId) {
          throw const CommandConflict('ownership');
        }
        if (existing.isEmpty
            ? expectedRevision != null
            : (existing.single['revision'] != expectedRevision ||
                  existing.single['kind'] != snapshot.kind.name)) {
          throw const CommandConflict('supporting_revision');
        }
        final old = existing.isEmpty
            ? null
            : await supportingRecord(snapshot.id.personId, snapshot.id.id);
        final now = DateTime.now().toUtc();
        final revision = SupportingRevision(
          snapshot: snapshot,
          revision: (old?.revision ?? 0) + 1,
          operationId: commandId,
          enteredAt: old?.enteredAt ?? now,
          revisionEnteredAt: now,
          isVoided: old?.isVoided ?? false,
        );
        await _writeSupportingRevision(revision, previous: old);
        return {
          'person': snapshot.id.personId,
          'supporting': revision.toJson(),
        };
      },
      failBeforeCommit: failBeforeCommit,
      beforeCommit: beforeCommit,
    );
    return SupportingRevision.fromJson(_supportingObject(result['supporting']));
  }

  Future<SupportingRevision> voidSupportingRecord(
    VoidSupportingRecordCommand command, {
    bool failBeforeCommit = false,
    Future<void> Function()? beforeCommit,
  }) async {
    _dailyGeneration(command.generation);
    final result = await _command(
      command.commandId,
      ['supporting_void', command.personId, command.toJson()],
      () async {
        await _activeOwner(command.personId, command.expectedPersonRevision);
        final old = await supportingRecord(command.personId, command.id);
        if (old == null ||
            old.revision != command.expectedRevision ||
            old.isVoided == command.isVoided) {
          throw const CommandConflict('supporting_revision');
        }
        final next = SupportingRevision(
          snapshot: old.snapshot,
          revision: old.revision + 1,
          operationId: command.commandId,
          enteredAt: old.enteredAt,
          revisionEnteredAt: DateTime.now().toUtc(),
          isVoided: command.isVoided,
        );
        await _writeSupportingRevision(next, previous: old);
        return {'person': command.personId, 'supporting': next.toJson()};
      },
      failBeforeCommit: failBeforeCommit,
      beforeCommit: beforeCommit,
    );
    return SupportingRevision.fromJson(_supportingObject(result['supporting']));
  }

  /// The supplied civil day only. An exact instant is never projected onto a
  /// saved-offset day here: collection/report chronology uses the requested
  /// display-zone date at query time, while the snapshot keeps the source zone
  /// and offset facts unchanged.
  String? _supportingDay(SupportingDate date) => date.civilDate?.toString();
  String _supportingUtcDay(DateTime instant) =>
      '${instant.year.toString().padLeft(4, '0')}-${instant.month.toString().padLeft(2, '0')}-${instant.day.toString().padLeft(2, '0')}';

  Future<void> _writeSupportingRevision(
    SupportingRevision revision, {
    SupportingRevision? previous,
  }) async {
    final snapshot = revision.snapshot,
        person = snapshot.id.personId,
        id = snapshot.id.id;
    final metricKind = snapshot.kind == SupportingRecordKind.labPanel
        ? SupportingMetricKind.lab
        : SupportingMetricKind.observation;
    // Validate immutable, explicit owner identities before writing any rows.
    for (final result in snapshot.results) {
      final found = await _rows(
        'SELECT person,kind FROM supporting_metric WHERE id=?',
        [result.metricId],
      );
      if (found.isNotEmpty &&
          (found.single['person'] != person ||
              found.single['kind'] != metricKind.name)) {
        throw const CommandConflict('ownership');
      }
    }
    for (final context in snapshot.contextLinks) {
      final table = context.kind == SupportingContextKind.item
          ? 'item'
          : 'event_record';
      if (context.personId != person ||
          (await _rows('SELECT id FROM $table WHERE id=? AND person=?', [
            context.id,
            person,
          ])).isEmpty) {
        throw const CommandConflict('ownership');
      }
    }
    String sourceKey(SupportingSourceReference s) => jsonEncode([
      s.id,
      s.personId,
      s.kind.name,
      s.version,
      s.contentVersionId,
    ]);
    final historicalSources = <String>{
      if (previous != null)
        for (final p in [
          previous.snapshot.provenance,
          ...previous.snapshot.results
              .map((r) => r.provenance)
              .whereType<SupportingProvenance>(),
        ])
          for (final s in p.sourceReferences) sourceKey(s),
    };
    final sources = <SupportingSourceReference>[];
    for (final provenance in [
      snapshot.provenance,
      ...snapshot.results
          .map((r) => r.provenance)
          .whereType<SupportingProvenance>(),
    ]) {
      for (final source in provenance.sourceReferences) {
        if (source.personId != person) throw const CommandConflict('ownership');
        if (source.kind == SupportingSourceKind.attachment) {
          final attachment = await attachmentById(source.id);
          final historical = historicalSources.contains(sourceKey(source));
          if (!historical &&
              (attachment == null ||
                  attachment.personId != person ||
                  attachment.revision != source.version ||
                  attachment.state != AttachmentState.ready ||
                  attachment.versionId != source.contentVersionId)) {
            throw const CommandConflict('attachment_revision');
          }
          // An unavailable original remains in the immutable source snapshot.
          // A live manifest projection is optional after that source is deleted.
          if (attachment != null &&
              attachment.personId == person &&
              attachment.versionId == source.contentVersionId) {
            sources.add(source);
          }
        }
      }
    }
    await _db.customStatement(
      'INSERT INTO supporting_record VALUES (?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET revision=excluded.revision,voided=excluded.voided,collection_day=excluded.collection_day,collection_at=excluded.collection_at,report_day=excluded.report_day,report_at=excluded.report_at',
      [
        id,
        person,
        snapshot.kind.name,
        revision.revision,
        revision.enteredAt.microsecondsSinceEpoch,
        _supportingUtcDay(revision.enteredAt),
        revision.isVoided ? 1 : 0,
        _supportingDay(snapshot.collectionDate),
        snapshot.collectionDate.instant?.microsecondsSinceEpoch,
        _supportingDay(snapshot.reportDate),
        snapshot.reportDate.instant?.microsecondsSinceEpoch,
      ],
    );
    final header = revision.toJson();
    header['snapshot'] = {...snapshot.toJson(), 'results': <Object?>[]};
    await _db.customStatement(
      'INSERT INTO supporting_revision VALUES (?,?,?,?,?,?,?)',
      [
        id,
        person,
        revision.revision,
        revision.operationId,
        revision.revisionEnteredAt.microsecondsSinceEpoch,
        jsonEncode(revision.toJson()),
        jsonEncode(header),
      ],
    );
    for (var position = 0; position < snapshot.results.length; position++) {
      final result = snapshot.results[position];
      await _db.customStatement(
        'INSERT INTO supporting_metric VALUES (?,?,?,?,1) ON CONFLICT(id) DO NOTHING',
        [result.metricId, person, metricKind.name, result.markerName],
      );
      await _db.customStatement(
        'INSERT INTO supporting_result VALUES (?,?,?,?,?,?,?,?,?,?,?)',
        [
          id,
          person,
          revision.revision,
          result.id,
          position,
          result.metricId,
          result.unit,
          result.value.kind.name,
          result.value.exactAmount?.numerator.toString(),
          result.value.exactAmount?.denominator.toString(),
          jsonEncode(result.toJson()),
        ],
      );
    }
    for (final context in snapshot.contextLinks) {
      await _db.customStatement(
        'INSERT INTO supporting_context VALUES (?,?,?,?,?)',
        [
          id,
          person,
          revision.revision,
          context.kind == SupportingContextKind.item ? context.id : null,
          context.kind == SupportingContextKind.event ? context.id : null,
        ],
      );
    }
    for (final source in sources) {
      await _db.customStatement(
        'INSERT INTO supporting_source VALUES (?,?,?,?,?,?)',
        [
          id,
          person,
          revision.revision,
          source.id,
          source.contentVersionId,
          source.version,
        ],
      );
    }
  }

  /// Disjoint record branches for one date basis.
  ///
  /// Chronology contract:
  /// - exact instant: the requested display-zone civil date, ordered by instant;
  /// - supplied day: that civil day, never converted between zones;
  /// - unknown/partial: unpositioned, after every known day.
  /// The branches are disjoint, so a record can appear in only one page stream.
  List<_HistorySql> _supportingDateBranches({
    required String at,
    required String day,
    CivilDate? from,
    CivilDate? before,
    required String zone,
    required bool includeUnknown,
  }) {
    final exact = <String>['$at IS NOT NULL'], exactArgs = <Object?>[];
    final civil = <String>['$at IS NULL', '$day IS NOT NULL'],
        civilArgs = <Object?>[];
    if (from != null) {
      exact.add('$at>=?');
      exactArgs.add(
        DisplayTime().dayBounds(from, zone).start.microsecondsSinceEpoch,
      );
      civil.add('$day>=?');
      civilArgs.add(from.toString());
    }
    if (before != null) {
      exact.add('$at<?');
      exactArgs.add(
        DisplayTime().dayBounds(before, zone).start.microsecondsSinceEpoch,
      );
      civil.add('$day<?');
      civilArgs.add(before.toString());
    }
    return [
      _HistorySql(exact.join(' AND '), exactArgs),
      _HistorySql(civil.join(' AND '), civilArgs),
      if (includeUnknown) _HistorySql('$at IS NULL AND $day IS NULL', const []),
    ];
  }

  String _supportingDisplayDay(int microseconds, String zone) => DisplayTime()
      .instant(
        DateTime.fromMicrosecondsSinceEpoch(microseconds, isUtc: true),
        zone,
      )
      .civilDate
      .toString();

  /// Cursor continuation for the exact/instant branch.
  ///
  /// An exact cursor continues below its instant. A civil cursor has already
  /// passed every exact row on its display day, so only earlier instants remain.
  _HistorySql _supportingExactCursor(
    String at,
    SupportingCursor cursor,
    String zone,
  ) {
    if (cursor.at != null) {
      return _HistorySql('($at<? OR ($at=? AND s.id>?))', [
        cursor.at,
        cursor.at,
        cursor.id,
      ]);
    }
    final day = cursor.day;
    if (day == null) return _HistorySql('0', const []);
    return _HistorySql('$at<?', [
      DisplayTime()
          .dayBounds(CivilDate.parse(day), zone)
          .start
          .microsecondsSinceEpoch,
    ]);
  }

  /// Cursor continuation for the supplied-civil-day branch.
  ///
  /// Civil rows within one day follow every exact row on that day. An exact
  /// cursor therefore leaves all civil rows of its display day. A civil cursor
  /// continues by id within the same day and then by earlier days.
  _HistorySql _supportingCivilCursor(String day, SupportingCursor cursor) {
    if (cursor.day == null) return _HistorySql('0', const []);
    if (cursor.at != null) return _HistorySql('$day<=?', [cursor.day]);
    return _HistorySql('($day<? OR ($day=? AND s.id>?))', [
      cursor.day,
      cursor.day,
      cursor.id,
    ]);
  }

  _HistorySql _supportingUnknownCursor(SupportingCursor cursor) =>
      cursor.day != null
      ? _HistorySql('1', const [])
      : _HistorySql('s.id>?', [cursor.id]);

  Future<SupportingPage> supportingRecords(
    SupportingQuery query, {
    SupportingCursor? cursor,
  }) async {
    _requireWritable();
    return _db.transaction(() async {
      await _chartGeneration();
      if (cursor != null &&
          (cursor.identity != query.identity ||
              cursor.schemaVersion != _db.schemaVersion ||
              cursor.datasetGeneration != generation)) {
        throw const TimelineCursorException('cursor_expired');
      }
      final common = <String>['s.person=?'],
          commonArgs = <Object?>[query.personId];
      if (!query.includeVoided) common.add('s.voided=0');
      if (query.kind != null) {
        common.add('s.kind=?');
        commonArgs.add(query.kind!.name);
      }
      for (final pair in [(query.itemId, 'item'), (query.eventId, 'event')]) {
        if (pair.$1 != null) {
          common.add(
            'EXISTS(SELECT 1 FROM supporting_context c WHERE c.record=s.id AND c.person=s.person AND c.revision=s.revision AND c.${pair.$2}=?)',
          );
          commonArgs.add(pair.$1);
        }
      }
      final found = <_SupportingFeedRow>[];
      if (query.dateBasis == SupportingDateBasis.entry) {
        // Entry is audit browsing only: a display-zone instant feed, never a
        // measurement chronology.
        final date = <String>[], args = <Object?>[];
        if (query.fromDate != null) {
          date.add('s.entered_at>=?');
          args.add(
            DisplayTime()
                .dayBounds(query.fromDate!, query.displayZone)
                .start
                .microsecondsSinceEpoch,
          );
        }
        if (query.beforeDate != null) {
          date.add('s.entered_at<?');
          args.add(
            DisplayTime()
                .dayBounds(query.beforeDate!, query.displayZone)
                .start
                .microsecondsSinceEpoch,
          );
        }
        if (cursor != null) {
          final more = _supportingExactCursor(
            's.entered_at',
            cursor,
            query.displayZone,
          );
          date.add(more.sql);
          args.addAll(more.args);
        }
        final rows = await _rows(
          'SELECT s.id,s.entered_at AS ordering_at FROM supporting_record s WHERE ${[...common, ...date].join(' AND ')} ORDER BY s.entered_at DESC,s.id LIMIT ?',
          [...commonArgs, ...args, query.limit + 1],
        );
        for (final row in rows) {
          final at = row['ordering_at'] as int;
          found.add(
            _SupportingFeedRow(
              row['id'] as String,
              _supportingDisplayDay(at, query.displayZone),
              at,
            ),
          );
        }
      } else {
        final at = query.dateBasis == SupportingDateBasis.report
            ? 's.report_at'
            : 's.collection_at';
        final day = query.dateBasis == SupportingDateBasis.report
            ? 's.report_day'
            : 's.collection_day';
        final branches = _supportingDateBranches(
          at: at,
          day: day,
          from: query.fromDate,
          before: query.beforeDate,
          zone: query.displayZone,
          includeUnknown: query.includeUnknownDates,
        );
        for (var branch = 0; branch < branches.length; branch++) {
          final clauses = <String>[...common, branches[branch].sql],
              args = <Object?>[...commonArgs, ...branches[branch].args];
          if (cursor != null) {
            final more = switch (branch) {
              0 => _supportingExactCursor(at, cursor, query.displayZone),
              1 => _supportingCivilCursor(day, cursor),
              _ => _supportingUnknownCursor(cursor),
            };
            clauses.add(more.sql);
            args.addAll(more.args);
          }
          final order = switch (branch) {
            0 => '$at DESC,s.id',
            1 => '$day DESC,s.id',
            _ => 's.id',
          };
          final rows = await _rows(
            'SELECT s.id,${branch == 0
                ? at
                : branch == 1
                ? day
                : 'NULL'} AS ordering_day,${branch == 0 ? at : 'NULL'} AS ordering_at FROM supporting_record s WHERE ${clauses.join(' AND ')} ORDER BY $order LIMIT ?',
            [...args, query.limit + 1],
          );
          for (final row in rows) {
            final instant = row['ordering_at'] as int?;
            found.add(
              _SupportingFeedRow(
                row['id'] as String,
                branch == 0
                    ? _supportingDisplayDay(instant!, query.displayZone)
                    : branch == 1
                    ? row['ordering_day'] as String
                    : null,
                instant,
              ),
            );
          }
        }
      }
      found.sort(_supportingFeedCompare);
      final window = found.take(query.limit + 1).toList(),
          parents = window.take(query.limit).toList(),
          ids = parents.map((r) => r.id).toList();
      final loaded = ids.isEmpty
          ? <Map<String, Object?>>[]
          : await _rows(
              'SELECT v.record,v.snapshot FROM supporting_revision v JOIN supporting_record s ON s.id=v.record AND s.person=v.person AND s.revision=v.revision WHERE s.person=? AND s.id IN (${List.filled(ids.length, '?').join(',')})',
              [query.personId, ...ids],
            );
      final byId = {
        for (final row in loaded) row['record']: _supportingRead(row),
      };
      final last = parents.lastOrNull;
      _requireWritable();
      return SupportingPage._(
        queryIdentity: query.identity,
        schemaVersion: _db.schemaVersion,
        datasetGeneration: generation,
        entries: parents.map((p) => byId[p.id]!),
        next: window.length <= query.limit || last == null
            ? null
            : SupportingCursor._(
                query.identity,
                _db.schemaVersion,
                generation,
                last.day,
                last.at,
                last.id,
              ),
      );
    });
  }

  Stream<SupportingPage> watchSupportingRecords(
    SupportingQuery query, {
    SupportingCursor? cursor,
  }) => _watch(() => supportingRecords(query, cursor: cursor));

  Future<SupportingTrendPage> supportingTrend(
    SupportingTrendQuery query, {
    int requestGeneration = 0,
  }) async {
    _requireWritable();
    if (query.dateBasis == SupportingDateBasis.entry) {
      // Entry is audit browsing, not a measurement chronology. A trend must
      // use the collection or report date the source actually supplied.
      throw ArgumentError('trend_basis');
    }
    return _db.transaction(() async {
      await _chartGeneration();
      final at = query.dateBasis == SupportingDateBasis.report
          ? 's.report_at'
          : 's.collection_at';
      final day = query.dateBasis == SupportingDateBasis.report
          ? 's.report_day'
          : 's.collection_day';
      // Bound the head-record window first, then fetch results for only those
      // head records. A narrow date range never scans the metric's lifetime.
      // Unknown/partial records remain a separate unpositioned source.
      final report = query.dateBasis == SupportingDateBasis.report;
      final branches = _supportingDateBranches(
        at: at,
        day: day,
        from: query.fromDate,
        before: query.beforeDate,
        zone: query.displayZone,
        includeUnknown: true,
      );
      final branchIndexes = report
          ? [
              'supporting_report_instant',
              'supporting_report_civil',
              'supporting_report_unpositioned',
            ]
          : [
              'supporting_collection_instant',
              'supporting_collection_civil',
              'supporting_collection_unpositioned',
            ];
      final branchSql = <String>[], branchArgs = <Object?>[];
      for (var i = 0; i < branches.length; i++) {
        branchSql.add(
          'SELECT s.id,s.person,s.revision FROM supporting_record s INDEXED BY ${branchIndexes[i]} '
          'WHERE s.person=? AND s.voided=0 AND (${branches[i].sql})',
        );
        branchArgs
          ..add(query.personId)
          ..addAll(branches[i].args);
      }
      // A UNION ALL keeps the three index paths disjoint. A single OR predicate
      // lets SQLite fall back to one person-only index and scan the lifetime.
      final matchedSql =
          'WITH matched AS MATERIALIZED (${branchSql.join(' UNION ALL ')}) '
          'SELECT r.record AS id,r.revision AS revision,r.position,v.header,r.snapshot FROM supporting_result r INDEXED BY supporting_result_metric '
          'JOIN matched m ON m.id=r.record AND m.person=r.person AND m.revision=r.revision '
          'JOIN supporting_revision v ON v.record=m.id AND v.person=m.person AND v.revision=m.revision '
          'WHERE r.person=? AND r.metric=?';
      final rows = <Map<String, Object?>>[];
      final comparison = query.comparisonGroup;
      if (comparison == null) {
        rows.addAll(
          await _rows('$matchedSql LIMIT ?', [
            ...branchArgs,
            query.personId,
            query.metricId,
            SupportingLimits.maxTrendRows + 1,
          ]),
        );
        if (rows.length > SupportingLimits.maxTrendRows) {
          throw const SupportingLimitException('trend_rows');
        }
      } else {
        // The 10,000-row bound applies to the chosen comparison group. A single
        // SQL LIMIT would let unrelated groups exhaust the bound before the
        // requested group is reached, so a filtered query reads bounded batches
        // and counts only its own group. The keyset batch is bounded by
        // maxTrendRows + 1 and reads only the date-bounded matched head window,
        // never the metric's lifetime revisions.
        final records = <String, SupportingRevision>{};
        SupportingRevision recordFor(
          Map<String, Object?> row,
        ) => records.putIfAbsent(row['id'] as String, () {
          final header = _supportingObject(jsonDecode(row['header'] as String));
          final snapshot = _supportingObject(header['snapshot']);
          // A revision needs at least one result to decode an observation;
          // the comparison key itself only reads record identity/provenance.
          snapshot['results'] = [jsonDecode(row['snapshot'] as String)];
          header['snapshot'] = snapshot;
          return SupportingRevision.fromJson(header);
        });
        String? afterRecord;
        int? afterRevision;
        int? afterPosition;
        while (true) {
          final more = afterRecord == null
              ? _HistorySql('1', const [])
              : _HistorySql(
                  '(r.record>? OR (r.record=? AND (r.revision>? OR (r.revision=? AND r.position>?))))',
                  [
                    afterRecord,
                    afterRecord,
                    afterRevision,
                    afterRevision,
                    afterPosition,
                  ],
                );
          final batch = await _rows(
            '$matchedSql AND ${more.sql} ORDER BY r.record,r.revision,r.position LIMIT ?',
            [
              ...branchArgs,
              query.personId,
              query.metricId,
              ...more.args,
              SupportingLimits.maxTrendRows + 1,
            ],
          );
          if (batch.isEmpty) break;
          for (final row in batch) {
            final result = LabResultSnapshot.fromJson(
              _supportingObject(jsonDecode(row['snapshot'] as String)),
            );
            final group = SupportingComparisonKey.forResult(
              recordFor(row),
              result,
            );
            if (group.identity != comparison) continue;
            rows.add(row);
            if (rows.length > SupportingLimits.maxTrendRows) {
              throw const SupportingLimitException('trend_rows');
            }
          }
          if (batch.length < SupportingLimits.maxTrendRows + 1) break;
          final last = batch.last;
          afterRecord = last['id'] as String;
          afterRevision = last['revision'] as int;
          afterPosition = last['position'] as int;
        }
      }
      final grouped = <String, List<Map<String, Object?>>>{};
      for (final row in rows) {
        grouped.putIfAbsent(row['id'] as String, () => []).add(row);
      }
      final revisions = <SupportingRevision>[];
      for (final group in grouped.values) {
        group.sort(
          (a, b) => (a['position'] as int).compareTo(b['position'] as int),
        );
        final header = _supportingObject(
          jsonDecode(group.first['header'] as String),
        );
        final snapshot = _supportingObject(header['snapshot']);
        snapshot['results'] = [
          for (final row in group) jsonDecode(row['snapshot'] as String),
        ];
        header['snapshot'] = snapshot;
        revisions.add(SupportingRevision.fromJson(header));
      }
      _requireWritable();
      return SupportingTrendPage.build(
        query: query,
        records: revisions,
        schemaVersion: _db.schemaVersion,
        datasetGeneration: generation,
        requestGeneration: requestGeneration,
      );
    });
  }

  Stream<SupportingTrendPage> watchSupportingTrend(
    SupportingTrendQuery query, {
    int requestGeneration = 0,
  }) => _watch(
    () => supportingTrend(query, requestGeneration: requestGeneration),
  );

  Future<void> _forgetSupportingPerson(String person) async {
    await _db.customStatement('DELETE FROM supporting_record WHERE person=?', [
      person,
    ]);
    await _db.customStatement('DELETE FROM supporting_metric WHERE person=?', [
      person,
    ]);
  }
}
