// Synthetic encrypted crash fixture. The runner owns every temporary file.
import 'dart:convert';
import 'dart:io';

import 'package:true_grit_vital/data/daily_codec.dart';
import 'package:true_grit_vital/data/record_store.dart';

Future<void> main(List<String> args) async {
  final mode = args[1];
  final inputFile = File('${args[0]}/input.json');
  final store = await RecordStore.open(
    path: '${args[0]}/interval.db',
    key: List.generate(32, (i) => i + 1),
    isNew: mode == 'init',
  );
  final date = CivilDate(2026, 10, 19);
  if (mode == 'init') {
    final item = await store.createItem(
      commandId: 'item',
      name: 'Synthetic interval crash',
      form: 'tablet',
      unit: 'mg',
      type: 'medicine',
    );
    final p = DailyPlanVersion(
      personId: meId,
      planId: 'plan',
      itemId: item.id,
      versionId: 'v1',
      start: date,
      timing: ElapsedInterval(
        segmentId: 'segment',
        duration: ExactElapsed.parseHours('6'),
        mode: IntervalMode.qualifyingActual,
        amount: PlannedAmount(
          quantity: ExactQuantity.parse('1.000'),
          enteredText: '1.000',
          unit: 'mg',
        ),
      ),
      zoneBasis: FixedHome('Europe/London'),
    );
    final saved = await store.saveDailyPlan(
      commandId: 'plan',
      plan: p,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
    );
    final anchor = await store.record(
      commandId: 'anchor',
      itemId: item.id,
      amount: '1',
      actualAt: DateTime.utc(2026, 10, 19, 4),
    );
    final review = await store.previewIntervalChange(
      plan: saved,
      recordId: anchor.id,
      expectedRecordRevision: 1,
      qualifies: true,
      now: DateTime.utc(2026, 10, 19, 10),
      observedZone: 'Europe/London',
    );
    await store.qualifyInterval(commandId: 'qualify', review: review);
    final row = (await store.dailyRows(
      from: date,
      toExclusive: date.addDays(1),
      observedZone: 'Europe/London',
    )).rows.single;
    inputFile.writeAsStringSync(
      jsonEncode({
        'generation': row.generation,
        'expectation': encodeDailyExpectation(row.expectation),
        'person': row.personRevision,
        'plan': row.planRevision,
        'revision': row.revision,
        'reminder': row.reminderRevision,
        'name': row.itemName,
      }),
    );
  } else {
    final input =
        jsonDecode(inputFile.readAsStringSync()) as Map<String, dynamic>;
    final row = DailyRow(
      generation: input['generation'] as String,
      personRevision: input['person'] as int,
      planRevision: input['plan'] as int,
      expectation: decodeDailyExpectation(
        input['expectation'] as Map<String, dynamic>,
      ),
      personName: 'Me',
      itemName: input['name'] as String,
      revision: input['revision'] as int,
      reminderRevision: input['reminder'] as int,
      actions: const [],
      takenCount: 0,
      skippedCount: 0,
    );
    if (mode == 'before' || mode == 'after' || mode == 'verify-retry') {
      final action = await store.actDaily(
        commandId: 'take',
        row: row,
        kind: DailyActionKind.taken,
        actualAt: DateTime.utc(2026, 10, 19, 9),
        beforeCommit: mode == 'before'
            ? () async {
                exit(71);
              }
            : null,
      );
      if (mode == 'after') exit(72);
      if (mode == 'verify-retry' &&
          (!action.alreadyCommitted ||
              (await store.records()).length != 2 ||
              (await store.intervalSources(
                    planId: 'plan',
                    personId: meId,
                  )).length !=
                  2 ||
              (await store.capturedDailyRows()).rows.single.takenCount != 1)) {
        throw StateError('interval_retry_not_atomic');
      }
    } else if (mode == 'verify-empty') {
      if ((await store.records()).length != 1 ||
          (await store.intervalSources(
                planId: 'plan',
                personId: meId,
              )).length !=
              1 ||
          (await store.capturedDailyRows()).rows.isNotEmpty) {
        throw StateError('partial_interval');
      }
    } else {
      throw ArgumentError('mode');
    }
  }
  await store.close();
  stdout.writeln('PASS interval $mode');
}
