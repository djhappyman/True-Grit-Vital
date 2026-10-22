import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/exports/exports.dart';

void main() {
  late Directory directory;
  late RecordStore store;
  late SubstanceItem item;
  final day = CivilDate(2026, 10, 5);
  const original = '=Original breakfast note.\r\nKeep these words.  ';

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-plan-output-');
    store = await RecordStore.open(
      path: '${directory.path}/records.db',
      key: List.generate(32, (index) => index + 1),
      isNew: true,
    );
    item = await store.createItem(
      commandId: 'item',
      name: 'Synthetic tablet',
      form: 'tablet',
      unit: 'count',
      type: 'Medicine',
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  Future<void> plan({
    String version = 'v1',
    String text = original,
    int? revision,
  }) async {
    await store.saveDailyPlan(
      commandId: 'save-$version',
      plan: DailyPlanVersion(
        personId: meId,
        planId: 'plan',
        itemId: item.id,
        versionId: version,
        start: version == 'v1' ? day : day.addDays(1),
        timing: DailyCount(
          1,
          PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'count'),
        ),
        zoneBasis: FixedHome('UTC'),
        calendar: const EveryDay(),
        instructions: text,
      ),
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      expectedPlanRevision: revision,
    );
  }

  Future<DailyAction> action({bool skip = false, CivilDate? date}) async {
    final at = date ?? day;
    final rows = await store.dailyRows(
      from: at,
      toExclusive: at.addDays(1),
      observedZone: 'UTC',
    );
    return store.actDaily(
      commandId: 'act-$at',
      row: rows.rows.single,
      kind: skip ? DailyActionKind.skip : DailyActionKind.taken,
      actualAt: skip ? null : DateTime.utc(at.year, at.month, at.day, 9),
    );
  }

  ReportSelection report({
    bool notes = true,
    Iterable<String> items = const [],
  }) => ReportSelection(
    personId: meId,
    fromDate: day,
    beforeDate: day.addDays(10),
    displayZone: 'UTC',
    includeNotes: notes,
    itemIds: items,
  );

  ExportSelection export({
    bool notes = true,
    ExportLimits limits = ExportLimits.standard,
  }) => ExportSelection(
    personId: meId,
    fromDay: day,
    beforeDay: day.addDays(10),
    zoneId: 'UTC',
    contents: const [ExportContent.doses],
    format: ExportFormat.json,
    includeNotes: notes,
    limits: limits,
  );

  test(
    'reports and exports retain the frozen version after plan edits',
    () async {
      await plan();
      final taken = await action();
      final before = await store.captureReport(
        selection: report(),
        now: () => DateTime.utc(2026, 10, 20),
      );
      final revision = (await store.dailyPlans(itemId: item.id))
          .single
          .revision;
      await plan(
        version: 'v2',
        text: 'New dinner instructions.',
        revision: revision,
      );
      final after = await store.captureReport(
        selection: report(),
        now: () => DateTime.utc(2026, 10, 20),
      );
      for (final snapshot in [before.snapshot, after.snapshot]) {
        final instruction = snapshot.records.single.planInstruction!;
        expect(instruction.text, original);
        expect(instruction.planId, 'plan');
        expect(instruction.versionId, 'v1');
        expect(snapshot.structuredText(use24Hour: true), contains(original));
        expect(
          ReportText.planInstructionLines(snapshot).join('\n'),
          contains(taken.recordId),
        );
        expect(
          snapshot.structuredText(use24Hour: true),
          isNot(contains('New dinner')),
        );
      }
      final portable = await store.captureExport(export());
      expect(portable.doses.single.planInstruction!.text, original);
      expect(portable.doses.single.planInstruction!.versionId, 'v1');
    },
  );

  test(
    'notes excluded removes text and version links in every output',
    () async {
      await plan();
      await action();
      final captured = await store.captureReport(
        selection: report(notes: false),
        now: () => DateTime.utc(2026, 10, 20),
      );
      expect(captured.snapshot.records.single.planInstruction, isNull);
      expect(
        captured.snapshot.structuredText(use24Hour: true),
        isNot(contains('Original breakfast')),
      );
      final portable = await store.captureExport(export(notes: false));
      expect(portable.doses.single.planInstruction, isNull);
      expect(
        jsonEncode(portable.toJson()),
        isNot(contains('Original breakfast')),
      );
      expect(encodeExportCsv(portable), isNot(contains('Original breakfast')));
    },
  );

  test(
    'standalone dose never inherits instructions from its item plan',
    () async {
      await plan();
      await store.record(
        commandId: 'standalone',
        itemId: item.id,
        amount: '1',
        actualAt: DateTime.utc(2026, 10, 5, 8),
      );
      final captured = await store.captureReport(
        selection: report(),
        now: () => DateTime.utc(2026, 10, 20),
      );
      expect(captured.snapshot.records.single.planInstruction, isNull);
      expect(
        (await store.captureExport(export())).doses.single.planInstruction,
        isNull,
      );
    },
  );

  test(
    'correcting the dose time preserves its original action version',
    () async {
      await plan();
      final taken = await action();
      await store.correct(
        commandId: 'correct',
        recordId: taken.recordId!,
        expectedRevision: 1,
        amount: '2',
        actualAt: DateTime.utc(2026, 10, 7, 22),
      );
      await plan(version: 'v2', text: 'Different current text.', revision: 1);
      final portable = await store.captureExport(export());
      expect(portable.doses, hasLength(2));
      for (final row in portable.doses) {
        expect(row.planInstruction!.text, original);
        expect(row.planInstruction!.versionId, 'v1');
      }
      final captured = await store.captureReport(
        selection: report(),
        now: () => DateTime.utc(2026, 10, 20),
      );
      expect(captured.snapshot.records.single.planInstruction!.versionId, 'v1');
    },
  );

  test(
    'skip exports resolve their action, preserve consent and quote CSV',
    () async {
      await plan();
      final skipped = await action(skip: true);
      final portable = await store.captureExport(export());
      expect(portable.skipped.single.actionId, skipped.id);
      expect(portable.skipped.single.planInstruction!.text, original);
      expect(portable.toJson()['schemaVersion'], 3);
      final csv = encodeExportCsv(portable);
      expect(csv, contains('plan_id,plan_version_id,plan_instructions'));
      expect(csv, contains("'=Original breakfast note."));
      final hidden = await store.captureExport(export(notes: false));
      expect(hidden.skipped.single.planInstruction, isNull);
      expect(encodeExportCsv(hidden), isNot(contains('Original breakfast')));
    },
  );

  test(
    'blank historical text is not replaced with later nonblank text',
    () async {
      await plan(text: '');
      await action();
      await plan(version: 'v2', text: 'Only applies later.', revision: 1);
      expect(
        (await store.captureExport(export())).doses.single.planInstruction,
        isNull,
      );
    },
  );

  test('new instruction bytes count towards existing export bounds', () async {
    await plan(text: List.filled(3000, 'x').join());
    await action();
    await expectLater(
      store.captureExport(export(limits: const ExportLimits(maxBytes: 6000))),
      throwsA(isA<ExportLimitException>()),
    );
  });

  test('a locked store cannot capture private output', () async {
    await plan();
    await action();
    store.suspendWrites(true);
    await expectLater(
      store.captureExport(export()),
      throwsA(isA<CommandConflict>()),
    );
    await expectLater(
      store.captureReport(
        selection: report(),
        now: () => DateTime.utc(2026, 10, 20),
      ),
      throwsA(isA<CommandConflict>()),
    );
  });
}
