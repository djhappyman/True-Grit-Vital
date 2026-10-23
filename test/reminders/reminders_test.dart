import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  const sample = ReminderClockSample(
    utcMilliseconds: 1792400400000,
    elapsedMilliseconds: 3600000,
    bootId: 'b1',
  );
  test('S01 S04 delay begins at Save sample, checked arithmetic', () {
    final deadline = snoozeDeadline(sample, 15);
    expect(deadline.elapsedMilliseconds, 4500000);
    expect(deadline.projectedUtc, sample.utc.add(const Duration(minutes: 15)));
    expect(snoozeDeadline(sample, 5).elapsedMilliseconds, 3900000);
  });
  test('S05 elapsed deadline remains stable despite wall change', () {
    expect(
      snoozeClockState(
        saved: sample,
        deadlineMilliseconds: 4500000,
        current: ReminderClockSample(
          utcMilliseconds: sample.utcMilliseconds + 7200000,
          elapsedMilliseconds: 3900000,
          bootId: 'b1',
        ),
      ),
      ReminderRepairState.pending,
    );
  });
  test(
    'S13 S14 missing clock waits, changed boot interrupted, no wall fallback',
    () {
      expect(
        snoozeClockState(
          saved: sample,
          deadlineMilliseconds: 4500000,
          current: null,
        ),
        ReminderRepairState.review,
      );
      expect(
        snoozeClockState(
          saved: sample,
          deadlineMilliseconds: 4500000,
          current: ReminderClockSample(
            utcMilliseconds: sample.utcMilliseconds,
            elapsedMilliseconds: 0,
            bootId: 'b2',
          ),
        ),
        ReminderRepairState.interrupted,
      );
    },
  );
  test('S16 zero negative native/instant overflow and expiry never wrap', () {
    for (final delay in [0, -1, 9223372036854775807]) {
      expect(() => snoozeDeadline(sample, delay), throwsFormatException);
    }
    expect(
      () => snoozeDeadline(
        const ReminderClockSample(
          utcMilliseconds: 8640000000000000,
          elapsedMilliseconds: 0,
          bootId: 'b',
        ),
        1,
      ),
      throwsFormatException,
    );
    expect(
      () => snoozeDeadline(
        const ReminderClockSample(
          utcMilliseconds: 0,
          elapsedMilliseconds: 9223372036854775800,
          bootId: 'b',
        ),
        1,
      ),
      throwsFormatException,
    );
    expect(
      snoozeClockState(
        saved: sample,
        deadlineMilliseconds: 3600000,
        current: sample,
      ),
      ReminderRepairState.expired,
    );
  });
  test('17-case design oracle remains complete and distinct from executable behavior tests', () {
    final oracle = jsonDecode(
      File('test/fixtures/reminders/snooze-contract.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(
      (oracle['cases'] as List).map((dynamic c) => c['id']),
      List.generate(17, (i) => 'S${(i + 1).toString().padLeft(2, '0')}'),
    );
  });
  DesiredReminder candidate(
    int index, {
    String person = 'ada',
    String plan = 'p',
    ReminderKind kind = ReminderKind.ordinary,
    ReminderRepairState state = ReminderRepairState.pending,
  }) {
    final instant = DateTime.utc(2026, 10, 19, 9);
    final expectation = DailyExpectation(
      identity: DailyIdentity(
        personId: person,
        planId: plan,
        originalDate: CivilDate(2026, 10, 19),
        slotId: index.toString().padLeft(3, '0'),
      ),
      itemId: 'item',
      versionId: 'v',
      zoneId: 'Europe/London',
      amount: PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
      resolution: DailyResolution.exact,
      calculatorVersion: 'daily-1',
      timezoneDataVersion: 'test',
      originalTime: WallTime(10, 0),
      effectiveTime: WallTime(10, 0),
      instant: instant,
      clockCandidates: [instant],
    );
    final row = DailyRow(
      generation: 'g',
      personRevision: 1,
      planRevision: 1,
      expectation: expectation,
      personName: person,
      itemName: 'Synthetic',
      revision: 0,
      actions: const [],
      takenCount: 0,
      skippedCount: 0,
    );
    return DesiredReminder(
      requestToken: 'reverse-${999 - index}-$person-$plan',
      takenToken: 't$index',
      snoozeToken: 's$index',
      skipToken: 'k$index',
      generation: 'g',
      namespace: 'n',
      target: ReminderTarget(row: row, snoozeRevision: 0),
      kind: kind,
      trigger: kind == ReminderKind.snooze
          ? ReminderTrigger.elapsed
          : ReminderTrigger.wall,
      deadlineMilliseconds: kind == ReminderKind.snooze
          ? 4500000
          : instant.millisecondsSinceEpoch,
      intentRevision: 0,
      repairState: state,
      sample: kind == ReminderKind.snooze ? sample : null,
      delayMinutes: kind == ReminderKind.snooze ? 15 : null,
    );
  }

  test('S15 stable equal-instant round robin uses occurrence identity not random token', () {
    final values = [
      for (var i = 239; i >= 0; i--) candidate(i),
      candidate(0, person: 'bea'),
    ];
    final first = allocateReminders(values);
    expect(first.selected.length, 232);
    expect(first.excluded.length, 9);
    expect(
      first.selected
          .take(4)
          .map(
            (r) =>
                '${r.target.row.expectation.identity.personId}:${r.target.row.expectation.identity.slotId}',
          ),
      ['ada:000', 'bea:000', 'ada:001', 'ada:002'],
    );
    final withSnoozes = allocateReminders([
      ...values,
      for (var i = 0; i < 16; i++) candidate(i, kind: ReminderKind.snooze),
      for (var i = 0; i < 20; i++)
        candidate(
          i,
          plan: 'history',
          kind: ReminderKind.snooze,
          state: ReminderRepairState.consumed,
        ),
    ]);
    expect(withSnoozes.selected.length, 248);
    expect(
      withSnoozes.selected.where((r) => r.kind == ReminderKind.snooze).length,
      16,
    );
    expect(
      withSnoozes.selected.any(
        (r) => r.repairState == ReminderRepairState.consumed,
      ),
      false,
    );
  });
  test(
    'optional follow-ups cannot displace primary alerts or reserved snoozes',
    () {
      final allocation = allocateReminders([
        for (var i = 0; i < 240; i++) candidate(i, kind: ReminderKind.followUp),
        for (var i = 0; i < 232; i++) candidate(i),
        for (var i = 0; i < 16; i++) candidate(i, kind: ReminderKind.snooze),
      ]);
      expect(
        allocation.selected.where((r) => r.kind == ReminderKind.ordinary),
        hasLength(232),
      );
      expect(
        allocation.selected.where((r) => r.kind == ReminderKind.snooze),
        hasLength(16),
      );
      expect(
        allocation.selected.where((r) => r.kind == ReminderKind.followUp),
        isEmpty,
      );
      expect(allocation.excluded, hasLength(240));
    },
  );
}
