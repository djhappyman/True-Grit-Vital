import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';

ReportCutoff cutoff(DateTime at) => ReportCutoff(
  generatedAt: at,
  datasetGeneration: 'generation',
  personRevision: 2,
  schemaVersion: 21,
);

UseRecord use({
  required String id,
  required String itemId,
  required String name,
  required String type,
  required String unit,
  String form = 'Tablet',
  String amount = '1',
  DateTime? at,
  ProductAdministrationSnapshot? product,
}) => UseRecord(
  id: id,
  personId: 'me',
  itemId: itemId,
  name: name,
  form: form,
  unit: unit,
  type: type,
  enteredAmount: amount,
  actualAt: at ?? DateTime.utc(2026, 10, 1, 9),
  enteredAt: at ?? DateTime.utc(2026, 10, 1, 9, 5),
  revision: 1,
  isVoided: false,
  product: product,
);

ProductAdministrationSnapshot productSnapshot({
  required String name,
  String? concentration,
  String volumeUnit = 'ml',
  String volume = '2',
}) {
  final label = ProductLabelSnapshot(
    personId: 'me',
    itemId: 'product',
    revision: 1,
    components: [
      ProductComponent(
        ingredientId: 'a',
        name: name,
        concentrationText: concentration,
        massUnit: 'mg',
        volumeUnit: volumeUnit,
      ),
      ProductComponent(
        ingredientId: 'b',
        name: 'Second ingredient',
        concentrationText: concentration,
        massUnit: 'mg',
        volumeUnit: volumeUnit,
      ),
    ],
  );
  return ProductAdministrationSnapshot(
    label: label,
    defaultLabel: label,
    volume: ExactAmount.parseEntry(volume),
  );
}

ReportSelection selection({
  Set<String> items = const {},
  bool notes = false,
  bool sources = false,
  bool context = false,
}) => ReportSelection(
  personId: 'me',
  fromDate: CivilDate(2026, 10, 1),
  beforeDate: CivilDate(2026, 11, 1),
  displayZone: 'UTC',
  itemIds: items,
  includeNotes: notes,
  includeAttachments: sources,
  includeSupporting: context,
);

