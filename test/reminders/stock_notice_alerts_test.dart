import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/app/reminder_reconciler.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/platform/reminders.dart';

/// Native stock notices sit on the existing reminder engine. These checks keep
/// the durable one-episode behaviour independent of a real Android adapter.
void main() {
  late Directory directory;
  late String path;
  late RecordStore store;
  final key = List.generate(32, (i) => i + 71);
  final now = DateTime.utc(2026, 10, 22, 12);
  ExactAmount n(int value) => ExactAmount(BigInt.from(value));

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-stock-alert-');
    path = '${directory.path}/records.db';
    store = await RecordStore.open(path: path, key: key, isNew: true);
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  Future<SubstanceItem> item(String name) => store.createItem(
    commandId: newCommandId(),
    expectedPersonRevision: 1,
    name: name,
    form: 'liquid',
    unit: 'ml',
    type: 'medicine',
  );

  Future<StoredStockContainer> container(
    SubstanceItem item, {
    ExactAmount? opening,
    ExactAmount? threshold,
    bool refill = false,
    String label = 'Bottle',
  }) => store.createStockContainer(
    commandId: newCommandId(),
    personId: meId,
    expectedPersonRevision: 1,
    expectedGeneration: store.generation,
    itemId: item.id,
    label: label,
    unit: item.unit,
    strength: LabelledStrength(
      ingredientId: item.id,
      label: '10 mg/ml',
      mgPerMl: n(10),
    ),
    opening: opening,
    lowThreshold: threshold,
    refillEnabled: refill,
  );

  Future<StockAlertPreference> enable({int expected = 0, bool on = true}) =>
      store.setStockAlerts(
        commandId: newCommandId(),
        enabled: on,
        expectedRevision: expected,
        expectedGeneration: store.generation,
      );

  Future<ReminderProjection> prepare([DateTime? at]) => store.prepareReminders(
    now: at ?? now,
    observedZone: 'Europe/London',
    clockSample: null,
    adapterFingerprint: 'test-adapter',
  );

  Future<void> acknowledge(
    StockNoticeReminder notice,
    ReminderReceipt receipt, {
    int sequence = 1,
    String? generation,
    int? intentRevision,
  }) async {
    expect(
      await store.acknowledgeReminder(
        generation: generation ?? store.generation,
        requestToken: notice.requestToken,
        intentRevision: intentRevision ?? notice.intentRevision,
        sequence: sequence,
        receipt: receipt,
        reason: null,
        adapterFingerprint: 'test-adapter',
      ),
      isTrue,
    );
  }

  Database raw() {
    final db = sqlite3.open(path);
    db.execute("PRAGMA cipher='chacha20'");
    db.execute(
      'PRAGMA key="x\'${key.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}\'"',
    );
    db.execute('PRAGMA foreign_keys=ON');
    return db;
  }

  int rawCount(String table) {
    final db = raw();
    try {
      return db.select('SELECT COUNT(*) AS n FROM $table').first['n'] as int;
    } finally {
      db.close();
    }
  }

  Map<String, Object?>? rawRequest(String token) {
    final db = raw();
    try {
      final rows = db.select(
        'SELECT * FROM stock_notice_request WHERE token=?',
        [token],
      );
      return rows.isEmpty ? null : Map<String, Object?>.from(rows.single);
    } finally {
      db.close();
    }
  }

  test(
    'uncertain presentation stays visible without rearming the notice',
    () async {
      final medicine = await item('Uncertain stock');
      await container(medicine, opening: n(1), threshold: n(5));
      await enable();
      final first = await prepare();
      final request = first.stockNotices.single;
      await acknowledge(
        request,
        ReminderReceipt.postUncertain,
        sequence: first.sequence,
      );
      final next = await prepare();
      expect(next.stockNotices, isEmpty);
      expect(
        next.stockNoticeAttention.single.repairState,
        ReminderRepairState.postUncertain,
      );
      expect(next.complete, isFalse);
      expect(rawCount('stock_notice_request'), 1);
      expect(
        (await store.captureStockNoticeOpen(
          envelopeId: 'uncertain-open',
          namespace: request.namespace,
          requestToken: request.requestToken,
          actionToken: request.requestToken,
          action: ReminderActionKind.open,
        ))?.itemId,
        medicine.id,
      );
    },
  );

  test('stock preference rejects a previous dataset generation', () async {
    await expectLater(
      store.setStockAlerts(
        commandId: 'stale-preference',
        enabled: true,
        expectedRevision: 0,
        expectedGeneration: 'old-dataset',
      ),
      throwsA(isA<CommandConflict>()),
    );
    expect((await store.stockAlertPreference()).enabled, isFalse);
  });

  test(
    'schema 25 upgrade preserves records and leaves stock alerts off',
    () async {
      final medicine = await item('Migration medicine');
      final dose = await store.record(
        commandId: 'migration-dose',
        itemId: medicine.id,
        amount: '1',
        actualAt: now,
      );
      await store.close();
      final db = raw();
      try {
        for (final table in [
          'stock_notice_request',
          'stock_notice_episode',
          'stock_notice_config',
        ]) {
          db.execute('DROP TABLE $table');
        }
        db.execute('PRAGMA user_version=25');
      } finally {
        db.close();
      }
      store = await RecordStore.open(path: path, key: key, isNew: false);
      expect((await store.records()).single.id, dose.id);
      expect((await store.stockAlertPreference()).enabled, isFalse);
      expect(rawCount('stock_notice_episode'), 0);
      expect(rawCount('stock_notice_request'), 0);
    },
  );

  test('default is off and unknown configured stock never alerts', () async {
    final known = await item('Known low');
    final unknown = await item('Unmeasured');
    final low = await container(known, opening: n(2), threshold: n(5));
    await container(unknown, threshold: n(5));
    final preference = await store.stockAlertPreference();
    expect(preference.enabled, isFalse);
    expect(preference.revision, 0);
    // The in-app notice still covers both configured states, including the
    // unknown one that native delivery must never turn into a quantity.
    final inApp = await store.stockNotices(scope: FeedScope.person(meId));
    expect(inApp.rows, hasLength(2));
    final projection = await prepare();
    expect(projection.stockNotices, isEmpty);
    expect(rawCount('stock_notice_episode'), 0);
    final db = raw();
    try {
      expect(
        db.select('PRAGMA user_version').single.values.single,
        currentRecordSchemaVersion,
      );
      expect(
        db
            .select(
              "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'stock_notice_%' ORDER BY name",
            )
            .map((row) => row['name']),
        ['stock_notice_config', 'stock_notice_episode', 'stock_notice_request'],
      );
    } finally {
      db.close();
    }
    expect(rawCount('stock_notice_request'), 0);
    expect(
      (await store.stockContainerById(
        personId: meId,
        containerId: low.id,
      ))!.notice,
      StockNoticeState.low,
    );
  });

  test(
    'one episode survives repeated passes, above ends it, low may alert once',
    () async {
      final row = await item('Episode item');
      final c = await container(row, opening: n(2), threshold: n(5));
      await enable();
      final first = await prepare();
      final request = first.stockNotices.single;
      expect(request.condition, StockNoticeState.low);
      expect(request.balance, n(2));
      expect(request.threshold, n(5));
      expect(rawCount('stock_notice_episode'), 1);
      expect(rawCount('stock_notice_request'), 1);
      await acknowledge(request, ReminderReceipt.consumed);
      for (var i = 0; i < 3; i++) {
        final repeated = await prepare();
        expect(repeated.stockNotices, isEmpty);
        expect(repeated.stockNoticeAttention, isEmpty);
      }
      expect(rawCount('stock_notice_episode'), 1);
      expect(rawCount('stock_notice_request'), 1);

      final current = (await store.stockContainerById(
        personId: meId,
        containerId: c.id,
      ))!;
      await store.addStockMovement(
        commandId: newCommandId(),
        personId: meId,
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
        containerId: c.id,
        expectedContainerRevision: current.revision,
        kind: StockMovementKind.restock,
        amount: EnteredStockAmount('10', 'ml'),
      );
      final above = await prepare();
      expect(above.stockNotices, isEmpty);
      expect(above.obsoleteTokens, contains(request.requestToken));
      expect(rawCount('stock_notice_episode'), 0);

      final restocked = (await store.stockContainerById(
        personId: meId,
        containerId: c.id,
      ))!;
      await store.addStockMovement(
        commandId: newCommandId(),
        personId: meId,
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
        containerId: c.id,
        expectedContainerRevision: restocked.revision,
        kind: StockMovementKind.waste,
        amount: EnteredStockAmount('10', 'ml'),
      );
      final lowAgain = await prepare();
      expect(lowAgain.stockNotices, hasLength(1));
      expect(
        lowAgain.stockNotices.single.requestToken,
        isNot(request.requestToken),
      );
    },
  );

  test(
    'refill zero and a known deficit use only measured conditions',
    () async {
      final refillItem = await item('Refill zero');
      final refill = await container(refillItem, opening: n(1), refill: true);
      final deficitItem = await item('Deficit item');
      final deficit = await container(
        deficitItem,
        opening: n(1),
        threshold: n(5),
      );
      for (final (row, amount) in [(refill, '1'), (deficit, '2')]) {
        await store.addStockMovement(
          commandId: newCommandId(),
          personId: meId,
          expectedPersonRevision: 1,
          expectedGeneration: store.generation,
          containerId: row.id,
          expectedContainerRevision: row.revision,
          kind: StockMovementKind.waste,
          amount: EnteredStockAmount(amount, 'ml'),
        );
      }
      await enable();
      final projection = await prepare();
      expect(projection.stockNotices, hasLength(2));
      final byContainer = {
        for (final notice in projection.stockNotices)
          notice.containerId: notice,
      };
      expect(byContainer[refill.id]?.condition, StockNoticeState.refill);
      expect(byContainer[refill.id]?.balance, ExactAmount.zero);
      expect(byContainer[deficit.id]?.condition, StockNoticeState.low);
      expect(byContainer[deficit.id]?.balance, ExactAmount(BigInt.from(-1)));
    },
  );

  test('reopening and replays keep one stable token per episode', () async {
    final row = await item('Reopen item');
    await container(row, opening: n(1), threshold: n(5));
    await store.setStockAlerts(
      commandId: 'alerts-on',
      enabled: true,
      expectedRevision: 0,
      expectedGeneration: store.generation,
    );
    final first = await prepare();
    final token = first.stockNotices.single.requestToken;
    await store.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final reopened = await prepare();
    expect(reopened.stockNotices.single.requestToken, token);
    final replayed = await store.setStockAlerts(
      commandId: 'alerts-on',
      enabled: true,
      expectedRevision: 0,
      expectedGeneration: store.generation,
    );
    expect(replayed.revision, 1);
    expect(
      (await store.setStockAlerts(
        commandId: 'alerts-on',
        enabled: true,
        expectedRevision: 0,
        expectedGeneration: store.generation,
      )).revision,
      1,
    );
    expect((await prepare()).stockNotices.single.requestToken, token);
  });

  test(
    'removing the rule cancels native state without a replacement',
    () async {
      final row = await item('Removed rule');
      final c = await container(row, opening: n(1), threshold: n(5));
      await enable();
      final request = (await prepare()).stockNotices.single;
      await store.configureStockNotices(
        commandId: newCommandId(),
        personId: meId,
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
        containerId: c.id,
        expectedContainerRevision: c.revision,
        lowThreshold: null,
        refillEnabled: false,
      );
      final after = await prepare();
      expect(after.stockNotices, isEmpty);
      expect(after.obsoleteTokens, contains(request.requestToken));
      expect(rawCount('stock_notice_episode'), 0);
      expect(
        (await store.stockNotices(scope: FeedScope.person(meId))).rows,
        isEmpty,
      );
    },
  );

  test(
    'global opt-out cancels and re-enabling may open one new episode',
    () async {
      final row = await item('Opt out item');
      await container(row, opening: n(1), threshold: n(5));
      await enable();
      final request = (await prepare()).stockNotices.single;
      await enable(expected: 1, on: false);
      final disabled = await prepare();
      expect(disabled.stockNotices, isEmpty);
      expect(disabled.obsoleteTokens, contains(request.requestToken));
      expect(rawCount('stock_notice_episode'), 0);
      await enable(expected: 2);
      final again = await prepare();
      expect(again.stockNotices, hasLength(1));
      expect(
        again.stockNotices.single.requestToken,
        isNot(request.requestToken),
      );
    },
  );

  test('terminal receipts, stale fences and Open stay non-clinical', () async {
    final row = await item('Open item');
    final c = await container(row, opening: n(1), threshold: n(5));
    await enable();
    final first = await prepare();
    final request = first.stockNotices.single;
    // A stale generation or intent fence cannot settle this live episode.
    for (final stale in [
      () => store.acknowledgeReminder(
        generation: 'old',
        requestToken: request.requestToken,
        intentRevision: request.intentRevision,
        sequence: first.sequence,
        receipt: ReminderReceipt.consumed,
        reason: null,
        adapterFingerprint: 'test-adapter',
      ),
      () => store.acknowledgeReminder(
        generation: store.generation,
        requestToken: request.requestToken,
        intentRevision: 2,
        sequence: first.sequence,
        receipt: ReminderReceipt.consumed,
        reason: null,
        adapterFingerprint: 'test-adapter',
      ),
    ]) {
      expect(await stale(), isFalse);
    }
    expect(rawRequest(request.requestToken)?['active'], 1);
    // Dose actions are never accepted for a stock notice.
    for (final action in [
      ReminderActionKind.taken,
      ReminderActionKind.snooze,
      ReminderActionKind.skip,
    ]) {
      expect(
        await store.captureStockNoticeOpen(
          envelopeId: 'env-$action',
          namespace: request.namespace,
          requestToken: request.requestToken,
          actionToken: request.takenToken,
          action: action,
        ),
        isNull,
      );
    }
    await acknowledge(request, ReminderReceipt.consumed);
    final afterConsumed = await prepare();
    final opened = await store.captureStockNoticeOpen(
      envelopeId: 'open-envelope',
      namespace: request.namespace,
      requestToken: request.requestToken,
      actionToken: request.requestToken,
      action: ReminderActionKind.open,
    );
    expect(opened?.itemId, row.id);
    expect(opened?.containerId, c.id);
    expect(
      await store.captureStockNoticeOpen(
        envelopeId: 'open-again',
        namespace: request.namespace,
        requestToken: request.requestToken,
        actionToken: request.requestToken,
        action: ReminderActionKind.open,
      ),
      isNull,
    );
    expect(await store.records(), isEmpty);
    expect(rawCount('stock_movement'), 1);
    expect(rawRequest(request.requestToken)?['state'], 'consumed');
    expect(rawRequest(request.requestToken)?['active'], 1);
    // A late accepted receipt cannot regress the terminal row.
    expect(
      await store.acknowledgeReminder(
        generation: store.generation,
        requestToken: request.requestToken,
        intentRevision: request.intentRevision,
        sequence: afterConsumed.sequence,
        receipt: ReminderReceipt.accepted,
        reason: null,
        adapterFingerprint: 'test-adapter',
      ),
      isFalse,
    );
    expect(rawRequest(request.requestToken)?['state'], 'consumed');
  });

  test('capacity is finite and visibly incomplete', () async {
    await enable();
    for (var i = 0; i < 9; i++) {
      final row = await item('Capacity $i');
      await container(row, opening: n(1), threshold: n(5), label: 'Bottle $i');
    }
    final projection = await prepare();
    expect(projection.stockNotices, hasLength(ReminderCapacity.stockNotices));
    expect(projection.stockNoticeAttention, hasLength(1));
    expect(
      projection.stockNoticeAttention.single.repairState,
      ReminderRepairState.capacity,
    );
    expect(
      projection.exclusions.where((e) => e.reason == 'capacity'),
      hasLength(1),
    );
    expect(projection.complete, isFalse);
  });

  test('a capacity-deferred notice keeps its immutable deadline', () async {
    await enable();
    for (var i = 0; i < 9; i++) {
      final row = await item('Deferred $i');
      await container(row, opening: n(1), threshold: n(5), label: 'Bottle $i');
    }
    final first = await prepare();
    final deferred = first.stockNoticeAttention.single;
    final consumed = first.stockNotices.first;
    await acknowledge(
      consumed,
      ReminderReceipt.consumed,
      sequence: first.sequence,
    );
    final later = now.add(const Duration(minutes: 2));
    final second = await prepare(later);
    final selected = second.stockNotices
        .where((notice) => notice.requestToken == deferred.requestToken)
        .single;
    expect(
      selected.deadlineMilliseconds,
      deferred.deadlineMilliseconds,
      reason: 'a native token must keep its original deadline',
    );
    expect(selected.requestToken, deferred.requestToken);
  });

  test('deleting the container cancels its native request', () async {
    final row = await item('Deleted container');
    final c = await container(row, opening: n(1), threshold: n(5));
    await enable();
    final request = (await prepare()).stockNotices.single;
    final db = raw();
    try {
      db.execute('DELETE FROM stock_container WHERE id=?', [c.id]);
    } finally {
      db.close();
    }
    expect(rawCount('stock_notice_episode'), 0);
    final after = await prepare();
    expect(after.stockNotices, isEmpty);
    expect(after.obsoleteTokens, contains(request.requestToken));
    expect(rawRequest(request.requestToken)?['active'], 0);
  });

  test('dataset restore clears device-local stock episodes and requests', () async {
    final row = await item('Restore item');
    await container(row, opening: n(1), threshold: n(5));
    await enable();
    await prepare();
    expect(rawCount('stock_notice_episode'), 1);
    expect(rawCount('stock_notice_request'), 1);
    await store.close();
    final archive = '${directory.path}/archive.db';
    await File(path).copy(archive);
    store = await RecordStore.open(path: path, key: key, isNew: false);
    await store.prepareRestoredDatabase(
      stagedPath: archive,
      rekeyTo: (_) async {},
    );
    final restored = await RecordStore.open(
      path: archive,
      key: key,
      isNew: false,
    );
    try {
      Database check() {
        final db = sqlite3.open(archive);
        db.execute("PRAGMA cipher='chacha20'");
        db.execute(
          'PRAGMA key="x\'${key.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}\'"',
        );
        return db;
      }

      final db = check();
      try {
        expect(
          db
              .select('SELECT COUNT(*) AS n FROM stock_notice_episode')
              .first['n'],
          0,
        );
        expect(
          db
              .select('SELECT COUNT(*) AS n FROM stock_notice_request')
              .first['n'],
          0,
        );
        expect(
          db.select('SELECT enabled,revision FROM stock_notice_config').single,
          {'enabled': 1, 'revision': 1},
        );
      } finally {
        db.close();
      }
      expect(
        await restored.stockAlertPreference(),
        isA<StockAlertPreference>(),
      );
    } finally {
      await restored.close();
    }
  });

  test('reconciler maps stock notices to a dedicated native purpose', () async {
    final row = await item('Reconciler item');
    await container(row, opening: n(1), threshold: n(5));
    await enable();
    final gateway = _StockGateway();
    final reports = <ReminderRepairReport>[];
    final worker = ReminderReconciler(
      gateway: gateway,
      repository: _StockRepair(store),
      observedZone: () => 'Europe/London',
      onReport: reports.add,
    );
    await worker.request();
    expect(gateway.purposes, [NativeReminderPurpose.stockLow]);
    expect(gateway.clocks, [ReminderNativeClock.wall]);
    expect(gateway.tokens, hasLength(1));
    expect(reports.last.projection?.stockNotices, hasLength(1));
    expect(
      reports.last.projection?.stockNotices.single.repairState,
      ReminderRepairState.prepared,
    );
    gateway.receipt = NativeReminderState.consumed;
    await worker.request();
    worker.dispose();
    final settled = await prepare();
    expect(settled.stockNotices, isEmpty);
    expect(gateway.tokens, isEmpty);
  });
}

