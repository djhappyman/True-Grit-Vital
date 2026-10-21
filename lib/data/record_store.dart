import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../backup/backup_worker.dart';
import '../domain/attachments.dart';
import '../domain/backup/backup.dart';
import '../domain/restore/restore.dart';
export '../domain/attachments.dart';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';

import '../domain/records.dart';
import '../domain/products/products.dart';
export '../domain/products/products.dart';
import '../domain/reminders/reminders.dart';
export '../domain/reminders/reminders.dart';
import '../domain/stock/stored_stock.dart';
export '../domain/stock/stored_stock.dart';
import '../domain/scheduling/daily_plan.dart';
import '../domain/scheduling/phase_plan.dart';
export '../domain/scheduling/phase_plan.dart';
import '../domain/scheduling/daily_resolver.dart';
import '../domain/scheduling/iana_clock.dart';
import '../domain/scheduling/interval_resolver.dart';
import '../domain/scheduling/stored_daily.dart';
import 'daily_codec.dart';
export '../domain/scheduling/daily_plan.dart';
export '../domain/scheduling/daily_resolver.dart';
export '../domain/scheduling/stored_daily.dart';
import '../domain/drafts/ordinary_draft.dart';
export '../domain/drafts/ordinary_draft.dart';
export '../domain/records.dart';
import '../domain/combined_use.dart';
export '../domain/combined_use.dart';
import '../domain/events/events.dart';
export '../domain/events/events.dart';
import '../domain/charts/charts.dart';
import '../domain/exports/exports.dart';
import '../domain/supporting/supporting.dart';
export '../domain/supporting/supporting.dart';
import '../domain/history/display_time.dart';
import '../domain/reports/reports.dart';
import '../domain/history/timeline_entry.dart';
import '../domain/history/timeline_page.dart';
import '../domain/history/timeline_query.dart';
export '../domain/history/display_time.dart';
export '../domain/reports/reports.dart';
export '../domain/history/timeline_entry.dart';
export '../domain/history/timeline_page.dart';
export '../domain/history/timeline_query.dart';
part 'daily_store.dart';
part 'interval_store.dart';
part 'pause_store.dart';
part 'phase_store.dart';
part 'catalogue_store.dart';
part 'stock_store.dart';
part 'product_store.dart';
part 'substance_status_store.dart';
part 'combined_store.dart';
part 'reminder_store.dart';
part 'event_store.dart';
part 'attachment_store.dart';
part 'history_store.dart';
part 'chart_store.dart';
part 'export_store.dart';
part 'supporting_store.dart';
part 'supporting_void_store.dart';
part 'report_store.dart';
part 'report_template_store.dart';
part 'backup_store.dart';
part 'restore_store.dart';

// No generated table layer is needed for this bounded, explicitly versioned SQL schema.
final class _Database extends drift.GeneratedDatabase {
  _Database(super.executor, this.initialGeneration);
  final String initialGeneration;
  @override
  int get schemaVersion => 21;
  @override
  Iterable<drift.TableInfo<drift.Table, Object?>> get allTables => const [];
  @override
  List<drift.DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  drift.MigrationStrategy get migration => drift.MigrationStrategy(
    onCreate: (_) => transaction(() async {
      for (final sql in schemaV1) {
        await customStatement(sql);
      }
      await customStatement('INSERT INTO dataset VALUES (?)', [
        initialGeneration,
      ]);
      await customStatement("INSERT INTO person VALUES ('me', 'Me')");
      await customStatement(settingsSchema);
      await _addCurrentIndexes();
      await _addProfiles();
      await customStatement(draftSchemaV6);
      for (final sql in dailySchemaV6) {
        await customStatement(sql);
      }
      for (final sql in catalogueSchemaV7) {
        await customStatement(sql);
      }
      for (final sql in stockSchemaV8) {
        await customStatement(sql);
      }
      for (final sql in reminderSchemaV9) {
        await customStatement(sql);
      }
      for (final sql in productSchemaV10) {
        await customStatement(sql);
      }
      for (final sql in intervalSchemaV11) {
        await customStatement(sql);
      }
      for (final sql in pauseSchemaV12) {
        await customStatement(sql);
      }
      for (final sql in phaseSchemaV13) {
        await customStatement(sql);
      }
      for (final sql in combinedSchemaV14) {
        await customStatement(sql);
      }
      for (final sql in eventSchemaV15) {
        await customStatement(sql);
      }
      for (final sql in attachmentSchemaV16) {
        await customStatement(sql);
      }
      await _migrateHistoryV17(this);
      await _migrateHistoryV18(this);
      await _migrateSupportingV19(this);
      await _migrateSupportingV20(this);
      await _migrateSupportingVoidV21(this);
    }),
    onUpgrade: (_, from, to) => transaction(() async {
      if (from < 1 || from > 20 || to != 21) {
        throw StateError('unsupported_schema');
      }
      if (from == 1) {
        await customStatement(settingsSchema);
      }
      if (from < 3) await _addCurrentIndexes();
      if (from < 4) await _addProfiles();
      if (from < 5) await customStatement(draftSchemaV5);
      if (from < 6) {
        await customStatement(
          'ALTER TABLE ordinary_draft RENAME TO ordinary_draft_v5',
        );
        await customStatement(draftSchemaV6);
        await customStatement(
          'INSERT INTO ordinary_draft SELECT * FROM ordinary_draft_v5',
        );
        await customStatement('DROP TABLE ordinary_draft_v5');
        for (final sql in dailySchemaV6) {
          await customStatement(sql);
        }
      }
      if (from < 7) {
        for (final sql in catalogueSchemaV7) {
          await customStatement(sql);
        }
      }
      if (from < 8) {
        for (final sql in stockSchemaV8) {
          await customStatement(sql);
        }
      }
      if (from < 9) {
        for (final sql in reminderSchemaV9) {
          await customStatement(sql);
        }
      }
      if (from < 10) {
        for (final sql in productSchemaV10) {
          await customStatement(sql);
        }
      }
      if (from < 11) {
        for (final sql in intervalSchemaV11) {
          await customStatement(sql);
        }
      }
      if (from < 12) {
        for (final sql in pauseSchemaV12) {
          await customStatement(sql);
        }
      }
      if (from < 13) {
        for (final sql in phaseSchemaV13) {
          await customStatement(sql);
        }
      }
      if (from < 14) {
        for (final sql in combinedSchemaV14) {
          await customStatement(sql);
        }
      }
      if (from < 15) {
        for (final sql in eventSchemaV15) {
          await customStatement(sql);
        }
      }
      if (from < 16) {
        for (final sql in attachmentSchemaV16) {
          await customStatement(sql);
        }
      }
      if (from < 17) await _migrateHistoryV17(this);
      if (from < 18) await _migrateHistoryV18(this);
      if (from < 19) await _migrateSupportingV19(this);
      if (from < 20) await _migrateSupportingV20(this);
      if (from < 21) await _migrateSupportingVoidV21(this);
    }),
  );
  Future<void> _addProfiles() async {
    for (final sql in profileSchemaV4) {
      await customStatement(sql);
    }
  }

  Future<void> _addCurrentIndexes() async {
    await customStatement(
      'ALTER TABLE administration ADD COLUMN actual INTEGER NOT NULL DEFAULT 0',
    );
    await customStatement(
      'UPDATE administration SET actual=(SELECT actual FROM revision WHERE record=administration.id AND person=administration.person AND revision=administration.revision)',
    );
    await customStatement(
      'CREATE INDEX administration_feed ON administration(person,actual DESC,id)',
    );
    await customStatement(
      'CREATE INDEX administration_item_feed ON administration(person,item,actual DESC,id)',
    );
  }
}

