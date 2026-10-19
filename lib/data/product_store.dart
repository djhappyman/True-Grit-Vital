part of 'record_store.dart';

const productSchemaV10 = [
  '''CREATE TABLE product_label(item TEXT NOT NULL,person TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),snapshot TEXT NOT NULL CHECK(length(snapshot)<=32000 AND json_valid(snapshot) AND json_extract(snapshot,'\$.personId') IS person AND json_extract(snapshot,'\$.itemId') IS item AND json_extract(snapshot,'\$.revision') IS revision AND json_array_length(snapshot,'\$.components') BETWEEN 2 AND 32),PRIMARY KEY(item,revision),FOREIGN KEY(item,person) REFERENCES item(id,person) ON DELETE CASCADE) STRICT''',
  "CREATE TRIGGER product_label_immutable BEFORE UPDATE ON product_label BEGIN SELECT RAISE(ABORT,'immutable_product_label'); END",
  '''CREATE TABLE revision_product(record TEXT NOT NULL,revision INTEGER NOT NULL,snapshot TEXT NOT NULL CHECK(length(snapshot)<=70000 AND json_valid(snapshot)),PRIMARY KEY(record,revision),FOREIGN KEY(record,revision) REFERENCES revision(record,revision) ON DELETE CASCADE) STRICT''',
  "CREATE TRIGGER revision_product_immutable BEFORE UPDATE ON revision_product BEGIN SELECT RAISE(ABORT,'immutable_product_actual'); END",
  """CREATE TRIGGER revision_product_context BEFORE INSERT ON revision_product WHEN json_extract(NEW.snapshot,'\$.label.personId') IS NOT (SELECT person FROM administration WHERE id=NEW.record) OR json_extract(NEW.snapshot,'\$.defaultLabel.personId') IS NOT (SELECT person FROM administration WHERE id=NEW.record) OR json_extract(NEW.snapshot,'\$.label.itemId') IS NOT (SELECT item FROM administration WHERE id=NEW.record) OR json_extract(NEW.snapshot,'\$.defaultLabel.itemId') IS NOT (SELECT item FROM administration WHERE id=NEW.record) OR json_extract(NEW.snapshot,'\$.volume[0]') IS NOT (SELECT numerator FROM revision_quantity WHERE record=NEW.record AND revision=NEW.revision) OR json_extract(NEW.snapshot,'\$.volume[1]') IS NOT (SELECT denominator FROM revision_quantity WHERE record=NEW.record AND revision=NEW.revision) OR (SELECT unit FROM revision_quantity WHERE record=NEW.record AND revision=NEW.revision) IS NOT 'ml' BEGIN SELECT RAISE(ABORT,'product_actual_context'); END""",
  'ALTER TABLE stock_container ADD COLUMN product_label TEXT',
  "CREATE TRIGGER stock_product_immutable BEFORE UPDATE OF product_label ON stock_container BEGIN SELECT RAISE(ABORT,'immutable_product_source'); END",
  """CREATE TRIGGER stock_product_context BEFORE INSERT ON stock_container WHEN NEW.product_label IS NOT NULL AND (NOT json_valid(NEW.product_label) OR json_extract(NEW.product_label,'\$.personId') IS NOT NEW.person OR json_extract(NEW.product_label,'\$.itemId') IS NOT NEW.item OR NEW.unit<>'ml') BEGIN SELECT RAISE(ABORT,'product_source_context'); END""",
  'ALTER TABLE ordinary_draft RENAME TO ordinary_draft_v9',
  "CREATE TABLE ordinary_draft(id TEXT PRIMARY KEY,generation TEXT NOT NULL,operation TEXT NOT NULL UNIQUE,kind TEXT NOT NULL CHECK(kind IN ('item','dose','correction','profile','dailyPlan','itemType','stockContainer','stockAdjustment','productLabel')),person TEXT REFERENCES person(id),person_revision INTEGER,target TEXT,target_revision INTEGER,snapshot TEXT NOT NULL) STRICT",
  'INSERT INTO ordinary_draft SELECT * FROM ordinary_draft_v9',
  'DROP TABLE ordinary_draft_v9',
];
ProductLabelSnapshot? _productLabelRead(Object? encoded) => encoded == null
    ? null
    : ProductLabelSnapshot.fromJson(
        jsonDecode(encoded as String) as Map<String, dynamic>,
      );
