import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  late Directory dir;
  late RecordStore store;
  late String path;
  late SubstanceItem item;
  final key = List.generate(32, (i) => i + 1);
  final at = DateTime.utc(2026, 10, 19, 8);
  ExactAmount n(int a, [int d = 1]) =>
      ExactAmount(BigInt.from(a), BigInt.from(d));
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vital-combined-');
    path = '${dir.path}/record.db';
    store = await RecordStore.open(path: path, key: key, isNew: true);
    item = await store.createItem(
      commandId: 'item',
      name: 'Separate source',
      form: 'liquid',
      unit: 'ml',
      type: 'medicine',
    );
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  Future<StoredStockContainer> container({
    String id = 'container',
    ExactAmount? opening,
  }) => store.createStockContainer(
    commandId: id,
    personId: meId,
    expectedPersonRevision: 1,
    expectedGeneration: store.generation,
    itemId: item.id,
    label: 'Selected vial',
    unit: 'ml',
    strength: LabelledStrength(ingredientId: item.id, label: 'Volume'),
    opening: opening ?? n(2),
  );
  CombinedUseComponent component({
    StoredStockContainer? source,
    String amount = '0.5',
    String? site,
    SubstanceItem? selected,
  }) => CombinedUseComponent(
    itemId: (selected ?? item).id,
    expectedItemRevision: (selected ?? item).revision,
    enteredAmount: amount,
    siteLabel: site,
    stockUse: source == null
        ? null
        : StockUseInput(
            expectedGeneration: store.generation,
            entered: EnteredStockAmount(amount, 'ml'),
            containerId: source.id,
            expectedContainerRevision: source.revision,
          ),
  );
  CombinedUseCommand command(
    List<CombinedUseComponent> parts, {
    String id = 'combined',
  }) => CombinedUseCommand(
    commandId: id,
    personId: meId,
    expectedPersonRevision: 1,
    expectedGeneration: store.generation,
    actualAt: at,
    components: parts,
  );
  CombinedCorrectionCommand correction(
    CombinedUseResult group, {
    String id = 'correct',
    bool voided = false,
    PhysicalCorrection choice = PhysicalCorrection.retainPhysicalEffect,
    String? amount = '0.25',
  }) => CombinedCorrectionCommand(
    commandId: id,
    actionId: group.actionId,
    personId: meId,
    expectedPersonRevision: 1,
    expectedGeneration: store.generation,
    voided: voided,
    components: [
      for (final r in group.records)
        CombinedCorrectionComponent(
          recordId: r.id,
          expectedRevision: r.revision,
          enteredAmount: voided ? null : amount,
          physicalCorrection: choice,
          siteLabel: r.siteLabel,
        ),
    ],
  );
  test('same-container cumulative exact outflow, identity, frozen retry and changed payload rejection', () async {
    final c = await container();
    final cmd = command([
      component(source: c, site: 'Left entered site'),
      component(source: c, amount: '0.75'),
    ]);
    final result = await store.recordCombined(cmd);
    expect(result.records, hasLength(2));
    expect(
      result.records.every((r) => r.combinedActionId == result.actionId),
      isTrue,
    );
    expect(result.records.first.siteLabel, 'Left entered site');
    expect(
      (await store.stockContainerById(
        personId: meId,
        containerId: c.id,
      ))!.balance.value,
      n(3, 4),
    );
    expect(
      await store.stockMovements(personId: meId, containerId: c.id),
      hasLength(3),
    );
    final replay = await store.recordCombined(
      decodeCombinedUse(
        jsonDecode(jsonEncode(encodeCombinedUse(cmd))) as Map<String, dynamic>,
      ),
    );
    expect(replay.alreadyCommitted, isTrue);
    expect(replay.records.map((r) => r.id), result.records.map((r) => r.id));
    await expectLater(
      store.recordCombined(
        command([component(source: c), component(source: c)]),
      ),
      throwsA(isA<CommandConflict>()),
    );
    expect(
      await store.combinedHistory(actionId: result.actionId, personId: meId),
      hasLength(1),
    );
  });
  test('failure in second component and explicit before-commit failure leave no partial record or stock', () async {
    final c = await container();
    final bad = CombinedUseComponent(
      itemId: item.id,
      expectedItemRevision: 1,
      enteredAmount: '0.5',
      stockUse: StockUseInput(
        expectedGeneration: store.generation,
        entered: EnteredStockAmount('0.5', 'ml'),
      ),
    );
    await expectLater(
      store.recordCombined(command([component(source: c), bad])),
      throwsA(anything),
    );
    expect(await store.records(), isEmpty);
    expect(
      (await store.stockContainerById(
        personId: meId,
        containerId: c.id,
      ))!.balance.value,
      n(2),
    );
    final cmd = command([component(source: c), component(source: c)]);
    await expectLater(
      store.recordCombined(cmd, failBeforeCommit: true),
      throwsA(anything),
    );
    expect(await store.records(), isEmpty);
    expect((await store.recordCombined(cmd)).records, hasLength(2));
  });
  test('blend plus separate source retains full independent vector and consumes blend once', () async {
    final blend = await store.createItem(
      commandId: 'blend',
      name: 'Original blend',
      form: 'liquid',
      unit: 'ml',
      type: 'medicine',
      productComponents: [
        ProductComponent(
          ingredientId: 'a',
          name: 'Known A',
          concentrationText: '3',
        ),
        ProductComponent(ingredientId: 'b', name: 'Unknown B'),
      ],
    );
    final label = (await store.productLabel(personId: meId, itemId: blend.id))!;
    final c = await store.createStockContainer(
      commandId: 'blend-source',
      personId: meId,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      itemId: blend.id,
      label: 'Blend vial',
      unit: 'ml',
      strength: LabelledStrength(ingredientId: blend.id, label: 'Volume'),
      productLabel: label,
      opening: n(2),
    );
    final input = CombinedUseComponent(
      itemId: blend.id,
      expectedItemRevision: blend.revision,
      enteredAmount: '0.5',
      productUse: ProductUseInput(
        expectedGeneration: store.generation,
        label: label,
        enteredVolume: EnteredStockAmount('0.5', 'ml'),
        containerId: c.id,
        expectedContainerRevision: c.revision,
        sourceLabel: label,
      ),
    );
    final r = await store.recordCombined(command([input, component()]));
    expect(r.records.first.product!.components, hasLength(2));
    expect(
      (await store.stockContainerById(
        personId: meId,
        containerId: c.id,
      ))!.balance.value,
      n(3, 2),
    );
    expect(
      await store.stockMovements(personId: meId, containerId: c.id),
      hasLength(2),
    );
  });
  test('wrong adult and stale item/source abort the whole group', () async {
    final other = await store.createProfile(
      commandId: 'other',
      name: 'Other',
      adultConfirmed: true,
    );
    final foreign = await store.createItem(
      commandId: 'foreign',
      personId: other.id,
      expectedPersonRevision: 1,
      name: 'Other item',
      form: 'liquid',
      unit: 'ml',
      type: 'medicine',
    );
    await expectLater(
      store.recordCombined(
        command([component(), component(selected: foreign)]),
      ),
      throwsA(isA<CommandConflict>()),
    );
    expect(await store.records(), isEmpty);
    final c = await container();
    await store.addStockMovement(
      commandId: 'add',
      personId: meId,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      containerId: c.id,
      expectedContainerRevision: c.revision,
      kind: StockMovementKind.restock,
      amount: EnteredStockAmount('1', 'ml'),
    );
    await expectLater(
      store.recordCombined(command([component(), component(source: c)])),
      throwsA(isA<CommandConflict>()),
    );
    expect(await store.records(), isEmpty);
  });
  test('correction and Undo are complete-group atomic, keep revisions, explicit physical returns', () async {
    final c = await container();
    final r = await store.recordCombined(
      command([
        component(source: c, site: 'Original site'),
        component(source: c),
      ]),
    );
    await expectLater(
      store.correct(
        commandId: 'partial',
        recordId: r.records.first.id,
        expectedRevision: 1,
        amount: '0.1',
        actualAt: at,
        stockCorrection: PhysicalCorrection.retainPhysicalEffect,
      ),
      throwsA(isA<CommandConflict>()),
    );
    final bad = CombinedCorrectionCommand(
      commandId: 'bad',
      actionId: r.actionId,
      personId: meId,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      components: [
        for (var i = 0; i < 2; i++)
          CombinedCorrectionComponent(
            recordId: r.records[i].id,
            expectedRevision: i == 0 ? 1 : 9,
            enteredAmount: '0.25',
            physicalCorrection: PhysicalCorrection.reverseRecordedEffect,
          ),
      ],
    );
    await expectLater(
      store.correctCombined(bad),
      throwsA(isA<CommandConflict>()),
    );
    expect(
      (await store.recordById(r.records.first.id, personId: meId))!.revision,
      1,
    );
    expect(
      (await store.stockContainerById(
        personId: meId,
        containerId: c.id,
      ))!.balance.value,
      n(1),
    );
    final cmd = correction(r, choice: PhysicalCorrection.reverseRecordedEffect);
    final corrected = await store.correctCombined(
      decodeCombinedCorrection(
        jsonDecode(jsonEncode(encodeCombinedCorrection(cmd)))
            as Map<String, dynamic>,
      ),
    );
    expect(corrected.records.every((r) => r.revision == 2), isTrue);
    expect(
      (await store.stockContainerById(
        personId: meId,
        containerId: c.id,
      ))!.balance.value,
      n(2),
    );
    expect(await store.history(r.records.first.id), hasLength(2));
    final undo = await store.correctCombined(
      correction(corrected, id: 'undo', voided: true),
    );
    expect(undo.records.every((r) => r.isVoided), isTrue);
    expect(
      await store.combinedHistory(actionId: r.actionId, personId: meId),
      hasLength(3),
    );
    expect((await store.correctCombined(cmd)).alreadyCommitted, isTrue);
  });
  test(
    'site edits retain person history without dose revision or stock movement',
    () async {
      final c = await container();
      final r = await store.record(
        commandId: 'single',
        itemId: item.id,
        amount: '0.5',
        actualAt: at,
        siteLabel: 'Entered site',
        stockUse: StockUseInput(
          expectedGeneration: store.generation,
          entered: EnteredStockAmount('0.5', 'ml'),
          containerId: c.id,
          expectedContainerRevision: c.revision,
        ),
      );
      await store.updateSite(
        commandId: 'site',
        personId: meId,
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
        recordId: r.id,
        expectedRevision: 1,
        siteLabel: 'Changed site',
      );
      expect(
        (await store.recordById(r.id, personId: meId))!.siteLabel,
        'Changed site',
      );
      expect(await store.history(r.id), hasLength(1));
      expect(
        await store.stockMovements(personId: meId, containerId: c.id),
        hasLength(2),
      );
      expect(
        await store.siteHistory(personId: meId),
        containsAll(['Entered site', 'Changed site']),
      );
    },
  );
  test(
    'independent connections serialize same operation and reject stale sources',
    () async {
      final c = await container();
      final second = await RecordStore.open(path: path, key: key, isNew: false);
      try {
        final cmd = command([component(source: c), component(source: c)]);
        final results = await Future.wait([
          store.recordCombined(cmd),
          second.recordCombined(cmd),
        ]);
        expect(results.where((r) => r.alreadyCommitted), hasLength(1));
        expect(await store.records(), hasLength(2));
        await expectLater(
          second.recordCombined(
            command([component(source: c), component(source: c)], id: 'stale'),
          ),
          throwsA(isA<CommandConflict>()),
        );
      } finally {
        await second.close();
      }
    },
  );
  test(
    'profile deletion erases group/site graph and invalidates replay',
    () async {
      final r = await store.recordCombined(
        command([component(site: 'Private site'), component()]),
      );
      await store.deleteProfile(
        commandId: 'delete',
        personId: meId,
        expectedRevision: 1,
      );
      expect(
        await store.combinedById(actionId: r.actionId, personId: meId),
        isNull,
      );
      expect(await store.siteHistory(personId: meId), isEmpty);
      await expectLater(
        store.recordCombined(
          command([component(site: 'Private site'), component()]),
        ),
        throwsA(isA<CommandConflict>()),
      );
    },
  );
  test('captured occurrence commits independently and direct occurrence Undo cannot split group', () async {
    final date = CivilDate(2026, 10, 19);
    final plan = DailyPlanVersion(
      personId: meId,
      planId: 'daily',
      itemId: item.id,
      versionId: 'v1',
      start: date,
      zoneBasis: const FollowingLocal(),
      timing: DailyCount(
        1,
        PlannedAmount(
          quantity: ExactQuantity.parse('0.5'),
          enteredText: '0.5',
          unit: 'ml',
        ),
      ),
    );
    await store.saveDailyPlan(
      commandId: 'plan',
      plan: plan,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
    );
    final row = (await store.dailyRows(
      from: date,
      toExclusive: date.addDays(1),
      observedZone: 'Europe/London',
    )).rows.single;
    final cmd = command([
      CombinedUseComponent(
        itemId: item.id,
        expectedItemRevision: item.revision,
        enteredAmount: '0.5',
        intendedRow: row,
      ),
      component(),
    ]);
    final decoded = decodeCombinedUse(
      jsonDecode(jsonEncode(encodeCombinedUse(cmd))) as Map<String, dynamic>,
    );
    final r = await store.recordCombined(decoded);
    expect(r.records, hasLength(2));
    final fresh = (await store.dailyRows(
      from: date,
      toExclusive: date.addDays(1),
      observedZone: 'Europe/London',
    )).rows.single;
    expect(fresh.takenCount, 1);
    await expectLater(
      store.undoDaily(
        commandId: 'partial-daily-undo',
        row: fresh,
        action: fresh.actions.single,
      ),
      throwsA(isA<CommandConflict>()),
    );
    await store.correctCombined(
      CombinedCorrectionCommand(
        commandId: 'undo-all',
        actionId: r.actionId,
        personId: meId,
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
        voided: true,
        components: [
          for (final a in r.records)
            CombinedCorrectionComponent(
              recordId: a.id,
              expectedRevision: a.revision,
              physicalCorrection: null,
            ),
        ],
      ),
    );
    expect(
      (await store.dailyRows(
        from: date,
        toExclusive: date.addDays(1),
        observedZone: 'Europe/London',
      )).rows.single.takenCount,
      0,
    );
  });
  test('qualifying interval is per linked component; correction requires complete future review', () async {
    final date = CivilDate(2026, 10, 19), now = DateTime.utc(2026, 10, 19, 10);
    final sample = ReminderClockSample(
      bootId: 'boot',
      utcMilliseconds: now.millisecondsSinceEpoch,
      elapsedMilliseconds: 1000,
    );
    final plan = DailyPlanVersion(
      personId: meId,
      planId: 'interval',
      itemId: item.id,
      versionId: 'iv1',
      start: date,
      zoneBasis: FixedHome('Europe/London'),
      timing: ElapsedInterval(
        segmentId: 'segment',
        duration: ExactElapsed.parseHours('6'),
        mode: IntervalMode.qualifyingActual,
        amount: PlannedAmount(
          quantity: ExactQuantity.parse('0.5'),
          enteredText: '0.5',
          unit: 'ml',
        ),
        reminderEnabled: true,
      ),
    );
    final saved = await store.saveDailyPlan(
      commandId: 'interval',
      plan: plan,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      intervalClockSample: sample,
    );
    final seed = await store.record(
      commandId: 'seed',
      itemId: item.id,
      amount: '0.5',
      actualAt: DateTime.utc(2026, 10, 19),
    );
    final initial = await store.previewIntervalChange(
      plan: saved,
      recordId: seed.id,
      expectedRecordRevision: 1,
      qualifies: true,
      now: now,
      observedZone: 'Europe/London',
      intervalClockSample: sample,
    );
    await store.qualifyInterval(commandId: 'seed-qualify', review: initial);
    final row = (await store.dailyRows(
      from: date,
      toExclusive: date.addDays(1),
      observedZone: 'Europe/London',
    )).rows.single;
    await expectLater(
      store.recordCombined(
        CombinedUseCommand(
          commandId: 'same-instant',
          personId: meId,
          expectedPersonRevision: 1,
          expectedGeneration: store.generation,
          actualAt: seed.actualAt,
          components: [
            CombinedUseComponent(
              itemId: item.id,
              expectedItemRevision: 1,
              enteredAmount: '0.5',
              intendedRow: row,
              intervalClockSample: sample,
            ),
            component(),
          ],
        ),
      ),
      throwsA(isA<CommandConflict>()),
    );
    expect(await store.records(), hasLength(1));
    expect(
      (await store.intervalSources(
        planId: 'interval',
        personId: meId,
      )).where((s) => s.qualifies),
      hasLength(1),
    );
    final group = await store.recordCombined(
      command([
        CombinedUseComponent(
          itemId: item.id,
          expectedItemRevision: 1,
          enteredAmount: '0.5',
          intendedRow: row,
          intervalClockSample: sample,
        ),
        component(),
      ]),
    );
    final sources = await store.intervalSources(
      planId: 'interval',
      personId: meId,
    );
    expect(sources.where((x) => x.qualifies), hasLength(2));
    expect(sources.any((x) => x.actualId == group.records.last.id), isFalse);
    await expectLater(
      store.correctCombined(
        CombinedCorrectionCommand(
          commandId: 'no-review',
          actionId: group.actionId,
          personId: meId,
          expectedPersonRevision: 1,
          expectedGeneration: store.generation,
          actualAt: DateTime.utc(2026, 10, 19, 9),
          components: [
            for (final a in group.records)
              CombinedCorrectionComponent(
                recordId: a.id,
                expectedRevision: 1,
                physicalCorrection: null,
              ),
          ],
        ),
      ),
      throwsA(isA<CommandConflict>()),
    );
    final review = await store.previewIntervalChange(
      plan: saved,
      recordId: group.records.first.id,
      expectedRecordRevision: 1,
      actualAt: DateTime.utc(2026, 10, 19, 9),
      now: now,
      observedZone: 'Europe/London',
      intervalClockSample: sample,
    );
    final corrected = await store.correctCombined(
      CombinedCorrectionCommand(
        commandId: 'with-review',
        actionId: group.actionId,
        personId: meId,
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
        actualAt: DateTime.utc(2026, 10, 19, 9),
        components: [
          for (final a in group.records)
            CombinedCorrectionComponent(
              recordId: a.id,
              expectedRevision: 1,
              physicalCorrection: null,
              intervalReviews: a.id == group.records.first.id ? [review] : [],
            ),
        ],
      ),
    );
    expect(
      corrected.records.every(
        (x) => x.actualAt == DateTime.utc(2026, 10, 19, 9),
      ),
      isTrue,
    );
  });
  test('different source strengths and unknown conversion retain exact independent physical effects', () async {
    Future<StoredStockContainer> source(String id, String? concentration) =>
        store.createStockContainer(
          commandId: id,
          personId: meId,
          expectedPersonRevision: 1,
          expectedGeneration: store.generation,
          itemId: item.id,
          label: id,
          unit: 'ml',
          strength: LabelledStrength(
            ingredientId: item.id,
            label: 'Entered strength',
            mgPerMl: concentration == null
                ? null
                : ExactAmount.parseEntry(concentration),
          ),
          opening: n(2),
        );
    final a = await source('a', '3'),
        b = await source('b', '6'),
        unknown = await source('unknown', null);
    CombinedUseComponent use(StoredStockContainer c) => CombinedUseComponent(
      itemId: item.id,
      expectedItemRevision: 1,
      enteredAmount: '3',
      stockUse: StockUseInput(
        expectedGeneration: store.generation,
        entered: EnteredStockAmount('3', 'mg'),
        containerId: c.id,
        expectedContainerRevision: c.revision,
      ),
    );
    final group = await store.recordCombined(
      command([use(a), use(b), use(unknown)]),
    );
    expect(
      group.records.every(
        (r) => r.exactActualAmount == n(3) && r.exactActualUnit == 'mg',
      ),
      isTrue,
    );
    expect(
      (await store.stockContainerById(
        personId: meId,
        containerId: a.id,
      ))!.balance.value,
      n(1),
    );
    expect(
      (await store.stockContainerById(
        personId: meId,
        containerId: b.id,
      ))!.balance.value,
      n(3, 2),
    );
    expect(
      (await store.stockContainerById(
        personId: meId,
        containerId: unknown.id,
      ))!.balance.value,
      isNull,
    );
  });
  test('repeated blend draws and unlinked group correction retain independent stock semantics', () async {
    final blend = await store.createItem(
      commandId: 'blend2',
      name: 'Blend',
      form: 'liquid',
      unit: 'ml',
      type: 'medicine',
      productComponents: [
        ProductComponent(ingredientId: 'a', name: 'A', concentrationText: '3'),
        ProductComponent(ingredientId: 'b', name: 'B'),
      ],
    );
    final label = (await store.productLabel(personId: meId, itemId: blend.id))!;
    final source = await store.createStockContainer(
      commandId: 'blend2-source',
      personId: meId,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      itemId: blend.id,
      label: 'Physical blend',
      unit: 'ml',
      strength: LabelledStrength(ingredientId: blend.id, label: 'Volume'),
      productLabel: label,
      opening: n(2),
    );
    CombinedUseComponent part() => CombinedUseComponent(
      itemId: blend.id,
      expectedItemRevision: 1,
      enteredAmount: '0.5',
      productUse: ProductUseInput(
        expectedGeneration: store.generation,
        label: label,
        enteredVolume: EnteredStockAmount('0.5', 'ml'),
        containerId: source.id,
        expectedContainerRevision: source.revision,
        sourceLabel: label,
      ),
    );
    final group = await store.recordCombined(
      command([part(), part(), component()]),
    );
    expect(
      (await store.stockContainerById(
        personId: meId,
        containerId: source.id,
      ))!.balance.value,
      n(1),
    );
    CombinedCorrectionCommand change(
      String id,
      CombinedUseResult current, {
      bool voided = false,
    }) => CombinedCorrectionCommand(
      commandId: id,
      actionId: current.actionId,
      personId: meId,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      voided: voided,
      components: [
        for (var i = 0; i < current.records.length; i++)
          CombinedCorrectionComponent(
            recordId: current.records[i].id,
            expectedRevision: current.records[i].revision,
            enteredAmount: voided ? null : '0.25',
            physicalCorrection: i == 2
                ? null
                : voided
                ? PhysicalCorrection.retainPhysicalEffect
                : PhysicalCorrection.reverseRecordedEffect,
          ),
      ],
    );
    await expectLater(
      store.correctCombined(
        change('fail-mixed', group),
        failBeforeCommit: true,
      ),
      throwsA(anything),
    );
    expect(
      (await store.combinedById(
        actionId: group.actionId,
        personId: meId,
      ))!.records.every((r) => r.revision == 1),
      isTrue,
    );
    expect(
      (await store.stockContainerById(
        personId: meId,
        containerId: source.id,
      ))!.balance.value,
      n(1),
    );
    final corrected = await store.correctCombined(
      change('mixed-correct', group),
    );
    expect(
      (await store.stockContainerById(
        personId: meId,
        containerId: source.id,
      ))!.balance.value,
      n(2),
    );
    expect(
      (await store.correctCombined(
        change('mixed-undo', corrected, voided: true),
      )).records.every((r) => r.isVoided),
      isTrue,
    );
  });
  test('independent connection contention accepts one fresh source group and rejects the other', () async {
    final source = await container();
    final second = await RecordStore.open(path: path, key: key, isNew: false);
    try {
      Future<Object> settle(Future<CombinedUseResult> f) async {
        try {
          return await f;
        } catch (e) {
          return e;
        }
      }

      final results = await Future.wait([
        settle(
          store.recordCombined(
            command([
              component(source: source),
              component(source: source),
            ], id: 'race-a'),
          ),
        ),
        settle(
          second.recordCombined(
            command([
              component(source: source),
              component(source: source),
            ], id: 'race-b'),
          ),
        ),
      ]);
      expect(results.whereType<CombinedUseResult>(), hasLength(1));
      expect(results.whereType<CommandConflict>(), hasLength(1));
      expect(await store.records(), hasLength(2));
    } finally {
      await second.close();
    }
  });
  test('late migration collisions roll back all new group schema and preserve v13 records', () async {
    for (final table in ['site_event', 'ordinary_draft_v13']) {
      final p = '${dir.path}/collision-$table.db';
      var db = sqlite3.open(p);
      db.execute("PRAGMA cipher='chacha20'");
      final keySql =
          'PRAGMA key="x\'${key.map((x) => x.toRadixString(16).padLeft(2, '0')).join()}\'"';
      db.execute(keySql);
      db.execute(
        File('test/data/fixtures/record_store_v13.sql').readAsStringSync(),
      );
      db.execute('CREATE TABLE $table(recovery TEXT)');
      final count = db
          .select('SELECT COUNT(*) FROM administration')
          .single
          .values
          .single;
      db.close();
      await expectLater(
        RecordStore.open(path: p, key: key, isNew: false),
        throwsA(anything),
      );
      db = sqlite3.open(p);
      db.execute("PRAGMA cipher='chacha20'");
      db.execute(keySql);
      expect(db.select('PRAGMA user_version').single.values.single, 13);
      expect(
        db.select(
          "SELECT name FROM sqlite_master WHERE name='combined_action'",
        ),
        isEmpty,
      );
      expect(
        db.select('SELECT COUNT(*) FROM administration').single.values.single,
        count,
      );
      expect(db.select('SELECT * FROM ordinary_draft'), isNotEmpty);
      expect(db.select('PRAGMA foreign_key_check'), isEmpty);
      db.close();
    }
  });
  test('populated v13 migration and migration collision rollback preserve all prior records/drafts', () async {
    Future<void> seed(String p, {bool collide = false}) async {
      final db = sqlite3.open(p);
      db.execute("PRAGMA cipher='chacha20'");
      db.execute(
        'PRAGMA key="x\'${key.map((x) => x.toRadixString(16).padLeft(2, '0')).join()}\'"',
      );
      db.execute(
        File('test/data/fixtures/record_store_v13.sql').readAsStringSync(),
      );
      if (collide) db.execute('CREATE TABLE combined_action(recovery TEXT)');
      db.close();
    }

    final p = '${dir.path}/v13.db';
    await seed(p);
    final migrated = await RecordStore.open(path: p, key: key, isNew: false);
    expect(
      await migrated.records(scope: const FeedScope.everyone()),
      isNotEmpty,
    );
    expect(await migrated.drafts(), isNotEmpty);
    await migrated.close();
    final fail = '${dir.path}/fail.db';
    await seed(fail, collide: true);
    await expectLater(
      RecordStore.open(path: fail, key: key, isNew: false),
      throwsA(anything),
    );
    final db = sqlite3.open(fail);
    db.execute("PRAGMA cipher='chacha20'");
    db.execute(
      'PRAGMA key="x\'${key.map((x) => x.toRadixString(16).padLeft(2, '0')).join()}\'"',
    );
    expect(db.select('PRAGMA user_version').single.values.single, 13);
    expect(db.select('SELECT * FROM ordinary_draft'), isNotEmpty);
    expect(db.select('PRAGMA foreign_key_check'), isEmpty);
    db.close();
  });
}