const profileSchemaV4 = [
  'ALTER TABLE person ADD COLUMN archived INTEGER NOT NULL DEFAULT 0 CHECK(archived IN (0,1))',
  'ALTER TABLE person ADD COLUMN revision INTEGER NOT NULL DEFAULT 1 CHECK(revision > 0)',
  'ALTER TABLE person ADD COLUMN adult_confirmed INTEGER NOT NULL DEFAULT 0 CHECK(adult_confirmed IN (0,1))',
  'ALTER TABLE person ADD COLUMN report_name TEXT',
  'ALTER TABLE person ADD COLUMN relationship TEXT',
  'ALTER TABLE person ADD COLUMN notes TEXT',
  'ALTER TABLE person ADD COLUMN reminders_stopped INTEGER NOT NULL DEFAULT 0 CHECK(reminders_stopped IN (0,1))',
  'CREATE INDEX person_active ON person(archived,id)',
  'CREATE INDEX administration_everyone ON administration(actual DESC,id)',
  'CREATE TABLE reminder_stop(person TEXT PRIMARY KEY, revision INTEGER NOT NULL) STRICT',
  "CREATE TABLE revision_source(record TEXT NOT NULL, revision INTEGER NOT NULL, source TEXT NOT NULL CHECK(source IN ('unspecified','selfReported','recordedOnBehalf')), PRIMARY KEY(record,revision), FOREIGN KEY(record,revision) REFERENCES revision(record,revision) ON DELETE CASCADE) STRICT",
];

const draftSchemaV5 =
    'CREATE TABLE ordinary_draft(id TEXT PRIMARY KEY,generation TEXT NOT NULL,operation TEXT NOT NULL UNIQUE,kind TEXT NOT NULL CHECK(kind IN (\'item\',\'dose\',\'correction\',\'profile\')),person TEXT REFERENCES person(id),person_revision INTEGER,target TEXT,target_revision INTEGER,snapshot TEXT NOT NULL) STRICT';

final draftSchemaV6 = draftSchemaV5.replaceFirst(
  "'profile'",
  "'profile','dailyPlan'",
);

const settingsSchema =
    'CREATE TABLE setting(key TEXT PRIMARY KEY, value TEXT NOT NULL) STRICT';
const schemaV1 = [
  'CREATE TABLE dataset(generation TEXT PRIMARY KEY) STRICT',
  'CREATE TABLE person(id TEXT PRIMARY KEY, name TEXT NOT NULL) STRICT',
  '''CREATE TABLE item(id TEXT PRIMARY KEY, person TEXT NOT NULL REFERENCES person(id),
    name TEXT NOT NULL, form TEXT NOT NULL, unit TEXT NOT NULL CHECK(unit IN ('mg','ml','count')),
    type TEXT NOT NULL, UNIQUE(id,person)) STRICT''',
  '''CREATE TABLE administration(id TEXT PRIMARY KEY, person TEXT NOT NULL,
    item TEXT NOT NULL, revision INTEGER NOT NULL CHECK(revision > 0),
    UNIQUE(id,person), FOREIGN KEY(item,person) REFERENCES item(id,person)) STRICT''',
  '''CREATE TABLE revision(record TEXT NOT NULL, person TEXT NOT NULL, revision INTEGER NOT NULL,
    name TEXT NOT NULL, form TEXT NOT NULL, unit TEXT NOT NULL CHECK(unit IN ('mg','ml','count')),
    type TEXT NOT NULL, amount INTEGER NOT NULL CHECK(amount > 0 AND amount <= 9000000000000000),
    entered TEXT NOT NULL, actual INTEGER NOT NULL, entered_at INTEGER NOT NULL,
    voided INTEGER NOT NULL CHECK(voided IN (0,1)), PRIMARY KEY(record,revision),
    FOREIGN KEY(record,person) REFERENCES administration(id,person)) STRICT''',
  '''CREATE TABLE operation(id TEXT PRIMARY KEY, payload TEXT NOT NULL, result TEXT NOT NULL) STRICT''',
  'CREATE INDEX administration_person ON administration(person,id)',
  'CREATE INDEX revision_actual ON revision(actual,record)',
];

enum DraftOperationStatus { pending, committed, invalidated }

/// One actual item type present in a scoped item collection, with the number
/// of items that share it under the same search used by the collection list.
/// A null [typeId] marks an item whose type row is missing; it can stay in the
/// whole-collection view but has no filter to reach.
final class SubstanceTypeSummary {
  const SubstanceTypeSummary({
    required this.typeId,
    required this.typeName,
    required this.count,
  });
  final String? typeId;
  final String typeName;
  final int count;
}

/// One immutable checkpoint captured while unlocked. Its one-shot persistence
/// may finish behind the privacy cover, without granting clinical write access.
final class DraftCheckpoint {
  DraftCheckpoint._(this._persist);
  final Future<void> Function() _persist;
  Future<void>? _pending;
  Future<void> persist() => _pending ??= _persist();
}

final class RecordStore {
  RecordStore._(this._db, this.generation, this._key, this.databasePath);
  final _Database _db;
  final String generation;
  final String databasePath;
  // Retained only for an authenticated whole-dataset backup. Never log or
  // expose this key; the database connection already requires it in memory.
  final List<int> _key;
  final _changes = StreamController<void>.broadcast();
  final _draftChanges = StreamController<void>.broadcast();
  bool _closed = false;
  bool _writesSuspended = false;
  final _capturedDraftOperations = <String, Set<String>>{};

  /// Draft identities adopted by an atomic migration: legacy draft key -> the
  /// stored operation that now belongs to the adopted row at another key. A
  /// late capture or discard for that identity must not register a tombstone
  /// alias under the legacy key or silently rewrite the adopted row, while the
  /// legacy key itself stays free for fresh drafts with their own operations.
  final _migratedDraftIds =
      <String, ({String operationId, String destinationId})>{};
  bool get writesSuspended => _writesSuspended;
  void suspendWrites(bool value) => _writesSuspended = value;
  void _requireWritable() {
    if (_closed || _writesSuspended) throw const CommandConflict('app_locked');
  }

  void _fenceMigratedDraftIdentity(
    String legacyId,
    String operationId,
    String destinationId,
  ) {
    _migratedDraftIds[legacyId] = (
      operationId: operationId,
      destinationId: destinationId,
    );
  }

  final _watchReads = <Future<void>>{};
  final _draftWrites = <Future<void>>{};
  final _reminderWork = <Future<void>>{};
  Future<void>? _closing;

  static Future<RecordStore> open({
    required String path,
    required List<int> key,
    required bool isNew,
  }) async {
    if (key.length != 32 || key.any((b) => b < 0 || b > 255)) {
      throw StateError('invalid_key');
    }
    final file = File(path);
    if (isNew ? await file.exists() : !await file.exists()) {
      throw StateError('dataset_state');
    }
    if (!isNew) {
      if (await file.length() < 512) {
        throw StateError('truncated_dataset');
      }
      final handle = await file.open();
      final header = await handle.read(16);
      await handle.close();
      if (utf8
          .decode(header, allowMalformed: true)
          .startsWith('SQLite format 3')) {
        throw StateError('plaintext_dataset');
      }
    }
    final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    final db = _Database(
      NativeDatabase.createInBackground(
        file,
        setup: (raw) {
          if (raw.select('PRAGMA cipher').isEmpty) {
            throw StateError('encryption_unavailable');
          }
          raw.execute("PRAGMA cipher = 'chacha20'");
          raw.execute("PRAGMA key = \"x'$hex'\"");
          raw.select('SELECT count(*) FROM sqlite_master');
          if (!isNew &&
              raw.select('PRAGMA integrity_check').single.values.single !=
                  'ok') {
            throw StateError('corrupt_dataset');
          }
          raw.execute('PRAGMA foreign_keys = ON');
          raw.execute('PRAGMA busy_timeout = 5000');
          raw.execute('PRAGMA synchronous = FULL');
          raw.execute('PRAGMA temp_store = MEMORY');
          if (raw.select('PRAGMA foreign_keys').single.values.single != 1) {
            throw StateError('constraints_unavailable');
          }
          if (!isNew &&
              raw.select('PRAGMA user_version').single.values.single == 0) {
            throw StateError('uninitialised_dataset');
          }
          if (!isNew &&
              (raw.select('SELECT generation FROM dataset').length != 1 ||
                  raw.select("SELECT id FROM person WHERE id='me'").length !=
                      1 ||
                  raw
                      .select(
                        'SELECT a.id FROM administration a LEFT JOIN revision r ON r.record=a.id AND r.person=a.person AND r.revision=a.revision WHERE r.record IS NULL LIMIT 1',
                      )
                      .isNotEmpty ||
                  raw.select('PRAGMA foreign_key_check').isNotEmpty)) {
            throw StateError('invalid_dataset_identity');
          }
        },
      ),
      newCommandId(),
    );
    try {
      final rows = await db
          .customSelect('SELECT generation FROM dataset')
          .get();
      if (rows.length != 1 ||
          (await db.customSelect('PRAGMA integrity_check').get()).single
                  .read<String>('integrity_check') !=
              'ok' ||
          (await db.customSelect('PRAGMA foreign_key_check').get())
              .isNotEmpty) {
        throw StateError('invalid_dataset');
      }
      final store = RecordStore._(
        db,
        rows.single.read<String>('generation'),
        List<int>.unmodifiable(key),
        file.path,
      );
      store._writesSuspended = await store.readSetting('app_lock') == 'true';
      return store;
    } catch (_) {
      await db.close();
      rethrow;
    }
  }

