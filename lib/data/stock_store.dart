part of 'record_store.dart';

const stockSchemaV8 = [
  "CREATE TABLE revision_quantity(record TEXT NOT NULL,revision INTEGER NOT NULL,numerator TEXT NOT NULL CHECK(length(numerator) BETWEEN 1 AND 20000 AND numerator NOT GLOB '*[^0-9]*' AND substr(numerator,1,1) BETWEEN '1' AND '9'),denominator TEXT NOT NULL CHECK(length(denominator) BETWEEN 1 AND 20000 AND denominator NOT GLOB '*[^0-9]*' AND substr(denominator,1,1) BETWEEN '1' AND '9'),unit TEXT NOT NULL CHECK(unit IN ('mg','ml','count')),entered TEXT NOT NULL,entered_unit TEXT NOT NULL CHECK(entered_unit IN ('mg','ml','count')),strength TEXT,replacement TEXT,PRIMARY KEY(record,revision),FOREIGN KEY(record,revision) REFERENCES revision(record,revision) ON DELETE CASCADE) STRICT",
  "CREATE TRIGGER revision_quantity_immutable BEFORE UPDATE ON revision_quantity BEGIN SELECT RAISE(ABORT,'immutable_actual_quantity'); END",
  '''CREATE TABLE stock_container(id TEXT PRIMARY KEY CHECK(length(id)>0),person TEXT NOT NULL,item TEXT NOT NULL,label TEXT NOT NULL CHECK(length(label) BETWEEN 1 AND 500),unit TEXT NOT NULL CHECK(unit IN ('mg','ml','count')),strength TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),sequence INTEGER NOT NULL CHECK(sequence>=0),measurement_sequence INTEGER NOT NULL CHECK(measurement_sequence>=0 AND measurement_sequence<=sequence),balance_status TEXT NOT NULL CHECK(balance_status IN ('known','unknown','limit')),numerator TEXT,denominator TEXT,threshold_n TEXT,threshold_d TEXT,refill INTEGER NOT NULL CHECK(refill IN (0,1)),notice_eligible INTEGER NOT NULL DEFAULT 0 CHECK(notice_eligible IN (0,1)),notice_active INTEGER NOT NULL DEFAULT 1 CHECK(notice_active IN (0,1)),UNIQUE(id,person),UNIQUE(id,person,item),FOREIGN KEY(item,person) REFERENCES item(id,person),CHECK((numerator IS NULL)=(denominator IS NULL)),CHECK((balance_status='known')=(numerator IS NOT NULL)),CHECK((threshold_n IS NULL)=(threshold_d IS NULL)),CHECK(numerator IS NULL OR (length(numerator) BETWEEN 1 AND 20000 AND length(denominator) BETWEEN 1 AND 20000))) STRICT''',
  'CREATE INDEX stock_container_owner ON stock_container(person,item,id)',
  'CREATE INDEX stock_container_notices ON stock_container(notice_active,notice_eligible,person,item,id)',
  '''CREATE TABLE stock_movement(id TEXT PRIMARY KEY CHECK(length(id)>0),person TEXT NOT NULL,container TEXT NOT NULL,sequence INTEGER NOT NULL CHECK(sequence>0),kind TEXT NOT NULL CHECK(kind IN ('restock','actualUse','waste','reconciliation','correction')),numerator TEXT,denominator TEXT,strength TEXT NOT NULL,entered TEXT,entered_unit TEXT CHECK(entered_unit IN ('mg','ml','count')),record TEXT UNIQUE,reverses TEXT UNIQUE,physical_choice TEXT CHECK(physical_choice IN ('reverseRecordedEffect','retainPhysicalEffect')),replacement TEXT,reason TEXT CHECK(length(reason)<=4000),operation TEXT NOT NULL UNIQUE CHECK(length(operation)>0),generation TEXT NOT NULL CHECK(length(generation)>0),recorded_at INTEGER NOT NULL,UNIQUE(container,sequence),UNIQUE(id,person,container),FOREIGN KEY(container,person) REFERENCES stock_container(id,person) ON DELETE CASCADE,FOREIGN KEY(record,person) REFERENCES administration(id,person),FOREIGN KEY(reverses,person,container) REFERENCES stock_movement(id,person,container),CHECK((numerator IS NULL)=(denominator IS NULL)),CHECK((kind='actualUse')=(record IS NOT NULL)),CHECK((kind='correction')=(reverses IS NOT NULL)),CHECK((kind='correction')=(physical_choice IS NOT NULL)),CHECK((entered IS NULL)=(entered_unit IS NULL)),CHECK(numerator IS NULL OR (length(numerator) BETWEEN 1 AND 20000 AND length(denominator) BETWEEN 1 AND 20000))) STRICT''',
  'CREATE INDEX stock_movement_owner ON stock_movement(person,container,sequence)',
  "CREATE TRIGGER stock_movement_pair BEFORE INSERT ON stock_movement WHEN NEW.numerator IS NOT NULL AND (NEW.denominator GLOB '*[^0-9]*' OR substr(NEW.denominator,1,1) NOT BETWEEN '1' AND '9' OR NOT (NEW.numerator='0' OR (NEW.numerator NOT GLOB '*[^0-9]*' AND substr(NEW.numerator,1,1) BETWEEN '1' AND '9') OR (substr(NEW.numerator,1,1)='-' AND substr(NEW.numerator,2) NOT GLOB '*[^0-9]*' AND substr(NEW.numerator,2,1) BETWEEN '1' AND '9'))) BEGIN SELECT RAISE(ABORT,'stock_pair'); END",
  "CREATE TRIGGER stock_movement_semantics BEFORE INSERT ON stock_movement WHEN (NEW.kind='restock' AND (NEW.numerator IS NULL OR NEW.numerator='0' OR substr(NEW.numerator,1,1)='-')) OR (NEW.kind IN ('actualUse','waste') AND NEW.numerator IS NOT NULL AND substr(NEW.numerator,1,1)<>'-') OR (NEW.kind='waste' AND NEW.numerator IS NULL) OR (NEW.kind IN ('reconciliation','correction') AND substr(NEW.numerator,1,1)='-') OR NEW.sequence<>(SELECT sequence+1 FROM stock_container WHERE id=NEW.container AND person=NEW.person) OR NEW.strength<>(SELECT strength FROM stock_container WHERE id=NEW.container AND person=NEW.person) OR NEW.generation<>(SELECT generation FROM dataset) OR (NEW.record IS NOT NULL AND (SELECT item FROM administration WHERE id=NEW.record AND person=NEW.person)<>(SELECT item FROM stock_container WHERE id=NEW.container AND person=NEW.person)) BEGIN SELECT RAISE(ABORT,'stock_semantics'); END",
  "CREATE TRIGGER stock_correction_target BEFORE INSERT ON stock_movement WHEN NEW.kind='correction' AND NOT EXISTS(SELECT 1 FROM stock_movement old WHERE old.id=NEW.reverses AND old.person=NEW.person AND old.container=NEW.container AND old.kind IN ('actualUse','waste') AND ((NEW.physical_choice='retainPhysicalEffect' AND NEW.numerator='0' AND NEW.denominator='1') OR (NEW.physical_choice='reverseRecordedEffect' AND ((old.numerator IS NULL AND NEW.numerator IS NULL) OR (NEW.numerator=substr(old.numerator,2) AND NEW.denominator=old.denominator))))) BEGIN SELECT RAISE(ABORT,'stock_correction_target'); END",
  "CREATE TRIGGER stock_movement_immutable BEFORE UPDATE ON stock_movement BEGIN SELECT RAISE(ABORT,'immutable_stock_movement'); END",
  "CREATE TRIGGER stock_container_identity BEFORE UPDATE OF id,person,item,label,unit,strength ON stock_container BEGIN SELECT RAISE(ABORT,'immutable_stock_identity'); END",
  'ALTER TABLE ordinary_draft RENAME TO ordinary_draft_v7',
  "CREATE TABLE ordinary_draft(id TEXT PRIMARY KEY,generation TEXT NOT NULL,operation TEXT NOT NULL UNIQUE,kind TEXT NOT NULL CHECK(kind IN ('item','dose','correction','profile','dailyPlan','itemType','stockContainer','stockAdjustment')),person TEXT REFERENCES person(id),person_revision INTEGER,target TEXT,target_revision INTEGER,snapshot TEXT NOT NULL) STRICT",
  'INSERT INTO ordinary_draft SELECT * FROM ordinary_draft_v7',
  'DROP TABLE ordinary_draft_v7',
];

