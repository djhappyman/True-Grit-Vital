import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  late Directory dir;
  late RecordStore store;
  late String path;
  final key = List.generate(32, (i) => i + 1);
  final date = CivilDate(2026, 10, 19);
  final now = DateTime.utc(2026, 10, 19, 6);
  final sample = ReminderClockSample(
    utcMilliseconds: DateTime.utc(2026, 10, 19, 9).millisecondsSinceEpoch,
    elapsedMilliseconds: 3600000,
    bootId: 'b1',
  );
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vital-reminder-');
    path = '${dir.path}/records.db';
    store = await RecordStore.open(path: path, key: key, isNew: true);
    final item = await store.createItem(
      commandId: 'item',
      name: 'Synthetic reminder secret',
      form: 'tablet',
      unit: 'mg',
      type: 'medicine',
    );
    await store.saveDailyPlan(
      commandId: 'plan',
      plan: DailyPlanVersion(
        personId: meId,
        planId: 'p1',
        itemId: item.id,
        versionId: 'v1',
        start: date,
        timing: DailySlots([
          DailySlot(
            id: 'am',
            time: WallTime(8, 0),
            amount: PlannedAmount(
              quantity: ExactQuantity.parse('1'),
              enteredText: '1.000',
              unit: 'mg',
            ),
            reminderEnabled: true,
          ),
        ]),
        zoneBasis: const FollowingLocal(),
      ),
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
    );
    await store.setPlanReminders(
      commandId: 'enable',
      planId: 'p1',
      personId: meId,
      expectedPlanRevision: 1,
      expectedPersonRevision: 1,
      enabled: true,
    );
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  Future<DailyRow> row([RecordStore? source]) async =>
      (await (source ?? store).dailyRows(
        from: date,
        toExclusive: date.addDays(1),
        observedZone: 'Europe/London',
      )).rows.single;
  Future<ReminderTarget> target([RecordStore? source]) async =>
      (source ?? store).reminderTarget(
        await row(source),
        observedZone: 'Europe/London',
      );
  Future<SnoozeResult> snooze(
    ReminderTarget t, {
    String id = 's1',
    int minutes = 15,
    ReminderClockSample? clock,
    RecordStore? source,
  }) => (source ?? store).snoozeReminder(
    SnoozeCommand(
      commandId: id,
      target: t,
      delayMinutes: minutes,
      sample: clock ?? sample,
      observedZone: 'Europe/London',
    ),
    currentObservedZone: 'Europe/London',
  );
  var lastSequence = 0;
  Future<ReminderProjection> projection({
    DateTime? at,
    ReminderClockSample? clock,
    String? zone = 'Europe/London',
  }) async {
    final result = await store.prepareReminders(
      now: at ?? now,
      observedZone: zone,
      clockSample: clock ?? sample,
      adapterFingerprint: 'test-adapter',
    );
    lastSequence = result.sequence;
    return result;
  }

  test('S01 S02 S03 encrypted intent/replay/replacement preserve clinical and stock truth', () async {
    final captured = await target();
    final first = await snooze(captured);
    expect(first.desired.deadlineMilliseconds, 4500000);
    expect(first.desired.target.snoozeRevision, 1);
    expect((await row()).revision, 0);
    expect(await store.records(), isEmpty);
    expect((await store.dailyPlans()).single.revision, 1);
    await store.close();
    expect(
      String.fromCharCodes(await File(path).readAsBytes()),
      isNot(contains('Synthetic reminder secret')),
    );
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final replay = await snooze(captured);
    expect(replay.alreadyCommitted, true);
    expect(replay.desired.requestToken, first.desired.requestToken);
    await expectLater(
      snooze(captured, minutes: 10),
      throwsA(isA<CommandConflict>()),
    );
    final second = await snooze(
      await target(),
      id: 's2',
      minutes: 10,
      clock: ReminderClockSample(
        utcMilliseconds: sample.utcMilliseconds + 300000,
        elapsedMilliseconds: 3900000,
        bootId: 'b1',
      ),
    );
    expect(second.desired.target.snoozeRevision, 2);
    expect(second.desired.deadlineMilliseconds, 4500000);
    final p = await projection();
    expect(p.desired.where((r) => r.kind == ReminderKind.snooze).length, 1);
    expect(p.obsoleteTokens, contains(first.desired.requestToken));
    await expectLater(
      snooze(captured, id: 'stale'),
      throwsA(isA<CommandConflict>()),
    );
  });
  test('S04 S17 locked writes reject and original owner persists in encrypted submitted picker', () async {
    final t = await target();
    final pending = await store.createReminderAction(
      target: t,
      action: ReminderActionKind.snooze,
      observedZone: 'Europe/London',
    );
    await store.updateReminderAction(pending.envelopeId, delayMinutes: 15);
    final submitted = await store.updateReminderAction(
      pending.envelopeId,
      submit: true,
      sample: sample,
    );
    expect(submitted.target.row.expectation.identity.personId, meId);
    store.suspendWrites(true);
    await expectLater(snooze(t), throwsA(isA<CommandConflict>()));
    await expectLater(
      store.pendingReminderActions(),
      throwsA(isA<CommandConflict>()),
    );
    store.suspendWrites(false);
    await store.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final reopened = (await store.pendingReminderActions()).single;
    expect(reopened.submitted, true);
    expect(reopened.sample!.elapsedMilliseconds, 3600000);
    await expectLater(
      store.updateReminderAction(reopened.envelopeId, delayMinutes: 30),
      throwsA(isA<CommandConflict>()),
    );
  });
  test('S05 following-local zone needs review without retargeting original occurrence', () async {
    final first = await snooze(await target());
    final p = await projection(zone: 'America/New_York');
    expect(
      p.desired.any((r) => r.requestToken == first.desired.requestToken),
      false,
    );
    expect(p.obsoleteTokens, contains(first.desired.requestToken));
    expect(p.coverage.first.complete, false);
    expect(first.desired.target.row.expectation.identity.originalDate, date);
  });
  test('S06 crossing midnight keeps original identity and independent tomorrow candidate', () async {
    final late = ReminderClockSample(
      utcMilliseconds: DateTime.utc(
        2026,
        10,
        19,
        23,
        59,
      ).millisecondsSinceEpoch,
      elapsedMilliseconds: 60000000,
      bootId: 'b1',
    );
    final first = await snooze(await target(), clock: late);
    expect(first.desired.projectedUtc.day, 20);
    expect(first.desired.target.row.expectation.identity.originalDate, date);
    final p = await projection(at: late.utc, clock: late);
    expect(
      p.desired.any(
        (r) =>
            r.kind == ReminderKind.ordinary &&
            r.target.row.expectation.identity.originalDate == date.addDays(1),
      ),
      true,
    );
    expect(await store.records(), isEmpty);
  });
  test('S07 S08 independent connections one terminal winner; stale pre-snooze Taken rejected', () async {
    final captured = await row();
    await snooze(await target());
    await expectLater(
      store.actDaily(
        commandId: 'stale-take',
        row: captured,
        kind: DailyActionKind.taken,
        actualAt: now,
      ),
      throwsA(isA<CommandConflict>()),
    );
    final fresh = await row();
    final second = await RecordStore.open(path: path, key: key, isNew: false);
    try {
      final outcomes = await Future.wait([
        store
            .actDaily(
              commandId: 'take',
              row: fresh,
              kind: DailyActionKind.taken,
              actualAt: now,
            )
            .then<DailyAction?>((a) => a, onError: (Object _) => null),
        second
            .actDaily(commandId: 'skip', row: fresh, kind: DailyActionKind.skip)
            .then<DailyAction?>((a) => a, onError: (Object _) => null),
      ]);
      expect(outcomes.whereType<DailyAction>().length, 1);
      final winner = outcomes.whereType<DailyAction>().single;
      final replay = await store.actDaily(
        commandId: winner.id,
        row: fresh,
        kind: winner.kind,
        actualAt: winner.kind == DailyActionKind.taken ? now : null,
      );
      expect(replay.alreadyCommitted, true);
      expect(
        (await projection()).desired.where(
          (r) => r.kind == ReminderKind.snooze,
        ),
        isEmpty,
      );
      await expectLater(target(), throwsA(isA<CommandConflict>()));
    } finally {
      await second.close();
    }
  });
  test('S09 reminder off rejects picker and generation mismatches cannot acknowledge', () async {
    final t = await target();
    final first = await snooze(t);
    await store.setPlanReminders(
      commandId: 'disable',
      planId: 'p1',
      personId: meId,
      expectedPlanRevision: 1,
      expectedPersonRevision: 1,
      enabled: false,
    );
    await expectLater(snooze(t, id: 'late'), throwsA(isA<CommandConflict>()));
    expect(
      await store.acknowledgeReminder(
        generation: 'old',
        requestToken: first.desired.requestToken,
        intentRevision: first.desired.intentRevision,
        sequence: lastSequence,
        receipt: ReminderReceipt.accepted,
        adapterFingerprint: 'test-adapter',
      ),
      false,
    );
    expect(
      (await projection()).obsoleteTokens,
      contains(first.desired.requestToken),
    );
  });
  test('S10 S11 S12 conditional receipts repair same token; consumed token never rearmed', () async {
    final first = await snooze(await target());
    final p1 = await projection();
    final p2 = await projection();
    expect(p1.sequence, p2.sequence);
    expect(
      p2.desired.any((r) => r.requestToken == first.desired.requestToken),
      true,
    );
    await store.acknowledgeReminder(
      generation: store.generation,
      requestToken: first.desired.requestToken,
      intentRevision: first.desired.intentRevision,
      sequence: lastSequence,
      receipt: ReminderReceipt.failed,
      reason: 'permission',
      adapterFingerprint: 'test-adapter',
    );
    expect((await projection()).coverage.first.complete, false);
    expect(await store.records(), isEmpty);
    await store.acknowledgeReminder(
      generation: store.generation,
      requestToken: first.desired.requestToken,
      intentRevision: first.desired.intentRevision,
      sequence: lastSequence,
      receipt: ReminderReceipt.consumed,
      adapterFingerprint: 'test-adapter',
    );
    expect(
      await store.acknowledgeReminder(
        generation: store.generation,
        requestToken: first.desired.requestToken,
        intentRevision: first.desired.intentRevision,
        sequence: lastSequence,
        receipt: ReminderReceipt.accepted,
        adapterFingerprint: 'test-adapter',
      ),
      false,
    );
    expect(
      (await projection()).desired.any(
        (r) => r.requestToken == first.desired.requestToken,
      ),
      false,
    );
    expect(
      await store.acknowledgeReminder(
        generation: store.generation,
        requestToken: first.desired.requestToken,
        intentRevision: first.desired.intentRevision,
        sequence: lastSequence,
        receipt: ReminderReceipt.unknown,
        adapterFingerprint: 'test-adapter',
      ),
      false,
    );
  });
  test(
    'S13 boot change interrupts saved snooze with zero auto rearm',
    () async {
      final first = await snooze(await target());
      final p = await projection(
        clock: ReminderClockSample(
          utcMilliseconds: sample.utcMilliseconds,
          elapsedMilliseconds: 0,
          bootId: 'b2',
        ),
      );
      expect(
        p.desired.any((r) => r.requestToken == first.desired.requestToken),
        false,
      );
      expect(p.obsoleteTokens, contains(first.desired.requestToken));
      expect(p.coverage.first.reason, 'snooze_interrupted');
    },
  );
  test('native transport capture durable deduplicated before ack and exact submitted Taken survives restart', () async {
    final p = await projection();
    final r = p.desired.first;
    final pending = await store.captureReminderAction(
      envelopeId: 'envelope',
      namespace: p.namespace,
      requestToken: r.requestToken,
      actionToken: r.takenToken,
      action: ReminderActionKind.taken,
    );
    expect(pending, isNotNull);
    await store.updateReminderAction(
      pending!.envelopeId,
      submit: true,
      actualAt: sample.utc,
    );
    await store.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final again = await store.captureReminderAction(
      envelopeId: 'envelope',
      namespace: p.namespace,
      requestToken: r.requestToken,
      actionToken: r.takenToken,
      action: ReminderActionKind.taken,
    );
    expect(again!.commandId, pending.commandId);
    expect(again.actualAt, sample.utc);
    await store.acknowledgeReminderAction(again.envelopeId);
    expect(
      await store.captureReminderAction(
        envelopeId: 'envelope',
        namespace: p.namespace,
        requestToken: r.requestToken,
        actionToken: r.takenToken,
        action: ReminderActionKind.taken,
      ),
      isNull,
    );
  });
  test('frozen populated schema8 preserves exact actual metadata and migration rollback', () async {
    await store.close();
    await File(path).delete();
    void fixture(String destination, {bool obstacle = false}) {
      final db = sqlite3.open(destination);
      final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      db.execute("PRAGMA cipher='chacha20'");
      db.execute("PRAGMA key=\"x'$hex'\"");
      db.execute(
        File('test/data/fixtures/record_store_v8.sql').readAsStringSync(),
      );
      if (obstacle) {
        db.execute('CREATE TABLE reminder_meta(obstacle TEXT) STRICT');
      }
      db.close();
    }

    fixture(path);
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final r = (await store.history('other-record')).single;
    expect(r.enteredAmount, '1');
    expect(r.actualAmount.numerator.toString(), '1');
    expect(r.actualAmount.denominator.toString(), '3');
    expect(r.originalEntry, '0.333333333333');
    expect((await store.drafts()).single.fields['amount'], '1.000');
    expect(await store.planRemindersEnabled('plan'), false);
    final failed = '${dir.path}/failed.db';
    fixture(failed, obstacle: true);
    await expectLater(
      RecordStore.open(path: failed, key: key, isNew: false),
      throwsA(anything),
    );
    final db = sqlite3.open(failed);
    final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    db.execute("PRAGMA cipher='chacha20'");
    db.execute("PRAGMA key=\"x'$hex'\"");
    expect(db.select('PRAGMA user_version').single.values.single, 8);
    expect(
      db
          .select('SELECT numerator,denominator FROM revision_quantity')
          .single
          .values,
      ['1', '3'],
    );
    db.close();
  });
  Future<void> densePlan() async {
    final old = (await store.dailyPlans()).single.plan;
    await store.saveDailyPlan(
      commandId: 'dense-plan',
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      expectedPlanRevision: 1,
      plan: DailyPlanVersion(
        personId: old.personId,
        planId: old.planId,
        itemId: old.itemId,
        versionId: 'dense-v2',
        start: date,
        timing: DailySlots([
          for (var i = 0; i < 100; i++)
            DailySlot(
              id: 's${i.toString().padLeft(3, '0')}',
              reminderEnabled: false,
              time: WallTime(8, 0),
              amount: PlannedAmount(
                quantity: ExactQuantity.parse('1'),
                enteredText: '1',
                unit: 'mg',
              ),
            ),
        ]),
        zoneBasis: const FollowingLocal(),
      ),
    );
  }

  test('S15 dense allocation earliest bounded and equal-instant coverage never crosses hole', () async {
    await densePlan();
    final p = await projection();
    expect(p.desired.length, 232);
    expect(p.complete, false);
    expect(p.exclusions.any((e) => e.reason == 'capacity'), true);
    final firstDay = p.desired
        .where((r) => r.target.row.expectation.identity.originalDate == date)
        .toList();
    expect(firstDay.length, 100);
    final prepared = firstDay.first;
    await store.acknowledgeReminder(
      generation: store.generation,
      requestToken: prepared.requestToken,
      intentRevision: prepared.intentRevision,
      sequence: lastSequence,
      receipt: ReminderReceipt.accepted,
      adapterFingerprint: 'test-adapter',
    );
    expect((await projection()).coverage.first.preparedThrough, isNull);
    for (final r in firstDay.skip(1)) {
      await store.acknowledgeReminder(
        generation: store.generation,
        requestToken: r.requestToken,
        intentRevision: r.intentRevision,
        sequence: lastSequence,
        receipt: ReminderReceipt.accepted,
        adapterFingerprint: 'test-adapter',
      );
    }
    expect(
      (await projection()).coverage.first.preparedThrough,
      DateTime.utc(2026, 10, 19, 7),
    );
  });
  test('terminal receipts do not exhaust lifetime ordinary or reserved snooze pools', () async {
    await densePlan();
    final first = await projection();
    for (final r in first.desired) {
      await store.acknowledgeReminder(
        generation: store.generation,
        requestToken: r.requestToken,
        intentRevision: r.intentRevision,
        sequence: lastSequence,
        receipt: ReminderReceipt.consumed,
        adapterFingerprint: 'test-adapter',
      );
    }
    final next = await projection();
    expect(next.desired.length, 232);
    expect(
      next.desired
          .map((r) => r.requestToken)
          .toSet()
          .intersection(first.desired.map((r) => r.requestToken).toSet()),
      isEmpty,
    );
    final rows = (await store.dailyRows(
      from: date,
      toExclusive: date.addDays(1),
      observedZone: 'Europe/London',
    )).rows;
    final snoozes = <DesiredReminder>[];
    for (var i = 0; i < 16; i++) {
      snoozes.add(
        (await snooze(
          await store.reminderTarget(rows[i], observedZone: 'Europe/London'),
          id: 'defer$i',
        )).desired,
      );
    }
    expect(
      (await projection()).desired
          .where((r) => r.kind == ReminderKind.snooze)
          .length,
      16,
    );
    for (final r in snoozes) {
      await store.acknowledgeReminder(
        generation: store.generation,
        requestToken: r.requestToken,
        intentRevision: r.intentRevision,
        sequence: lastSequence,
        receipt: ReminderReceipt.consumed,
        adapterFingerprint: 'test-adapter',
      );
    }
    final fresh = (await snooze(
      await store.reminderTarget(rows[16], observedZone: 'Europe/London'),
      id: 'fresh-defer',
    )).desired;
    expect(
      (await projection()).desired
          .where((r) => r.kind == ReminderKind.snooze)
          .map((r) => r.requestToken),
      [fresh.requestToken],
    );
  });
  test('obsolete cancellation drains beyond256 with sequence fences and deleted snapshots scrubbed', () async {
    await densePlan();
    await projection();
    await store.deleteProfile(
      commandId: 'delete-me',
      personId: meId,
      expectedRevision: 1,
    );
    var p = await projection();
    var count = 0;
    expect(p.obsoleteTokens.length, 256);
    expect(
      await store.acknowledgeObsoleteReminder(
        generation: store.generation,
        requestToken: p.obsoleteTokens.first,
        sequence: p.sequence - 1,
        receipt: ReminderReceipt.cancelled,
        adapterFingerprint: 'test-adapter',
      ),
      false,
    );
    for (var page = 0; page < 5 && p.obsoleteTokens.isNotEmpty; page++) {
      for (final token in p.obsoleteTokens) {
        expect(
          await store.acknowledgeObsoleteReminder(
            generation: store.generation,
            requestToken: token,
            sequence: p.sequence,
            receipt: ReminderReceipt.cancelled,
            adapterFingerprint: 'test-adapter',
          ),
          true,
        );
        count++;
      }
      p = await projection();
    }
    expect(count, 700);
    expect(p.obsoleteTokens, isEmpty);
    expect(await store.pendingReminderActions(), isEmpty);
  });
  test(
    'stale in-flight accepted/unknown cannot override boot/zone review',
    () async {
      final r = (await snooze(await target())).desired;
      await projection(
        clock: ReminderClockSample(
          utcMilliseconds: sample.utcMilliseconds,
          elapsedMilliseconds: 0,
          bootId: 'b2',
        ),
      );
      expect(
        await store.acknowledgeReminder(
          generation: store.generation,
          requestToken: r.requestToken,
          intentRevision: r.intentRevision,
          sequence: lastSequence,
          receipt: ReminderReceipt.accepted,
          adapterFingerprint: 'test-adapter',
        ),
        false,
      );
      final p = await projection();
      expect(p.attention.single.repairState, ReminderRepairState.interrupted);
    },
  );

  test('native terminal action context validates config and current zone atomically yet replays committed result', () async {
    final t = await target();
    await expectLater(
      store.actDaily(
        commandId: 'changed-zone',
        row: t.row,
        kind: DailyActionKind.skip,
        reminderTarget: t,
        reminderObservedZone: 'America/New_York',
      ),
      throwsA(isA<CommandConflict>()),
    );
    await store.setPlanReminders(
      commandId: 'off-action',
      planId: 'p1',
      personId: meId,
      expectedPlanRevision: 1,
      expectedPersonRevision: 1,
      enabled: false,
    );
    await expectLater(
      store.actDaily(
        commandId: 'disabled-taken',
        row: t.row,
        kind: DailyActionKind.taken,
        actualAt: sample.utc,
        reminderTarget: t,
        reminderObservedZone: 'Europe/London',
      ),
      throwsA(isA<CommandConflict>()),
    );
    await store.setPlanReminders(
      commandId: 'on-action',
      planId: 'p1',
      personId: meId,
      expectedPlanRevision: 1,
      expectedPersonRevision: 1,
      enabled: true,
    );
    final fresh = await target();
    final first = await store.actDaily(
      commandId: 'valid-notification',
      row: fresh.row,
      kind: DailyActionKind.skip,
      reminderTarget: fresh,
      reminderObservedZone: 'Europe/London',
    );
    final replay = await store.actDaily(
      commandId: 'valid-notification',
      row: fresh.row,
      kind: DailyActionKind.skip,
      reminderTarget: fresh,
      reminderObservedZone: 'America/New_York',
    );
    expect(replay.id, first.id);
    expect(replay.alreadyCommitted, true);
    expect(await store.records(), isEmpty);
  });
  test(
    'Snooze current zone validation is separate from immutable replay payload',
    () async {
      final t = await target();
      final command = SnoozeCommand(
        commandId: 'frozen-zone',
        target: t,
        delayMinutes: 15,
        sample: sample,
        observedZone: 'Europe/London',
      );
      await expectLater(
        store.snoozeReminder(command, currentObservedZone: 'America/New_York'),
        throwsA(isA<CommandConflict>()),
      );
      final first = await store.snoozeReminder(
        command,
        currentObservedZone: 'Europe/London',
      );
      final replay = await store.snoozeReminder(
        command,
        currentObservedZone: 'America/New_York',
      );
      expect(replay.alreadyCommitted, true);
      expect(replay.desired.requestToken, first.desired.requestToken);
    },
  );
  test('plan preference exact lookup remains enabled beyond1000 earlier plan heads', () async {
    final original = (await store.dailyPlans()).single.plan;
    await store.close();
    final db = sqlite3.open(path);
    final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    db.execute("PRAGMA cipher='chacha20'");
    db.execute("PRAGMA key=\"x'$hex'\"");
    final snapshot =
        db.select('SELECT snapshot FROM daily_version WHERE plan=?', [
              'p1',
            ]).single['snapshot']
            as String;
    db.execute('BEGIN');
    for (var i = 0; i < 1001; i++) {
      final id = 'a${i.toString().padLeft(4, '0')}';
      db.execute(
        'INSERT INTO item(id,person,name,form,unit,type,type_id,item_revision,catalogue_snapshot) SELECT ?,person,name,form,unit,type,type_id,item_revision,catalogue_snapshot FROM item WHERE id=?',
        ['item-$id', original.itemId],
      );
      db.execute('INSERT INTO daily_plan VALUES (?,?,?,1)', [
        id,
        meId,
        'item-$id',
      ]);
      db.execute('INSERT INTO daily_version VALUES (?,?,?,?,?,?)', [
        'version-$id',
        id,
        meId,
        date.toString(),
        null,
        snapshot
            .replaceAll('"p1"', '"$id"')
            .replaceAll('"v1"', '"version-$id"')
            .replaceAll('"${original.itemId}"', '"item-$id"'),
      ]);
    }
    db.execute('COMMIT');
    db.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    expect(await store.planRemindersEnabled('p1'), true);
  });

  test('S07 Snooze versus Taken independent lock race has one initial winner and refreshed terminal cancels', () async {
    final captured = await row();
    final t = await target();
    final second = await RecordStore.open(path: path, key: key, isNew: false);
    try {
      final results = await Future.wait<Object?>([
        snooze(
          t,
          source: second,
        ).then<Object?>((r) => r, onError: (Object _) => null),
        store
            .actDaily(
              commandId: 'racing-take',
              row: captured,
              kind: DailyActionKind.taken,
              actualAt: sample.utc,
            )
            .then<Object?>((r) => r, onError: (Object _) => null),
      ]);
      expect(results.where((r) => r != null).length, 1);
      if (!(await row()).isResolved) {
        await store.actDaily(
          commandId: 'refreshed-take',
          row: await row(),
          kind: DailyActionKind.taken,
          actualAt: sample.utc,
        );
      }
      expect((await store.records()).length, 1);
      expect(
        (await projection()).desired.any((r) => r.kind == ReminderKind.snooze),
        false,
      );
    } finally {
      await second.close();
    }
  });
  test('S09 S17 another adult immutable target survives visible scope and archive never silently resumes', () async {
    final adult = await store.createProfile(
      commandId: 'ada',
      name: 'Ada',
      adultConfirmed: true,
    );
    final item = await store.createItem(
      commandId: 'ada-item',
      name: 'Ada synthetic',
      form: 'tablet',
      unit: 'mg',
      type: 'medicine',
      personId: adult.id,
    );
    await store.saveDailyPlan(
      commandId: 'ada-plan',
      expectedGeneration: store.generation,
      expectedPersonRevision: 1,
      plan: DailyPlanVersion(
        personId: adult.id,
        planId: 'ada-plan',
        itemId: item.id,
        versionId: 'ada-v1',
        start: date,
        timing: DailySlots([
          DailySlot(
            id: 'ada-slot',
            reminderEnabled: false,
            time: WallTime(8, 0),
            amount: PlannedAmount(
              quantity: ExactQuantity.parse('1'),
              unit: 'mg',
            ),
          ),
        ]),
        zoneBasis: const FollowingLocal(),
      ),
    );
    await store.setPlanReminders(
      commandId: 'ada-optin',
      planId: 'ada-plan',
      personId: adult.id,
      expectedPlanRevision: 1,
      expectedPersonRevision: 1,
      enabled: true,
    );
    final adaRow = (await store.dailyRows(
      scope: FeedScope.person(adult.id),
      from: date,
      toExclusive: date.addDays(1),
      observedZone: 'Europe/London',
    )).rows.single;
    final adaTarget = await store.reminderTarget(
      adaRow,
      observedZone: 'Europe/London',
    );
    final pending = await store.createReminderAction(
      target: adaTarget,
      action: ReminderActionKind.snooze,
      observedZone: 'Europe/London',
    );
    await store.saveBrowsingScope(const FeedScope.me());
    expect(
      (await store.pendingReminderActions())
          .single
          .target
          .row
          .expectation
          .identity
          .personId,
      adult.id,
    );
    expect(pending.target.row.personName, 'Ada');
    await store.archiveProfile(
      commandId: 'archive-ada',
      personId: adult.id,
      expectedRevision: 1,
    );
    await store.reactivateProfile(
      commandId: 'reactivate-ada',
      personId: adult.id,
      expectedRevision: 2,
    );
    expect(await store.planRemindersEnabled('ada-plan'), false);
    await expectLater(
      snooze(adaTarget, id: 'stale-ada'),
      throwsA(isA<CommandConflict>()),
    );
    expect(await store.planRemindersEnabled('p1'), true);
    expect(await store.records(), isEmpty);
  });
  test(
    'S05 fixed-home snooze keeps elapsed identity after observed zone changes',
    () async {
      final old = (await store.dailyPlans()).single.plan;
      await store.saveDailyPlan(
        commandId: 'home-plan',
        expectedGeneration: store.generation,
        expectedPersonRevision: 1,
        expectedPlanRevision: 1,
        plan: DailyPlanVersion(
          personId: old.personId,
          planId: old.planId,
          itemId: old.itemId,
          versionId: 'home-v2',
          start: date,
          timing: old.timing,
          zoneBasis: FixedHome('Europe/London'),
        ),
      );
      final r = (await snooze(await target())).desired;
      final p = await projection(zone: 'America/New_York');
      expect(p.desired.any((d) => d.requestToken == r.requestToken), true);
      expect(r.target.row.expectation.zoneId, 'Europe/London');
      expect(r.deadlineMilliseconds, 4500000);
    },
  );
  test('close waits for started nonclinical reminder transaction and forbids new work', () async {
    final pending = projection();
    final closing = store.close();
    await pending;
    await closing;
    await expectLater(
      store.prepareReminders(
        now: now,
        observedZone: 'Europe/London',
        clockSample: sample,
        adapterFingerprint: 'test-adapter',
      ),
      throwsStateError,
    );
    store = await RecordStore.open(path: path, key: key, isNew: false);
  });

  test('postUncertain receipt remains review, never rearmed, cannot regress to failure', () async {
    final p = await projection();
    final r = p.desired.first;
    expect(
      await store.acknowledgeReminder(
        generation: store.generation,
        requestToken: r.requestToken,
        intentRevision: r.intentRevision,
        sequence: p.sequence,
        receipt: ReminderReceipt.postUncertain,
        adapterFingerprint: 'test-adapter',
      ),
      true,
    );
    expect(
      await store.acknowledgeReminder(
        generation: store.generation,
        requestToken: r.requestToken,
        intentRevision: r.intentRevision,
        sequence: p.sequence,
        receipt: ReminderReceipt.failed,
        adapterFingerprint: 'test-adapter',
      ),
      false,
    );
    final next = await projection();
    expect(next.desired.any((d) => d.requestToken == r.requestToken), false);
    expect(
      next.attention.any(
        (d) =>
            d.requestToken == r.requestToken &&
            d.repairState == ReminderRepairState.postUncertain,
      ),
      true,
    );
    expect(next.coverage.first.preparedThrough, isNull);
  });
  test('S14 ordinary wall requests prepare without a monotonic boot sample and missing zone is explicit', () async {
    final p = await store.prepareReminders(
      now: now,
      observedZone: 'Europe/London',
      clockSample: null,
      adapterFingerprint: 'test-adapter',
    );
    expect(p.desired, isNotEmpty);
    expect(p.desired.every((r) => r.trigger == ReminderTrigger.wall), true);
    final missing = await store.prepareReminders(
      now: now,
      observedZone: null,
      clockSample: null,
      adapterFingerprint: 'test-adapter',
    );
    expect(missing.complete, false);
    expect(
      missing.exclusions.any((e) => e.reason == 'observedZoneUnavailable'),
      true,
    );
  });
  test('disable and re-enable permanently invalidates captured and pending reminder contexts', () async {
    final direct = await target();
    final pending = await store.createReminderAction(
      target: direct,
      action: ReminderActionKind.taken,
      observedZone: 'Europe/London',
    );
    await store.setPlanReminders(
      commandId: 'disable-cycle',
      planId: 'p1',
      personId: meId,
      expectedPlanRevision: 1,
      expectedPersonRevision: 1,
      enabled: false,
    );
    await store.setPlanReminders(
      commandId: 'reenable-cycle',
      planId: 'p1',
      personId: meId,
      expectedPlanRevision: 1,
      expectedPersonRevision: 1,
      enabled: true,
    );
    await expectLater(
      snooze(direct, id: 'old-direct'),
      throwsA(isA<CommandConflict>()),
    );
    await expectLater(
      store.actDaily(
        commandId: pending.commandId,
        row: pending.target.row,
        kind: DailyActionKind.taken,
        actualAt: sample.utc,
        reminderTarget: pending.target,
        reminderObservedZone: 'Europe/London',
      ),
      throwsA(isA<CommandConflict>()),
    );
    final fresh = await target();
    expect(fresh.configRevision, greaterThan(direct.configRevision));
    expect(
      (await snooze(fresh, id: 'fresh-config')).desired.target.configRevision,
      fresh.configRevision,
    );
    expect(await store.records(), isEmpty);
  });
  test(
    'preset to empty custom survives restart without reviving a hidden delay',
    () async {
      final p = await store.createReminderAction(
        target: await target(),
        action: ReminderActionKind.snooze,
        observedZone: 'Europe/London',
      );
      await store.updateReminderAction(
        p.envelopeId,
        delayMinutes: 15,
        clearDelayText: true,
      );
      await store.updateReminderAction(
        p.envelopeId,
        delayText: '7',
        clearDelayMinutes: true,
      );
      await store.updateReminderAction(
        p.envelopeId,
        delayText: '',
        clearDelayMinutes: true,
      );
      await store.close();
      store = await RecordStore.open(path: path, key: key, isNew: false);
      final reopened = (await store.pendingReminderActions()).single;
      expect(reopened.delayText, '');
      expect(reopened.delayMinutes, isNull);
      await expectLater(
        store.updateReminderAction(p.envelopeId, submit: true, sample: sample),
        throwsFormatException,
      );
      final preset = await store.updateReminderAction(
        p.envelopeId,
        delayMinutes: 30,
        clearDelayText: true,
      );
      expect(preset.delayText, isNull);
      expect(preset.delayMinutes, 30);
      final submitted = await store.updateReminderAction(
        p.envelopeId,
        submit: true,
        sample: sample,
      );
      expect(submitted.submitted, true);
      await expectLater(
        store.updateReminderAction(
          p.envelopeId,
          delayText: '',
          clearDelayMinutes: true,
        ),
        throwsA(isA<CommandConflict>()),
      );
    },
  );
  test('calendar preview feed native request dates agree and selector edit rejects stale pending and ack', () async {
    final initial = await projection();
    final stale = initial.desired.first;
    final pending = await store.createReminderAction(
      target: stale.target,
      action: ReminderActionKind.taken,
      observedZone: 'Europe/London',
    );
    final old = (await store.dailyPlans()).single.plan;
    final edited = DailyPlanVersion(
      personId: old.personId,
      planId: old.planId,
      itemId: old.itemId,
      versionId: 'calendar-v2',
      start: date,
      timing: old.timing,
      zoneBasis: old.zoneBasis,
      calendar: SelectedWeekdays([1, 3, 5]),
    );
    await store.saveDailyPlan(
      commandId: 'calendar-edit',
      plan: edited,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      expectedPlanRevision: 1,
    );
    expect(
      await store.acknowledgeReminder(
        generation: store.generation,
        requestToken: stale.requestToken,
        intentRevision: stale.intentRevision,
        sequence: initial.sequence,
        receipt: ReminderReceipt.accepted,
        adapterFingerprint: 'test-adapter',
      ),
      false,
    );
    await expectLater(
      store.actDaily(
        commandId: pending.commandId,
        row: pending.target.row,
        kind: DailyActionKind.taken,
        actualAt: now,
        reminderTarget: pending.target,
        reminderObservedZone: 'Europe/London',
      ),
      throwsA(isA<CommandConflict>()),
    );
    final expected = [date, date.addDays(2), date.addDays(4)];
    final preview = DailyResolver().expand(
      edited,
      from: date,
      toExclusive: date.addDays(7),
      observedZone: 'Europe/London',
      maxDates: 7,
      maxRows: 10,
    );
    final feed = await store.dailyRows(
      from: date,
      toExclusive: date.addDays(7),
      observedZone: 'Europe/London',
    );
    final today = await store.todayDailyRows(
      now: now,
      observedZone: 'Europe/London',
    );
    final native = await projection();
    expect(native.complete, true);
    expect(preview.rows.map((r) => r.identity.originalDate), expected);
    expect(feed.rows.map((r) => r.expectation.identity.originalDate), expected);
    expect(today.rows.single.expectation.identity.originalDate, date);
    expect(
      native.desired.map((r) => r.target.row.expectation.identity.originalDate),
      expected,
    );
    expect(native.desired.map((r) => r.target.row.expectation.instant), [
      DateTime.utc(2026, 10, 19, 7),
      DateTime.utc(2026, 10, 21, 7),
      DateTime.utc(2026, 10, 23, 7),
    ]);
    final request = native.desired.first;
    expect(
      await store.acknowledgeReminder(
        generation: store.generation,
        requestToken: request.requestToken,
        intentRevision: request.intentRevision,
        sequence: native.sequence,
        receipt: ReminderReceipt.accepted,
        adapterFingerprint: 'test-adapter',
      ),
      true,
    );
    await store.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    expect(
      (await projection()).desired.map(
        (r) => r.target.row.expectation.identity.originalDate,
      ),
      expected,
    );
  });
}