final class _StockRepair
    implements ReminderRepairRepository, StockNoticeRepairRepository {
  _StockRepair(this.store);
  final RecordStore store;

  @override
  Future<ReminderProjection> prepare({
    required DateTime now,
    required String? observedZone,
    required ReminderClockSample? clockSample,
    required String adapterFingerprint,
  }) => store.prepareReminders(
    now: now,
    observedZone: observedZone,
    clockSample: clockSample,
    adapterFingerprint: adapterFingerprint,
  );

  @override
  Future<bool> acknowledge({
    required int sequence,
    required DesiredReminder desired,
    required ReminderReceipt receipt,
    required String? reason,
    required String adapterFingerprint,
  }) => store.acknowledgeReminder(
    sequence: sequence,
    generation: desired.generation,
    requestToken: desired.requestToken,
    intentRevision: desired.intentRevision,
    receipt: receipt,
    reason: reason,
    adapterFingerprint: adapterFingerprint,
  );

  @override
  Future<bool> acknowledgeStockNotice({
    required int sequence,
    required StockNoticeReminder desired,
    required ReminderReceipt receipt,
    required String? reason,
    required String adapterFingerprint,
  }) => store.acknowledgeReminder(
    sequence: sequence,
    generation: desired.generation,
    requestToken: desired.requestToken,
    intentRevision: desired.intentRevision,
    receipt: receipt,
    reason: reason,
    adapterFingerprint: adapterFingerprint,
  );

  @override
  Future<void> acknowledgeObsolete({
    required String generation,
    required int sequence,
    required String requestToken,
    required ReminderReceipt receipt,
    required String? reason,
    required String adapterFingerprint,
  }) async {
    await store.acknowledgeObsoleteReminder(
      generation: generation,
      sequence: sequence,
      requestToken: requestToken,
      receipt: receipt,
      reason: reason,
      adapterFingerprint: adapterFingerprint,
    );
  }
}