/// Schema 24 adds optional, descriptive pack details to an existing container
/// identity. Every column is additive and older rows read null. Capacity is
/// stored as the same exact rational pair as every other quantity; it is never
/// used as a balance cap. Each created or edited metadata state is retained in
/// an immutable history table, separate from movement revisions.
const stockMetadataSchemaV24 = [
  'ALTER TABLE stock_container ADD COLUMN lot TEXT',
  'ALTER TABLE stock_container ADD COLUMN expiry_date TEXT',
  'ALTER TABLE stock_container ADD COLUMN capacity_n TEXT',
  'ALTER TABLE stock_container ADD COLUMN capacity_d TEXT',
  '''CREATE TABLE stock_container_metadata(container TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),lot TEXT,expiry_date TEXT,capacity_n TEXT,capacity_d TEXT,source TEXT NOT NULL CHECK(source IN ('created','edited','migrated')),recorded_at INTEGER NOT NULL,PRIMARY KEY(container,revision),FOREIGN KEY(container) REFERENCES stock_container(id) ON DELETE CASCADE,CHECK((capacity_n IS NULL)=(capacity_d IS NULL))) STRICT''',
  'CREATE INDEX stock_container_metadata_owner ON stock_container_metadata(container,revision DESC)',
  "CREATE TRIGGER stock_pack_details_insert BEFORE INSERT ON stock_container WHEN (NEW.capacity_n IS NULL)<>(NEW.capacity_d IS NULL) OR (NEW.capacity_n IS NOT NULL AND (NEW.capacity_n GLOB '*[^0-9]*' OR substr(NEW.capacity_n,1,1) NOT BETWEEN '1' AND '9' OR NEW.capacity_d GLOB '*[^0-9]*' OR substr(NEW.capacity_d,1,1) NOT BETWEEN '1' AND '9')) OR (NEW.lot IS NOT NULL AND length(NEW.lot) NOT BETWEEN 1 AND 200) OR (NEW.expiry_date IS NOT NULL AND NEW.expiry_date NOT GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]') BEGIN SELECT RAISE(ABORT,'stock_pack_details'); END",
  "CREATE TRIGGER stock_pack_details_update BEFORE UPDATE OF lot,expiry_date,capacity_n,capacity_d ON stock_container WHEN (NEW.capacity_n IS NULL)<>(NEW.capacity_d IS NULL) OR (NEW.capacity_n IS NOT NULL AND (NEW.capacity_n GLOB '*[^0-9]*' OR substr(NEW.capacity_n,1,1) NOT BETWEEN '1' AND '9' OR NEW.capacity_d GLOB '*[^0-9]*' OR substr(NEW.capacity_d,1,1) NOT BETWEEN '1' AND '9')) OR (NEW.lot IS NOT NULL AND length(NEW.lot) NOT BETWEEN 1 AND 200) OR (NEW.expiry_date IS NOT NULL AND NEW.expiry_date NOT GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]') BEGIN SELECT RAISE(ABORT,'stock_pack_details'); END",
  "CREATE TRIGGER stock_metadata_immutable BEFORE UPDATE ON stock_container_metadata BEGIN SELECT RAISE(ABORT,'immutable_stock_metadata'); END",
  "INSERT INTO stock_container_metadata(container,revision,lot,expiry_date,capacity_n,capacity_d,source,recorded_at) SELECT id,revision,NULL,NULL,NULL,NULL,'migrated',0 FROM stock_container",
];

List<String>? _stockPair(ExactAmount? a) =>
    a == null ? null : [a.numerator.toString(), a.denominator.toString()];
Map<String, Object?> _strengthJson(LabelledStrength s) => {
  'ingredient': s.ingredientId,
  'label': s.label,
  'pair': _stockPair(s.mgPerMl),
};
LabelledStrength _strengthDecode(Object encoded) {
  final m = encoded is String
      ? jsonDecode(encoded) as Map<String, dynamic>
      : encoded as Map<String, dynamic>;
  final p = m['pair'] as List<dynamic>?;
  return LabelledStrength(
    ingredientId: m['ingredient'] as String,
    label: m['label'] as String,
    mgPerMl: p == null
        ? null
        : ExactAmount.fromStorage(p[0] as String, p[1] as String),
  );
}

