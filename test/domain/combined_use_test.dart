import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/combined_use.dart';
import 'package:true_grit_vital/domain/records.dart';
import 'package:true_grit_vital/domain/products/products.dart';
import 'package:true_grit_vital/domain/stock/stored_stock.dart';
import 'package:true_grit_vital/domain/scheduling/daily_plan.dart';
import 'package:true_grit_vital/domain/scheduling/stored_daily.dart';

CombinedUseComponent component({String item = 'item', String? site}) =>
    CombinedUseComponent(
      itemId: item,
      expectedItemRevision: 1,
      enteredAmount: '0.100000',
      siteLabel: site,
    );
CombinedUseCommand command(Iterable<CombinedUseComponent> components) =>
    CombinedUseCommand(
      commandId: 'command',
      expectedGeneration: 'generation',
      personId: 'me',
      expectedPersonRevision: 1,
      actualAt: DateTime.utc(2026, 10, 19),
      components: components,
    );
CombinedStockOutflow draw(
  ExactAmount? amount, {
  String person = 'me',
  String item = 'item',
  String container = 'vial',
  int revision = 1,
  String unit = 'ml',
}) => CombinedStockOutflow(
  containerId: container,
  personId: person,
  itemId: item,
  unit: unit,
  expectedRevision: revision,
  amount: amount,
);