final class _StockGateway implements ReminderGateway {
  NativeReminderState receipt = NativeReminderState.accepted;
  final purposes = <NativeReminderPurpose>[];
  final clocks = <ReminderNativeClock>[];
  final tokens = <String>[];
  String? lastNamespace;

  @override
  Future<ReminderCapabilities> capabilities() async =>
      const ReminderCapabilities(
        supported: true,
        notificationPermission: true,
        appEnabled: true,
        channelEnabled: true,
        exactAlarm: true,
        protectedStorageAvailable: true,
        bootIdentityAvailable: true,
        fingerprint: 'test-adapter',
      );

  @override
  Future<ReminderClockSample> sampleClock() async => const ReminderClockSample(
    utcMilliseconds: 1792400400000,
    elapsedMilliseconds: 3600000,
    bootId: 'b1',
  );

  @override
  Future<NativeReminderSnapshot> applySnapshot({
    required String epoch,
    required int sequence,
    required List<NativeReminderRequest> desired,
    required List<String> obsoleteTokens,
  }) async {
    lastNamespace = epoch;
    purposes
      ..clear()
      ..addAll(desired.map((r) => r.purpose));
    clocks
      ..clear()
      ..addAll(desired.map((r) => r.clock));
    tokens
      ..clear()
      ..addAll(desired.map((r) => r.requestToken));
    return NativeReminderSnapshot(
      accepted: true,
      epoch: epoch,
      sequence: sequence,
      receipts: [
        for (final request in desired)
          NativeReminderReceipt(
            requestToken: request.requestToken,
            state: receipt,
          ),
      ],
      fingerprint: 'test-adapter',
    );
  }

  @override
  Future<NativeReminderAction?> getInitialAction() async => null;

  @override
  Future<void> acknowledgeAction(String envelopeId) async {}

  @override
  Stream<void> get changes => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