  Future<List<Map<String, Object?>>> _rows(
    String sql, [
    List<Object?> args = const [],
  ]) async =>
      (await _db
              .customSelect(
                sql,
                variables: args.map((v) => drift.Variable(v)).toList(),
              )
              .get())
          .map((r) => r.data)
          .toList();

  Future<Map<String, Object?>> _command(
    String id,
    List<Object?> payload,
    Future<Map<String, Object?>> Function() body, {
    bool failBeforeCommit = false,
    Future<void> Function()? beforeCommit,
  }) async {
    if (_closed || id.isEmpty || id.length > 256) {
      throw StateError('invalid_command');
    }
    _requireWritable();
    final identity = jsonEncode([generation, ...payload]);
    final result = await _db.transaction(() async {
      // Acquire the write lock before any revision/idempotency reads, including on independent connections.
      await _db.customStatement('UPDATE dataset SET generation=generation');
      if ((await _rows('SELECT generation FROM dataset'))
              .single['generation'] !=
          generation) {
        throw const CommandConflict('generation');
      }
      final prior = await _rows('SELECT * FROM operation WHERE id=?', [id]);
      if (prior.isNotEmpty) {
        if (prior.single['result'] == '{"invalidated":true}') {
          throw const CommandConflict('deleted_context');
        }
        if (prior.single['payload'] != identity) {
          throw const CommandConflict('payload');
        }
        await _db.customStatement(
          'DELETE FROM ordinary_draft WHERE operation=?',
          [id],
        );
        return {
          ...jsonDecode(prior.single['result'] as String)
              as Map<String, dynamic>,
          'replay': true,
        };
      }
      _requireWritable();
      final result = await body();
      await _db.customStatement('INSERT INTO operation VALUES (?,?,?)', [
        id,
        identity,
        jsonEncode(result),
      ]);
      await _db.customStatement(
        'DELETE FROM ordinary_draft WHERE operation=?',
        [id],
      );
      await beforeCommit?.call();
      _requireWritable();
      if (failBeforeCommit) {
        throw StateError('injected_commit_failure');
      }
      return result;
    });
    _changes.add(null);
    _draftChanges.add(null);
    return result;
  }

  /// Activates the single-user product boundary before a live installation
  /// becomes available. The older ownership schema remains readable by the
  /// archive inspector and regression fixtures. It is not a profile manager.
  /// Never merge or silently delete an unexpected older person's records.
  Future<void> enableSingleUser() async {
    await _db.transaction(() async {
      final people = await _rows('SELECT id,archived FROM person LIMIT 2');
      if (people.length != 1 ||
          people.single['id'] != meId ||
          people.single['archived'] != 0) {
        throw StateError('single_user_required');
      }
      await _db.customStatement(
        "DELETE FROM setting WHERE key='browsing_scope'",
      );
      // Also stop direct repository calls from adding a second person after
      // bootstrap. These guards travel with the protected backup snapshot.
      await _db.customStatement("""
        CREATE TRIGGER IF NOT EXISTS single_user_insert
        BEFORE INSERT ON person WHEN NEW.id <> 'me'
        BEGIN SELECT RAISE(ABORT, 'single_user_required'); END
      """);
      await _db.customStatement("""
        CREATE TRIGGER IF NOT EXISTS single_user_update
        BEFORE UPDATE ON person WHEN NEW.id <> 'me' OR NEW.archived <> 0
        BEGIN SELECT RAISE(ABORT, 'single_user_required'); END
      """);
      await _db.customStatement("""
        CREATE TRIGGER IF NOT EXISTS single_user_delete
        BEFORE DELETE ON person
        BEGIN SELECT RAISE(ABORT, 'single_user_required'); END
      """);
    });
  }

  AdultProfile _profile(Map<String, Object?> r) => AdultProfile(
    id: r['id'] as String,
    name: r['name'] as String,
    revision: r['revision'] as int,
    isArchived: r['archived'] == 1,
    adultConfirmed: r['adult_confirmed'] == 1,
    remindersStopped: r['reminders_stopped'] == 1,
    reportName: r['report_name'] as String?,
    relationship: r['relationship'] as String?,
    notes: r['notes'] as String?,
    alreadyCommitted: r['replay'] == true,
  );

  Future<List<AdultProfile>> profiles({
    bool includeArchived = false,
  }) async => (await _rows(
    'SELECT * FROM person ${includeArchived ? '' : 'WHERE archived=0'} ORDER BY name,id',
  )).map(_profile).toList();
  Future<AdultProfile?> profileById(String personId) async {
    final rows = await _rows('SELECT * FROM person WHERE id=?', [personId]);
    return rows.isEmpty ? null : _profile(rows.single);
  }

  Stream<List<AdultProfile>> watchProfiles({bool includeArchived = false}) =>
      _watch(() => profiles(includeArchived: includeArchived));

  Future<Map<String, Object?>> _activeOwner(String id, int? expected) async {
    final rows = await _rows('SELECT * FROM person WHERE id=?', [id]);
    if (rows.isEmpty ||
        rows.single['archived'] == 1 ||
        (expected != null && rows.single['revision'] != expected)) {
      throw const CommandConflict('person_context');
    }
    return rows.single;
  }

  void _profileFields(
    String name,
    bool adultConfirmed,
    List<String?> optional,
  ) {
    if (!adultConfirmed) throw const FormatException('adult_confirmation');
    if (name.trim().isEmpty ||
        name.length > 500 ||
        optional.any((v) => v != null && v.length > 4000)) {
      throw const FormatException('profile_fields');
    }
  }

  Future<AdultProfile> createProfile({
    required String commandId,
    required String name,
    required bool adultConfirmed,
    String? reportName,
    String? relationship,
    String? notes,
  }) async {
    _profileFields(name, adultConfirmed, [reportName, relationship, notes]);
    return _profile(
      await _command(
        commandId,
        [
          'profile_create',
          name,
          adultConfirmed,
          reportName,
          relationship,
          notes,
        ],
        () async {
          final id = newCommandId();
          await _db.customStatement(
            'INSERT INTO person(id,name,adult_confirmed,report_name,relationship,notes) VALUES (?,?,1,?,?,?)',
            [id, name, reportName, relationship, notes],
          );
          return (await _rows('SELECT * FROM person WHERE id=?', [id])).single;
        },
      ),
    );
  }

  Future<AdultProfile> editProfile({
    required String commandId,
    required String personId,
    required int expectedRevision,
    required String name,
    required bool adultConfirmed,
    String? reportName,
    String? relationship,
    String? notes,
  }) async {
    _profileFields(name, adultConfirmed, [reportName, relationship, notes]);
    return _profile(
      await _command(
        commandId,
        [
          'profile_edit',
          personId,
          expectedRevision,
          name,
          adultConfirmed,
          reportName,
          relationship,
          notes,
        ],
        () async {
          final current = await profileById(personId);
          if (current == null || current.revision != expectedRevision) {
            throw const CommandConflict('person_context');
          }
          await _db.customStatement(
            'UPDATE person SET name=?,adult_confirmed=1,report_name=?,relationship=?,notes=?,revision=revision+1 WHERE id=?',
            [name, reportName, relationship, notes, personId],
          );
          return (await _rows('SELECT * FROM person WHERE id=?', [
            personId,
          ])).single;
        },
      ),
    );
  }

