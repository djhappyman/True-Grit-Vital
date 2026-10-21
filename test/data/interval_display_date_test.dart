import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';

/// An elapsed occurrence is identified by its UTC calendar date, while it is
/// shown and expanded on the local date of the observed zone. In a
/// positive-offset zone those dates differ for an occurrence between local
/// midnight and UTC midnight. Validation must resolve the display date, while
/// still rejecting a forged occurrence.
void main() {
  late Directory dir;
  late RecordStore store;
  late SubstanceItem item;
  final key = List.generate(32, (i) => i + 1);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vital-interval-date-');
    store = await RecordStore.open(
      path: '${dir.path}/records.db',
      key: key,
      isNew: true,
    );
    item = await store.createItem(
      commandId: 'item',
      name: 'Synthetic midnight crossing',
      form: 'tablet',
      unit: 'mg',
      type: 'medicine',
    );
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  Future<void> expectDisplayDateAccepted({
    required DateTime instant,
    required String zone,
    required CivilDate planStart,
  }) async {
    final now = DateTime.now().toUtc();
    final identityDate = CivilDate.fromDateTime(instant);
    final displayDate = DailyResolver().clock.dateAt(instant, zone);
    expect(displayDate, isNot(identityDate));
    final plan = DailyPlanVersion(
      personId: meId,
      planId: 'interval-plan',
      itemId: item.id,
      versionId: 'interval-version',
      start: planStart,
      zoneBasis: FixedHome(zone),
      timing: ElapsedInterval(
        segmentId: 'segment',
        duration: ExactElapsed.parseHours('6'),
        mode: IntervalMode.qualifyingActual,
        amount: PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
        reminderEnabled: false,
      ),
    );
    final sample = ReminderClockSample(
      bootId: 'boot',
      utcMilliseconds: now.millisecondsSinceEpoch,
      elapsedMilliseconds: 1000,
    );
    final saved = await store.saveDailyPlan(
      commandId: 'plan',
      plan: plan,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      intervalClockSample: sample,
    );
    final seed = await store.record(
      commandId: 'seed',
      itemId: item.id,
      amount: '1',
      actualAt: instant.subtract(const Duration(hours: 6)),
    );
    await store.qualifyInterval(
      commandId: 'qualify',
      review: await store.previewIntervalChange(
        plan: saved,
        recordId: seed.id,
        expectedRecordRevision: seed.revision,
        qualifies: true,
        now: now,
        observedZone: zone,
        intervalClockSample: sample,
      ),
    );
    final row = (await store.dailyRows(
      from: displayDate,
      toExclusive: displayDate.addDays(1),
      observedZone: zone,
    )).rows.single;
    expect(row.expectation.instant, instant);
    expect(row.expectation.identity.originalDate, identityDate);

    final e = row.expectation;
    final forgedInstant = instant.add(const Duration(minutes: 1));
    await expectLater(
      store.actDaily(
        commandId: 'forged',
        kind: DailyActionKind.taken,
        actualAt: now,
        row: DailyRow(
          generation: row.generation,
          personRevision: row.personRevision,
          planRevision: row.planRevision,
          expectation: DailyExpectation(
            identity: e.identity,
            itemId: e.itemId,
            versionId: e.versionId,
            zoneId: e.zoneId,
            amount: e.amount,
            resolution: e.resolution,
            calculatorVersion: e.calculatorVersion,
            timezoneDataVersion: e.timezoneDataVersion,
            originalTime: e.originalTime,
            effectiveTime: e.effectiveTime,
            instant: forgedInstant,
            reminderEnabled: e.reminderEnabled,
            clockCandidates: [forgedInstant],
          ),
          personName: row.personName,
          itemName: row.itemName,
          revision: row.revision,
          actions: row.actions,
          takenCount: row.takenCount,
          skippedCount: row.skippedCount,
        ),
      ),
      throwsA(isA<CommandConflict>()),
    );

    final action = await store.actDaily(
      commandId: 'taken',
      row: row,
      kind: DailyActionKind.taken,
      actualAt: now,
    );
    expect(action.recordId, isNotNull);
    expect((await store.records()).length, 2);
  }

  test(
    'a planned elapsed occurrence crossing UTC midnight keeps its display date',
    () async {
      final now = DateTime.now().toUtc();
      // The most recent 23:30 UTC is always in the past, and always falls on
      // the following civil date in a constant UTC+9 zone.
      var instant = DateTime.utc(now.year, now.month, now.day, 23, 30);
      if (!instant.isBefore(now)) {
        instant = instant.subtract(const Duration(days: 1));
      }
      await expectDisplayDateAccepted(
        instant: instant,
        zone: 'Asia/Tokyo',
        planStart: CivilDate.fromDateTime(instant).addDays(-1),
      );
    },
  );

  test('a summer London occurrence after local midnight keeps its display '
      'date', () async {
    // 23:30Z is 00:30 BST the next civil date, so the identity date and the
    // display date deliberately differ.
    await expectDisplayDateAccepted(
      instant: DateTime.utc(2026, 7, 1, 23, 30),
      zone: 'Europe/London',
      planStart: CivilDate(2026, 6, 30),
    );
  });
}
