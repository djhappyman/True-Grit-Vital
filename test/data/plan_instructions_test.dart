import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/daily_codec.dart';
import 'package:true_grit_vital/data/record_store.dart';
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
    dir = await Directory.systemTemp.createTemp('vital-plan-instructions-');
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
    String planId = 'plan',
    DailyTiming? timing,
  }) => DailyPlanVersion(
    personId: meId,
    planId: planId,
    itemId: item.id,
    versionId: version,
    start: date,
    timing: timing ?? DailyCount(1, amount()),
    zoneBasis: const FollowingLocal(),
    calendar: const EveryDay(),
    instructions: instructions,
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

  test(
    'legacy plan JSON without instructions stays the frozen default shape',
    () {
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
      expect(decoded.instructions, isEmpty);

      final encoded = encodeDailyPlan(decoded);
      expect(encoded.containsKey('instructions'), isFalse);
      expect(jsonEncode(encoded), jsonEncode(legacy));
      expect(
        jsonEncode(encodeDailyPlan(plan())),
        jsonEncode(encoded),
        reason: 'A blank saved plan keeps the same additive JSON shape.',
      );
    },
  );

  test('multiline instructions survive encode and decode exactly', () {
    const text = 'Take with food.\r\nAt bedtime.  \n\nKeep spacing.';
    final encoded = jsonDecode(
      jsonEncode(encodeDailyPlan(plan(instructions: text))),
    ) as Map<String, dynamic>;
    expect(encoded['instructions'], text);
    expect(decodeDailyPlan(encoded).instructions, text);
  });

  test(
    'save, encrypted restart and backup snapshot retain exact text',
    () async {
      const text = 'With breakfast.\nAt bedtime.';
      await save(plan(instructions: text));
      expect(
        (await store.dailyPlans(itemId: item.id)).single.plan.instructions,
        text,
      );

      await store.close();
      final cipherText = String.fromCharCodes(await File(path).readAsBytes());
      expect(cipherText, isNot(contains('breakfast')));
      expect(cipherText, isNot(contains('bedtime')));
      store = await RecordStore.open(path: path, key: key, isNew: false);
      expect(
        (await store.dailyPlans(itemId: item.id)).single.plan.instructions,
        text,
      );

      final snapshot = await store.createBackupSnapshot(
        directory: dir,
        sessionId: 'plan-instructions',
      );
      await store.releaseBackupPins('plan-instructions');
      final restored = await RecordStore.open(
        path: snapshot.path,
        key: key,
        isNew: false,
      );
      try {
        expect(
          (await restored.dailyPlans(itemId: item.id)).single.plan.instructions,
          text,
        );
      } finally {
        await restored.close();
      }
    },
  );

  test(
    'resolved expectations never carry the private text into outputs',
    () async {
      await save(plan(instructions: 'Private bedtime note.'));
      final rows = await store.dailyRows(
        from: date,
        toExclusive: date.addDays(1),
        observedZone: 'Europe/London',
      );
      final encoded = jsonEncode(
        encodeDailyExpectation(rows.rows.single.expectation),
      );
      expect(encoded, isNot(contains('Private bedtime note.')));
      expect(encoded, isNot(contains('instructions')));
    },
  );

  test('retry is idempotent and preserves the saved instructions', () async {
    const text = 'With water.\nAt bedtime.';
    final value = plan(instructions: text);
    final first = await save(value, op: 'same-command');
    final second = await save(value, op: 'same-command');
    expect(first.alreadyCommitted, isFalse);
    expect(second.alreadyCommitted, isTrue);
    expect(second.plan.instructions, text);
    final saved = (await store.dailyPlans(itemId: item.id)).single;
    expect(saved.plan.instructions, text);
    expect((await store.dailyPlanAudit('plan', personId: meId)), hasLength(1));
  });

  test('a stale revision cannot overwrite a newer version', () async {
    await save(plan(instructions: 'Keep this.'), op: 'v1');
    final current = (await store.dailyPlans(itemId: item.id)).single;
    await expectLater(
      save(
        plan(version: 'v2', instructions: 'Stale text.'),
        op: 'v2',
        revision: current.revision - 1,
      ),
      throwsA(isA<CommandConflict>()),
    );
    expect(
      (await store.dailyPlans(itemId: item.id)).single.plan.instructions,
      'Keep this.',
    );
  });

  test(
    'an edit appends an immutable audit version and keeps the old text',
    () async {
      await save(plan(instructions: 'First wording.\nLine two.'), op: 'v1');
      final first = (await store.dailyPlans(itemId: item.id)).single;
      await save(
        plan(version: 'v2', instructions: 'Second wording.'),
        op: 'v2',
        revision: first.revision,
      );
      final current = (await store.dailyPlans(itemId: item.id)).single;
      expect(current.plan.instructions, 'Second wording.');
      final audit = await store.dailyPlanAudit('plan', personId: meId);
      expect(audit.map((row) => row.plan.instructions), [
        'First wording.\nLine two.',
        'Second wording.',
      ]);
    },
  );

  test('pause and phase copies carry the authored instructions', () {
    const text = 'Take with food.\nAt bedtime.';
    final original = plan(instructions: text);
    final paused = pauseCandidate(
      original,
      versionId: 'paused',
      instant: DateTime.utc(2026, 10, 20, 8),
      choice: 'pause',
      restartAnchor: '',
    );
    expect(paused.instructions, text);

    final entry = PhaseEntry()..load(original);
    try {
      expect(entry.candidate(original, 'mg').instructions, text);
    } finally {
      entry.dispose();
    }
  });

  test('the instruction bound is explicit and exact', () {
    expect(
      () => plan(instructions: 'x' * DailyPlanVersion.maxInstructionsLength),
      returnsNormally,
    );
    expect(
      () => plan(
        instructions: 'x' * (DailyPlanVersion.maxInstructionsLength + 1),
      ),
      throwsArgumentError,
    );
  });
}