  Future<AdultProfile> archiveProfile({
    required String commandId,
    required String personId,
    required int expectedRevision,
  }) => _setArchived(commandId, personId, expectedRevision, true);
  Future<AdultProfile> reactivateProfile({
    required String commandId,
    required String personId,
    required int expectedRevision,
  }) => _setArchived(commandId, personId, expectedRevision, false);
  Future<AdultProfile> _setArchived(
    String commandId,
    String personId,
    int expectedRevision,
    bool archived,
  ) async => _profile(
    await _command(
      commandId,
      ['profile_archive', personId, expectedRevision, archived],
      () async {
        final current = await profileById(personId);
        if (current == null ||
            current.isMe ||
            current.revision != expectedRevision ||
            current.isArchived == archived) {
          throw const CommandConflict('person_context');
        }
        await _db.customStatement(
          'UPDATE person SET archived=?,revision=revision+1,reminders_stopped=1 WHERE id=?',
          [archived ? 1 : 0, personId],
        );
        await _db.customStatement(
          'UPDATE stock_container SET notice_active=? WHERE person=?',
          [archived ? 0 : 1, personId],
        );
        await _stopReminders(personId, expectedRevision + 1);
        if (archived) await _resetScope(personId);
        return (await _rows('SELECT * FROM person WHERE id=?', [
          personId,
        ])).single;
      },
    ),
  );
  Future<void> _stopReminders(String personId, int revision) async {
    await _stopPersonReminderRequests(personId);
    await _db.customStatement(
      'UPDATE daily_reminder_intent SET stopped=1,revision=revision+1 WHERE person=?',
      [personId],
    );
    await _db.customStatement(
      'INSERT INTO reminder_stop VALUES (?,?) ON CONFLICT(person) DO UPDATE SET revision=excluded.revision',
      [personId, revision],
    );
  }

  Future<Map<String, int>> reminderStopIntents() async => {
    for (final r in await _rows('SELECT * FROM reminder_stop'))
      r['person'] as String: r['revision'] as int,
  };
  Future<void> _resetScope(String personId) async {
    if (await readSetting('browsing_scope') == personId) {
      await _db.customStatement(
        "UPDATE setting SET value='everyone' WHERE key='browsing_scope'",
      );
    }
  }