ProductAdministrationSnapshot? _productRead(Object? encoded) => encoded == null
    ? null
    : ProductAdministrationSnapshot.fromJson(
        jsonDecode(encoded as String) as Map<String, dynamic>,
      );
bool _sameProductLabel(ProductLabelSnapshot? a, ProductLabelSnapshot? b) =>
    jsonEncode(a?.toJson()) == jsonEncode(b?.toJson());

extension ProductRecordStore on RecordStore {
  Future<ProductLabelSnapshot?> productLabel({
    required String personId,
    required String itemId,
  }) async {
    final rows = await _rows(
      'SELECT snapshot FROM product_label WHERE item=? AND person=? ORDER BY revision DESC LIMIT 1',
      [itemId, personId],
    );
    return rows.isEmpty ? null : _productLabelRead(rows.single['snapshot']);
  }

  Stream<ProductLabelSnapshot?> watchProductLabel({
    required String personId,
    required String itemId,
  }) => _watch(() => productLabel(personId: personId, itemId: itemId));
  Future<void> _insertProductLabel(ProductLabelSnapshot label) async {
    await _db.customStatement('INSERT INTO product_label VALUES (?,?,?,?)', [
      label.itemId,
      label.personId,
      label.revision,
      jsonEncode(label.toJson()),
    ]);
  }

  Future<ProductLabelSnapshot> saveProductLabel({
    required String commandId,
    required String personId,
    required int expectedPersonRevision,
    required String expectedGeneration,
    required String itemId,
    required int expectedItemRevision,
    required int expectedProductRevision,
    required List<ProductComponent> components,
  }) async {
    _stockGeneration(expectedGeneration);
    final label = ProductLabelSnapshot(
      personId: personId,
      itemId: itemId,
      revision: expectedProductRevision + 1,
      components: components,
    );
    final result = await _command(
      commandId,
      [
        'product_label',
        personId,
        itemId,
        expectedPersonRevision,
        expectedItemRevision,
        expectedProductRevision,
        label.toJson(),
      ],
      () async {
        await _activeOwner(personId, expectedPersonRevision);
        final item = await itemById(itemId, personId: personId);
        if (item == null ||
            item.unit != 'ml' ||
            item.revision != expectedItemRevision) {
          throw const CommandConflict('product_item');
        }
        final previous = await productLabel(personId: personId, itemId: itemId);
        if ((previous?.revision ?? 0) != expectedProductRevision) {
          throw const CommandConflict('product_revision');
        }
        await _insertProductLabel(label);
        await _db.customStatement(
          'UPDATE item SET item_revision=item_revision+1 WHERE id=? AND person=?',
          [itemId, personId],
        );
        final plans = await _rows(
          'SELECT id,revision FROM daily_plan WHERE item=? AND person=?',
          [itemId, personId],
        );
        for (final p in plans) {
          await _dailyIntent(
            p['id'] as String,
            personId,
            p['revision'] as int,
            false,
          );
        }
        return {'person': personId, 'label': label.toJson()};
      },
    );
    return ProductLabelSnapshot.fromJson(
      Map<String, dynamic>.from(result['label'] as Map),
    );
  }

  Future<UseRecord> recordProduct({
    required String commandId,
    required String personId,
    required int expectedPersonRevision,
    required String itemId,
    required DateTime actualAt,
    required ProductUseInput use,
    String? siteLabel,
    bool failBeforeCommit = false,
    Future<void> Function()? beforeCommit,
  }) => record(
    commandId: commandId,
    personId: personId,
    expectedPersonRevision: expectedPersonRevision,
    itemId: itemId,
    amount: use.enteredVolume.originalText,
    actualAt: actualAt,
    productUse: use,
    siteLabel: siteLabel,
    failBeforeCommit: failBeforeCommit,
    beforeCommit: beforeCommit,
  );