Map<String, Object?>? _replacementJson(StockReplacement? r) => r == null
    ? null
    : {
        'old': _strengthJson(r.oldStrength),
        'new': _strengthJson(r.newStrength),
        'keep': r.keep.name,
      };
StockReplacement? _replacementDecode(Object? encoded) {
  if (encoded == null) return null;
  final m = jsonDecode(encoded as String) as Map<String, dynamic>;
  return StockReplacement(
    oldStrength: _strengthDecode(m['old'] as Object),
    newStrength: _strengthDecode(m['new'] as Object),
    keep: FixedReplacementAmount.values.byName(m['keep'] as String),
  );
}

List<Object?>? _stockUsePayload(StockUseInput? use) => use == null
    ? null
    : [
        use.expectedGeneration,
        use.containerId,
        use.expectedContainerRevision,
        use.entered.originalText,
        use.entered.unit,
        _replacementJson(use.replacement),
        use.strength == null ? null : _strengthJson(use.strength!),
      ];
ExactAmount? _storedPair(Map<String, Object?> r, String n, String d) {
  if ((r[n] == null) != (r[d] == null)) {
    throw const FormatException('rational_pair');
  }
  return r[n] == null
      ? null
      : ExactAmount.fromStorage(r[n] as String, r[d] as String);
}

extension StockRecordStore on RecordStore {
  void _stockGeneration(String expected) {
    if (expected != generation) throw const CommandConflict('generation');
  }

  void _stockAmountBound(ExactAmount? a, {bool nonnegative = false}) {
    if (a == null) return;
    ExactAmount.fromStorage(a.numerator.toString(), a.denominator.toString());
    if (nonnegative && a < ExactAmount.zero) {
      throw const FormatException('negative_stock');
    }
  }

  void _stockStrengthBound(LabelledStrength strength) {
    if (strength.label.isEmpty ||
        strength.label.length > 4000 ||
        strength.ingredientId.isEmpty ||
        strength.ingredientId.length > 256) {
      throw const FormatException('strength_fields');
    }
    final value = strength.mgPerMl;
    _stockAmountBound(value);
    if (value != null) {
      final scaled = value * ExactAmount(BigInt.from(1000000));
      if (value > ExactAmount.maxEntered || scaled.denominator != BigInt.one) {
        throw const FormatException('strength_entry_bounds');
      }
    }
  }

  bool _stockNoticeEligible(Map<String, Object?> row) {
    final configured = row['refill'] == 1 || row['threshold_n'] != null;
    final balance = _storedPair(row, 'numerator', 'denominator');
    if (row['balance_status'] != 'known') return configured;
    if (balance == null) {
      throw const FormatException('known_stock_without_balance');
    }
    if (balance < ExactAmount.zero) return true;
    if (row['refill'] == 1 && balance <= ExactAmount.zero) return true;
    final threshold = _storedPair(row, 'threshold_n', 'threshold_d');
    return threshold != null && balance <= threshold;
  }

  Future<void> _refreshStockNotice(String id) async {
    final row = (await _rows('SELECT * FROM stock_container WHERE id=?', [
      id,
    ])).single;
    await _db.customStatement(
      'UPDATE stock_container SET notice_eligible=? WHERE id=?',
      [_stockNoticeEligible(row) ? 1 : 0, id],
    );
  }

  Future<StockNoticePage> stockNotices({
    required FeedScope scope,
    int limit = 50,
    int offset = 0,
  }) async {
    _pageBounds(limit, offset);
    final rows = await _rows(
      'SELECT c.*,p.name AS person_name,i.name AS item_name FROM stock_container c JOIN person p ON p.id=c.person JOIN item i ON i.id=c.item AND i.person=c.person WHERE c.notice_active=1 AND c.notice_eligible=1 AND p.archived=0${scope.isEveryone ? '' : ' AND c.person=?'} ORDER BY c.person,c.item,c.id LIMIT ? OFFSET ?',
      [if (!scope.isEveryone) scope.personId, limit + 1, offset],
    );
    return StockNoticePage(
      rows: rows
          .take(limit)
          .map(
            (r) => StockNoticeRow(
              container: _stockContainer(r),
              personName: r['person_name'] as String,
              itemName: r['item_name'] as String,
            ),
          ),
      hasMore: rows.length > limit,
    );
  }

  Stream<StockNoticePage> watchStockNotices({
    required FeedScope scope,
    int limit = 50,
    int offset = 0,
  }) => _watch(() => stockNotices(scope: scope, limit: limit, offset: offset));
  StoredStockContainer _stockContainer(Map<String, Object?> r) {
    if (r['notice_eligible'] != (_stockNoticeEligible(r) ? 1 : 0)) {
      throw const FormatException('stock_notice_projection');
    }
    return StoredStockContainer(
      id: r['id'] as String,
      personId: r['person'] as String,
      itemId: r['item'] as String,
      label: r['label'] as String,
      unit: r['unit'] as String,
      strength: _strengthDecode(r['strength'] as String),
      productLabel: _productLabelRead(r['product_label']),
      revision: r['revision'] as int,
      sequence: r['sequence'] as int,
      balance: StockBalance(
        _storedPair(r, 'numerator', 'denominator'),
        limitReached: r['balance_status'] == 'limit',
      ),
      lowThreshold: _storedPair(r, 'threshold_n', 'threshold_d'),
      lot: r['lot'] as String?,
      expiryDate: switch (r['expiry_date']) {
        final String value when value.isNotEmpty => CivilDate.parse(value),
        _ => null,
      },
      capacity: _storedPair(r, 'capacity_n', 'capacity_d'),
      refillEnabled: r['refill'] == 1,
      alreadyCommitted: r['replay'] == true,
    );
  }

  Future<StoredStockContainer?> stockContainerById({
    required String personId,
    required String containerId,
  }) async {
    final rows = await _rows(
      'SELECT * FROM stock_container WHERE id=? AND person=?',
      [containerId, personId],
    );
    return rows.isEmpty ? null : _stockContainer(rows.single);
  }

  Stream<StoredStockContainer?> watchStockContainerById({
    required String personId,
    required String containerId,
  }) => _watch(
    () => stockContainerById(personId: personId, containerId: containerId),
  );
  Future<List<StoredStockContainer>> stockContainers({
    required String personId,
    String? itemId,
    int limit = 100,
    int offset = 0,
  }) async {
    _pageBounds(limit, offset);
    return (await _rows(
      'SELECT * FROM stock_container WHERE person=?${itemId == null ? '' : ' AND item=?'} ORDER BY ${itemId == null ? 'item,' : ''}id LIMIT ? OFFSET ?',
      [personId, ?itemId, limit, offset],
    )).map(_stockContainer).toList();
  }

