import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/daily_codec.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/exports/exports.dart';
import 'package:true_grit_vital/features/plans/phase_editor.dart';
import 'package:true_grit_vital/features/plans/pause_editor.dart';

void main() {
  late Directory dir;
  late RecordStore store;
  late SubstanceItem item;
  late String path;
  final key = List.generate(32, (i) => i + 1);
  final date = CivilDate(2026, 10, 19);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vital-plan-requirements-');
    path = '${dir.path}/records.db';
    store = await RecordStore.open(path: path, key: key, isNew: true);
    item = await store.createItem(
      commandId: 'item',
      name: 'Synthetic tablet',
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
    String version = 'v1',
    String instructions = '',
    ScheduleRequirement? requirements,
    int startOffset = 0,
  }) => DailyPlanVersion(
    personId: meId,
    planId: 'plan',
    itemId: item.id,
    versionId: version,
    start: date.addDays(startOffset),
    timing: DailyCount(1, amount()),
    zoneBasis: const FollowingLocal(),
    calendar: const EveryDay(),
    instructions: instructions,
    requirements: requirements,
  );

  Future<SavedDailyPlan> save(
    DailyPlanVersion value, {
    String op = 'plan-save',
    int? revision,
  }) => store.saveDailyPlan(
    commandId: op,
    plan: value,
    expectedPersonRevision: 1,
    expectedGeneration: store.generation,
    expectedPlanRevision: revision,
  );

  test('legacy plan JSON without requirements keeps the frozen shape', () {
    final legacy = <String, Object?>{
      'person': meId,
      'plan': 'plan',
      'item': item.id,
      'version': 'v1',
      'start': '2026-10-19',
      'end': null,
      'home': null,
      'timing': {
        'kind': 'count',
        'count': 1,
        'amount': {'entered': '1.000', 'unit': 'mg'},
      },
    };
    final decoded = decodeDailyPlan(Map<String, dynamic>.from(legacy));
    expect(decoded.requirements, isNull);
    expect(jsonEncode(encodeDailyPlan(decoded)), jsonEncode(legacy));
  });

  test('food and bedtime labels round-trip as explicit choices only', () {
    const requirements = ScheduleRequirement(
      food: FoodRequirement.withFood,
      atBedtime: true,
    );
    final encoded = jsonDecode(
      jsonEncode(encodeDailyPlan(plan(requirements: requirements))),
    ) as Map<String, dynamic>;
    expect(encoded['requirements'], {'food': 'withFood', 'bedtime': true});
    expect(
      decodeDailyPlan(encoded).requirements,
      const ScheduleRequirement(
        food: FoodRequirement.withFood,
        atBedtime: true,
      ),
    );
  });

  test('absent, empty and partial objects stay unspecified or exact', () {
    expect(ScheduleRequirement.fromJson(null), isNull);
    expect(ScheduleRequirement.fromJson(<String, Object?>{}), isNull);
    expect(
      ScheduleRequirement.fromJson({'bedtime': false}),
      isNull,
      reason: 'An explicitly false bedtime is still no structured choice.',
    );
    expect(
      ScheduleRequirement.fromJson({'food': 'afterFood'}),
      const ScheduleRequirement(food: FoodRequirement.afterFood),
    );
    expect(
      ScheduleRequirement.fromJson({'bedtime': true}),
      const ScheduleRequirement(atBedtime: true),
    );
  });

  test('unknown or malformed requirement fields are rejected', () {
    expect(
      () => ScheduleRequirement.fromJson({'food': 'betweenMeals'}),
      throwsFormatException,
    );
    expect(
      () => ScheduleRequirement.fromJson({'food': 12}),
      throwsFormatException,
    );
    expect(
      () => ScheduleRequirement.fromJson({'bedtime': 'yes'}),
      throwsFormatException,
    );
    expect(
      () => ScheduleRequirement.fromJson('bedtime'),
      throwsFormatException,
    );
  });

  test('an empty structured requirement cannot enter a saved version', () {
    expect(
      () => plan(requirements: const ScheduleRequirement()),
      throwsArgumentError,
    );
  });

  test('labels are value-equal and keep the authored text independent', () {
    const one = ScheduleRequirement(
      food: FoodRequirement.emptyStomach,
      atBedtime: true,
    );
    expect(
      one.withBedtime(false),
      const ScheduleRequirement(food: FoodRequirement.emptyStomach),
    );
    expect(one.withFood(null), const ScheduleRequirement(atBedtime: true));
    expect(one.isNotEmpty, isTrue);
    expect(const ScheduleRequirement().isEmpty, isTrue);
  });

  test(
    'save, encrypted restart and backup restore retain the exact labels',
    () async {
      const requirements = ScheduleRequirement(
        food: FoodRequirement.beforeFood,
        atBedtime: true,
      );
      await save(plan(requirements: requirements));
      expect(
        (await store.dailyPlans(itemId: item.id)).single.plan.requirements,
        requirements,
      );

      await store.close();
      final cipherText = String.fromCharCodes(await File(path).readAsBytes());
      expect(cipherText, isNot(contains('beforeFood')));
      expect(cipherText, isNot(contains('bedtime')));
      store = await RecordStore.open(path: path, key: key, isNew: false);
      expect(
        (await store.dailyPlans(itemId: item.id)).single.plan.requirements,
        requirements,
      );

      final snapshot = await store.createBackupSnapshot(
        directory: dir,
        sessionId: 'plan-requirements',
      );
      await store.releaseBackupPins('plan-requirements');
      final restored = await RecordStore.open(
        path: snapshot.path,
        key: key,
        isNew: false,
      );
      try {
        expect(
          (await restored.dailyPlans(itemId: item.id)).single.plan.requirements,
          requirements,
        );
      } finally {
        await restored.close();
      }
    },
  );

  test(
    'an edit appends an immutable audit version and keeps the old labels',
    () async {
      await save(
        plan(
          requirements: const ScheduleRequirement(
            food: FoodRequirement.withFood,
            atBedtime: true,
          ),
        ),
        op: 'v1',
      );
      final first = (await store.dailyPlans(itemId: item.id)).single;
      await save(
        plan(
          version: 'v2',
          requirements: const ScheduleRequirement(
            food: FoodRequirement.afterFood,
          ),
        ),
        op: 'v2',
        revision: first.revision,
      );
      final current = (await store.dailyPlans(itemId: item.id)).single;
      expect(
        current.plan.requirements,
        const ScheduleRequirement(food: FoodRequirement.afterFood),
      );
      final audit = await store.dailyPlanAudit('plan', personId: meId);
      expect(audit.map((row) => row.plan.requirements), [
        const ScheduleRequirement(
          food: FoodRequirement.withFood,
          atBedtime: true,
        ),
        const ScheduleRequirement(food: FoodRequirement.afterFood),
      ]);
    },
  );

  test('pause and phase copies carry the structured labels', () {
    const requirements = ScheduleRequirement(
      food: FoodRequirement.beforeFood,
      atBedtime: true,
    );
    final original = plan(requirements: requirements);
    final paused = pauseCandidate(
      original,
      versionId: 'paused',
      instant: DateTime.utc(2026, 10, 20, 8),
      choice: 'pause',
      restartAnchor: '',
    );
    expect(paused.requirements, requirements);

    final entry = PhaseEntry()..load(original);
    try {
      expect(entry.candidate(original, 'mg').requirements, requirements);
    } finally {
      entry.dispose();
    }
  });

  Future<DailyAction> action() async {
    final rows = await store.dailyRows(
      from: date,
      toExclusive: date.addDays(1),
      observedZone: 'UTC',
    );
    return store.actDaily(
      commandId: 'act',
      row: rows.rows.single,
      kind: DailyActionKind.taken,
      actualAt: DateTime.utc(2026, 10, 19, 9),
    );
  }

  ReportSelection report({required bool notes}) => ReportSelection(
    personId: meId,
    fromDate: date,
    beforeDate: date.addDays(10),
    displayZone: 'UTC',
    includeNotes: notes,
  );

  ExportSelection export({required bool notes}) => ExportSelection(
    personId: meId,
    fromDay: date,
    beforeDay: date.addDays(10),
    zoneId: 'UTC',
    contents: const [ExportContent.doses],
    format: ExportFormat.json,
    includeNotes: notes,
  );

  test(
    'reports and exports carry exact labels only under notes consent',
    () async {
      const requirements = ScheduleRequirement(
        food: FoodRequirement.afterFood,
        atBedtime: true,
      );
      await save(plan(requirements: requirements));
      await action();

      final shared = await store.captureReport(
        selection: report(notes: true),
        now: () => DateTime.utc(2026, 10, 20),
      );
      final instruction = shared.snapshot.records.single.planInstruction!;
      expect(instruction.text, isEmpty);
      expect(instruction.requirements, requirements);
      expect(
        ReportText.planInstructionLines(shared.snapshot).join('\n'),
        allOf(contains('After food'), contains('At bedtime')),
      );

      final private = await store.captureReport(
        selection: report(notes: false),
        now: () => DateTime.utc(2026, 10, 20),
      );
      expect(private.snapshot.records.single.planInstruction, isNull);
      expect(
        private.snapshot.structuredText(use24Hour: true),
        isNot(contains('After food')),
      );

      final portable = await store.captureExport(export(notes: true));
      expect(portable.doses.single.planInstruction!.requirements, requirements);
      expect(
        jsonEncode(portable.toJson()),
        allOf(contains('"food":"afterFood"'), contains('"bedtime":true')),
      );
      final hidden = await store.captureExport(export(notes: false));
      expect(hidden.doses.single.planInstruction, isNull);
      expect(jsonEncode(hidden.toJson()), isNot(contains('afterFood')));
      expect(encodeExportCsv(hidden), isNot(contains('afterFood')));
    },
  );

  test('a later edit never rewrites the saved action labels', () async {
    await save(
      plan(
        requirements: const ScheduleRequirement(food: FoodRequirement.withFood),
      ),
    );
    await action();
    final current = (await store.dailyPlans(itemId: item.id)).single;
    await save(
      plan(
        version: 'v2',
        startOffset: 1,
        requirements: const ScheduleRequirement(
          food: FoodRequirement.emptyStomach,
          atBedtime: true,
        ),
      ),
      op: 'v2',
      revision: current.revision,
    );

    await store.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final history = await store.timeline(
      TimelineQuery(filter: TimelineFilter(), displayZone: 'UTC'),
    );
    expect(
      history.entries
          .whereType<RecordTimelineEntry>()
          .single
          .planContext!
          .requirements,
      const ScheduleRequirement(food: FoodRequirement.withFood),
    );

    final reported = await store.captureReport(
      selection: report(notes: true),
      now: () => DateTime.utc(2026, 10, 20),
    );
    final instruction = reported.snapshot.records.single.planInstruction!;
    expect(instruction.versionId, 'v1');
    expect(
      instruction.requirements,
      const ScheduleRequirement(food: FoodRequirement.withFood),
    );
    expect(
      reported.snapshot.structuredText(use24Hour: true),
      isNot(contains('Empty stomach')),
    );
  });
  test(
    'skipped history and source inspection use saved requirements',
    () async {
      const labels = ScheduleRequirement(
        food: FoodRequirement.beforeFood,
        atBedtime: true,
      );
      await save(plan(requirements: labels));
      final rows = await store.dailyRows(
        from: date,
        toExclusive: date.addDays(1),
        observedZone: 'UTC',
      );
      final skipped = await store.actDaily(
        commandId: 'skip',
        row: rows.rows.single,
        kind: DailyActionKind.skip,
      );
      final page = await store.timeline(
        TimelineQuery(filter: TimelineFilter(), displayZone: 'UTC'),
      );
      expect(
        page.entries
            .whereType<SkippedTimelineEntry>()
            .single
            .context
            .requirements,
        labels,
      );
      expect(
        (await store.dailyActionSource(
          skipped.id,
          personId: meId,
        ))!.context.requirements,
        labels,
      );
    },
  );
}
