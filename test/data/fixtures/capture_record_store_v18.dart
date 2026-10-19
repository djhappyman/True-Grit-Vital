// Frozen synthetic v18 capture, run before schema19 edits.
// Starts from unchanged v17; adds an ordinary draft, another adult and
// an extra protected synthetic source with an immutable pin during deletion.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';

Future<void> main(List<String> args) async {
  final dir = await Directory.systemTemp.createTemp('vital-v18-capture-');
  final key = List.generate(32, (i) => i + 1);
  final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  Database open(String path) {
    final db = sqlite3.open(path);
    db.execute("PRAGMA cipher='chacha20'");
    db.execute("PRAGMA key=\"x'$hex'\"");
    db.execute('PRAGMA foreign_keys=ON');
    return db;
  }

  RecordStore? store;
  try {
    final path = '${dir.path}/db';
    final initial = open(path);
    initial.execute(
      File('test/data/fixtures/record_store_v17.sql').readAsStringSync(),
    );
    initial.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final other = await store.createProfile(
      commandId: 'v18-person',
      name: 'Me',
      adultConfirmed: true,
    );
    await store.createItem(
      commandId: 'v18-other-item',
      personId: other.id,
      name: 'Synthetic v18 source',
      form: 'tablet',
      unit: 'mg',
      type: 'medicine',
    );
    await store.saveDraft(
      OrdinaryDraft(
        id: 'v18-private-draft',
        generation: store.generation,
        operationId: 'v18-unsubmitted',
        kind: DraftKind.dose,
        personId: meId,
        personRevision: 1,
        targetId: '8b234b4f194700ef5b1e199a7d6e7f9d8a45eac6ccd63070',
        targetRevision: 1,
        fields: {'amount': '0.125'},
      ),
    );
    await store.close();
    store = null;
    final clone = open(path);
    final original = clone
        .select(
          "SELECT * FROM attachment_record WHERE id='fixture-ready-attachment'",
        )
        .single;
    final snapshot =
        jsonDecode(original['snapshot'] as String) as Map<String, dynamic>;
    snapshot['id'] = 'v18-deleting';
    snapshot['versionId'] = 'v18-deleting-version';
    // Typed validation before storing this invented migration-only source.
    AttachmentRecord.fromJson(snapshot);
    clone.execute('INSERT INTO attachment_record VALUES (?,?,?,?,?,?,?,?,?)', [
      'v18-deleting',
      original['person'],
      original['target_kind'],
      original['target'],
      'v18-deleting-version',
      original['revision'],
      original['state'],
      original['created_at'],
      jsonEncode(snapshot),
    ]);
    clone.execute(
      "INSERT INTO attachment_link SELECT 'v18-deleting',person,item,record FROM attachment_link WHERE attachment='fixture-ready-attachment'",
    );
    clone.execute(
      "INSERT INTO attachment_chunk SELECT 'v18-deleting-version',offset,bytes,digest FROM attachment_chunk WHERE version='fixture-ready-version'",
    );
    clone.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final source = (await store.attachmentById('v18-deleting'))!;
    await store.pinAttachment(
      id: source.id,
      generation: store.generation,
      expectedRevision: source.revision,
      purpose: 'backup',
      sessionId: 'v18-capture',
    );
    await store.deleteAttachment(
      commandId: 'v18-delete-pinned',
      attachment: source,
      expectedPersonRevision: 1,
    );
    await store.close();
    store = null;
    final db = open(path);
    try {
      if (db.select('PRAGMA user_version').single.values.single != 18) {
        throw StateError('capture_requires_schema18_source');
      }
      final out = StringBuffer(
        '-- Frozen populated schema18, synthetic data. Source hashes retained in 19 supporting evidence.\nPRAGMA foreign_keys=OFF;\n',
      );
      final entities = db.select(
        "SELECT type,name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY CASE type WHEN 'table' THEN 0 WHEN 'index' THEN 1 ELSE 2 END,name",
      );
      String literal(Object? value) => value == null
          ? 'NULL'
          : value is Uint8List
          ? "X'${value.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}'"
          : value is num
          ? '$value'
          : "'${(value as String).replaceAll("'", "''")}'";
      for (final table in entities.where((r) => r['type'] == 'table')) {
        out.writeln('${table['sql']};');
        final name = table['name'] as String;
        for (final row in db.select('SELECT * FROM "$name"')) {
          out.writeln(
            'INSERT INTO "$name" VALUES (${row.values.map(literal).join(',')});',
          );
        }
      }
      for (final entity in entities.where((r) => r['type'] != 'table')) {
        out.writeln('${entity['sql']};');
      }
      out.writeln('PRAGMA user_version=18;\nPRAGMA foreign_keys=ON;');
      File(args.single).writeAsStringSync(out.toString());
    } finally {
      db.close();
    }
  } finally {
    await store?.close();
    await dir.delete(recursive: true);
  }
}