  Stream<List<StoredStockContainer>> watchStockContainers({
    required String personId,
    String? itemId,
    int limit = 100,
    int offset = 0,
  }) => _watch(
    () => stockContainers(
      personId: personId,
      itemId: itemId,
      limit: limit,
      offset: offset,
    ),
  );
  Future<Map<String, Object?>> _stockContext(
    String person,
    String container,
    int expected,
  ) async {
    final rows = await _rows(
      'SELECT * FROM stock_container WHERE id=? AND person=?',
      [container, person],
    );
    if (rows.isEmpty) throw const CommandConflict('stock_ownership');
    if (rows.single['revision'] != expected) {
      throw const CommandConflict('stock_revision');
    }
    return rows.single;
  }

  Future<StoredStockContainer> createStockContainer({
    required String commandId,
    required String personId,
    required int expectedPersonRevision,
    required String expectedGeneration,
    required String itemId,
    required String label,
    required String unit,
    required LabelledStrength strength,
    ProductLabelSnapshot? productLabel,
    ExactAmount? opening,
    ExactAmount? lowThreshold,
    String? lot,
    CivilDate? expiryDate,
    ExactAmount? capacity,
    bool refillEnabled = false,
    bool failBeforeCommit = false,
  }) async {
    _stockGeneration(expectedGeneration);
    if (label.trim().isEmpty ||
        label.length > 500 ||
        !const {'mg', 'ml', 'count'}.contains(unit) ||
        strength.label.length > 4000 ||
        strength.ingredientId.length > 256) {
      throw const FormatException('stock_fields');
    }
    _stockAmountBound(opening, nonnegative: true);
    _stockAmountBound(lowThreshold, nonnegative: true);
    _stockStrengthBound(strength);
    final packLot = _stockLot(lot);
    final packCapacity = _stockCapacity(capacity);
    final snapshot = jsonEncode(_strengthJson(strength));
    return _stockContainer(
      await _command(
        commandId,
        [
          'stock_container',
          personId,
          itemId,
          label,
          unit,
          snapshot,
          _stockPair(opening),
          _stockPair(lowThreshold),
          refillEnabled,
          expectedPersonRevision,
          if (packLot != null ||
              expiryDate != null ||
              packCapacity != null) ...[
            packLot,
            expiryDate?.toString(),
            _stockPair(packCapacity),
          ],
          if (productLabel != null) productLabel.toJson(),
        ],
        () async {
          await _activeOwner(personId, expectedPersonRevision);
          if (await itemById(itemId, personId: personId) == null) {
            throw const CommandConflict('ownership');
          }
          final currentProduct = await this.productLabel(
            personId: personId,
            itemId: itemId,
          );
          if ((currentProduct != null) != (productLabel != null) ||
              (productLabel != null &&
                  (unit != 'ml' ||
                      productLabel.personId != personId ||
                      productLabel.itemId != itemId))) {
            throw const CommandConflict('product_source');
          }
          final id = newCommandId();
          await _db.customStatement(
            'INSERT INTO stock_container(id,person,item,label,unit,strength,revision,sequence,measurement_sequence,balance_status,numerator,denominator,threshold_n,threshold_d,refill,product_label,lot,expiry_date,capacity_n,capacity_d) VALUES (?,?,?,?,?,?,1,0,0,\'unknown\',NULL,NULL,?,?,?,?,?,?,?,?)',
            [
              id,
              personId,
              itemId,
              label,
              unit,
              snapshot,
              lowThreshold?.numerator.toString(),
              lowThreshold?.denominator.toString(),
              refillEnabled ? 1 : 0,
              productLabel == null ? null : jsonEncode(productLabel.toJson()),
              packLot,
              expiryDate?.toString(),
              packCapacity?.numerator.toString(),
              packCapacity?.denominator.toString(),
            ],
          );
          await _db.customStatement(
            'INSERT INTO stock_container_metadata(container,revision,lot,expiry_date,capacity_n,capacity_d,source,recorded_at) VALUES (?,1,?,?,?,?,\'created\',?)',
            [
              id,
              packLot,
              expiryDate?.toString(),
              packCapacity?.numerator.toString(),
              packCapacity?.denominator.toString(),
              DateTime.now().microsecondsSinceEpoch,
            ],
          );
          final row = (await _rows('SELECT * FROM stock_container WHERE id=?', [
            id,
          ])).single;
          await _appendStock(
            row,
            commandId,
            StockMovementKind.reconciliation,
            opening,
          );
          return (await _rows('SELECT * FROM stock_container WHERE id=?', [
            id,
          ])).single;
        },
        failBeforeCommit: failBeforeCommit,
      ),
    );
  }

  /// Trims an optional lot or batch. Empty entry means no lot is recorded.
  String? _stockLot(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    if (text.length > 200) throw const FormatException('stock_lot');
    return text;
  }

  /// Capacity is descriptive and must be a positive exact amount in the
  /// container's own unit. It never becomes a balance limit.
  ExactAmount? _stockCapacity(ExactAmount? value) {
    if (value == null) return null;
    if (value <= ExactAmount.zero) {
      throw const FormatException('stock_capacity');
    }
    _stockAmountBound(value);
    return value;
  }