void main() {
  test('private notes and source files default off and identity is exact', () {
    final base = selection();
    expect(base.includeNotes, false);
    expect(base.includeAttachments, false);
    expect(base.includeSupporting, false);
    expect(base.identity, isNot(selection(notes: true).identity));
    expect(base.identity, isNot(selection(sources: true).identity));
    expect(base.identity, isNot(selection(items: {'a'}).identity));
    expect(
      () => ReportSelection(
        personId: 'me',
        fromDate: CivilDate(2026, 10, 2),
        beforeDate: CivilDate(2026, 10, 2),
        displayZone: 'UTC',
      ),
      throwsA(isA<ReportSelectionFailure>()),
    );
  });

  test('totals stay exact and never combine unlike units or types', () {
    final snapshot = ReportSnapshot.build(
      selection: selection(),
      cutoff: cutoff(DateTime.utc(2026, 10, 20)),
      person: const ReportPerson(id: 'me', name: 'Synthetic Person'),
      records: [
        ReportRecord.fromUseRecord(
          use(
            id: '1',
            itemId: 'tablet',
            name: 'Tablet item',
            type: 'Medicine',
            unit: 'mg',
            amount: '0.1',
          ),
        ),
        ReportRecord.fromUseRecord(
          use(
            id: '2',
            itemId: 'tablet',
            name: 'Tablet item',
            type: 'Medicine',
            unit: 'mg',
            amount: '0.2',
          ),
        ),
        ReportRecord.fromUseRecord(
          use(
            id: '3',
            itemId: 'liquid',
            name: 'Liquid item',
            type: 'Medicine',
            unit: 'ml',
            amount: '1.5',
          ),
        ),
        ReportRecord.fromUseRecord(
          use(
            id: '4',
            itemId: 'supplement',
            name: 'Supplement item',
            type: 'Supplement',
            unit: 'count',
            amount: '2',
          ),
        ),
      ],
    );
    expect(snapshot.totals.recordCount, 4);
    expect(snapshot.totals.typeCount, 2);
    expect(snapshot.totals.itemCount, 3);
    final medicine = snapshot.totals.groups.singleWhere(
      (group) => group.type == 'Medicine',
    );
    expect(medicine.items.map((item) => item.unit), ['ml', 'mg']);
    expect(
      medicine.items.singleWhere((item) => item.unit == 'mg').total,
      ExactAmount.parseEntry('0.3'),
    );
    expect(
      medicine.items.singleWhere((item) => item.unit == 'ml').total,
      ExactAmount.parseEntry('1.5'),
    );
    expect(
      snapshot.totals.groups
          .singleWhere((group) => group.type == 'Supplement')
          .items
          .single
          .total,
      ExactAmount.parseEntry('2'),
    );
  });

  test('ready-mixed volume and ingredient amounts stay separate', () {
    final snapshot = ReportSnapshot.build(
      selection: selection(),
      cutoff: cutoff(DateTime.utc(2026, 10, 20)),
      person: const ReportPerson(id: 'me', name: 'Synthetic Person'),
      records: [
        ReportRecord.fromUseRecord(
          use(
            id: '1',
            itemId: 'product',
            name: 'Ready mix',
            type: 'Medicine',
            unit: 'ml',
            amount: '2',
            product: productSnapshot(
              name: 'Ingredient one',
              concentration: '5',
            ),
          ),
        ),
        ReportRecord.fromUseRecord(
          use(
            id: '2',
            itemId: 'product',
            name: 'Ready mix',
            type: 'Medicine',
            unit: 'ml',
            amount: '3',
            at: DateTime.utc(2026, 10, 2, 9),
            product: productSnapshot(
              name: 'Ingredient one',
              concentration: '5',
              volume: '3',
            ),
          ),
        ),
      ],
    );
    final product = snapshot.totals.groups.single.products.single;
    expect(product.volume, ExactAmount.parseEntry('5'));
    expect(product.administrations, 2);
    expect(product.ingredients.first.unit, 'mg');
    expect(product.ingredients.first.complete, true);
    expect(
      product.ingredients.first.knownSubtotal,
      ExactAmount.parseEntry('25'),
    );
    expect(
      product.ingredients.every(
        (ingredient) =>
            ingredient.knownSubtotal == ExactAmount.parseEntry('25'),
      ),
      true,
    );
  });

  test('unknown ingredient concentration is never guessed', () {
    final snapshot = ReportSnapshot.build(
      selection: selection(),
      cutoff: cutoff(DateTime.utc(2026, 10, 20)),
      person: const ReportPerson(id: 'me', name: 'Synthetic Person'),
      records: [
        ReportRecord.fromUseRecord(
          use(
            id: '1',
            itemId: 'product',
            name: 'Ready mix',
            type: 'Medicine',
            unit: 'ml',
            amount: '2',
            product: productSnapshot(name: 'Ingredient one'),
          ),
        ),
      ],
    );
    final ingredient =
        snapshot.totals.groups.single.products.single.ingredients.first;
    expect(ingredient.complete, false);
    expect(ingredient.knownSubtotal, isNull);
  });

  test('structured text keeps identity, definitions and limitations', () {
    final snapshot = ReportSnapshot.build(
      selection: selection(notes: true, context: false),
      cutoff: cutoff(DateTime.utc(2026, 10, 20, 12)),
      person: const ReportPerson(
        id: 'me',
        name: 'Synthetic Person',
        reportName: 'Example report name',
      ),
      records: [
        ReportRecord.fromUseRecord(
          use(
            id: '1',
            itemId: 'tablet',
            name: 'A long item name ${'x' * 120}',
            type: 'Medicine',
            unit: 'mg',
            amount: '0.125',
          ),
        ),
      ],
    );
    final text = snapshot.structuredText(use24Hour: true);
    expect(text, contains('Substance summary'));
    expect(text, contains('Person: Synthetic Person'));
    expect(text, contains('Report name: Example report name'));
    expect(text, contains('Recorded doses: 1'));
    expect(text, contains('Type: Medicine'));
    expect(text, contains('0.125 mg'));
    expect(text, contains('does not confirm that a dose was taken'));
    expect(text, contains('Private notes: included where recorded'));
    expect(text, contains('Source files: not included'));
    expect(text, isNot(contains('Other adult')));
  });

  test('amount display is exact where possible and marks rounding', () {
    expect(formatAmount(ExactAmount.parseEntry('0.125')), '0.125');
    expect(formatAmount(ExactAmount.parseEntry('1000')), '1000');
    expect(formatAmount(ExactAmount(BigInt.one, BigInt.from(3))), '~0.333333');
  });
}
