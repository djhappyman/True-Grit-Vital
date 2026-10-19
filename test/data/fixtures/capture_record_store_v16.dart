// Synthetic v16 capture using the frozen pre-event package configuration.
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:true_grit_vital/data/record_store.dart';
import 'package:sqlite3/sqlite3.dart';

Future<void> main(List<String> args) async {
  final dir = await Directory.systemTemp.createTemp('vital-v16-capture-');
  RecordStore? activeStore;
  Database? activeDatabase;
  try {
    final path = '${dir.path}/fixture.db';
    final key = List.generate(32, (i) => i + 1);
    final store = await RecordStore.open(path: path, key: key, isNew: true);
    activeStore = store;
    final item = await store.createItem(
      commandId: 'v16-item',
      name: 'V15 synthetic source',
      form: 'tablet',
      unit: 'count',
      type: 'medicine',
    );
    final command = CombinedUseCommand(
      commandId: 'v16-combined',
      expectedGeneration: store.generation,
      personId: meId,
      expectedPersonRevision: 1,
      actualAt: DateTime.utc(2026, 10, 15, 12),
      components: [
        for (var i = 0; i < 2; i++)
          CombinedUseComponent(
            itemId: item.id,
            expectedItemRevision: 1,
            enteredAmount: '1',
            siteLabel: i == 0 ? 'V15 synthetic site' : null,
          ),
      ],
    );
    final group = await store.recordCombined(command);
    await store.correctCombined(
      CombinedCorrectionCommand(
        commandId: 'v16-group-time',
        actionId: group.actionId,
        personId: meId,
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
        actualAt: DateTime.utc(2026, 10, 16, 13),
        components: [
          for (final record in group.records)
            CombinedCorrectionComponent(
              recordId: record.id,
              expectedRevision: record.revision,
              physicalCorrection: null,
            ),
        ],
      ),
    );
    final bytes = Uint8List.fromList(
      'Synthetic protected fixture original'.codeUnits,
    );
    AttachmentJob job(String id) => AttachmentJob(
      id: id,
      generation: store.generation,
      personId: meId,
      expectedPersonRevision: 1,
      targetKind: AttachmentTargetKind.item,
      targetId: item.id,
      targetRevision: 1,
      attachmentId: '$id-attachment',
      versionId: '$id-version',
      name: 'Synthetic original',
      createdAt: DateTime.utc(2026, 10, 16),
    );
    final ready = job('fixture-ready');
    await store.beginAttachment(
      BeginAttachmentCommand(commandId: 'fixture-begin', job: ready),
    );
    await store.appendAttachmentChunk(
      commandId: 'fixture-chunk',
      jobId: ready.id,
      generation: store.generation,
      offset: 0,
      bytes: bytes,
    );
    final attachment = await store.publishAttachment(
      commandId: 'fixture-publish',
      jobId: ready.id,
      generation: store.generation,
      inspection: AttachmentInspection(
        mediaKind: AttachmentMediaKind.other,
        byteCount: bytes.length,
        sha256: sha256.convert(bytes).toString(),
        mimeType: 'application/octet-stream',
      ),
    );
    await store.pinAttachment(
      id: attachment.id,
      generation: store.generation,
      expectedRevision: 1,
      sessionId: 'fixture-session',
      purpose: 'preview',
    );
    final staged = job('fixture-staged');
    await store.beginAttachment(
      BeginAttachmentCommand(commandId: 'fixture-stage-begin', job: staged),
    );
    await store.appendAttachmentChunk(
      commandId: 'fixture-stage-chunk',
      jobId: staged.id,
      generation: store.generation,
      offset: 0,
      bytes: bytes,
    );

    final event = EventRecord(
      id: 'fixture-event',
      personId: meId,
      name: 'Synthetic fixture course',
      eventType: 'course',
      zoneId: 'Europe/London',
      revision: 1,
      plannedEnd: EventDate.day(CivilDate(2026, 10, 25)),
      memberships: [
        EventMembership(
          id: 'fixture-membership',
          itemId: item.id,
          personId: meId,
          effectiveFrom: DateTime.utc(2026, 10, 1),
          revision: 1,
        ),
      ],
    );
    final eventCommand = SaveEventCommand(
      commandId: 'v16-event',
      generation: store.generation,
      expectedRevision: null,
      event: event,
    );
    await store.saveEvent(
      eventCommand,
      membershipReview: await store.previewEventMembership(eventCommand),
    );
    await store.saveUsePeriod(
      SaveUsePeriodCommand(
        commandId: 'v16-period',
        generation: store.generation,
        expectedRevision: null,
        period: RecordedUsePeriod(
          id: 'fixture-use-period',
          personId: meId,
          itemId: item.id,
          revision: 1,
          start: EventDate(
            precision: EventDatePrecision.month,
            value: '2026-09',
          ),
          firstEver: true,
        ),
      ),
    );
    await store.applyEventItemDecision(
      commandId: 'v16-continue',
      review: await store.eventEndReview(event.id),
      itemId: item.id,
      continuePlan: true,
    );
    await store.prepareReminders(
      now: DateTime.utc(2026, 10, 20),
      observedZone: 'Europe/London',
      clockSample: null,
      adapterFingerprint: 'fixture',
    );
    await store.writeSetting('v16-capture', 'preserve');
    await store.close();
    final db = sqlite3.open(path);
    activeDatabase = db;
    db.execute("PRAGMA cipher='chacha20'");
    db.execute(
      'PRAGMA key="x\'${key.map((v) => v.toRadixString(16).padLeft(2, '0')).join()}\'"',
    );
    if (db.select('PRAGMA user_version').single.values.single != 16) {
      throw StateError('capture_requires_frozen_v16_package');
    }
    final out = StringBuffer(
      '-- Frozen populated schema16, generated from pre-event runtime. Synthetic data only.\nPRAGMA foreign_keys=OFF;\n',
    );
    final entities = db.select(
      "SELECT type,name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY CASE type WHEN 'table' THEN 0 WHEN 'index' THEN 1 ELSE 2 END,name",
    );
    for (final t in entities.where((r) => r['type'] == 'table')) {
      out.writeln('${t['sql']};');
      final name = t['name'] as String;
      final rows = db.select('SELECT * FROM "${name.replaceAll('"', '""')}"');
      String literal(Object? v) => v == null
          ? 'NULL'
          : v is Uint8List
          ? "X'${v.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}'"
          : v is num
          ? '$v'
          : "'${(v as String).replaceAll("'", "''")}'";
      for (final row in rows) {
        out.writeln(
          'INSERT INTO "$name" VALUES (${row.values.map(literal).join(',')});',
        );
      }
    }
    for (final e in entities.where((r) => r['type'] != 'table')) {
      out.writeln('${e['sql']};');
    }
    out.writeln('PRAGMA user_version=16;\nPRAGMA foreign_keys=ON;');
    File(args.single).writeAsStringSync(out.toString());
    db.close();
    activeDatabase = null;
    stdout.writeln('PASS captured populated schema16 ${args.single}');
  } finally {
    activeDatabase?.close();
    await activeStore?.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