  /// Edits the optional pack facts without touching the ledger, the balance,
  /// the current strength snapshot or any saved movement. The container
  /// revision is the optimistic guard; the command identity makes a retry
  /// after a lost reply idempotent.
  Future<StoredStockContainer> updateStockMetadata({
    required String commandId,
    required String personId,
    required int expectedPersonRevision,
    required String expectedGeneration,
    required String containerId,
    required int expectedContainerRevision,
    String? lot,
    CivilDate? expiryDate,
    ExactAmount? capacity,
  }) async {
    _stockGeneration(expectedGeneration);
    final packLot = _stockLot(lot);
    final packCapacity = _stockCapacity(capacity);
    return _stockContainer(
      await _command(
        commandId,
        [
          'stock_metadata',
          personId,
          containerId,
          expectedContainerRevision,
          expectedPersonRevision,
          packLot,
          expiryDate?.toString(),
          _stockPair(packCapacity),
        ],
        () async {
          await _activeOwner(personId, expectedPersonRevision);
          await _stockContext(personId, containerId, expectedContainerRevision);
          await _db.customStatement(
            'UPDATE stock_container SET lot=?,expiry_date=?,capacity_n=?,capacity_d=?,revision=revision+1 WHERE id=?',
            [
              packLot,
              expiryDate?.toString(),
              packCapacity?.numerator.toString(),
              packCapacity?.denominator.toString(),
              containerId,
            ],
          );
          final row = (await _rows(
            'SELECT revision FROM stock_container WHERE id=?',
            [containerId],
          )).single;
          await _db.customStatement(
            'INSERT INTO stock_container_metadata(container,revision,lot,expiry_date,capacity_n,capacity_d,source,recorded_at) VALUES (?,?,?,?,?,?,\'edited\',?)',
            [
              containerId,
              row['revision'],
              packLot,
              expiryDate?.toString(),
              packCapacity?.numerator.toString(),
              packCapacity?.denominator.toString(),
              DateTime.now().microsecondsSinceEpoch,
            ],
          );
          return (await _rows('SELECT * FROM stock_container WHERE id=?', [
            containerId,
          ])).single;
        },
      ),
    );
  }

  /// Immutable pack-detail history, newest first. Movement revisions are not
  /// metadata edits and therefore do not create rows here.
  Future<List<StoredStockMetadataRevision>> stockMetadataHistory({
    required String personId,
    required String containerId,
    int limit = 20,
    int offset = 0,
  }) async {
    _requireWritable();
    _pageBounds(limit, offset);
    final rows = await _rows(
      'SELECT m.* FROM stock_container_metadata m JOIN stock_container c ON c.id=m.container AND c.person=? WHERE m.container=? ORDER BY m.revision DESC LIMIT ? OFFSET ?',
      [personId, containerId, limit, offset],
    );
    _requireWritable();
    return [
      for (final row in rows)
        StoredStockMetadataRevision(
          containerId: row['container'] as String,
          revision: row['revision'] as int,
          lot: row['lot'] as String?,
          expiryDate: switch (row['expiry_date']) {
            final String value when value.isNotEmpty => CivilDate.parse(value),
            _ => null,
          },
          capacity: _storedPair(row, 'capacity_n', 'capacity_d'),
          source: row['source'] as String,
          recordedAt: DateTime.fromMicrosecondsSinceEpoch(
            row['recorded_at'] as int,
            isUtc: true,
          ),
        ),
    ];
  }

  Stream<List<StoredStockMetadataRevision>> watchStockMetadataHistory({
    required String personId,
    required String containerId,
    int limit = 20,
    int offset = 0,
  }) => _watch(
    () => stockMetadataHistory(
      personId: personId,
      containerId: containerId,
      limit: limit,
      offset: offset,
    ),
  );

  static const _stockInventoryBound = 2000;

  StockInventoryBalance _stockInventoryBalance(StoredStockContainer c) {
    final value = c.balance.value;
    if (value == null || c.balance.limitReached) {
      return StockInventoryBalance.unknown;
    }
    if (value < ExactAmount.zero) return StockInventoryBalance.low;
    if (c.refillEnabled && value <= ExactAmount.zero) {
      return StockInventoryBalance.low;
    }
    final threshold = c.lowThreshold;
    if (threshold != null && value <= threshold) {
      return StockInventoryBalance.low;
    }
    if (value > ExactAmount.zero) return StockInventoryBalance.adequate;
    // A known zero without a refill rule is still not adequate.
    return StockInventoryBalance.low;
  }

  /// Whole-collection inventory read. Search, the item scope, the inventory
  /// filter and every count use this one store-backed snapshot, never only the
  /// first loaded page. The plan state comes from the same bounded status
  /// projection used by the Substances list.
  Future<StockInventorySnapshot> stockInventory({
    required String personId,
    required DateTime now,
    String? observedZone,
    String? itemId,
    String search = '',
    StockInventoryFilter filter = StockInventoryFilter.all,
  }) async {
    _requireWritable();
    return _db.transaction(() async {
      _requireWritable();
      final query = search.trim();
      final conditions = <String>['c.person=?', 'o.archived=0'];
      final args = <Object?>[personId];
      if (itemId != null) {
        conditions.add('c.item=?');
        args.add(itemId);
      }
      if (query.isNotEmpty) {
        conditions.add(
          r"(i.name LIKE ? ESCAPE '\' OR c.label LIKE ? ESCAPE '\')",
        );
        final escaped = '%${RecordStore._escapeLike(query)}%';
        args
          ..add(escaped)
          ..add(escaped);
      }
      final rows = await _rows(
        'SELECT c.*,i.name AS item_name FROM stock_container c JOIN item i ON i.id=c.item AND i.person=c.person JOIN person o ON o.id=c.person WHERE ${conditions.join(' AND ')} ORDER BY i.name,c.id LIMIT ?',
        [...args, _stockInventoryBound + 1],
      );
      final complete = rows.length <= _stockInventoryBound;
      final candidates = rows
          .take(_stockInventoryBound)
          .map(_stockContainer)
          .toList();

      final statuses = await substanceStatusSnapshot(
        personId: personId,
        scope: FeedScope.person(personId),
        now: now,
        observedZone: observedZone,
      );

      final balances = <String, StockInventoryBalance>{};
      final planStates = <String, StockInventoryPlanState>{};
      var low = 0, adequate = 0, unknown = 0, paused = 0, unresolved = 0;
      for (final container in candidates) {
        final balance = _stockInventoryBalance(container);
        balances[container.id] = balance;
        switch (balance) {
          case StockInventoryBalance.low:
            low++;
          case StockInventoryBalance.adequate:
            adequate++;
          case StockInventoryBalance.unknown:
            unknown++;
        }
        final itemStatuses = statuses.statusesFor(container.itemId);
        final itemUnresolved = statuses.isUnresolved(container.itemId);
        final planState = itemUnresolved
            ? StockInventoryPlanState.unresolved
            : itemStatuses.contains(SubstancePlanStatus.paused)
            ? (itemStatuses.contains(SubstancePlanStatus.active) ||
                      itemStatuses.contains(SubstancePlanStatus.asNeeded)
                  ? StockInventoryPlanState.mixed
                  : StockInventoryPlanState.paused)
            : itemStatuses.contains(SubstancePlanStatus.active)
            ? StockInventoryPlanState.active
            : itemStatuses.contains(SubstancePlanStatus.asNeeded)
            ? StockInventoryPlanState.asNeeded
            : StockInventoryPlanState.unscheduled;
        planStates[container.id] = planState;
        if (planState == StockInventoryPlanState.paused ||
            planState == StockInventoryPlanState.mixed) {
          paused++;
        }
        if (itemUnresolved) unresolved++;
      }

      final filtered = candidates.where((container) {
        return switch (filter) {
          StockInventoryFilter.all => true,
          StockInventoryFilter.low =>
            balances[container.id] == StockInventoryBalance.low,
          StockInventoryFilter.adequate =>
            balances[container.id] == StockInventoryBalance.adequate,
          StockInventoryFilter.unknown =>
            balances[container.id] == StockInventoryBalance.unknown,
          StockInventoryFilter.paused =>
            planStates[container.id] == StockInventoryPlanState.paused ||
                planStates[container.id] == StockInventoryPlanState.mixed,
        };
      }).toList();

      _requireWritable();
      return StockInventorySnapshot(
        containers: filtered,
        balances: balances,
        planStates: planStates,
        complete: complete,
        counts: StockInventoryCounts(
          all: candidates.length,
          low: low,
          adequate: adequate,
          paused: paused,
          unknown: unknown,
          unresolved: unresolved,
        ),
      );
    });
  }

