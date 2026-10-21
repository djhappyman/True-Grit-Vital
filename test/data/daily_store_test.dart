import 'dart:io';
import 'dart:convert';

import 'package:true_grit_vital/data/daily_codec.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  late Directory dir;
  late RecordStore store;
  late SubstanceItem item;
  late String path;
  final key = List.generate(32, (i) => i + 1);
  final date = CivilDate(2026, 10, 19);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vital-daily-');
    path = '${dir.path}/records.db';
    store = await RecordStore.open(path: path, key: key, isNew: true);
    item = await store.createItem(
      commandId: 'item',
      name: 'Synthetic item',
      form: 'tablet',
      unit: 'mg',
      type: 'medicine',
    );
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  PlannedAmount amount([String text = '1.000']) => PlannedAmount(
    quantity: ExactQuantity.parse(text),
    enteredText: text,
    unit: 'mg',
  );
  DailyPlanVersion plan({
    int count = 1,
    bool timed = false,
    CivilDate? start,
    String version = 'v1',
    String? person,
    String? itemId,
    DailyTiming? timing,
    CalendarPattern calendar = const EveryDay(),
  }) => DailyPlanVersion(
    personId: person ?? meId,
    planId: 'plan',
    itemId: itemId ?? item.id,
    versionId: version,
    start: start ?? date,
    timing:
        timing ??
        (timed
            ? DailySlots([
                DailySlot(
                  id: 'stable-slot',
                  time: WallTime(8, 0),
                  amount: amount(),
                  reminderEnabled: true,
                ),
              ])
            : DailyCount(count, amount())),
    zoneBasis: const FollowingLocal(),
    calendar: calendar,
  );
  Future<SavedDailyPlan> save(
    DailyPlanVersion p, {
    String op = 'plan-save',
    int? revision,
  }) => store.saveDailyPlan(
    commandId: op,
    plan: p,
    expectedPersonRevision: 1,
    expectedGeneration: store.generation,
    expectedPlanRevision: revision,
  );
  Future<DailyRow> row([RecordStore? source, CivilDate? day]) async =>
      (await (source ?? store).dailyRows(
        from: day ?? date,
        toExclusive: (day ?? date).addDays(1),
        observedZone: 'Europe/London',
      )).rows.single;
  Future<DailyAction> take(
    DailyRow r, {
    String op = 'take',
    RecordStore? source,
  }) => (source ?? store).actDaily(
    commandId: op,
    row: r,
    kind: DailyActionKind.taken,
    actualAt: DateTime.utc(2026, 10, 19, 7),
  );
  test('plan and frozen expectation encrypted restart retain exact lexeme and historical zone', () async {
    await save(plan(timed: true));
    final action = await take(await row());
    expect(action.recordId, isNotNull);
    await store.close();
    expect(
      String.fromCharCodes(await File(path).readAsBytes()),
      isNot(contains('Synthetic item')),
    );
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final history = (await store.dailyRows(
      from: date,
      toExclusive: date.addDays(1),
      observedZone: 'Pacific/Auckland',
    )).rows.single;
    expect(history.expectation.zoneId, 'Europe/London');
    expect(history.expectation.amount.enteredText, '1.000');
    expect(history.takenCount, 1);
    expect((await store.records()).single.enteredAmount, '1.000');
  });
  test(
    'Timed competing Taken and Skip independent connections have one winner',
    () async {
      await save(plan(timed: true));
      final r = await row();
      final second = await RecordStore.open(path: path, key: key, isNew: false);
      try {
        final outcomes = await Future.wait([
          take(r).then((_) => true, onError: (Object _) => false),
          second
              .actDaily(commandId: 'skip', row: r, kind: DailyActionKind.skip)
              .then((_) => true, onError: (Object _) => false),
        ]);
        expect(outcomes.where((x) => x).length, 1);
        final current = await row();
        expect(current.takenCount + current.skippedCount, 1);
        expect((await store.records()).length, current.takenCount);
      } finally {
        await second.close();
      }
    },
  );
  test('count progress separate Skip audit no invented actual and final opportunity race', () async {
    await save(plan(count: 2));
    await take(await row());
    var current = await row();
    expect(current.expectation.instant, isNull);
    expect(current.expectation.originalTime, isNull);
    final second = await RecordStore.open(path: path, key: key, isNew: false);
    try {
      final outcomes = await Future.wait([
        take(
          current,
          op: 'second',
        ).then((_) => true, onError: (Object _) => false),
        second
            .actDaily(
              commandId: 'skip',
              row: current,
              kind: DailyActionKind.skip,
            )
            .then((_) => true, onError: (Object _) => false),
      ]);
      expect(outcomes.where((x) => x).length, 1);
    } finally {
      await second.close();
    }
    current = await row();
    expect(current.takenCount + current.skippedCount, 2);
    expect((await store.records()).length, current.takenCount);
    await expectLater(
      take(current, op: 'overflow'),
      throwsA(isA<CommandConflict>()),
    );
  });
  test(
    'Skip Undo is revision guarded; bucket preserved and second undo conflicts',
    () async {
      await save(plan(count: 2));
      final skipped = await store.actDaily(
        commandId: 'skip',
        row: await row(),
        kind: DailyActionKind.skip,
      );
      final current = await row();
      expect(current.skippedCount, 1);
      expect(await store.records(), isEmpty);
      await store.undoDaily(commandId: 'undo', row: current, action: skipped);
      expect((await row()).skippedCount, 0);
      expect((await row()).actions.single.isUndone, true);
      await store.undoDaily(commandId: 'undo', row: current, action: skipped);
      await expectLater(
        store.undoDaily(
          commandId: 'different-undo',
          row: current,
          action: skipped,
        ),
        throwsA(isA<CommandConflict>()),
      );
    },
  );
  test('Taken replay after response loss retains result before current revision validation', () async {
    await save(plan());
    final captured = await row();
    final first = await take(captured);
    await store.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final replay = await take(captured);
    expect(replay.id, first.id);
    expect(replay.alreadyCommitted, true);
    expect((await store.records()).length, 1);
    await expectLater(
      store.actDaily(
        commandId: 'take',
        row: captured,
        kind: DailyActionKind.skip,
      ),
      throwsA(isA<CommandConflict>()),
    );
  });
  test('atomic failure keeps draft and no expectation action or actual; success clears draft', () async {
    await save(plan());
    final captured = await row();
    await store.saveDraft(
      OrdinaryDraft(
        id: 'draft',
        generation: store.generation,
        operationId: 'take',
        kind: DraftKind.dose,
        personId: meId,
        personRevision: 1,
        targetId: item.id,
        targetRevision: null,
        fields: {'amount': '1.000'},
      ),
    );
    await expectLater(
      store.actDaily(
        commandId: 'take',
        row: captured,
        kind: DailyActionKind.taken,
        actualAt: DateTime.utc(2026, 10, 19, 7),
        failBeforeCommit: true,
      ),
      throwsStateError,
    );
    expect((await row()).revision, 0);
    expect((await row()).actions, isEmpty);
    expect(await store.records(), isEmpty);
    expect(await store.draftById('draft'), isNotNull);
    await take(captured);
    expect(await store.draftById('draft'), isNull);
  });
  test('correct and void linked actual update action/bucket atomically, snapshots retained', () async {
    await save(plan());
    final a = await take(await row());
    final before = await row();
    await store.correct(
      commandId: 'correct',
      recordId: a.recordId!,
      expectedRevision: 1,
      amount: '2',
      actualAt: DateTime.utc(2026, 10, 18),
    );
    final corrected = await row();
    expect(corrected.takenCount, 1);
    expect(corrected.revision, before.revision + 1);
    expect(corrected.expectation.amount.enteredText, '1.000');
    await expectLater(
      store.undoDaily(commandId: 'stale-undo', row: before, action: a),
      throwsA(isA<CommandConflict>()),
    );
    await store.voidRecord(
      commandId: 'void',
      recordId: a.recordId!,
      expectedRevision: 2,
    );
    final undone = await row();
    expect(undone.takenCount, 0);
    expect(undone.actions.single.isUndone, true);
    expect((await store.history(a.recordId!)).length, 3);
    await take(undone, op: 'replace');
    expect((await row()).takenCount, 1);
  });
  test(
    'explicit undo Taken creates historical void and leaves frozen expectation',
    () async {
      await save(plan());
      await take(await row());
      final captured = await row();
      await store.undoDaily(
        commandId: 'undo',
        row: captured,
        action: captured.actions.single,
      );
      expect((await row()).takenCount, 0);
      expect((await store.records()).single.isVoided, true);
      expect((await row()).expectation.versionId, 'v1');
    },
  );
  test('effective edit rejects captured day and preserves previous version snapshots', () async {
    await save(plan(timed: true));
    await take(await row());
    await expectLater(
      save(plan(version: 'v2'), op: 'bad-edit', revision: 1),
      throwsA(isA<CommandConflict>()),
    );
    await save(
      plan(start: date.addDays(1), version: 'v2', count: 3),
      op: 'edit',
      revision: 1,
    );
    final versions = await store.dailyPlanVersions('plan', personId: meId);
    expect(versions.length, 2);
    expect(versions.first.plan.endExclusive, date.addDays(1));
    expect((await row()).takenCount, 1);
    expect((await row(null, date.addDays(1))).plannedCount, 3);
    await expectLater(
      save(
        plan(start: date.addDays(2), version: 'v3'),
        op: 'stale-edit',
        revision: 1,
      ),
      throwsA(isA<CommandConflict>()),
    );
  });
  test(
    'uncaptured effective-date replacement and plan replay remain explicit',
    () async {
      final p = plan();
      await save(p);
      await save(plan(version: 'v2', count: 4), op: 'edit', revision: 1);
      expect((await row()).plannedCount, 4);
      expect((await store.dailyPlanVersions('plan', personId: meId)).length, 1);
      expect((await save(p)).alreadyCommitted, true);
    },
  );
  test(
    'PRN has no expectations yet permits deliberate independent actual records',
    () async {
      await save(plan(timing: const AsNeeded()));
      expect(
        (await store.dailyRows(
          from: date,
          toExclusive: date.addDays(1),
          observedZone: 'Europe/London',
        )).rows,
        isEmpty,
      );
      expect((await store.dailyPlans()).single.plan.timing, isA<AsNeeded>());
      for (var i = 0; i < 2; i++) {
        await store.record(
          commandId: 'prn$i',
          itemId: item.id,
          amount: '1',
          actualAt: DateTime.utc(2026, 10, 19),
        );
      }
      expect((await store.records()).length, 2);
    },
  );
  test('old generation and changed person action contexts reject', () async {
    await save(plan());
    final captured = await row();
    await store.editProfile(
      commandId: 'profile',
      personId: meId,
      expectedRevision: 1,
      name: 'Me',
      adultConfirmed: true,
    );
    await expectLater(take(captured), throwsA(isA<CommandConflict>()));
    await expectLater(
      store.saveDailyPlan(
        commandId: 'old-gen',
        plan: plan(version: 'v2'),
        expectedPersonRevision: 2,
        expectedGeneration: 'old',
        expectedPlanRevision: 1,
      ),
      throwsA(isA<CommandConflict>()),
    );
  });
  test('ownership, archive and delete remove only target schedule graph and stop intents', () async {
    final adult = await store.createProfile(
      commandId: 'adult',
      name: 'Alex',
      adultConfirmed: true,
    );
    final other = await store.createItem(
      commandId: 'other-item',
      name: 'Other',
      form: 'tablet',
      unit: 'mg',
      type: 'medicine',
      personId: adult.id,
    );
    await expectLater(
      save(plan(person: adult.id)),
      throwsA(isA<CommandConflict>()),
    );
    await save(plan(person: adult.id, itemId: other.id));
    final captured = await row();
    await take(captured);
    await store.archiveProfile(
      commandId: 'archive',
      personId: adult.id,
      expectedRevision: 1,
    );
    expect((await store.dailyPlans()), isEmpty);
    expect((await store.dailyReminderIntents()).single['stopped'], 1);
    await expectLater(
      take(captured, op: 'stale'),
      throwsA(isA<CommandConflict>()),
    );
    await store.deleteProfile(
      commandId: 'delete',
      personId: adult.id,
      expectedRevision: 2,
    );
    expect(await store.dailyPlans(scope: FeedScope.person(adult.id)), isEmpty);
    expect(await store.dailyReminderIntents(), isEmpty);
    expect((await store.items()).single.id, item.id);
    await expectLater(take(captured), throwsA(isA<CommandConflict>()));
    expect((await store.reminderStopIntents())[adult.id], 3);
  });
  test('clock choices scoped persist and mismatch action conflicts', () async {
    final spring = CivilDate(2026, 3, 29);
    final p = plan(
      start: spring,
      timing: DailySlots([
        DailySlot(
          id: 'gap',
          time: WallTime(1, 30),
          amount: amount(),
          reminderEnabled: true,
        ),
      ]),
    );
    await save(p);
    var captured = await row(null, spring);
    expect(captured.expectation.resolution, DailyResolution.missingClock);
    await store.chooseDailyClock(
      commandId: 'clock',
      row: captured,
      decision: const NoAlert(),
    );
    await expectLater(take(captured), throwsA(isA<CommandConflict>()));
    captured = await row(null, spring);
    expect(captured.expectation.resolution, DailyResolution.noAlert);
    await take(captured);
    expect((await row(null, spring)).takenCount, 1);
  });
  test('unsupported range surfaces incomplete; captured snapshots bypass recalculation', () async {
    await save(plan(start: CivilDate(1900, 1, 1), timed: true));
    final result = await store.dailyRows(
      from: CivilDate(1900, 1, 1),
      toExclusive: CivilDate(1900, 1, 2),
      observedZone: 'Europe/London',
    );
    expect(result.complete, false);
    expect(result.issue, DailyCalculationIssue.unsupportedTimezoneRange);
  });
  test('bounded rows explicitly incomplete and fixed home today differs observed day', () async {
    final p = DailyPlanVersion(
      personId: meId,
      planId: 'plan',
      itemId: item.id,
      versionId: 'v1',
      start: date,
      timing: DailyCount(1, amount()),
      zoneBasis: FixedHome('Pacific/Auckland'),
    );
    await save(p);
    final today = await store.todayDailyRows(
      now: DateTime.utc(2026, 10, 19, 23),
      observedZone: 'America/Los_Angeles',
    );
    expect(
      today.rows.single.expectation.identity.originalDate,
      date.addDays(1),
    );
    final result = await store.dailyRows(
      from: date,
      toExclusive: date.addDays(3),
      observedZone: 'Europe/London',
      maxRows: 1,
    );
    expect(result.complete, false);
    expect(result.rows.length, 1);
  });
  test('frozen populated v5 migration retains all prior semantics and draft restart', () async {
    await store.close();
    await File(path).delete();
    final db = sqlite3.open(path);
    final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    db.execute("PRAGMA cipher='chacha20'");
    db.execute("PRAGMA key=\"x'$hex'\"");
    db.execute(
      await File('test/data/fixtures/record_store_v5.sql').readAsString(),
    );
    db.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    expect(store.generation, 'fixture-generation');
    expect((await store.drafts()).single.fields['amount'], '1.000');
    expect((await store.history('record')).map((r) => r.enteredAmount), [
      '0.125000',
      '0.5',
    ]);
    expect(
      (await store.history('other-record')).single.source,
      RecordSource.recordedOnBehalf,
    );
    await store.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    expect(await store.dailyPlans(), isEmpty);
  });
  test(
    'v5 migration failure rolls back and retains recovery dataset',
    () async {
      final failed = '${dir.path}/failure.db';
      final db = sqlite3.open(failed);
      final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
      db.execute("PRAGMA cipher='chacha20'");
      db.execute("PRAGMA key=\"x'$hex'\"");
      db.execute(
        await File('test/data/fixtures/record_store_v5.sql').readAsString(),
      );
      db.execute('CREATE TABLE daily_plan(obstacle TEXT) STRICT');
      db.close();
      await expectLater(
        RecordStore.open(path: failed, key: key, isNew: false),
        throwsA(anything),
      );
      final check = sqlite3.open(failed);
      check.execute("PRAGMA cipher='chacha20'");
      check.execute("PRAGMA key=\"x'$hex'\"");
      expect(check.select('PRAGMA user_version').single.values.single, 5);
      expect(check.select('SELECT * FROM ordinary_draft').length, 1);
      expect(check.select('SELECT * FROM revision').length, 3);
      check.close();
    },
  );

  test('superseded future versions retain original immutable audit and explicit pages', () async {
    await save(plan());
    await save(
      plan(start: date.addDays(5), version: 'future'),
      op: 'future',
      revision: 1,
    );
    await save(
      plan(start: date.addDays(2), version: 'replacement'),
      op: 'replacement',
      revision: 2,
    );
    final audit = await store.dailyPlanAudit('plan', personId: meId);
    expect(audit.map((p) => p.plan.versionId), ['v1', 'future', 'replacement']);
    expect(audit.first.plan.endExclusive, isNull);
    expect(audit[1].plan.start, date.addDays(5));
    expect(
      (await store.dailyPlanVersions(
        'plan',
        personId: meId,
      )).map((p) => p.plan.versionId),
      ['v1', 'replacement'],
    );
    expect(
      (await store.dailyPlanAudit(
        'plan',
        personId: meId,
        limit: 1,
        offset: 1,
      )).single.plan.versionId,
      'future',
    );
  });
  test(
    'Skip entry audit order is latest first and Undo targets captured action',
    () async {
      await save(plan(count: 3));
      await take(await row(), op: 'z-first');
      final skipped = await store.actDaily(
        commandId: 'a-second',
        row: await row(),
        kind: DailyActionKind.skip,
      );
      final current = await row();
      expect(current.actions.first.id, 'a-second');
      expect(current.actions.first.sequence, 2);
      expect(current.actions.first.recordedAt.isUtc, true);
      expect(current.actions.first.recordId, isNull);
      await store.undoDaily(
        commandId: 'undo-second',
        row: current,
        action: skipped,
      );
      final after = await row();
      expect(after.takenCount, 1);
      expect(after.skippedCount, 0);
      expect(after.actions.first.sequence, 2);
      expect(after.actions.first.recordedAt, skipped.recordedAt);
    },
  );
  test('travel invalidates uncaptured local clock choice without breaking feed or action', () async {
    final fold = CivilDate(2026, 10, 25);
    await save(
      plan(
        start: fold,
        timing: DailySlots([
          DailySlot(
            id: 'fold',
            time: WallTime(1, 30),
            amount: amount(),
            reminderEnabled: true,
          ),
        ]),
      ),
    );
    final london = await row(null, fold);
    expect(london.expectation.resolution, DailyResolution.repeatedClock);
    await store.chooseDailyClock(
      commandId: 'choose',
      row: london,
      decision: const ChooseClockInstance(1),
    );
    final travelled = await store.dailyRows(
      from: fold,
      toExclusive: fold.addDays(1),
      observedZone: 'America/New_York',
    );
    expect(travelled.complete, true);
    expect(travelled.rows.single.expectation.zoneId, 'America/New_York');
    expect(travelled.rows.single.expectation.resolution, DailyResolution.exact);
    await store.actDaily(
      commandId: 'travelled-skip',
      row: travelled.rows.single,
      kind: DailyActionKind.skip,
    );
    final captured = (await store.dailyRows(
      from: fold,
      toExclusive: fold.addDays(1),
      observedZone: 'Europe/London',
    )).rows.single;
    expect(captured.expectation.zoneId, 'America/New_York');
  });
  test('captured-only history never generates expectations; discarded draft blocks quick action', () async {
    await save(plan());
    expect((await store.capturedDailyRows()).rows, isEmpty);
    await store.saveDraft(
      OrdinaryDraft(
        id: 'discard',
        generation: store.generation,
        operationId: 'discarded-action',
        kind: DraftKind.dose,
        personId: meId,
        personRevision: 1,
        targetId: item.id,
        targetRevision: null,
        fields: {'amount': '1'},
      ),
    );
    await store.discardDraft('discard');
    await expectLater(
      take(await row(), op: 'discarded-action'),
      throwsA(isA<CommandConflict>()),
    );
    expect((await store.capturedDailyRows()).rows, isEmpty);
    await take(await row());
    expect((await store.capturedDailyRows()).rows.single.takenCount, 1);
  });
  test(
    'indexed today seek finds current after 1100 old effective versions',
    () async {
      await save(plan(start: CivilDate(2020, 1, 1)));
      await store.close();
      final db = sqlite3.open(path);
      final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
      db.execute("PRAGMA cipher='chacha20'");
      db.execute("PRAGMA key=\"x'$hex'\"");
      db.execute('DELETE FROM daily_version');
      db.execute('DELETE FROM daily_version_audit');
      db.execute('BEGIN');
      for (var i = 0; i < 1101; i++) {
        final start = CivilDate(2020, 1, 1).addDays(i);
        final end = i == 1100 ? null : start.addDays(1);
        final p = DailyPlanVersion(
          personId: meId,
          planId: 'plan',
          itemId: item.id,
          versionId: 'old$i',
          start: start,
          endExclusive: end,
          timing: DailyCount(1, amount()),
          zoneBasis: const FollowingLocal(),
        );
        final encoded = jsonEncode(encodeDailyPlan(p));
        db.execute('INSERT INTO daily_version VALUES (?,?,?,?,?,?)', [
          'old$i',
          'plan',
          meId,
          start.toString(),
          end?.toString(),
          encoded,
        ]);
        db.execute('INSERT INTO daily_version_audit VALUES (?,?,?,?,?)', [
          'old$i',
          'plan',
          meId,
          1,
          encoded,
        ]);
      }
      db.execute('COMMIT');
      db.close();
      store = await RecordStore.open(path: path, key: key, isNew: false);
      final today = await store.todayDailyRows(
        now: DateTime.utc(2026, 10, 19, 12),
        observedZone: 'Europe/London',
      );
      expect(today.complete, true);
      expect(today.rows.single.expectation.versionId, 'old1100');
      final next = await store.nextDailyPlans(
        now: DateTime.utc(2026, 10, 19, 12),
        observedZone: 'Europe/London',
      );
      expect(next.complete, true);
      expect(next.rows.single.plan.versionId, 'old1100');
      expect(next.rows.single.result.next!.identity.originalDate, date);

      expect(
        (await store.dailyPlanVersions(
          'plan',
          personId: meId,
          limit: 100,
          offset: 1100,
        )).single.plan.versionId,
        'old1100',
      );
    },
  );
  test('dense bucket statuses aggregate all actions but materialise bounded audit pages', () async {
    await save(plan(count: 1000));
    await store.actDaily(
      commandId: 'initial',
      row: await row(),
      kind: DailyActionKind.skip,
    );
    final original = await row();
    await store.close();
    final db = sqlite3.open(path);
    final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    db.execute("PRAGMA cipher='chacha20'");
    db.execute("PRAGMA key=\"x'$hex'\"");
    final bucket = dailyIdentityKey(original.expectation.identity);
    db.execute('UPDATE daily_action SET undone=1');
    db.execute('BEGIN');
    for (var i = 2; i <= 253; i++) {
      db.execute(
        'INSERT INTO daily_action(id,bucket,person,kind,record,revision,undone,sequence,recorded_at,occurs_at) VALUES (?,?,?,?,?,1,?,?,?,(SELECT occurs_at FROM daily_expectation WHERE id=? AND person=?))',
        [
          'audit$i',
          bucket,
          meId,
          'skip',
          null,
          i <= 250 ? 1 : 0,
          i,
          DateTime.utc(2026, 10, 19).microsecondsSinceEpoch + i,
          bucket,
          meId,
        ],
      );
    }
    db.execute('UPDATE daily_expectation SET revision=253');
    db.execute('COMMIT');
    db.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final dense = await row();
    expect(dense.skippedCount, 3);
    expect(dense.actions.length, 100);
    expect(dense.actionsComplete, false);
    expect(dense.actions.first.sequence, 253);
    expect(
      (await store.dailyActions(
        dense.expectation.identity,
        limit: 100,
        offset: 200,
      )).length,
      53,
    );
    await store.undoDaily(
      commandId: 'undo-oldest-active',
      row: dense,
      action: dense.actions.first,
    );
    expect((await row()).skippedCount, 2);
  });
  test('reactivation and quick action retain stopped intent until explicit resume capability', () async {
    final adult = await store.createProfile(
      commandId: 'adult',
      name: 'Alex',
      adultConfirmed: true,
    );
    final other = await store.createItem(
      commandId: 'other',
      name: 'Other',
      form: 'tablet',
      unit: 'mg',
      type: 'medicine',
      personId: adult.id,
    );
    await save(plan(person: adult.id, itemId: other.id));
    await store.archiveProfile(
      commandId: 'archive',
      personId: adult.id,
      expectedRevision: 1,
    );
    await store.reactivateProfile(
      commandId: 'reactivate',
      personId: adult.id,
      expectedRevision: 2,
    );
    await store.actDaily(
      commandId: 'after-reactivate',
      row: await row(),
      kind: DailyActionKind.skip,
    );
    expect((await store.dailyReminderIntents()).single['stopped'], 1);
  });

  test('next timed seek skips elapsed today time and finds tomorrow independently of preview', () async {
    await save(plan(timed: true));
    final next = await store.nextDailyPlans(
      now: DateTime.utc(2026, 10, 19, 12),
      observedZone: 'Europe/London',
    );
    expect(next.complete, true);
    expect(
      next.rows.single.result.next!.identity.originalDate,
      date.addDays(1),
    );
    expect(
      next.rows.single.result.next!.instant,
      DateTime.utc(2026, 10, 20, 7),
    );
  });
  test('next count skips fully resolved today bucket and future recorded timed opportunity', () async {
    await save(plan());
    await take(await row());
    final next = await store.nextDailyPlans(
      now: DateTime.utc(2026, 10, 19, 12),
      observedZone: 'Europe/London',
    );
    expect(
      next.rows.single.result.next!.identity.originalDate,
      date.addDays(1),
    );
    expect(next.rows.single.result.next!.instant, isNull);
    await store.saveDailyPlan(
      commandId: 'timed-next',
      plan: plan(timed: true, start: date.addDays(1), version: 'timed'),
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      expectedPlanRevision: 1,
    );
    await store.actDaily(
      commandId: 'future-done',
      row: await row(null, date.addDays(1)),
      kind: DailyActionKind.skip,
    );
    final timed = await store.nextDailyPlans(
      now: DateTime.utc(2026, 10, 20, 5),
      observedZone: 'Europe/London',
    );
    expect(timed.complete, true);
    expect(
      timed.rows.single.result.next!.identity.originalDate,
      date.addDays(2),
    );
  });
  test('next uses current version before future PRN and explicit version bound is incomplete', () async {
    await save(plan(timed: true));
    await save(
      plan(
        start: date.addDays(2),
        version: 'future-prn',
        timing: const AsNeeded(),
      ),
      op: 'future',
      revision: 1,
    );
    var next = await store.nextDailyPlans(
      now: DateTime.utc(2026, 10, 19, 12),
      observedZone: 'Europe/London',
    );
    expect(next.complete, true);
    expect(next.rows.single.plan.versionId, 'v1');
    expect(
      next.rows.single.result.next!.identity.originalDate,
      date.addDays(1),
    );
    next = await store.nextDailyPlans(
      now: DateTime.utc(2026, 10, 20, 12),
      observedZone: 'Europe/London',
      maxVersions: 1,
    );
    expect(next.complete, false);
    expect(next.rows.single.result.complete, false);
    expect(next.rows.single.result.next, isNull);
  });
  test(
    'next retains clock review and explicit incomplete at date budget',
    () async {
      final spring = CivilDate(2026, 3, 29);
      await save(
        plan(
          start: spring,
          timing: DailySlots([
            DailySlot(
              id: 'gap',
              time: WallTime(1, 30),
              amount: amount(),
              reminderEnabled: true,
            ),
          ]),
        ),
      );
      var next = await store.nextDailyPlans(
        now: DateTime.utc(2026, 3, 29),
        observedZone: 'Europe/London',
        maxDates: 1,
      );
      expect(next.complete, false);
      expect(
        next.rows.single.result.needsReview.single.resolution,
        DailyResolution.missingClock,
      );
      next = await store.nextDailyPlans(
        now: DateTime.utc(2026, 3, 29),
        observedZone: 'Europe/London',
      );
      expect(next.complete, true);
      expect(
        next.rows.single.result.needsReview.single.identity.originalDate,
        spring,
      );
      expect(
        next.rows.single.result.next!.identity.originalDate,
        spring.addDays(1),
      );
    },
  );
  test('missing observed zone keeps fixed-home Today and next while local plan explicitly incomplete', () async {
    await save(plan());
    final homeItem = await store.createItem(
      commandId: 'home-item',
      name: 'Home',
      form: 'tablet',
      unit: 'mg',
      type: 'medicine',
    );
    final home = DailyPlanVersion(
      personId: meId,
      planId: 'home',
      itemId: homeItem.id,
      versionId: 'home-v1',
      start: date,
      timing: DailySlots([
        DailySlot(
          id: 'home-slot',
          time: WallTime(8, 0),
          amount: amount(),
          reminderEnabled: true,
        ),
      ]),
      zoneBasis: FixedHome('Pacific/Auckland'),
    );
    await store.saveDailyPlan(
      commandId: 'home-plan',
      plan: home,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
    );
    final today = await store.todayDailyRows(
      now: DateTime.utc(2026, 10, 19, 12),
      observedZone: null,
    );
    expect(today.complete, false);
    expect(today.issue, DailyCalculationIssue.observedZoneUnavailable);
    expect(today.rows.single.expectation.identity.planId, 'home');
    final next = await store.nextDailyPlans(
      now: DateTime.utc(2026, 10, 19, 12),
      observedZone: null,
    );
    expect(next.complete, false);
    expect(
      next.rows.singleWhere((r) => r.plan.planId == 'home').result.next!.zoneId,
      'Pacific/Auckland',
    );
    expect(
      next.rows.singleWhere((r) => r.plan.planId == 'plan').result.issue,
      DailyCalculationIssue.observedZoneUnavailable,
    );
    final range = await store.dailyRows(
      from: date,
      toExclusive: date.addDays(1),
      observedZone: null,
    );
    expect(range.rows.single.expectation.zoneId, 'Pacific/Auckland');
    expect(range.complete, false);
  });

  test('next timed seek retains pending sibling at same instant after one slot resolved', () async {
    await save(
      plan(
        timing: DailySlots([
          for (final id in ['a', 'b'])
            DailySlot(
              id: id,
              time: WallTime(8, 0),
              amount: amount(),
              reminderEnabled: true,
            ),
        ]),
      ),
    );
    final rows = await store.dailyRows(
      from: date,
      toExclusive: date.addDays(1),
      observedZone: 'Europe/London',
    );
    await store.actDaily(
      commandId: 'resolve-a',
      row: rows.rows.firstWhere((r) => r.expectation.identity.slotId == 'a'),
      kind: DailyActionKind.skip,
    );
    final next = await store.nextDailyPlans(
      now: DateTime.utc(2026, 10, 19, 6),
      observedZone: 'Europe/London',
    );
    expect(next.complete, true);
    expect(next.rows.single.result.next!.identity.slotId, 'b');
    expect(next.rows.single.result.next!.identity.originalDate, date);
    expect(
      next.rows.single.result.next!.instant,
      DateTime.utc(2026, 10, 19, 7),
    );
  });
  test('next resolved timed seek cannot reset date horizon and claim unseen tomorrow', () async {
    await save(plan(timed: true));
    await store.actDaily(
      commandId: 'resolved',
      row: await row(),
      kind: DailyActionKind.skip,
    );
    final next = await store.nextDailyPlans(
      now: DateTime.utc(2026, 10, 19, 6),
      observedZone: 'Europe/London',
      maxDates: 1,
    );
    expect(next.complete, false);
    expect(next.rows.single.result.complete, false);
    expect(next.rows.single.result.next, isNull);
  });
  test('calendar selectors round trip encrypted schema10 with explicit policy and anchors', () async {
    final patterns = <CalendarPattern>[
      SelectedWeekdays([7, 1, 1]),
      EveryNDays(anchor: CivilDate(2020, 1, 1), interval: 13),
      EveryNWeeks(
        anchorWeekStart: CivilDate(2020, 12, 28),
        interval: 2,
        weekdays: [1, 5],
      ),
      EveryNMonths(
        anchorMonth: CivilDate(2026, 1, 1),
        interval: 1,
        selector: DayOfMonth(
          31,
          missingDatePolicy: MissingDatePolicy.lastValid,
        ),
      ),
      EveryNMonths(
        anchorMonth: CivilDate(2026, 1, 1),
        interval: 12,
        selector: OrdinalWeekday(
          5,
          1,
          missingDatePolicy: MissingDatePolicy.omit,
        ),
      ),
      EveryNMonths(
        anchorMonth: CivilDate(2026, 1, 1),
        interval: 3,
        selector: LastWeekday(5),
      ),
    ];
    for (final pattern in patterns) {
      final encoded = encodeDailyPlan(plan(calendar: pattern));
      expect(
        encodeDailyPlan(
          decodeDailyPlan(
            jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>,
          ),
        ),
        encoded,
      );
    }
    final p = plan(calendar: patterns[3]);
    await save(p);
    await store.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    expect(
      encodeDailyPlan((await store.dailyPlans()).single.plan),
      encodeDailyPlan(p),
    );
    expect((await save(p)).alreadyCommitted, true);
    await expectLater(
      save(plan(calendar: patterns[0])),
      throwsA(isA<CommandConflict>()),
    );
  });
  test('populated current schema legacy daily JSON reopens without reinterpretation', () async {
    await save(plan(timed: true));
    await take(await row());
    await store.close();
    final db = sqlite3.open(path);
    final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    db.execute("PRAGMA cipher='chacha20'");
    db.execute("PRAGMA key=\"x'$hex'\"");
    expect(db.select('PRAGMA user_version').single.values.single, 23);
    for (final table in ['daily_version', 'daily_version_audit']) {
      db.execute(
        "UPDATE $table SET snapshot=json_remove(snapshot,'\$.calendar')",
      );
    }
    db.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    expect((await store.dailyPlans()).single.plan.calendar, isA<EveryDay>());
    expect((await save(plan(timed: true))).alreadyCommitted, true);
    expect((await row()).takenCount, 1);
    expect((await store.records()).single.enteredAmount, '1.000');
    await store.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    expect((await row()).expectation.identity.originalDate, date);
  });
  test(
    'calendar effective edit retains captured history and closed selector',
    () async {
      await save(plan(calendar: SelectedWeekdays([1]), timed: true));
      final before = await row();
      await take(before);
      await save(
        plan(
          start: date.addDays(1),
          version: 'tuesdays',
          calendar: SelectedWeekdays([2]),
        ),
        op: 'edit-calendar',
        revision: 1,
      );
      final versions = await store.dailyPlanVersions('plan', personId: meId);
      expect((versions.first.plan.calendar as SelectedWeekdays).weekdays, [1]);
      expect((await row()).expectation.versionId, 'v1');
      expect(
        (await store.capturedDailyRows()).rows.single.expectation.instant,
        before.expectation.instant,
      );
      await expectLater(
        take(before, op: 'stale-calendar'),
        throwsA(isA<CommandConflict>()),
      );
      final future = await store.dailyRows(
        from: date.addDays(1),
        toExclusive: date.addDays(8),
        observedZone: 'Europe/London',
      );
      expect(future.rows.map((r) => r.expectation.identity.originalDate), [
        date.addDays(1),
      ]);
    },
  );
  test('sparse next retains calendar date beyond preview and skips resolved future bucket', () async {
    final pattern = EveryNMonths(
      anchorMonth: CivilDate(2028, 2, 1),
      interval: 48,
      selector: DayOfMonth(29, missingDatePolicy: MissingDatePolicy.omit),
    );
    await save(plan(calendar: pattern));
    expect(
      (await store.dailyRows(
        from: date,
        toExclusive: date.addDays(7),
        observedZone: 'Europe/London',
      )).rows,
      isEmpty,
    );
    var next = await store.nextDailyPlans(
      now: DateTime.utc(2026, 10, 19),
      observedZone: 'Europe/London',
    );
    expect(next.complete, true);
    expect(
      next.rows.single.result.next!.identity.originalDate,
      CivilDate(2028, 2, 29),
    );
    expect(next.rows.single.result.datesExamined, lessThanOrEqualTo(2));
    await store.actDaily(
      commandId: 'future-leap',
      row: await row(null, CivilDate(2028, 2, 29)),
      kind: DailyActionKind.skip,
    );
    next = await store.nextDailyPlans(
      now: DateTime.utc(2026, 10, 19),
      observedZone: 'Europe/London',
    );
    expect(
      next.rows.single.result.next!.identity.originalDate,
      CivilDate(2032, 2, 29),
    );
    expect(next.rows.single.result.datesExamined, lessThanOrEqualTo(3));
  });
  test(
    'sparse timed next beyond named-zone rules retains known date and issue',
    () async {
      await save(
        plan(
          timed: true,
          calendar: EveryNMonths(
            anchorMonth: CivilDate(2200, 1, 1),
            interval: 1200,
            selector: DayOfMonth(1),
          ),
        ),
      );
      final next = (await store.nextDailyPlans(
        now: DateTime.utc(2026, 10, 19),
        observedZone: 'Europe/London',
      )).rows.single.result;
      expect(next.complete, false);
      expect(next.issue, DailyCalculationIssue.unsupportedTimezoneRange);
      expect(next.calendarDate, CivilDate(2200, 1, 1));
    },
  );

  test('unknown calendar versions and missing date choices fail instead of daily fallback', () {
    final encoded = encodeDailyPlan(plan());
    expect(
      () => decodeDailyPlan({
        ...encoded,
        'calendar': {'version': 2, 'kind': 'daily'},
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => decodeDailyPlan({
        ...encoded,
        'calendar': {'version': 1, 'kind': 'mystery'},
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => decodeDailyPlan({
        ...encoded,
        'calendar': {
          'version': 1,
          'kind': 'months',
          'anchor': '2026-01-01',
          'interval': 1,
          'selector': {'kind': 'day', 'day': 31},
        },
      }),
      throwsArgumentError,
    );
  });
  test('unsupported saved composition stays explicit across reopen and shared reads', () async {
    await save(
      plan(
        calendar: const UnsupportedCalendarPattern('interval_plus_calendar'),
      ),
    );
    await store.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final rows = await store.dailyRows(
      from: date,
      toExclusive: date.addDays(7),
      observedZone: 'Europe/London',
    );
    expect(rows.complete, false);
    expect(rows.issue, DailyCalculationIssue.unsupportedCalendarComposition);
    expect(rows.rows, isEmpty);
    final next = await store.nextDailyPlans(
      now: DateTime.utc(2026, 10, 19),
      observedZone: 'Europe/London',
    );
    expect(next.complete, false);
    expect(
      next.rows.single.result.issue,
      DailyCalculationIssue.unsupportedCalendarComposition,
    );
  });
}