void main() {
  test('freezes bounded independent sources and exact site snapshots', () {
    final inputs = [component(site: ' Left arm '), component(item: 'other')];
    final saved = command(inputs);
    inputs.clear();
    expect(saved.components.length, 2);
    expect(saved.components.first.siteLabel, ' Left arm ');
    expect(saved.components.first.enteredAmount, '0.100000');
    expect(() => saved.components.clear(), throwsUnsupportedError);
    expect(() => command([component()]), throwsFormatException);
    expect(
      () => command(List.generate(17, (_) => component())),
      throwsFormatException,
    );
    expect(
      command(List.generate(16, (_) => component())).components.length,
      16,
    );
  });
  test('rejects conflicting quantities, sources and container revisions', () {
    expect(
      () => CombinedUseComponent(
        itemId: 'item',
        expectedItemRevision: 1,
        enteredAmount: '1',
        stockUse: StockUseInput(
          expectedGeneration: 'generation',
          entered: EnteredStockAmount('2', 'ml'),
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => CombinedUseComponent(
        itemId: 'item',
        expectedItemRevision: 1,
        enteredAmount: '1',
        stockUse: StockUseInput(
          expectedGeneration: 'generation',
          entered: EnteredStockAmount('1', 'ml'),
          containerId: 'vial',
        ),
      ),
      throwsFormatException,
    );
    expect(() => component(site: ' '), throwsFormatException);
  });
  test('rejects old-generation and cross-person product snapshots', () {
    ProductUseInput input(String person, String generation) => ProductUseInput(
      expectedGeneration: generation,
      enteredVolume: EnteredStockAmount('1', 'ml'),
      label: ProductLabelSnapshot(
        personId: person,
        itemId: 'item',
        revision: 1,
        components: [
          ProductComponent(ingredientId: 'a', name: 'A'),
          ProductComponent(ingredientId: 'b', name: 'B'),
        ],
      ),
    );
    for (final pair in [('other', 'generation'), ('me', 'stale')]) {
      expect(
        () => command([
          CombinedUseComponent(
            itemId: 'item',
            expectedItemRevision: 1,
            enteredAmount: '1',
            productUse: input(pair.$1, pair.$2),
          ),
          component(),
        ]),
        throwsA(isA<CommandConflict>()),
      );
    }
  });
  test('blend retains independent concentrations and one physical outflow', () {
    final label = ProductLabelSnapshot(
      personId: 'me',
      itemId: 'blend',
      revision: 1,
      components: [
        ProductComponent(
          ingredientId: 'a',
          name: 'A',
          concentrationText: '100',
        ),
        ProductComponent(ingredientId: 'b', name: 'B', concentrationText: '25'),
        ProductComponent(ingredientId: 'c', name: 'C'),
      ],
    );
    final use = ProductUseInput(
      expectedGeneration: 'generation',
      label: label,
      enteredVolume: EnteredStockAmount('0.100000', 'ml'),
      containerId: 'blend-vial',
      expectedContainerRevision: 1,
    );
    final saved = command([
      CombinedUseComponent(
        itemId: 'blend',
        expectedItemRevision: 1,
        enteredAmount: '0.100000',
        productUse: use,
      ),
      component(item: 'separate'),
    ]);
    final actual = ProductAdministrationSnapshot(
      label: label,
      defaultLabel: label,
      volume: use.enteredVolume.value,
    );
    expect(actual.components.map((c) => c.amount).toList(), [
      ExactAmount(BigInt.from(10)),
      ExactAmount(BigInt.from(5), BigInt.two),
      null,
    ]);
    final outflows = combineStockOutflows([
      draw(
        actual.volume,
        item: saved.components.first.itemId,
        container: 'blend-vial',
      ),
      draw(
        ExactAmount(BigInt.one),
        item: 'separate',
        container: 'separate-vial',
      ),
    ]);
    expect(outflows.length, 2);
    expect(outflows.first.amount, ExactAmount(BigInt.one, BigInt.from(10)));
  });
  test('captured occurrence ownership and duplicate identity reject', () {
    DailyRow row({String person = 'me'}) => DailyRow(
      generation: 'generation',
      personRevision: 1,
      planRevision: 1,
      personName: 'Person',
      itemName: 'Item',
      revision: 1,
      actions: const [],
      takenCount: 0,
      skippedCount: 0,
      expectation: DailyExpectation(
        identity: DailyIdentity(
          personId: person,
          planId: 'plan',
          originalDate: CivilDate(2026, 10, 19),
        ),
        itemId: 'item',
        versionId: 'version',
        zoneId: 'Etc/UTC',
        amount: PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
        resolution: DailyResolution.untimed,
        plannedCount: 1,
        calculatorVersion: 'test',
        timezoneDataVersion: 'test',
      ),
    );
    CombinedUseComponent linked(DailyRow row) => CombinedUseComponent(
      itemId: 'item',
      expectedItemRevision: 1,
      enteredAmount: '1',
      intendedRow: row,
    );
    expect(
      () => command([linked(row(person: 'other')), component()]),
      throwsA(isA<CommandConflict>()),
    );
    expect(
      () => command([linked(row()), linked(row())]),
      throwsFormatException,
    );
    expect(
      command([linked(row()), component(item: 'other')]).components.length,
      2,
    );
  });
  test('same container folds repeating fractions exactly once per source', () {
    final third = ExactAmount(BigInt.one, BigInt.from(3));
    final total = combineStockOutflows([draw(third), draw(third), draw(third)]);
    expect(total.single.amount, ExactAmount(BigInt.one));
    expect(() => total.clear(), throwsUnsupportedError);
  });
  test('unknown conversion remains unknown in either source order', () {
    final one = ExactAmount(BigInt.one);
    expect(combineStockOutflows([draw(one), draw(null)]).single.amount, isNull);
    expect(combineStockOutflows([draw(null), draw(one)]).single.amount, isNull);
    final separate = combineStockOutflows([
      draw(one),
      draw(null, container: 'other'),
    ]);
    expect(separate.first.amount, one);
    expect(separate.last.amount, isNull);
  });
  test('same physical container cannot hide conflicting frozen snapshots', () {
    final one = ExactAmount(BigInt.one);
    for (final bad in [
      draw(one, person: 'other'),
      draw(one, item: 'other'),
      draw(one, unit: 'mg'),
      draw(one, revision: 2),
    ]) {
      expect(
        () => combineStockOutflows([draw(one), bad]),
        throwsA(isA<CommandConflict>()),
      );
    }
    expect(() => combineStockOutflows([draw(-one)]), throwsFormatException);
    expect(
      () => combineStockOutflows(List.generate(17, (_) => draw(one))),
      throwsFormatException,
    );
  });
  test(
    'correction freezes all member guards and explicit physical policies',
    () {
      final components = [
        CombinedCorrectionComponent(
          recordId: 'a',
          expectedRevision: 1,
          physicalCorrection: PhysicalCorrection.retainPhysicalEffect,
        ),
        CombinedCorrectionComponent(
          recordId: 'b',
          expectedRevision: 2,
          physicalCorrection: PhysicalCorrection.reverseRecordedEffect,
        ),
      ];
      CombinedCorrectionCommand correction({
        bool voided = false,
        DateTime? actualAt,
      }) => CombinedCorrectionCommand(
        commandId: 'correction',
        actionId: 'group',
        personId: 'me',
        expectedPersonRevision: 1,
        expectedGeneration: 'generation',
        components: components,
        voided: voided,
        actualAt: actualAt,
      );
      final saved = correction();
      components.clear();
      expect(saved.components.length, 2);
      expect(
        saved.components.first.physicalCorrection,
        PhysicalCorrection.retainPhysicalEffect,
      );
      expect(() => saved.components.clear(), throwsUnsupportedError);
      expect(() => correction(), throwsFormatException);
    },
  );
  test('Undo cannot include an amount/time change or duplicate member', () {
    final a = CombinedCorrectionComponent(
      recordId: 'a',
      expectedRevision: 1,
      physicalCorrection: null,
      enteredAmount: '1',
    );
    expect(
      () => CombinedCorrectionCommand(
        commandId: 'correction',
        actionId: 'g',
        personId: 'me',
        expectedPersonRevision: 1,
        expectedGeneration: 'generation',
        components: [a, a],
      ),
      throwsFormatException,
    );
    final b = CombinedCorrectionComponent(
      recordId: 'b',
      expectedRevision: 1,
      physicalCorrection: null,
    );
    expect(
      () => CombinedCorrectionCommand(
        commandId: 'correction',
        actionId: 'g',
        personId: 'me',
        expectedPersonRevision: 1,
        expectedGeneration: 'generation',
        components: [a, b],
        voided: true,
      ),
      throwsFormatException,
    );
  });
}