  Future<void> deleteProfile({
    required String commandId,
    required String personId,
    required int expectedRevision,
  }) async {
    await _command(
      commandId,
      ['profile_delete', personId, expectedRevision],
      () async {
        final current = await profileById(personId);
        if (current == null || current.revision != expectedRevision) {
          throw const CommandConflict('person_context');
        }
        // Remove cached command payloads/results for this ownership graph, otherwise replay could resurrect deleted sensitive content.
        await _db.customStatement(
          "UPDATE operation SET payload='[]',result='{\"invalidated\":true}' WHERE (json_extract(payload,'\$[1]') IN ('item','record','revise','profile_edit','profile_archive','profile_delete','daily_plan','daily_action','daily_undo','daily_clock','stock_container','stock_adjust','stock_notices','product_label','supporting_save','supporting_void') AND json_extract(payload,'\$[2]')=?) OR json_extract(result,'\$.person')=? OR (json_extract(payload,'\$[1]')='profile_create' AND json_extract(result,'\$.id')=?)",
          [personId, personId, personId],
        );
        await _db.customStatement(
          'INSERT INTO operation SELECT operation,\'[]\',\'{"invalidated":true}\' FROM ordinary_draft WHERE person=? AND operation<>? ON CONFLICT(id) DO NOTHING',
          [personId, commandId],
        );
        await _db.customStatement('DELETE FROM ordinary_draft WHERE person=?', [
          personId,
        ]);
        await _forgetReminderPerson(personId);
        await _forgetAttachmentPerson(personId);
        await _forgetSupportingPerson(personId);
        await _forgetEventPerson(personId);
        await _db.customStatement('DELETE FROM daily_plan WHERE person=?', [
          personId,
        ]);
        await _db.customStatement(
          'DELETE FROM stock_container WHERE person=?',
          [personId],
        );
        await _db.customStatement(
          'DELETE FROM combined_action WHERE person=?',
          [personId],
        );
        await _db.customStatement('DELETE FROM revision WHERE person=?', [
          personId,
        ]);
        await _db.customStatement('DELETE FROM administration WHERE person=?', [
          personId,
        ]);
        await _db.customStatement('DELETE FROM item WHERE person=?', [
          personId,
        ]);
        await _db.customStatement(
          'DELETE FROM personal_item_type WHERE person=?',
          [personId],
        );
        await _stopReminders(personId, expectedRevision + 1);
        if (personId == meId) {
          await _db.customStatement(
            'UPDATE person SET revision=revision+1,reminders_stopped=1 WHERE id=?',
            [personId],
          );
        } else {
          await _db.customStatement('DELETE FROM person WHERE id=?', [
            personId,
          ]);
        }
        await _resetScope(personId);
        return {'person': personId, 'deleted': true};
      },
    );
    // Association/ownership deletion is already committed. Reclaim only a
    // bounded batch of known unpinned protected content outside that command.
    while (!await _cleanupAttachmentDeletes()) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<FeedScope> readBrowsingScope() async {
    final value = await readSetting('browsing_scope');
    if (value == null || value == 'everyone') return const FeedScope.everyone();
    if (value == meId) return const FeedScope.me();
    final person = await profileById(value);
    return person == null || person.isArchived
        ? const FeedScope.everyone()
        : FeedScope.person(value);
  }

  Future<void> saveBrowsingScope(FeedScope scope) async {
    _requireWritable();
    await _db.transaction(() async {
      await _db.customStatement('UPDATE dataset SET generation=generation');
      if (!scope.isEveryone) await _activeOwner(scope.personId!, null);
      await _db.customStatement(
        'INSERT INTO setting VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
        ['browsing_scope', scope.personId ?? 'everyone'],
      );
    });
    _changes.add(null);
  }

  Stream<FeedScope> watchBrowsingScope() => _watch(readBrowsingScope);

  Future<SubstanceItem> createItem({
    required String commandId,
    required String name,
    required String form,
    required String unit,
    required String type,
    String personId = meId,
    int? expectedPersonRevision,
    String? typeId,
    int? expectedTypeRevision,
    CatalogueSnapshot? catalogueSnapshot,
    List<ProductComponent>? productComponents,
  }) async {
    if (productComponents != null) {
      if (unit != 'ml') throw const FormatException('product_volume_unit');
      ProductLabelSnapshot(
        personId: personId,
        itemId: 'validation',
        revision: 1,
        components: productComponents,
      );
    }
    final productLimit = catalogueSnapshot == null ? 500 : 2048;
    if ([name, form].any((s) => s.trim().isEmpty || s.length > productLimit) ||
        type.trim().isEmpty ||
        type.length > 500 ||
        !['mg', 'ml', 'count'].contains(unit)) {
      throw const FormatException('item_fields');
    }
    final r = await _command(
      commandId,
      [
        'item',
        personId,
        name,
        form,
        unit,
        type,
        ?expectedPersonRevision,
        if (typeId != null ||
            expectedTypeRevision != null ||
            catalogueSnapshot != null)
          {
            'typeId': typeId,
            'typeRevision': expectedTypeRevision,
            'catalogue': catalogueSnapshot?.toJson(),
          },
        if (productComponents != null)
          productComponents.map((c) => c.toJson()).toList(),
      ],
      () async {
        await _activeOwner(personId, expectedPersonRevision ?? 1);
        final selectedType = await _resolveItemType(personId, typeId, type);
        if (expectedTypeRevision != null &&
            selectedType.revision != expectedTypeRevision) {
          throw const CommandConflict('revision');
        }
        if (catalogueSnapshot != null &&
            (name != catalogueSnapshot.product.name ||
                (catalogueSnapshot.product.form.isNotEmpty &&
                    form != catalogueSnapshot.product.form))) {
          throw const FormatException('catalogue_selection');
        }
        final snapshot = catalogueSnapshot == null
            ? null
            : jsonEncode(catalogueSnapshot.toJson());
        if (snapshot != null && snapshot.length > 32000) {
          throw const FormatException('catalogue_snapshot_bound');
        }
        final id = newCommandId();
        await _db.customStatement(
          'INSERT INTO item(id,person,name,form,unit,type,type_id,catalogue_snapshot) VALUES (?,?,?,?,?,?,?,?)',
          [
            id,
            personId,
            name,
            form,
            unit,
            selectedType.name,
            selectedType.id,
            snapshot,
          ],
        );
        if (productComponents != null) {
          await _insertProductLabel(
            ProductLabelSnapshot(
              personId: personId,
              itemId: id,
              revision: 1,
              components: productComponents,
            ),
          );
        }
        return {
          'id': id,
          'person': personId,
          'name': name,
          'form': form,
          'unit': unit,
          'type': selectedType.name,
          'type_id': selectedType.id,
          'item_revision': 1,
          'catalogue_snapshot': snapshot,
        };
      },
    );
    return _item(r);
  }

  SubstanceItem _item(Map<String, Object?> r) => SubstanceItem(
    id: r['id'] as String,
    personId: r['person'] as String,
    name: r['name'] as String,
    form: r['form'] as String,
    unit: r['unit'] as String,
    type: r['type'] as String,
    alreadyCommitted: r['replay'] == true,
    typeId: r['type_id'] as String?,
    revision: r['item_revision'] as int? ?? 1,
    catalogueSnapshot: _catalogueSnapshot(r['catalogue_snapshot']),
  );
  /// Keeps SQL wildcard input literal for `LIKE`: `\\`, `%` and `_` are
  /// escaped and the query runs with `ESCAPE '\'`. Other characters (including
  /// apostrophes) stay bound as a parameter.
  static String _escapeLike(String search) => search
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');

  List<Object?> _itemFilterArgs(
    String? personId,
    FeedScope? scope,
    String? search,
    String? typeId,
  ) => [
    if (scope?.isEveryone != true) scope?.personId ?? personId,
    if ((search?.trim().isNotEmpty ?? false))
      '%${_escapeLike(search!.trim())}%',
    ?typeId,
  ];

  String _itemFilterSql(
    String? personId,
    FeedScope? scope,
    String? search,
    String? typeId,
  ) {
    final conditions = [
      scope?.isEveryone == true
          ? 'person IN (SELECT id FROM person WHERE archived=0)'
          : 'person=?',
      if (search?.trim().isNotEmpty ?? false) r"name LIKE ? ESCAPE '\'",
      if (typeId != null) 'type_id=?',
    ];
    return conditions.join(' AND ');
  }

  Future<List<SubstanceItem>> items({
    String personId = meId,
    FeedScope? scope,
    String? search,
    String? typeId,
    int limit = 100,
    int offset = 0,
  }) async {
    // Search and the optional type filter run over the whole scoped
    // collection, so results never depend on how many cards are loaded.
    _pageBounds(limit, offset);
    return (await _rows(
      'SELECT * FROM item WHERE ${_itemFilterSql(personId, scope, search, typeId)} ORDER BY name,id LIMIT ? OFFSET ?',
      [
        ..._itemFilterArgs(personId, scope, search, typeId),
        limit,
        offset,
      ],
    )).map(_item).toList();
  }

  Stream<SubstanceItem?> watchItemById(String id) => _watch(() => itemById(id));
  Stream<UseRecord?> watchRecordById(String id, String personId) =>
      _watch(() => recordById(id, personId: personId));
  Future<SubstanceItem?> itemById(String itemId, {String? personId}) async {
    final rows = await _rows(
      'SELECT * FROM item WHERE id=?${personId == null ? '' : ' AND person=?'}',
      [itemId, ?personId],
    );
    return rows.isEmpty ? null : _item(rows.single);
  }

  Future<UseRecord> record({
    required String commandId,
    required String itemId,
    required String amount,
    required DateTime actualAt,
    String personId = meId,
    int? expectedPersonRevision,
    StockUseInput? stockUse,
    ProductUseInput? productUse,
    String? siteLabel,
    bool failBeforeCommit = false,
    Future<void> Function()? beforeCommit,
  }) async {
    ExactQuantity.parse(amount);
    _validateSite(siteLabel);
    return _record(
      await _command(
        commandId,
        [
          'record',
          personId,
          itemId,
          amount,
          actualAt.microsecondsSinceEpoch,
          ?expectedPersonRevision,
          if (stockUse != null) _stockUsePayload(stockUse),
          if (productUse != null) productUse.toJson(),
          ?siteLabel,
        ],
        () => _recordInTransaction(
          commandId: commandId,
          personId: personId,
          expectedPersonRevision: expectedPersonRevision,
          itemId: itemId,
          amount: amount,
          actualAt: actualAt,
          stockUse: stockUse,
          productUse: productUse,
          siteLabel: siteLabel,
        ),
        failBeforeCommit: failBeforeCommit,
        beforeCommit: beforeCommit,
      ),
    );
  }

  Future<Map<String, Object?>> _recordInTransaction({
    required String commandId,
    required String personId,
    int? expectedPersonRevision,
    required String itemId,
    required String amount,
    required DateTime actualAt,
    StockUseInput? stockUse,
    ProductUseInput? productUse,
    String? siteLabel,
  }) async {
    final quantity = ExactQuantity.parse(amount);

    await _activeOwner(personId, expectedPersonRevision ?? 1);
    final item = await _rows('SELECT * FROM item WHERE id=? AND person=?', [
      itemId,
      personId,
    ]);
    if (item.isEmpty) {
      throw const CommandConflict('ownership');
    }
    final label = await productLabel(personId: personId, itemId: itemId);
    if ((label != null) != (productUse != null) ||
        (productUse != null &&
            (stockUse != null || item.single['unit'] != 'ml'))) {
      throw const CommandConflict('product_input');
    }
    final id = newCommandId();
    await _db.customStatement('INSERT INTO administration VALUES (?,?,?,1,?)', [
      id,
      personId,
      itemId,
      actualAt.microsecondsSinceEpoch,
    ]);
    final data = <String, Object?>{
      ...item.single,
      'id': id,
      'item': itemId,
      'revision': 1,
      'amount': quantity.scaled,
      'entered': amount,
      'actual': actualAt.microsecondsSinceEpoch,
      'entered_at': DateTime.now().microsecondsSinceEpoch,
      'voided': 0,
      'source': personId == meId
          ? RecordSource.selfReported.name
          : RecordSource.recordedOnBehalf.name,
    };
    data.addAll(
      productUse != null
          ? await _consumeProduct(
              commandId,
              personId,
              itemId,
              id,
              productUse,
              amount,
            )
          : await _consumeStock(
              commandId,
              personId,
              itemId,
              id,
              stockUse,
              item.single['unit'] as String,
              amount,
            ),
    );
    await _insertRevision(data);
    if (siteLabel != null) await _setSite(commandId, personId, id, siteLabel);
    return {...data, 'site_label': siteLabel};
  }

  Future<UseRecord> correct({
    required String commandId,
    required String recordId,
    required int expectedRevision,
    required String? amount,
    required DateTime actualAt,
    String personId = meId,
    int? expectedPersonRevision,
    PhysicalCorrection? stockCorrection,
    List<IntervalChangeReview>? intervalReviews,
    String? siteLabel,
  }) => _revise(
    commandId,
    recordId,
    expectedRevision,
    personId,
    amount,
    actualAt,
    false,
    expectedPersonRevision,
    stockCorrection,
    intervalReviews,
    siteLabel,
  );
  Future<UseRecord> voidRecord({
    required String commandId,
    required String recordId,
    required int expectedRevision,
    String personId = meId,
    int? expectedPersonRevision,
    PhysicalCorrection? stockCorrection,
    List<IntervalChangeReview>? intervalReviews,
  }) => _revise(
    commandId,
    recordId,
    expectedRevision,
    personId,
    null,
    null,
    true,
    expectedPersonRevision,
    stockCorrection,
    intervalReviews,
    null,
  );
  Future<UseRecord> _revise(
    String commandId,
    String id,
    int expected,
    String person,
    String? amount,
    DateTime? actual,
    bool voided,
    int? expectedPersonRevision,
    PhysicalCorrection? stockCorrection,
    List<IntervalChangeReview>? intervalReviews,
    String? siteLabel,
  ) async {
    if (amount != null) ExactQuantity.parse(amount);
    _validateSite(siteLabel);
    return _record(
      await _command(
        commandId,
        [
          'revise',
          person,
          id,
          expected,
          amount,
          actual?.microsecondsSinceEpoch,
          voided,
          ?expectedPersonRevision,
          if (stockCorrection != null) stockCorrection.name,
          ?siteLabel,
          if (intervalReviews?.isNotEmpty == true)
            [for (final r in intervalReviews!) _intervalReviewPayload(r)],
        ],
        () => _reviseInTransaction(
          commandId,
          id,
          expected,
          person,
          amount,
          actual,
          voided,
          expectedPersonRevision,
          stockCorrection,
          intervalReviews,
          siteLabel: siteLabel,
        ),
      ),
    );
  }

  Future<Map<String, Object?>> _reviseInTransaction(
    String commandId,
    String id,
    int expected,
    String person,
    String? amount,
    DateTime? actual,
    bool voided,
    int? expectedPersonRevision,
    PhysicalCorrection? stockCorrection,
    List<IntervalChangeReview>? intervalReviews, {
    String? siteLabel,
    bool allowCombined = false,
    bool intervalReviewsValidated = false,
  }) async {
    final quantity = amount == null ? null : ExactQuantity.parse(amount);

    await _activeOwner(person, expectedPersonRevision ?? 1);
    final rows = await _rows('$_current WHERE a.id=? AND a.person=?', [
      id,
      person,
    ]);
    if (rows.isEmpty) {
      throw const CommandConflict('ownership');
    }
    if (!allowCombined &&
        (await _rows(
          'SELECT action FROM combined_member WHERE record=? AND person=?',
          [id, person],
        )).isNotEmpty) {
      throw const CommandConflict('combined_action_required');
    }
    final old = rows.single;
    if (old['revision'] != expected || old['voided'] == 1) {
      throw const CommandConflict('revision');
    }
    if (!intervalReviewsValidated) {
      await _validateIntervalRevisionReviews(
        id,
        person,
        expected,
        actual,
        voided,
        intervalReviews,
      );
    }
    final data = <String, Object?>{
      ...old,
      'revision': expected + 1,
      'amount': quantity?.scaled ?? old['amount'],
      'entered': amount ?? old['entered'],
      'actual': actual?.microsecondsSinceEpoch ?? old['actual'],
      'entered_at': DateTime.now().microsecondsSinceEpoch,
      'voided': voided ? 1 : 0,
    };
    await _correctStock(commandId, person, id, stockCorrection);
    if (!voided && amount != null) {
      data.remove('actual_n');
      data.remove('actual_d');
      data['actual_unit'] = old['actual_unit'] ?? old['unit'];
      data['quantity_replacement'] = null;
      data['original_entry'] = amount;
      data['original_unit'] = data['actual_unit'];
    }
    final product = _productRead(old['product_snapshot']);
    if (product != null && !voided && amount != null) {
      data['product_snapshot'] = jsonEncode(
        ProductAdministrationSnapshot(
          label: product.label,
          defaultLabel: product.defaultLabel,
          volume: ExactAmount.parseEntry(amount),
        ).toJson(),
      );
    }
    await _insertRevision(data);
    await _db.customStatement(
      'UPDATE administration SET revision=?,actual=? WHERE id=?',
      [expected + 1, data['actual'], id],
    );
    final linked = await _rows(
      'SELECT d.id,d.bucket,e.plan,e.person FROM daily_action d JOIN daily_expectation e ON e.id=d.bucket WHERE d.record=? AND d.undone=0',
      [id],
    );
    for (final link in linked) {
      await _db.customStatement(
        'UPDATE daily_action SET revision=revision+1,undone=? WHERE id=?',
        [voided ? 1 : 0, link['id']],
      );
      await _db.customStatement(
        'UPDATE daily_expectation SET revision=revision+1 WHERE id=?',
        [link['bucket']],
      );
      final head = (await _rows('SELECT revision FROM daily_plan WHERE id=?', [
        link['plan'],
      ])).single;
      await _dailyIntent(
        link['plan'] as String,
        person,
        head['revision'] as int,
        false,
      );
    }
    await _intervalActualChanged(id, person, reviews: intervalReviews);
    if (siteLabel != null) {
      await _setSite(commandId, person, id, siteLabel);
      data['site_label'] = siteLabel;
    }
    return data;
  }

  Future<void> _insertRevision(Map<String, Object?> r) async {
    await _db.customStatement(
      'INSERT INTO revision VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        'id',
        'person',
        'revision',
        'name',
        'form',
        'unit',
        'type',
        'amount',
        'entered',
        'actual',
        'entered_at',
        'voided',
      ].map((k) => r[k]).toList(),
    );
    await _db.customStatement('INSERT INTO revision_catalogue VALUES (?,?,?)', [
      r['id'],
      r['revision'],
      r['catalogue_snapshot'],
    ]);
    final actual = r['actual_n'] == null
        ? ExactAmount.parseEntry(r['entered'] as String)
        : ExactAmount.fromStorage(
            r['actual_n'] as String,
            r['actual_d'] as String,
          );
    await _db.customStatement(
      'INSERT INTO revision_quantity VALUES (?,?,?,?,?,?,?,?,?)',
      [
        r['id'],
        r['revision'],
        actual.numerator.toString(),
        actual.denominator.toString(),
        r['actual_unit'] ?? r['unit'],
        r['original_entry'] ?? r['entered'],
        r['original_unit'] ?? r['unit'],
        r['quantity_strength'],
        r['quantity_replacement'],
      ],
    );
    if (r['product_snapshot'] != null) {
      await _db.customStatement('INSERT INTO revision_product VALUES (?,?,?)', [
        r['id'],
        r['revision'],
        r['product_snapshot'],
      ]);
    }
    await _db.customStatement('INSERT INTO revision_source VALUES (?,?,?)', [
      r['id'],
      r['revision'],
      r['source'] ?? RecordSource.unspecified.name,
    ]);
  }

