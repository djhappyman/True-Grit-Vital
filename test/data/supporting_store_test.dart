import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  late Directory directory;
  late String path;
  late RecordStore store;
  final key = List.generate(32, (i) => i + 1);
  Database raw() {
    final db = sqlite3.open(path);
    db.execute("PRAGMA cipher='chacha20'");
    db.execute(
      'PRAGMA key="x\'${key.map((v) => v.toRadixString(16).padLeft(2, '0')).join()}\'"',
    );
    db.execute('PRAGMA foreign_keys=ON');
    return db;
  }

  final provenance = SupportingProvenance(
    mode: SupportingProvenanceMode.manualTranscription,
    laboratoryId: 'lab',
    laboratoryName: 'Original laboratory',
    methodId: 'method',
    methodText: 'Original method',
    specimenId: 'serum',
    specimenText: 'Original specimen',
  );
  LabResultSnapshot result({
    String id = 'result',
    String metric = 'metric',
    SupportingValue? value,
    String? unit = 'mg/L',
    SupportingProvenance? source,
  }) => LabResultSnapshot(
    id: id,
    metricId: metric,
    markerName: 'Full original marker',
    value: value ?? SupportingValue.numeric('0.000'),
    unit: unit,
    referenceRange: SourceReferenceRange(
      originalText: 'Source supplied: 0 to 1',
      lower: SupportingRangeBound(value: ExactAmount.zero),
      upper: SupportingRangeBound(value: ExactAmount(BigInt.one)),
      unit: unit,
    ),
    provenance: source,
  );
  LabPanelSnapshot panel(
    String id, {
    String person = meId,
    List<LabResultSnapshot>? results,
    SupportingDate? date,
    SupportingDate? reported,
    SupportingProvenance? source,
    List<SupportingContextLink> links = const [],
  }) => LabPanelSnapshot(
    id: SupportingRecordId(id: id, personId: person),
    title: 'Original report',
    collectionDate:
        date ??
        SupportingDate.day(CivilDate(2026, 10, 1), zoneId: 'Europe/London'),
    reportDate: reported ?? SupportingDate.day(CivilDate(2026, 10, 4)),
    provenance: source ?? provenance,
    results: results ?? [result()],
    contextLinks: links,
  );
  Future<SupportingRevision> save(
    LabPanelSnapshot value, {
    String? operation,
    int? revision,
    bool fail = false,
  }) => store.saveLabPanel(
    SaveLabPanelCommand(
      commandId: operation ?? 'save-${value.id.id}-$revision',
      generation: store.generation,
      expectedPersonRevision: 1,
      expectedRevision: revision,
      panel: value,
    ),
    failBeforeCommit: fail,
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-supporting-');
    path = '${directory.path}/db';
    store = await RecordStore.open(path: path, key: key, isNew: true);
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test('manual panel retains original values ranges dates and replay through encrypted reopen', () async {
    final value = panel(
      'panel',
      results: [
        result(),
        result(
          id: 'negative',
          metric: 'signed',
          value: SupportingValue.numeric('-1.250e-3'),
        ),
        result(
          id: 'qualified',
          metric: 'qualified',
          value: SupportingValue.numeric('<0.10'),
        ),
        result(
          id: 'missing',
          metric: 'missing',
          value: SupportingValue.missing(originalText: 'Not reported'),
          unit: null,
        ),
      ],
    );
    final first = await save(value, operation: 'stable');
    final replay = await save(value, operation: 'stable');
    expect(replay.toJson(), first.toJson());
    expect(first.enteredAt.isAfter(DateTime.utc(2026, 10, 4)), isTrue);
    await store.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final reopened = (await store.supportingRecord(meId, 'panel'))!;
    expect(reopened.snapshot.toJson(), value.toJson());
    expect(reopened.snapshot.results.first.value.exactAmount, ExactAmount.zero);
    expect(reopened.snapshot.results.last.unit, isNull);
    expect(await store.recordCount(), 0);
    final db = raw();
    expect(
      db
          .select(
            'SELECT value_kind,numerator,denominator FROM supporting_result ORDER BY position',
          )
          .map((r) => r.values.toList())
          .toList(),
      [
        ['numeric', '0', '1'],
        ['numeric', '-1', '800'],
        ['numeric', '1', '10'],
        ['missing', null, null],
      ],
    );
    expect(db.select('PRAGMA foreign_key_check'), isEmpty);
    db.close();
  });

  test('correction void restore stale writes and payload conflicts retain audit without stock', () async {
    final first = await save(panel('panel'), operation: 'first');
    final changed = panel(
      'panel',
      date: SupportingDate.unknown(originalText: 'Collection unknown'),
      results: [result(value: SupportingValue.qualitative('Not detected'))],
    );
    final corrected = await save(changed, revision: 1, operation: 'correct');
    expect(corrected.enteredAt, first.enteredAt);
    expect(corrected.revision, 2);
    await expectLater(
      save(changed, revision: 1, operation: 'stale'),
      throwsA(isA<CommandConflict>()),
    );
    await expectLater(
      save(changed, operation: 'first'),
      throwsA(isA<CommandConflict>()),
    );
    final voided = await store.voidSupportingRecord(
      VoidSupportingRecordCommand(
        commandId: 'void',
        generation: store.generation,
        personId: meId,
        id: 'panel',
        expectedPersonRevision: 1,
        expectedRevision: 2,
      ),
    );
    expect(voided.isVoided, isTrue);
    expect(
      (await store.supportingRecords(SupportingQuery(personId: meId))).entries,
      isEmpty,
    );
    final restored = await store.voidSupportingRecord(
      VoidSupportingRecordCommand(
        commandId: 'restore',
        generation: store.generation,
        personId: meId,
        id: 'panel',
        expectedPersonRevision: 1,
        expectedRevision: 3,
        isVoided: false,
      ),
    );
    expect(restored.isVoided, isFalse);
    expect(
      (await store.supportingRevisions(meId, 'panel')).map((r) => r.revision),
      [4, 3, 2, 1],
    );
    expect(
      (await store.supportingRecord(
        meId,
        'panel',
        revision: 1,
      ))!.snapshot.toJson(),
      first.snapshot.toJson(),
    );
    final db = raw();
    expect(db.select('SELECT * FROM stock_movement'), isEmpty);
    expect(db.select('SELECT * FROM administration'), isEmpty);
    db.close();
  });

  test(
    'empty partial panels and observation components work with no file',
    () async {
      await save(
        panel(
          'empty',
          results: [],
          date: SupportingDate.partial(year: 2026, originalText: '2026'),
          reported: SupportingDate.unknown(),
        ),
      );
      final observation = ObservationSnapshot(
        id: SupportingRecordId(id: 'reading', personId: meId),
        title: 'Optional supporting reading',
        measuredDate: SupportingDate.unknown(),
        provenance: SupportingProvenance(
          mode: SupportingProvenanceMode.manualObservation,
        ),
        components: [
          result(
            metric: 'bp-systolic',
            unit: 'mmHg',
            value: SupportingValue.numeric('120'),
          ),
          result(
            id: 'diastolic',
            metric: 'bp-diastolic',
            unit: 'mmHg',
            value: SupportingValue.numeric('80'),
          ),
        ],
      );
      await store.saveObservation(
        SaveObservationCommand(
          commandId: 'reading',
          generation: store.generation,
          expectedPersonRevision: 1,
          observation: observation,
        ),
      );
      expect(
        (await store.supportingRecords(SupportingQuery(personId: meId)))
            .entries,
        hasLength(2),
      );
      expect(await store.attachments(personId: meId), isEmpty);
      expect(
        await store.supportingMetrics(
          personId: meId,
          kind: SupportingMetricKind.observation,
        ),
        hasLength(2),
      );
    },
  );

  test(
    'cross-person metric and context IDs reject through commands and SQL',
    () async {
      final other = await store.createProfile(
        commandId: 'other',
        name: 'Me',
        adultConfirmed: true,
      );
      final item = await store.createItem(
        commandId: 'other-item',
        personId: other.id,
        name: 'Owned item',
        form: 'tablet',
        unit: 'mg',
        type: 'medicine',
      );
      await save(
        panel(
          'owned',
          person: other.id,
          results: [result(metric: 'other-metric')],
        ),
      );
      await expectLater(
        save(panel('bad', results: [result(metric: 'other-metric')])),
        throwsA(isA<CommandConflict>()),
      );
      await expectLater(
        save(
          panel(
            'bad-context',
            links: [
              SupportingContextLink(
                id: item.id,
                personId: meId,
                kind: SupportingContextKind.item,
              ),
            ],
          ),
        ),
        throwsA(isA<CommandConflict>()),
      );
      await save(panel('mine'));
      final db = raw();
      expect(
        () => db.execute(
          "INSERT INTO supporting_context VALUES ('mine','me',1,?,NULL)",
          [item.id],
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => db.execute(
          "UPDATE supporting_result SET person=? WHERE record='mine'",
          [other.id],
        ),
        throwsA(isA<SqliteException>()),
      );
      db.execute('BEGIN');
      db.execute("UPDATE supporting_record SET revision=999 WHERE id='mine'");
      expect(() => db.execute('COMMIT'), throwsA(isA<SqliteException>()));
      db.execute('ROLLBACK');
      expect(db.select('PRAGMA foreign_key_check'), isEmpty);
      db.close();
    },
  );

  test('failed save and old generation leave no head projection metric or operation', () async {
    await expectLater(
      save(panel('failed'), operation: 'fail', fail: true),
      throwsA(anything),
    );
    expect(await store.supportingRecord(meId, 'failed'), isNull);
    expect(
      await store.supportingMetrics(
        personId: meId,
        kind: SupportingMetricKind.lab,
      ),
      isEmpty,
    );
    await expectLater(
      store.saveLabPanel(
        SaveLabPanelCommand(
          commandId: 'old',
          generation: 'old-generation',
          expectedPersonRevision: 1,
          panel: panel('old'),
        ),
      ),
      throwsA(isA<CommandConflict>()),
    );
    await save(panel('failed'), operation: 'fail');
    store.suspendWrites(true);
    await expectLater(
      store.supportingRecord(meId, 'failed'),
      throwsA(isA<CommandConflict>()),
    );
    store.suspendWrites(false);
  });

  test('tie-stable parent paging preserves unknown dates and bound cursor identity', () async {
    for (var i = 0; i < 55; i++) {
      await save(
        panel(
          'panel-${i.toString().padLeft(2, '0')}',
          date: i < 3
              ? SupportingDate.unknown()
              : SupportingDate.day(CivilDate(2026, 10, 1)),
        ),
      );
    }
    final query = SupportingQuery(personId: meId, limit: 7);
    var page = await store.supportingRecords(query);
    final seen = <String>[];
    while (true) {
      seen.addAll(page.entries.map((r) => r.id.id));
      if (!page.hasMore) break;
      page = await store.supportingRecords(
        query,
        cursor: SupportingCursor.decode(page.next!.encode()),
      );
    }
    expect(seen, hasLength(55));
    expect(seen.toSet(), hasLength(55));
    expect(seen.last, 'panel-02');
    final first = await store.supportingRecords(query);
    await expectLater(
      store.supportingRecords(
        SupportingQuery(personId: meId, kind: SupportingRecordKind.labPanel),
        cursor: first.next,
      ),
      throwsA(isA<TimelineCursorException>()),
    );
    final filtered = await store.supportingRecords(
      SupportingQuery(
        personId: meId,
        fromDate: CivilDate(2026, 10, 2),
        beforeDate: CivilDate(2026, 10, 3),
        includeUnknownDates: false,
      ),
    );
    expect(filtered.entries, isEmpty);
    final unknown = await store.supportingRecords(
      SupportingQuery(
        personId: meId,
        fromDate: CivilDate(2026, 10, 2),
        beforeDate: CivilDate(2026, 10, 3),
      ),
    );
    expect(unknown.entries, hasLength(3));
  });

  test('supporting trends retain provenance gaps and independent collection report entry basis', () async {
    await save(
      panel('known', results: [result(value: SupportingValue.numeric('1.25'))]),
    );
    await save(
      panel(
        'gap',
        results: [result(value: SupportingValue.numeric('<0.1'))],
        date: SupportingDate.day(CivilDate(2026, 10, 2)),
      ),
    );
    await save(
      panel(
        'unknown',
        results: [result(value: SupportingValue.missing())],
        date: SupportingDate.unknown(),
      ),
    );
    final query = SupportingTrendQuery(
      personId: meId,
      metricId: 'metric',
      fromDate: CivilDate(2026, 10, 1),
      beforeDate: CivilDate(2026, 10, 3),
    );
    final trend = await store.supportingTrend(query, requestGeneration: 7);
    expect(trend.requestGeneration, 7);
    expect(trend.groups.single.entries, hasLength(2));
    expect(trend.groups.single.entries.where((e) => e.isGap), hasLength(1));
    expect(trend.unpositioned, hasLength(1));
    final report = await store.supportingTrend(
      SupportingTrendQuery(
        personId: meId,
        metricId: 'metric',
        fromDate: CivilDate(2026, 10, 4),
        beforeDate: CivilDate(2026, 10, 5),
        dateBasis: SupportingDateBasis.report,
      ),
    );
    expect(report.groups.single.entries, hasLength(3));
    final entry = await store.supportingTrend(
      SupportingTrendQuery(
        personId: meId,
        metricId: 'metric',
        fromDate: CivilDate(2026, 10, 1),
        beforeDate: CivilDate(2026, 10, 3),
        dateBasis: SupportingDateBasis.entry,
      ),
    );
    expect(entry.groups, isEmpty);
  });

  test(
    'requested-zone exact dates include travel and DST boundaries',
    () async {
      await save(
        panel(
          'travel',
          date: SupportingDate.exact(
            DateTime.utc(2026, 10, 1, 0, 30),
            zoneId: 'UTC',
            utcOffsetMinutes: 0,
          ),
        ),
      );
      final query = SupportingTrendQuery(
        personId: meId,
        metricId: 'metric',
        fromDate: CivilDate(2026, 9, 30),
        beforeDate: CivilDate(2026, 10, 1),
        displayZone: 'America/Los_Angeles',
      );
      final page = await store.supportingTrend(query);
      expect(page.sourceCount, 1);
      expect(page.groups.single.entries.single.day, CivilDate(2026, 9, 30));
    },
  );

  test('narrow trend avoids lifetime cap while broad overflow returns no partial page', () async {
    await save(
      panel(
        'large',
        results: [for (var i = 0; i < 1000; i++) result(id: 'row-$i')],
      ),
    );
    final db = raw();
    db.execute('BEGIN');
    for (var i = 0; i < 10; i++) {
      final id = 'old-$i';
      db.execute(
        "INSERT INTO supporting_record SELECT ?,person,kind,revision,entered_at,entry_day,voided,'2025-10-01',NULL,report_day,report_at FROM supporting_record WHERE id='large'",
        [id],
      );
      db.execute(
        "INSERT INTO supporting_revision SELECT ?,person,revision,?,entered_at,json_set(snapshot,'\$.snapshot.id.id',?,'\$.snapshot.collectionDate.civilDate','2025-10-01','\$.operationId',?),json_set(header,'\$.snapshot.id.id',?,'\$.snapshot.collectionDate.civilDate','2025-10-01','\$.operationId',?) FROM supporting_revision WHERE record='large'",
        [id, 'op-$i', id, 'op-$i', id, 'op-$i'],
      );
      db.execute(
        "INSERT INTO supporting_result SELECT ?,person,revision,id,position,metric,unit,value_kind,numerator,denominator,snapshot FROM supporting_result WHERE record='large'",
        [id],
      );
    }
    db.execute('COMMIT');
    expect(db.select('PRAGMA foreign_key_check'), isEmpty);
    db.close();
    final narrow = await store.supportingTrend(
      SupportingTrendQuery(
        personId: meId,
        metricId: 'metric',
        fromDate: CivilDate(2026, 10, 1),
        beforeDate: CivilDate(2026, 10, 2),
      ),
    );
    expect(narrow.sourceCount, 1000);
    await expectLater(
      store.supportingTrend(
        SupportingTrendQuery(
          personId: meId,
          metricId: 'metric',
          fromDate: CivilDate(2025, 1, 1),
          beforeDate: CivilDate(2027, 1, 1),
        ),
      ),
      throwsA(isA<SupportingLimitException>()),
    );
  });

  test('supporting attachment has a real owned target and immutable pinned original', () async {
    final parent = await save(panel('panel'));
    final job = AttachmentJob(
      id: 'job',
      generation: store.generation,
      personId: meId,
      expectedPersonRevision: 1,
      targetKind: AttachmentTargetKind.supporting,
      targetId: 'panel',
      targetRevision: parent.revision,
      attachmentId: 'source',
      versionId: 'source-version',
      name: 'Original report',
      createdAt: DateTime.now().toUtc(),
    );
    await store.beginAttachment(
      BeginAttachmentCommand(commandId: 'begin', job: job),
    );
    final bytes = Uint8List.fromList('Original synthetic report'.codeUnits);
    await store.appendAttachmentChunk(
      commandId: 'chunk',
      jobId: 'job',
      generation: store.generation,
      offset: 0,
      bytes: bytes,
    );
    final published = await store.publishAttachment(
      commandId: 'publish',
      jobId: 'job',
      generation: store.generation,
      inspection: AttachmentInspection(
        mediaKind: AttachmentMediaKind.other,
        byteCount: bytes.length,
        sha256: sha256.convert(bytes).toString(),
        mimeType: 'application/octet-stream',
      ),
    );
    final pin = await store.pinAttachment(
      id: published.id,
      generation: store.generation,
      expectedRevision: published.revision,
      purpose: 'report',
    );
    final linked = panel(
      'panel',
      source: SupportingProvenance(
        mode: SupportingProvenanceMode.manualTranscription,
        sourceReferences: [
          SupportingSourceReference(
            id: published.id,
            personId: meId,
            version: published.revision,
            kind: SupportingSourceKind.attachment,
            contentVersionId: published.versionId,
            originalText: published.name,
          ),
        ],
      ),
    );
    await save(linked, revision: 1, operation: 'source-link');
    final db = raw();
    expect(
      db
          .select(
            "SELECT supporting,item,record FROM attachment_link WHERE attachment='source'",
          )
          .single
          .values
          .toList(),
      ['panel', null, null],
    );
    db.close();
    final renamed = await store.renameAttachment(
      commandId: 'rename',
      attachment: published,
      expectedPersonRevision: 1,
      name: 'New live name',
    );
    expect(pin.attachment.name, 'Original report');
    await store.deleteAttachment(
      commandId: 'delete',
      attachment: renamed,
      expectedPersonRevision: 1,
    );
    final chunks = await store.readAttachmentPin(pin).toList();
    expect(chunks.expand((v) => v).toList(), bytes);
    await store.releaseAttachmentPin(pin);
    expect(await store.attachmentById('source'), isNull);
    // Historical references remain auditable after the original disappears.
    await save(linked, revision: 2, operation: 'after-source-deletion');
    await store.voidSupportingRecord(
      VoidSupportingRecordCommand(
        commandId: 'void-unavailable',
        generation: store.generation,
        personId: meId,
        id: 'panel',
        expectedPersonRevision: 1,
        expectedRevision: 3,
      ),
    );
    await save(linked, revision: 4, operation: 'correct-voided');
    expect((await store.supportingRecord(meId, 'panel'))!.isVoided, isTrue);
    expect(
      (await store.supportingRecord(
        meId,
        'panel',
      ))!.snapshot.provenance.sourceReferences.single.originalText,
      'Original report',
    );
  });
  test(
    'supporting drafts stay private and profile deletion clears captured graph',
    () async {
      final item = await store.createItem(
        commandId: 'context-item',
        name: 'Source item',
        form: 'tablet',
        unit: 'mg',
        type: 'medicine',
      );
      final snapshot = panel(
        'owned',
        links: [
          SupportingContextLink(
            id: item.id,
            personId: meId,
            kind: SupportingContextKind.item,
          ),
        ],
      );
      final command = SaveLabPanelCommand(
        commandId: 'submitted-panel',
        generation: store.generation,
        expectedPersonRevision: 1,
        panel: snapshot,
      );
      await store.saveDraft(
        OrdinaryDraft(
          id: 'supporting-draft',
          generation: store.generation,
          operationId: command.commandId,
          kind: DraftKind.labPanel,
          personId: meId,
          personRevision: 1,
          targetId: null,
          targetRevision: null,
          fields: {
            'payload': jsonEncode(snapshot.toJson()),
            'frozen': jsonEncode(command.toJson()),
          },
          submitted: true,
        ),
      );
      expect(
        (await store.draftById('supporting-draft'))!.route,
        '/supporting/me/add-panel',
      );
      await store.close();
      store = await RecordStore.open(path: path, key: key, isNew: false);
      final restored = SaveLabPanelCommand.fromJson(
        jsonDecode(
          (await store.draftById('supporting-draft'))!.fields['frozen']!,
        ) as Map<String, dynamic>,
      );
      await store.saveLabPanel(restored);
      expect(await store.draftById('supporting-draft'), isNull);
      await store.deleteProfile(
        commandId: 'delete-owner',
        personId: meId,
        expectedRevision: 1,
      );
      expect(await store.supportingRecord(meId, 'owned'), isNull);
      final db = raw();
      expect(db.select('SELECT * FROM supporting_revision'), isEmpty);
      expect(db.select('SELECT * FROM supporting_result'), isEmpty);
      expect(db.select('SELECT * FROM supporting_metric'), isEmpty);
      expect(db.select('PRAGMA foreign_key_check'), isEmpty);
      db.close();
      await expectLater(
        store.saveLabPanel(restored),
        throwsA(isA<CommandConflict>()),
      );
    },
  );
}