  Stream<StockInventorySnapshot> watchStockInventory({
    required String personId,
    required DateTime now,
    String? observedZone,
    String? itemId,
    String search = '',
    StockInventoryFilter filter = StockInventoryFilter.all,
  }) => _watch(
    () => stockInventory(
      personId: personId,
      now: now,
      observedZone: observedZone,
      itemId: itemId,
      search: search,
      filter: filter,
    ),
  );

  /// One container's bounded schedule projection. It reads the same saved
  /// versions, phases, pauses and ends as the occurrence resolver.
  Future<StockRunOutForecast?> stockForecastForContainer({
    required String personId,
    required String containerId,
    required DateTime now,
    String? observedZone,
  }) async {
    _requireWritable();
    return _db.transaction(() async {
      _requireWritable();
      final row = (await _rows(
        'SELECT * FROM stock_container WHERE id=? AND person=?',
        [containerId, personId],
      )).firstOrNull;
      if (row == null) return null;
      final container = _stockContainer(row);
      final saved = await dailyPlans(
        scope: FeedScope.person(personId),
        itemId: container.itemId,
        limit: 101,
      );
      if (saved.length > 100) {
        return const StockRunOutForecast.unavailable(
          StockForecastReason.unsupportedSchedule,
        );
      }
      final plans = <PhasePlan>[];
      for (final entry in saved) {
        try {
          final phase = await phasePlan(
            planId: entry.plan.planId,
            personId: personId,
          );
          plans.add(phase ?? PhasePlan(phases: [entry.plan]));
        } on Object {
          return const StockRunOutForecast.unavailable(
            StockForecastReason.unsupportedSchedule,
          );
        }
      }
      _requireWritable();
      return forecastStockRunOut(
        balance: container.balance,
        unit: container.unit,
        strength: container.strength,
        plans: plans,
        now: now,
        observedZone: observedZone,
      );
    });
  }

  Stream<StockRunOutForecast?> watchStockForecast({
    required String personId,
    required String containerId,
    required DateTime now,
    String? observedZone,
  }) => _watch(
    () => stockForecastForContainer(
      personId: personId,
      containerId: containerId,
      now: now,
      observedZone: observedZone,
    ),
  );

  Future<StoredStockContainer> configureStockNotices({
    required String commandId,
    required String personId,
    required int expectedPersonRevision,
    required String expectedGeneration,
    required String containerId,
    required int expectedContainerRevision,
    ExactAmount? lowThreshold,
    required bool refillEnabled,
  }) async {
    _stockGeneration(expectedGeneration);
    _stockAmountBound(lowThreshold, nonnegative: true);
    return _stockContainer(
      await _command(
        commandId,
        [
          'stock_notices',
          personId,
          containerId,
          expectedContainerRevision,
          expectedPersonRevision,
          _stockPair(lowThreshold),
          refillEnabled,
        ],
        () async {
          await _activeOwner(personId, expectedPersonRevision);
          await _stockContext(personId, containerId, expectedContainerRevision);
          await _db.customStatement(
            'UPDATE stock_container SET threshold_n=?,threshold_d=?,refill=?,revision=revision+1 WHERE id=?',
            [
              lowThreshold?.numerator.toString(),
              lowThreshold?.denominator.toString(),
              refillEnabled ? 1 : 0,
              containerId,
            ],
          );
          await _refreshStockNotice(containerId);
          return (await _rows('SELECT * FROM stock_container WHERE id=?', [
            containerId,
          ])).single;
        },
      ),
    );
  }

  /// Relocates one pre-variant stock-adjustment notices draft, still stored at
  /// the shared quantity key, to the stable notices variant key. The move is
  /// one guarded transaction: exact stockAdjustment/person/raw-container
  /// identity, notices fields, a free destination, and an operation that is
  /// neither committed nor invalidated are all verified before the row id
  /// alone changes. Content, captured revisions, dataset generation and the
  /// pending operation identity are preserved exactly. Returning null means
  /// no legacy row exists to adopt; a refusal surfaces as a conflict rather
  /// than dropping either draft.
  Future<OrdinaryDraft?> relocateLegacyStockNoticesDraft({
    required String legacyId,
    required String destinationId,
    required String personId,
    required String targetId,
  }) async {
    _requireWritable();
    OrdinaryDraft? adopted;
    String? legacyOperationId;
    await _db.transaction(() async {
      await _db.customStatement('UPDATE dataset SET generation=generation');
      if ((await _rows('SELECT generation FROM dataset'))
              .single['generation'] !=
          generation) {
        throw const CommandConflict('generation');
      }
      // A late captured callback for the legacy key cannot recreate its row:
      // the preserved operation keeps ordinary_draft.operation UNIQUE, so any
      // such upsert fails without touching either draft.
      final rows = await _rows(
        'SELECT * FROM ordinary_draft WHERE id=? AND generation=?',
        [legacyId, generation],
      );
      if (rows.isEmpty) return;
      final legacy = OrdinaryDraft.decode(rows.single);
      if (legacy.kind != DraftKind.stockAdjustment ||
          legacy.personId != personId ||
          legacy.targetId != targetId ||
          legacy.fields['kind'] != 'notices' ||
          legacyId == destinationId) {
        throw const CommandConflict('draft_identity');
      }
      if ((await _rows('SELECT id FROM ordinary_draft WHERE id=?', [
        destinationId,
      ])).isNotEmpty) {
        // Never drop or overwrite either draft when both already exist.
        throw const CommandConflict('draft_identity');
      }
      // Never replay a committed intent and never resurrect an invalidated one.
      if ((await _rows('SELECT id FROM operation WHERE id=?', [
        legacy.operationId,
      ])).isNotEmpty) {
        throw const CommandConflict('draft_identity');
      }
      await _db.customStatement(
        'UPDATE ordinary_draft SET id=? WHERE id=? AND generation=?',
        [destinationId, legacyId, generation],
      );
      _capturedDraftOperations.remove(legacyId);
      legacyOperationId = legacy.operationId;
      adopted = OrdinaryDraft.decode(
        (await _rows('SELECT * FROM ordinary_draft WHERE id=?', [
          destinationId,
        ])).single,
      );
    });
    if (adopted != null) {
      // Only a committed move fences the identity, so a refused or rolled
      // back migration never leaves a false fence: the legacy key keeps
      // working for captures of its own rows.
      _fenceMigratedDraftIdentity(legacyId, legacyOperationId!, destinationId);
      _draftChanges.add(null);
      _changes.add(null);
    }
    return adopted;
  }