  static const _current = '''SELECT a.id,a.item,r.*,s.source,c.catalogue_snapshot,q.numerator AS actual_n,q.denominator AS actual_d,q.unit AS actual_unit,q.entered AS original_entry,q.entered_unit AS original_unit,q.strength AS quantity_strength,q.replacement AS quantity_replacement,x.snapshot AS product_snapshot,(SELECT label FROM site_event WHERE record=a.id AND person=a.person ORDER BY sequence DESC LIMIT 1) AS site_label,(SELECT action FROM combined_member WHERE record=a.id AND person=a.person) AS combined_action FROM administration a JOIN revision r
    ON r.record=a.id AND r.person=a.person AND r.revision=a.revision LEFT JOIN revision_source s ON s.record=r.record AND s.revision=r.revision LEFT JOIN revision_catalogue c ON c.record=r.record AND c.revision=r.revision LEFT JOIN revision_quantity q ON q.record=r.record AND q.revision=r.revision LEFT JOIN revision_product x ON x.record=r.record AND x.revision=r.revision''';
  UseRecord _record(Map<String, Object?> r) => UseRecord(
    id: r['id'] as String,
    personId: r['person'] as String,
    itemId: r['item'] as String,
    name: r['name'] as String,
    form: r['form'] as String,
    unit: r['unit'] as String,
    type: r['type'] as String,
    enteredAmount: r['entered'] as String,
    actualAt: DateTime.fromMicrosecondsSinceEpoch(
      r['actual'] as int,
      isUtc: true,
    ),
    enteredAt: DateTime.fromMicrosecondsSinceEpoch(
      r['entered_at'] as int,
      isUtc: true,
    ),
    revision: r['revision'] as int,
    isVoided: r['voided'] == 1,
    alreadyCommitted: r['replay'] == true,
    source: RecordSource.values.byName(r['source'] as String? ?? 'unspecified'),
    catalogueSnapshot: _catalogueSnapshot(r['catalogue_snapshot']),
    exactActualAmount: _storedPair(r, 'actual_n', 'actual_d'),
    exactActualUnit: r['actual_unit'] as String?,
    originalEntry: r['original_entry'] as String?,
    originalUnit: r['original_unit'] as String?,
    labelledStrength: r['quantity_strength'] == null
        ? null
        : _strengthDecode(r['quantity_strength'] as String),
    replacement: _replacementDecode(r['quantity_replacement']),
    product: _productRead(r['product_snapshot']),
    siteLabel: r['site_label'] as String?,
    combinedActionId: r['combined_action'] as String?,
  );
  List<Object?> _filterArgs(
    String personId,
    String? itemId,
    DateTime? actualFrom,
    DateTime? actualBefore,
  ) => [
    personId,
    ?itemId,
    if (actualFrom != null) actualFrom.microsecondsSinceEpoch,
    if (actualBefore != null) actualBefore.microsecondsSinceEpoch,
  ];
  String _filterSql(
    String? itemId,
    DateTime? actualFrom,
    DateTime? actualBefore,
  ) =>
      'a.person=?${itemId == null ? '' : ' AND a.item=?'}${actualFrom == null ? '' : ' AND a.actual>=?'}${actualBefore == null ? '' : ' AND a.actual<?'}';
  String _scopedFilter(
    FeedScope? scope,
    String? itemId,
    DateTime? actualFrom,
    DateTime? actualBefore,
  ) => scope?.isEveryone == true
      ? "a.person IN (SELECT id FROM person WHERE archived=0)${itemId == null ? '' : ' AND a.item=?'}${actualFrom == null ? '' : ' AND a.actual>=?'}${actualBefore == null ? '' : ' AND a.actual<?'}"
      : _filterSql(itemId, actualFrom, actualBefore);
  void _pageBounds(int limit, int offset) {
    if (limit < 1 || limit > 500 || offset < 0) throw RangeError('page_bounds');
  }

