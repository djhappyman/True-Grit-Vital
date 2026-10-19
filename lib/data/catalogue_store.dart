part of 'record_store.dart';

const catalogueSchemaV7 = [
  'CREATE TABLE personal_item_type(id TEXT PRIMARY KEY,person TEXT NOT NULL REFERENCES person(id),name TEXT NOT NULL,revision INTEGER NOT NULL DEFAULT 1 CHECK(revision>0),UNIQUE(person,name),UNIQUE(id,person)) STRICT',
  'CREATE INDEX personal_item_type_owner ON personal_item_type(person,name,id)',
  'ALTER TABLE item ADD COLUMN type_id TEXT REFERENCES personal_item_type(id)',
  'ALTER TABLE item ADD COLUMN item_revision INTEGER NOT NULL DEFAULT 1 CHECK(item_revision>0)',
  'ALTER TABLE item ADD COLUMN catalogue_snapshot TEXT',
  'INSERT INTO personal_item_type(id,person,name) SELECT lower(hex(randomblob(24))),person,type FROM item GROUP BY person,type',
  'UPDATE item SET type_id=(SELECT id FROM personal_item_type t WHERE t.person=item.person AND t.name=item.type)',
  "CREATE TRIGGER item_type_insert BEFORE INSERT ON item WHEN NEW.type_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM personal_item_type t WHERE t.id=NEW.type_id AND t.person=NEW.person) BEGIN SELECT RAISE(ABORT,'item_type_owner'); END",
  "CREATE TRIGGER item_type_update BEFORE UPDATE OF type_id,person ON item WHEN NEW.type_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM personal_item_type t WHERE t.id=NEW.type_id AND t.person=NEW.person) BEGIN SELECT RAISE(ABORT,'item_type_owner'); END",
  'CREATE INDEX item_type_owner ON item(person,type_id,id)',
  'CREATE TABLE revision_catalogue(record TEXT NOT NULL,revision INTEGER NOT NULL,catalogue_snapshot TEXT,PRIMARY KEY(record,revision),FOREIGN KEY(record,revision) REFERENCES revision(record,revision) ON DELETE CASCADE) STRICT',
  'ALTER TABLE ordinary_draft RENAME TO ordinary_draft_v6',
  "CREATE TABLE ordinary_draft(id TEXT PRIMARY KEY,generation TEXT NOT NULL,operation TEXT NOT NULL UNIQUE,kind TEXT NOT NULL CHECK(kind IN ('item','dose','correction','profile','dailyPlan','itemType')),person TEXT REFERENCES person(id),person_revision INTEGER,target TEXT,target_revision INTEGER,snapshot TEXT NOT NULL) STRICT",
  'INSERT INTO ordinary_draft SELECT * FROM ordinary_draft_v6',
  'DROP TABLE ordinary_draft_v6',
];

CatalogueSnapshot? _catalogueSnapshot(Object? encoded) => encoded == null
    ? null
    : CatalogueSnapshot.fromJson(
        jsonDecode(encoded as String) as Map<String, dynamic>,
      );

extension CatalogueRecords on RecordStore {
  PersonalItemType _itemType(Map<String, Object?> row) => PersonalItemType(
    id: row['id'] as String,
    personId: row['person'] as String,
    name: row['name'] as String,
    revision: row['revision'] as int,
    alreadyCommitted: row['replay'] == true,
  );

  Future<List<PersonalItemType>> itemTypes({
    String personId = meId,
    int limit = 100,
    int offset = 0,
  }) async {
    _pageBounds(limit, offset);
    return (await _rows(
      'SELECT * FROM personal_item_type WHERE person=? ORDER BY name,id LIMIT ? OFFSET ?',
      [personId, limit, offset],
    )).map(_itemType).toList();
  }

  Stream<List<PersonalItemType>> watchItemTypes({
    String personId = meId,
    int limit = 100,
    int offset = 0,
  }) =>
      _watch(() => itemTypes(personId: personId, limit: limit, offset: offset));

  Future<PersonalItemType?> itemTypeById(
    String id, {
    required String personId,
  }) async {
    final rows = await _rows(
      'SELECT * FROM personal_item_type WHERE id=? AND person=?',
      [id, personId],
    );
    return rows.isEmpty ? null : _itemType(rows.single);
  }

  Stream<PersonalItemType?> watchItemTypeById(
    String id, {
    required String personId,
  }) => _watch(() => itemTypeById(id, personId: personId));

  void _typeName(String name) {
    if (name.trim().isEmpty || name.length > 500) {
      throw const FormatException('item_type_name');
    }
  }

  Future<PersonalItemType> _resolveItemType(
    String person,
    String? id,
    String name,
  ) async {
    final rows = await _rows(
      'SELECT * FROM personal_item_type WHERE person=? AND ${id == null ? 'name' : 'id'}=?',
      [person, id ?? name],
    );
    if (rows.isNotEmpty) return _itemType(rows.single);
    if (id != null) throw const CommandConflict('type_context');
    final newId = newCommandId();
    await _db.customStatement(
      'INSERT INTO personal_item_type(id,person,name) VALUES (?,?,?)',
      [newId, person, name],
    );
    return PersonalItemType(
      id: newId,
      personId: person,
      name: name,
      revision: 1,
    );
  }

  Future<PersonalItemType> createItemType({
    required String commandId,
    required String name,
    String personId = meId,
    int? expectedPersonRevision,
  }) async {
    _typeName(name);
    return _itemType(
      await _command(
        commandId,
        ['itemType', personId, name, ?expectedPersonRevision],
        () async {
          await _activeOwner(personId, expectedPersonRevision ?? 1);
          if ((await _rows(
            'SELECT id FROM personal_item_type WHERE person=? AND name=?',
            [personId, name],
          )).isNotEmpty) {
            throw const CommandConflict('type_exists');
          }
          final type = await _resolveItemType(personId, null, name);
          return {
            'id': type.id,
            'person': personId,
            'name': name,
            'revision': 1,
          };
        },
      ),
    );
  }

  Future<PersonalItemType> renameItemType({
    required String commandId,
    required String typeId,
    required int expectedRevision,
    required String name,
    String personId = meId,
    int? expectedPersonRevision,
  }) async {
    _typeName(name);
    return _itemType(
      await _command(
        commandId,
        [
          'renameItemType',
          personId,
          typeId,
          expectedRevision,
          name,
          ?expectedPersonRevision,
        ],
        () async {
          await _activeOwner(personId, expectedPersonRevision ?? 1);
          final rows = await _rows(
            'SELECT * FROM personal_item_type WHERE id=? AND person=?',
            [typeId, personId],
          );
          if (rows.isEmpty) throw const CommandConflict('type_context');
          if (rows.single['revision'] != expectedRevision) {
            throw const CommandConflict('revision');
          }
          if ((await _rows(
            'SELECT id FROM personal_item_type WHERE person=? AND name=? AND id<>?',
            [personId, name, typeId],
          )).isNotEmpty) {
            throw const CommandConflict('type_exists');
          }
          await _db.customStatement(
            'UPDATE personal_item_type SET name=?,revision=revision+1 WHERE id=? AND person=?',
            [name, typeId, personId],
          );
          await _db.customStatement(
            'UPDATE item SET type=?,item_revision=item_revision+1 WHERE person=? AND type_id=?',
            [name, personId, typeId],
          );
          return {
            ...rows.single,
            'name': name,
            'revision': expectedRevision + 1,
          };
        },
      ),
    );
  }
}