  Future<Map<String, Object?>> _consumeProduct(
    String command,
    String person,
    String item,
    String record,
    ProductUseInput use,
    String amount,
  ) async {
    _stockGeneration(use.expectedGeneration);
    if (use.enteredVolume.unit != 'ml' ||
        use.enteredVolume.originalText != amount ||
        use.label.personId != person ||
        use.label.itemId != item) {
      throw const CommandConflict('product_context');
    }
    final selectedItem = await itemById(item, personId: person);
    if (selectedItem == null ||
        (use.expectedItemRevision != null &&
            use.expectedItemRevision != selectedItem.revision)) {
      throw const CommandConflict('product_item');
    }
    final current = await productLabel(personId: person, itemId: item);
    if (!_sameProductLabel(current, use.label)) {
      throw const CommandConflict('product_revision');
    }
    var selected = use.label;
    if (use.containerId == null) {
      if (use.expectedContainerRevision != null || use.sourceLabel != null) {
        throw const CommandConflict('product_source');
      }
    } else {
      if (use.expectedContainerRevision == null) {
        throw const CommandConflict('stock_revision');
      }
      final source = await _stockContext(
        person,
        use.containerId!,
        use.expectedContainerRevision!,
      );
      final label = _productLabelRead(source['product_label']);
      if (source['item'] != item ||
          source['unit'] != 'ml' ||
          label == null ||
          label.personId != person ||
          label.itemId != item ||
          !_sameProductLabel(label, use.sourceLabel ?? use.label)) {
        throw const CommandConflict('product_source');
      }
      selected = label;
      await _appendStock(
        source,
        command,
        StockMovementKind.actualUse,
        -use.enteredVolume.value,
        entered: use.enteredVolume,
        recordId: record,
      );
    }
    final snapshot = ProductAdministrationSnapshot(
      label: selected,
      defaultLabel: use.label,
      volume: use.enteredVolume.value,
    );
    return {
      'product_snapshot': jsonEncode(snapshot.toJson()),
      'actual_n': use.enteredVolume.value.numerator.toString(),
      'actual_d': use.enteredVolume.value.denominator.toString(),
      'actual_unit': 'ml',
      'original_entry': use.enteredVolume.originalText,
      'original_unit': 'ml',
    };
  }

  Future<ProductTotals> productTotals({
    required String personId,
    String? itemId,
    DateTime? actualFrom,
    DateTime? actualBefore,
    int maxRecords = 100000,
    int maxBits = 65536,
  }) async {
    if (maxRecords < 1 ||
        maxRecords > 100000 ||
        maxBits < 64 ||
        maxBits > 65536) {
      throw ArgumentError('product_budget');
    }
    return _db.transaction(() async {
      final rows = await _rows(
        '${RecordStore._current} WHERE a.person=? AND r.voided=0 AND x.snapshot IS NOT NULL'
        '${itemId == null ? '' : ' AND a.item=?'}${actualFrom == null ? '' : ' AND a.actual>=?'}${actualBefore == null ? '' : ' AND a.actual<?'}'
        ' ORDER BY a.actual,a.id LIMIT ?',
        [
          personId,
          ?itemId,
          ?actualFrom?.microsecondsSinceEpoch,
          ?actualBefore?.microsecondsSinceEpoch,
          maxRecords + 1,
        ],
      );
      return aggregateProducts(
        rows.map((r) => _productRead(r['product_snapshot'])!),
        maxRecords: maxRecords,
        maxBits: maxBits,
      );
    });
  }

  Stream<ProductTotals> watchProductTotals({
    required String personId,
    String? itemId,
  }) => _watch(() => productTotals(personId: personId, itemId: itemId));
}
