import 'package:sqlite3/sqlite3.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  late Directory dir;
  late RecordStore store;
  final key = List.generate(32, (i) => i + 1);
  ExactAmount n(String v) => ExactAmount.parseEntry(v);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vital-properties-');
    store = await RecordStore.open(
      path: '${dir.path}/records.db',
      key: key,
      isNew: true,
    );
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  Future<SubstanceItem> item([SubstanceProfile? profile]) => store.createItem(
    commandId: 'item',
    name: 'Synthetic substance',
    form: 'Powder',
    unit: 'ml',
    type: 'Medicine',
    profile: profile,
  );
  Future<StoredStockContainer> vial(
    SubstanceItem i,
    String id,
    String volume,
  ) => store.createStockContainer(
    commandId: id,
    personId: meId,
    expectedPersonRevision: 1,
    expectedGeneration: store.generation,
    itemId: i.id,
    label: id,
    unit: 'ml',
    strength: LabelledStrength(
      ingredientId: i.id,
      label: id,
      mgPerMl: VialPreparation(
        powderAmount: '1',
        massUnit: 'mg',
        finalVolumeMl: volume,
      ).mgPerMl,
      preparation: VialPreparation(
        powderAmount: '1',
        massUnit: 'mg',
        finalVolumeMl: volume,
      ),
    ),
    opening: n(volume),
  );
  test(
    'profile is atomic with creation and survives guarded edits and reopen',
    () async {
      final profile = SubstanceProfile(
        route: SubstanceRoute.injectable,
        form: SubstanceForm.powderToMix,
        halfLife: HalfLife(
          value: '12',
          unit: 'hours',
          context: 'Specific formulation',
        ),
      );
      final i = await item(profile);
      final detail = (await store.itemDetail(i.id))!;
      expect(detail.profile!.toJson(), profile.toJson());
      final replay = await item(profile);
      expect(replay.id, i.id);
      expect(replay.alreadyCommitted, true);
      await store.saveItemDetail(
        commandId: 'details',
        itemId: i.id,
        instructions: 'Original instruction',
        notes: '',
        expectedRevision: 1,
        profile: SubstanceProfile(
          route: SubstanceRoute.injectable,
          form: SubstanceForm.water,
        ),
      );
      await expectLater(
        store.saveItemDetail(
          commandId: 'stale',
          itemId: i.id,
          instructions: 'Lost text',
          notes: '',
          expectedRevision: 1,
          profile: profile,
        ),
        throwsA(isA<CommandConflict>()),
      );
      await store.close();
      store = await RecordStore.open(
        path: '${dir.path}/records.db',
        key: key,
        isNew: false,
      );
      expect(
        (await store.itemDetail(i.id))!.profile!.form,
        SubstanceForm.water,
      );
      expect(
        (await store.itemDetail(i.id))!.instructions,
        'Original instruction',
      );
    },
  );
  test('different vials freeze rational strengths and each dose keeps its preparation', () async {
    final i = await item();
    final a = await vial(i, 'A', '3');
    final b = await vial(i, 'B', '6');
    final dose = await store.record(
      commandId: 'dose',
      itemId: i.id,
      amount: '0.25',
      actualAt: DateTime.utc(2026, 10, 22),
      stockUse: StockUseInput(
        expectedGeneration: store.generation,
        containerId: a.id,
        expectedContainerRevision: a.revision,
        entered: EnteredStockAmount('0.25', 'ml'),
      ),
    );
    expect(
      dose.labelledStrength!.mgPerMl,
      ExactAmount(BigInt.one, BigInt.from(3)),
    );
    expect(dose.labelledStrength!.preparation!.finalVolumeMl, '3');
    expect(b.strength.mgPerMl, ExactAmount(BigInt.one, BigInt.from(6)));
    expect(
      (await store.stockContainerById(
        personId: meId,
        containerId: a.id,
      ))!.balance.value,
      n('2.75'),
    );
    await store.saveItemDetail(
      commandId: 'later-profile',
      itemId: i.id,
      instructions: '',
      notes: '',
      expectedRevision: null,
      profile: SubstanceProfile(
        route: SubstanceRoute.injectable,
        form: SubstanceForm.oil,
        strengthText: '400',
      ),
    );
    await store.close();
    store = await RecordStore.open(
      path: '${dir.path}/records.db',
      key: key,
      isNew: false,
    );
    final saved = (await store.records()).single;
    expect(saved.labelledStrength!.preparation!.finalVolumeMl, '3');
    expect(
      saved.labelledStrength!.equivalent(
        saved.actualAmount,
        from: 'ml',
        to: 'mg',
      ),
      ExactAmount(BigInt.one, BigInt.from(12)),
    );
  });
  test(
    'tablet strength deducts exact count from mass without inventing volume',
    () async {
      final i = await item();
      final c = await store.createStockContainer(
        commandId: 'tablets',
        personId: meId,
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
        itemId: i.id,
        label: 'Tablets',
        unit: 'count',
        strength: LabelledStrength(
          ingredientId: i.id,
          label: '250 micrograms each',
          mgPerCount: n('0.25'),
        ),
        opening: n('20'),
      );
      final r = await store.record(
        commandId: 'tablet-use',
        itemId: i.id,
        amount: '0.5',
        actualAt: DateTime.utc(2026, 10, 22),
        stockUse: StockUseInput(
          expectedGeneration: store.generation,
          containerId: c.id,
          expectedContainerRevision: c.revision,
          entered: EnteredStockAmount('0.5', 'mg'),
        ),
      );
      expect(r.originalUnit, 'mg');
      expect(r.labelledStrength!.mgPerCount, n('0.25'));
      expect(
        (await store.stockContainerById(
          personId: meId,
          containerId: c.id,
        ))!.balance.value,
        n('18'),
      );
    },
  );
  test(
    'schema 24 upgrade retains legacy details, drafts and unknown strength',
    () async {
      final i = await item();
      await store.saveItemDetail(
        commandId: 'legacy-detail',
        itemId: i.id,
        instructions: 'Original wording',
        notes: '',
        expectedRevision: null,
      );
      final c = await store.createStockContainer(
        commandId: 'legacy-source',
        personId: meId,
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
        itemId: i.id,
        label: 'Legacy source',
        unit: 'ml',
        strength: LabelledStrength(ingredientId: i.id, label: 'Unknown'),
      );
      final draft = OrdinaryDraft(
        id: 'legacy-draft',
        operationId: 'legacy-operation',
        generation: store.generation,
        kind: DraftKind.itemDetails,
        personId: meId,
        personRevision: 1,
        targetId: i.id,
        targetRevision: 1,
        fields: const {'instructions': 'Unfinished wording', 'notes': ''},
      );
      await store.saveDraft(draft);
      await store.close();
      final db = sqlite3.open('${dir.path}/records.db');
      db.execute("PRAGMA cipher='chacha20'");
      final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
      db.execute("PRAGMA key=\"x'$hex'\"");
      db.execute('ALTER TABLE item_detail DROP COLUMN profile');
      db.execute('PRAGMA user_version=24');
      db.close();
      store = await RecordStore.open(
        path: '${dir.path}/records.db',
        key: key,
        isNew: false,
      );
      final detail = (await store.itemDetail(i.id))!;
      expect(detail.instructions, 'Original wording');
      expect(detail.profile, isNull);
      expect((await store.draftById(draft.id))!.fields, draft.fields);
      final old = (await store.stockContainerById(
        personId: meId,
        containerId: c.id,
      ))!;
      expect(old.strength.mgPerMl, isNull);
      expect(old.strength.preparation, isNull);
      expect(old.strength.mgPerCount, isNull);
    },
  );
  test('a default strength is frozen through later profile edits and dose corrections', () async {
    final profile = SubstanceProfile(
      route: SubstanceRoute.oral,
      form: SubstanceForm.tablet,
      strengthText: '250',
      massUnit: 'mcg',
    );
    final i = await item(profile);
    final dose = await store.record(
      commandId: 'default-dose',
      itemId: i.id,
      amount: '2',
      actualAt: DateTime.utc(2026, 10, 22),
      stockUse: StockUseInput(
        expectedGeneration: store.generation,
        entered: EnteredStockAmount('2', 'count'),
        strength: profile.labelledStrength(i.id, i.name),
      ),
    );
    await store.saveItemDetail(
      commandId: 'new-default',
      itemId: i.id,
      instructions: '',
      notes: '',
      expectedRevision: 1,
      profile: SubstanceProfile(
        route: SubstanceRoute.oral,
        form: SubstanceForm.tablet,
        strengthText: '500',
        massUnit: 'mcg',
      ),
    );
    final corrected = await store.correct(
      commandId: 'correct-default-dose',
      recordId: dose.id,
      expectedRevision: dose.revision,
      amount: '3',
      actualAt: dose.actualAt,
    );
    expect(corrected.labelledStrength!.mgPerCount, n('0.25'));
    expect(
      corrected.labelledStrength!.equivalent(
        corrected.actualAmount,
        from: 'count',
        to: 'mg',
      ),
      n('0.75'),
    );
    expect((await store.itemDetail(i.id))!.profile!.strengthMg, n('0.5'));
    expect(
      await store.stockUseForRecord(personId: meId, recordId: dose.id),
      isNull,
    );
  });
}
