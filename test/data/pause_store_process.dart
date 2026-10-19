import 'dart:convert';
import 'dart:io';

import 'package:true_grit_vital/data/daily_codec.dart';
import 'package:true_grit_vital/data/record_store.dart';

Future<void> main(List<String> args) async {
  final mode = args[1], file = File('${args[0]}/input.json');
  final store = await RecordStore.open(
    path: '${args[0]}/pause.db',
    key: List.generate(32, (i) => i + 1),
    isNew: mode == 'init',
  );
  final now = DateTime.utc(2026, 10, 19, 7);
  if (mode == 'init') {
    final item = await store.createItem(
      commandId: 'item',
      name: 'Synthetic pause crash',
      form: 'tablet',
      unit: 'mg',
      type: 'medicine',
    );
    final p = DailyPlanVersion(
      personId: meId,
      planId: 'plan',
      itemId: item.id,
      versionId: 'v1',
      start: CivilDate(2026, 10, 19),
      timing: DailyCount(
        1,
        PlannedAmount(
          quantity: ExactQuantity.parse('1'),
          enteredText: '1',
          unit: 'mg',
        ),
      ),
      zoneBasis: FixedHome('Europe/London'),
    );
    await store.saveDailyPlan(
      commandId: 'plan',
      plan: p,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
    );
    file.writeAsStringSync(
      jsonEncode({'plan': encodeDailyPlan(p), 'generation': store.generation}),
    );
  } else {
    final input = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final p = decodeDailyPlan(input['plan'] as Map<String, dynamic>);
    final proposed = DailyPlanVersion(
      personId: p.personId,
      planId: p.planId,
      itemId: p.itemId,
      versionId: 'v2',
      start: p.start,
      timing: p.timing,
      zoneBasis: p.zoneBasis,
      pauses: [PlanPause(start: now)],
    );
    final review = PauseChangeReview(
      plan: SavedDailyPlan(plan: p, revision: 1),
      proposed: proposed,
      personRevision: 1,
      generation: input['generation'] as String,
      sourceGuard: '[]',
      now: now,
      observedZone: 'Europe/London',
    );
    if (mode == 'before' || mode == 'after' || mode == 'verify-retry') {
      final result = await store.savePauseChange(
        commandId: 'pause',
        review: review,
        beforeCommit: mode == 'before'
            ? () async {
                exit(71);
              }
            : null,
      );
      if (mode == 'after') exit(72);
      if (mode == 'verify-retry' &&
          (!result.alreadyCommitted ||
              (await store.pauseHistory(
                    planId: 'plan',
                    personId: meId,
                  )).length !=
                  1 ||
              (await store.dailyPlans()).single.revision != 2 ||
              (await store.records()).isNotEmpty)) {
        throw StateError('pause_retry_not_atomic');
      }
    } else if (mode == 'verify-empty') {
      if ((await store.pauseHistory(
            planId: 'plan',
            personId: meId,
          )).isNotEmpty ||
          (await store.dailyPlans()).single.revision != 1) {
        throw StateError('partial_pause');
      }
    } else {
      throw ArgumentError('mode');
    }
  }
  await store.close();
  stdout.writeln('PASS pause $mode');
}