  Future<List<UseRecord>> records({
    String personId = meId,
    FeedScope? scope,
    String? itemId,
    DateTime? actualFrom,
    DateTime? actualBefore,
    int limit = 100,
    int offset = 0,
  }) async {
    if (limit < 1 || limit > 500 || offset < 0) {
      throw RangeError('page_bounds');
    }
    if (scope?.isEveryone == true) {
      return _db.transaction(() async {
        final people = await _rows(
          'SELECT id FROM person WHERE archived=0 ORDER BY id',
        );
        if (people.isEmpty) return <UseRecord>[];
        final branch =
            'SELECT * FROM ($_current WHERE ${_filterSql(itemId, actualFrom, actualBefore)} ORDER BY a.actual DESC,a.id LIMIT ?)';
        // Bound each indexed branch, and each chunk's merge, independently of total history.
        // Chunking also avoids SQLite's compound SELECT limit for large adult lists.
        final rows = <Map<String, Object?>>[];
        for (var start = 0; start < people.length; start += 100) {
          final chunk = people.skip(start).take(100).toList();
          rows.addAll(
            await _rows(
              '${List.filled(chunk.length, branch).join(' UNION ALL ')} ORDER BY actual DESC,id LIMIT ?',
              [
                for (final person in chunk) ...[
                  ..._filterArgs(
                    person['id'] as String,
                    itemId,
                    actualFrom,
                    actualBefore,
                  ),
                  limit + offset,
                ],
                limit + offset,
              ],
            ),
          );
        }
        rows.sort((a, b) {
          final time = (b['actual'] as int).compareTo(a['actual'] as int);
          return time != 0
              ? time
              : (a['id'] as String).compareTo(b['id'] as String);
        });
        return rows.skip(offset).take(limit).map(_record).toList();
      });
    }
    return (await _rows(
      '$_current WHERE ${_scopedFilter(scope, itemId, actualFrom, actualBefore)} ORDER BY a.actual DESC,a.id LIMIT ? OFFSET ?',
      [
        ..._filterArgs(
          scope?.personId ?? personId,
          itemId,
          actualFrom,
          actualBefore,
        ).skip(scope?.isEveryone == true ? 1 : 0),
        limit,
        offset,
      ],
    )).map(_record).toList();
  }

  Future<int> recordCount({
    String personId = meId,
    FeedScope? scope,
    String? itemId,
    DateTime? actualFrom,
    DateTime? actualBefore,
  }) async =>
      (await _rows(
            'SELECT COUNT(*) AS count FROM administration a WHERE ${_scopedFilter(scope, itemId, actualFrom, actualBefore)}',
            _filterArgs(
              scope?.personId ?? personId,
              itemId,
              actualFrom,
              actualBefore,
            ).skip(scope?.isEveryone == true ? 1 : 0).toList(),
          )).single['count']
          as int;
  Future<UseRecord?> recordById(
    String recordId, {
    String personId = meId,
  }) async {
    final rows = await _rows('$_current WHERE a.id=? AND a.person=?', [
      recordId,
      personId,
    ]);
    return rows.isEmpty ? null : _record(rows.single);
  }

  Future<List<UseRecord>> history(String recordId) async => (await _rows(
    '''SELECT a.id,a.item,r.*,s.source,c.catalogue_snapshot,q.numerator AS actual_n,q.denominator AS actual_d,q.unit AS actual_unit,q.entered AS original_entry,q.entered_unit AS original_unit,q.strength AS quantity_strength,q.replacement AS quantity_replacement,x.snapshot AS product_snapshot,(SELECT label FROM site_event WHERE record=a.id AND person=a.person AND record_revision<=r.revision ORDER BY sequence DESC LIMIT 1) AS site_label,(SELECT action FROM combined_member WHERE record=a.id AND person=a.person) AS combined_action FROM administration a
    JOIN revision r ON r.record=a.id AND r.person=a.person LEFT JOIN revision_source s ON s.record=r.record AND s.revision=r.revision LEFT JOIN revision_catalogue c ON c.record=r.record AND c.revision=r.revision LEFT JOIN revision_quantity q ON q.record=r.record AND q.revision=r.revision LEFT JOIN revision_product x ON x.record=r.record AND x.revision=r.revision WHERE a.id=? ORDER BY r.revision''',
    [recordId],
  )).map(_record).toList();
  Stream<T> _watch<T>(
    Future<T> Function() read, {
    Stream<void>? changes,
  }) => Stream.multi((sink) {
    if (_closed) {
      sink.close();
      return;
    }
    // Subscribe before initial read so a concurrent commit cannot be missed.
    Future<void> queue = Future.value();
    var cancelled = false;
    void refresh() {
      if (_closed || cancelled) return;
      late final Future<void> work;
      work = queue.then((_) async {
        if (_closed || cancelled) return;
        try {
          final value = await read();
          if (!cancelled) sink.add(value);
        } catch (e, s) {
          if (!cancelled) sink.addError(e, s);
        }
      });
      queue = work;
      _watchReads.add(work);
      unawaited(work.then((_) => _watchReads.remove(work)));
    }

    final subscription = (changes ?? _changes.stream).listen(
      (_) => refresh(),
      onDone: () async {
        await queue;
        sink.close();
      },
    );
    refresh();
    sink.onCancel = () async {
      cancelled = true;
      await subscription.cancel();
      await queue;
    };
  });
  /// Whole-scoped item counts grouped by actual item type, under the same
  /// search the collection list uses. Counts are bounded by distinct types and
  /// say how many items share each type; no status or schedule is involved.
  Future<List<SubstanceTypeSummary>> itemTypeCounts({
    String personId = meId,
    FeedScope? scope,
    String? search,
  }) async {
    final conditions = [
      scope?.isEveryone == true
          ? 'item.person IN (SELECT id FROM person WHERE archived=0)'
          : 'item.person=?',
      if (search?.trim().isNotEmpty ?? false) r"item.name LIKE ? ESCAPE '\'",
    ];
    return [
      for (final row in await _rows(
        'SELECT item.type_id AS type_id, COALESCE(t.name, item.type) AS type_name, COUNT(*) AS count FROM item LEFT JOIN personal_item_type t ON t.id=item.type_id AND t.person=item.person WHERE ${conditions.join(' AND ')} GROUP BY item.type_id, item.type ORDER BY type_name, item.type_id',
        _itemFilterArgs(personId, scope, search, null),
      ))
        SubstanceTypeSummary(
          typeId: row['type_id'] as String?,
          typeName: row['type_name'] as String? ?? '',
          count: row['count'] as int,
        ),
    ];
  }

  Stream<List<SubstanceItem>> watchItems({
    String personId = meId,
    FeedScope? scope,
    String? search,
    String? typeId,
    int limit = 100,
    int offset = 0,
  }) => _watch(
    () => items(
      personId: personId,
      scope: scope,
      search: search,
      typeId: typeId,
      limit: limit,
      offset: offset,
    ),
  );