  Future<StoredStockContainer> addStockMovement({
    required String commandId,
    required String personId,
    required int expectedPersonRevision,
    required String expectedGeneration,
    required String containerId,
    required int expectedContainerRevision,
    required StockMovementKind kind,
    EnteredStockAmount? amount,
    ExactAmount? measured,
    String? reason,
    bool failBeforeCommit = false,
  }) async {
    _stockGeneration(expectedGeneration);
    _stockAmountBound(measured, nonnegative: true);
    if (reason != null && reason.length > 4000) {
      throw const FormatException('stock_reason');
    }
    if (!const {
          StockMovementKind.restock,
          StockMovementKind.waste,
          StockMovementKind.reconciliation,
        }.contains(kind) ||
        (kind == StockMovementKind.reconciliation
            ? amount != null
            : amount == null || measured != null)) {
      throw const FormatException('stock_adjustment');
    }
    return _stockContainer(
      await _command(
        commandId,
        [
          'stock_adjust',
          personId,
          containerId,
          expectedContainerRevision,
          expectedPersonRevision,
          kind.name,
          amount?.originalText,
          amount?.unit,
          _stockPair(measured),
          reason,
        ],
        () async {
          await _activeOwner(personId, expectedPersonRevision);
          final row = await _stockContext(
            personId,
            containerId,
            expectedContainerRevision,
          );
          ExactAmount? delta = measured;
          if (amount != null) {
            delta = _strengthDecode(row['strength'] as String).equivalent(
              amount.value,
              from: amount.unit,
              to: row['unit'] as String,
            );
            if (delta == null) throw const CommandConflict('stock_conversion');
            if (kind == StockMovementKind.waste) delta = -delta;
          }
          await _appendStock(
            row,
            commandId,
            kind,
            delta,
            entered: amount,
            reason: reason,
          );
          return (await _rows('SELECT * FROM stock_container WHERE id=?', [
            containerId,
          ])).single;
        },
        failBeforeCommit: failBeforeCommit,
      ),
    );
  }