  Stream<List<SubstanceTypeSummary>> watchItemTypeCounts({
    String personId = meId,
    FeedScope? scope,
    String? search,
  }) => _watch(
    () => itemTypeCounts(personId: personId, scope: scope, search: search),
  );
  Stream<List<UseRecord>> watchRecords({
    String personId = meId,
    FeedScope? scope,
    String? itemId,
    DateTime? actualFrom,
    DateTime? actualBefore,
    int limit = 100,
    int offset = 0,
  }) => _watch(
    () => records(
      personId: personId,
      scope: scope,
      itemId: itemId,
      actualFrom: actualFrom,
      actualBefore: actualBefore,
      limit: limit,
      offset: offset,
    ),
  );
  Future<String?> readSetting(String key) async {
    final rows = await _rows('SELECT value FROM setting WHERE key=?', [key]);
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  Stream<Map<String, String>> watchSettings() => _watch(
    () async => {
      for (final r in await _rows('SELECT * FROM setting'))
        r['key'] as String: r['value'] as String,
    },
  );
  Future<void> writeSetting(
    String key,
    String value, {
    bool failBeforeCommit = false,
    bool Function()? canCommit,
  }) async {
    _requireWritable();
    await _db.transaction(() async {
      _requireWritable();
      await _db.customStatement(
        'INSERT INTO setting VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
        [key, value],
      );
      _requireWritable();
      if (canCommit != null && !canCommit()) {
        throw const CommandConflict('app_locked');
      }
      if (failBeforeCommit) {
        throw StateError('injected_settings_failure');
      }
    });
    _changes.add(null);
  }

  Future<List<OrdinaryDraft>> drafts() async {
    _requireWritable();
    return (await _rows(
      'SELECT * FROM ordinary_draft WHERE generation=? ORDER BY id',
      [generation],
    )).map(OrdinaryDraft.decode).toList();
  }

  Stream<List<OrdinaryDraft>> watchDrafts() =>
      _watch(drafts, changes: _draftChanges.stream);
  Future<OrdinaryDraft?> draftById(String id) async {
    _requireWritable();
    final rows = await _rows(
      'SELECT * FROM ordinary_draft WHERE id=? AND generation=?',
      [id, generation],
    );
    return rows.isEmpty ? null : OrdinaryDraft.decode(rows.single);
  }

  DraftCheckpoint captureDraftCheckpoint(OrdinaryDraft draft) {
    _requireWritable();
    final migrated = _migratedDraftIds[draft.id];
    if (migrated != null && migrated.operationId == draft.operationId) {
      // A late callback for an adopted identity is rejected truthfully when
      // it persists, and never registers under the legacy key: an entry there
      // would let a legacy discard tombstone the adopted operation and a
      // legacy write silently rewrite the adopted row.
      return DraftCheckpoint._(
        () async => throw const CommandConflict('draft_identity'),
      );
    }
    (_capturedDraftOperations[draft.id] ??= {}).add(draft.operationId);
    return DraftCheckpoint._(() => _saveCapturedDraft(draft));
  }

  Future<void> saveDraft(OrdinaryDraft draft) async =>
      await captureDraftCheckpoint(draft).persist();
  Future<void> _saveCapturedDraft(OrdinaryDraft draft) {
    final work = _persistCapturedDraft(draft);
    _draftWrites.add(work);
    unawaited(
      work.then<void>(
        (_) {
          _draftWrites.remove(work);
        },
        onError: (Object _, StackTrace _) {
          _draftWrites.remove(work);
        },
      ),
    );
    return work;
  }

  Future<void> _persistCapturedDraft(OrdinaryDraft draft) async {
    if (_closed) throw const CommandConflict('deleted_context');
    // A capture taken before the adoption may only persist before the move:
    // once the identity is fenced the late write refuses instead of touching
    // either row, leaving no stale alias behind.
    final migrated = _migratedDraftIds[draft.id];
    if (migrated != null && migrated.operationId == draft.operationId) {
      throw const CommandConflict('draft_identity');
    }
    await _db.transaction(() async {
      await _db.customStatement('UPDATE dataset SET generation=generation');
      if (_closed) throw const CommandConflict('deleted_context');
      if (draft.generation != generation ||
          (await _rows('SELECT generation FROM dataset'))
                  .single['generation'] !=
              generation) {
        throw const CommandConflict('generation');
      }
      // A late form callback cannot resurrect a committed or deleted operation.
      final operation = await _rows('SELECT result FROM operation WHERE id=?', [
        draft.operationId,
      ]);
      if (operation.isNotEmpty) {
        if (operation.single['result'] == '{"invalidated":true}') {
          throw const CommandConflict('deleted_context');
        }
        return;
      }
      final existing = await _rows('SELECT * FROM ordinary_draft WHERE id=?', [
        draft.id,
      ]);
      if (existing.isNotEmpty) {
        final old = OrdinaryDraft.decode(existing.single);
        if (old.generation != draft.generation ||
            old.operationId != draft.operationId ||
            old.kind != draft.kind ||
            old.personId != draft.personId ||
            old.personRevision != draft.personRevision ||
            old.targetId != draft.targetId ||
            old.targetRevision != draft.targetRevision) {
          throw const CommandConflict('draft_identity');
        }
      }
      if (draft.personId != null) {
        final owner = await profileById(draft.personId!);
        if (owner == null) throw const CommandConflict('deleted_context');
        // Existing archived/stale drafts remain available for review, but a late
        // callback after scoped deletion must not recreate Me's old content.
        final prior = await _rows('SELECT id FROM ordinary_draft WHERE id=?', [
          draft.id,
        ]);
        if (prior.isEmpty && owner.revision != draft.personRevision) {
          throw const CommandConflict('person_context');
        }
      }
      await _db.customStatement(
        'INSERT INTO ordinary_draft VALUES (?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET snapshot=excluded.snapshot',
        [
          draft.id,
          draft.generation,
          draft.operationId,
          draft.kind.name,
          draft.personId,
          draft.personRevision,
          draft.targetId,
          draft.targetRevision,
          draft.encode(),
        ],
      );
      if (_closed) throw const CommandConflict('deleted_context');
    });
    if (!_closed) _draftChanges.add(null);
  }

  Future<void> discardDraft(String id) async {
    _requireWritable();
    await _db.transaction(() async {
      await _db.customStatement('UPDATE dataset SET generation=generation');
      _requireWritable();
      if ((await _rows('SELECT generation FROM dataset'))
              .single['generation'] !=
          generation) {
        throw const CommandConflict('generation');
      }
      final rows = await _rows(
        'SELECT operation FROM ordinary_draft WHERE id=? AND generation=?',
        [id, generation],
      );
      // The adopted identity keeps its operation alive even when a stale
      // captured callback left it under the legacy key.
      final migrated = _migratedDraftIds[id];
      final operations = {
        ...?_capturedDraftOperations[id]?.where(
          (op) => op != migrated?.operationId,
        ),
        for (final row in rows) row['operation'] as String,
      };
      for (final operation in operations) {
        await _db.customStatement(
          'INSERT INTO operation VALUES (?,\'[]\',\'{"invalidated":true}\') ON CONFLICT(id) DO NOTHING',
          [operation],
        );
      }
      await _db.customStatement(
        'DELETE FROM ordinary_draft WHERE id=? AND generation=?',
        [id, generation],
      );
    });
    _capturedDraftOperations.remove(id);
    _draftChanges.add(null);
    _changes.add(null);
  }

  Stream<DraftOperationStatus> watchDraftOperation(String id) => _watch(
    () async {
      final rows = await _rows('SELECT result FROM operation WHERE id=?', [id]);
      if (rows.isEmpty) return DraftOperationStatus.pending;
      return rows.single['result'] == '{"invalidated":true}'
          ? DraftOperationStatus.invalidated
          : DraftOperationStatus.committed;
    },
  );

  /// Resolve an uncertain acknowledgement before validating current revisions.
  Future<bool> operationCommitted(String id) async {
    _requireWritable();
    final rows = await _rows('SELECT result FROM operation WHERE id=?', [id]);
    if (rows.isEmpty) return false;
    if (rows.single['result'] == '{"invalidated":true}') {
      throw const CommandConflict('deleted_context');
    }
    return true;
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    // A watched Everyone read owns a transaction. Let started reads finish before
    // closing the executor; queued/cancelled reads stop without opening new work.
    await Future.wait(_watchReads.toList());
    await Future.wait(_reminderWork.toList());
    await Future.wait(
      _draftWrites
          .map(
            (work) =>
                work.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
          )
          .toList(),
    );
    await _changes.close();
    await _draftChanges.close();
    await _db.close();
  }
}