  /// Applies one immutable fact to the same-transaction checkpoint. Correction
  /// targets are indexed point reads, never a replay of the container history.
  Future<void> _appendStock(
    Map<String, Object?> row,
    String operation,
    StockMovementKind kind,
    ExactAmount? delta, {
    EnteredStockAmount? entered,
    String? recordId,
    StoredStockMovement? target,
    PhysicalCorrection? choice,
    StockReplacement? replacement,
    String? reason,
  }) async {
    _stockAmountBound(delta);
    final sequence = (row['sequence'] as int) + 1;
    final measurement = row['measurement_sequence'] as int;
    var limit = row['balance_status'] == 'limit';
    var balance = _storedPair(row, 'numerator', 'denominator');
    final beforeMeasurement = target != null && target.sequence <= measurement;
    if (kind == StockMovementKind.reconciliation) {
      balance = delta;
      limit = false;
    } else if (!beforeMeasurement && !limit) {
      if (delta != null &&
          (delta.numerator.bitLength > 65536 ||
              delta.denominator.bitLength > 65536)) {
        balance = null;
        limit = true;
      } else {
        balance = balance == null || delta == null ? null : balance + delta;
      }
    }
    if (balance != null &&
        (balance.numerator.bitLength > 65536 ||
            balance.denominator.bitLength > 65536 ||
            balance.numerator.toString().length > 20000 ||
            balance.denominator.toString().length > 20000)) {
      balance = null;
      limit = true;
    }
    if (delta != null &&
        (delta.numerator.bitLength > 65536 ||
            delta.denominator.bitLength > 65536) &&
        kind != StockMovementKind.correction) {
      balance = null;
      limit = true;
    }
    await _db.customStatement(
      'INSERT INTO stock_movement VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        newCommandId(),
        row['person'],
        row['id'],
        sequence,
        kind.name,
        delta?.numerator.toString(),
        delta?.denominator.toString(),
        row['strength'],
        entered?.originalText,
        entered?.unit,
        recordId,
        target?.id,
        choice?.name,
        replacement == null ? null : jsonEncode(_replacementJson(replacement)),
        reason,
        operation,
        generation,
        DateTime.now().microsecondsSinceEpoch,
      ],
    );
    await _db.customStatement(
      'UPDATE stock_container SET sequence=?,measurement_sequence=?,revision=revision+1,balance_status=?,numerator=?,denominator=? WHERE id=?',
      [
        sequence,
        kind == StockMovementKind.reconciliation ? sequence : measurement,
        limit
            ? 'limit'
            : balance == null
            ? 'unknown'
            : 'known',
        balance?.numerator.toString(),
        balance?.denominator.toString(),
        row['id'],
      ],
    );
    await _refreshStockNotice(row['id'] as String);
  }

  Future<Map<String, Object?>> _consumeStock(
    String command,
    String person,
    String item,
    String recordId,
    StockUseInput? use,
    String itemUnit,
    String originalAmount,
  ) async {
    if (use == null) return {};
    _stockGeneration(use.expectedGeneration);
    if (use.entered.value != ExactAmount.parseEntry(originalAmount)) {
      throw const FormatException('stock_entry_mismatch');
    }
    Map<String, Object?>? row;
    if (use.containerId != null) {
      if (use.expectedContainerRevision == null) {
        throw const CommandConflict('stock_revision');
      }
      row = await _stockContext(
        person,
        use.containerId!,
        use.expectedContainerRevision!,
      );
      if (row['item'] != item) throw const CommandConflict('stock_item');
    }
    final strength = row == null
        ? use.strength
        : _strengthDecode(row['strength'] as String);
    if (strength == null) {
      throw const FormatException('labelled_strength_required');
    }
    _stockStrengthBound(strength);
    final replacement = use.replacement;
    ExactAmount? physical;
    var actual = use.entered.value;
    var actualUnit = use.entered.unit;
    if (replacement == null) {
      physical = row == null
          ? null
          : strength.equivalent(
              actual,
              from: actualUnit,
              to: row['unit'] as String,
            );
    } else {
      if (jsonEncode(_strengthJson(replacement.newStrength)) !=
          jsonEncode(_strengthJson(strength))) {
        throw const CommandConflict('stock_strength');
      }
      _stockStrengthBound(replacement.oldStrength);
      final result = ReplacementAmounts.calculate(
        entered: use.entered,
        oldStrength: replacement.oldStrength,
        newStrength: replacement.newStrength,
        keep: replacement.keep,
      );
      if (result != null) {
        actualUnit = const {'mg', 'ml'}.contains(itemUnit)
            ? itemUnit
            : use.entered.unit;
        actual = actualUnit == 'mg' ? result.milligrams : result.millilitres;
        physical = row == null
            ? null
            : switch (row['unit']) {
                'mg' => result.milligrams,
                'ml' => result.millilitres,
                _ => null,
              };
      }
    }
    _stockAmountBound(actual);
    if (row != null) {
      await _appendStock(
        row,
        command,
        StockMovementKind.actualUse,
        physical == null ? null : -physical,
        entered: use.entered,
        recordId: recordId,
        replacement: replacement,
      );
    }
    return {
      'actual_n': actual.numerator.toString(),
      'actual_d': actual.denominator.toString(),
      'actual_unit': actualUnit,
      'original_entry': use.entered.originalText,
      'original_unit': use.entered.unit,
      'quantity_strength': jsonEncode(_strengthJson(strength)),
      'quantity_replacement': replacement == null
          ? null
          : jsonEncode(_replacementJson(replacement)),
    };
  }

  StoredStockMovement _stockMovement(Map<String, Object?> r) {
    final kind = StockMovementKind.values.byName(r['kind'] as String);
    final amount = _storedPair(r, 'numerator', 'denominator');
    if ((kind == StockMovementKind.restock &&
            (amount == null || amount <= ExactAmount.zero)) ||
        ((kind == StockMovementKind.actualUse ||
                kind == StockMovementKind.waste) &&
            amount != null &&
            amount.compareTo(ExactAmount.zero) >= 0) ||
        (kind == StockMovementKind.reconciliation &&
            amount != null &&
            amount < ExactAmount.zero) ||
        (kind == StockMovementKind.correction &&
            amount != null &&
            amount < ExactAmount.zero)) {
      throw const FormatException('stock_movement_sign');
    }
    return StoredStockMovement(
      id: r['id'] as String,
      personId: r['person'] as String,
      containerId: r['container'] as String,
      sequence: r['sequence'] as int,
      kind: kind,
      amount: amount,
      strength: _strengthDecode(r['strength'] as String),
      recordedAt: DateTime.fromMicrosecondsSinceEpoch(
        r['recorded_at'] as int,
        isUtc: true,
      ),
      recordId: r['record'] as String?,
      enteredText: r['entered'] as String?,
      enteredUnit: r['entered_unit'] as String?,
      reversesId: r['reverses'] as String?,
      physicalCorrection: r['physical_choice'] == null
          ? null
          : PhysicalCorrection.values.byName(r['physical_choice'] as String),
      reviewedCorrection: r['reviewed_choice'] == null
          ? null
          : PhysicalCorrection.values.byName(r['reviewed_choice'] as String),
      replacement: _replacementDecode(r['replacement']),
      reason: r['reason'] as String?,
    );
  }

  static const _movementSelect =
      'SELECT m.*,c.physical_choice AS reviewed_choice FROM stock_movement m LEFT JOIN stock_movement c ON c.reverses=m.id';
  Future<List<StoredStockMovement>> stockMovements({
    required String personId,
    required String containerId,
    int limit = 100,
    int offset = 0,
  }) async {
    _pageBounds(limit, offset);
    return (await _rows(
      '$_movementSelect WHERE m.person=? AND m.container=? ORDER BY m.sequence DESC LIMIT ? OFFSET ?',
      [personId, containerId, limit, offset],
    )).map(_stockMovement).toList();
  }

  Future<StoredStockMovement?> stockUseForRecord({
    required String personId,
    required String recordId,
  }) async {
    final rows = await _rows(
      '$_movementSelect WHERE m.person=? AND m.record=?',
      [personId, recordId],
    );
    return rows.isEmpty ? null : _stockMovement(rows.single);
  }

  Stream<StoredStockMovement?> watchStockUseForRecord({
    required String personId,
    required String recordId,
  }) => _watch(() => stockUseForRecord(personId: personId, recordId: recordId));
  Future<void> _correctStock(
    String command,
    String person,
    String record,
    PhysicalCorrection? choice,
  ) async {
    final target = await stockUseForRecord(personId: person, recordId: record);
    if (target == null) {
      if (choice != null) throw const CommandConflict('stock_unlinked');
      return;
    }
    if (choice == null) throw const CommandConflict('stock_choice');
    if (target.reviewedCorrection != null) {
      if (choice != PhysicalCorrection.retainPhysicalEffect) {
        throw const CommandConflict('stock_already_corrected');
      }
      return;
    }
    final row = (await _rows(
      'SELECT * FROM stock_container WHERE id=? AND person=?',
      [target.containerId, person],
    )).single;
    final delta = choice == PhysicalCorrection.retainPhysicalEffect
        ? ExactAmount.zero
        : target.amount == null
        ? null
        : -target.amount!;
    await _appendStock(
      row,
      command,
      StockMovementKind.correction,
      delta,
      target: target,
      choice: choice,
    );
  }
}
