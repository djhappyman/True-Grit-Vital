import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/charts/charts.dart';
import 'package:true_grit_vital/domain/products/products.dart';
import 'package:true_grit_vital/domain/stock/exact_amount.dart';

import 'chart_test_data.dart';

ExactAmount fraction(int numerator, int denominator) =>
    ExactAmount(BigInt.from(numerator), BigInt.from(denominator));

ChartObservation exactObservation({
  String record = 'record-1',
  required ExactAmount amount,
  required DateTime at,
  String unit = 'mg',
  String item = 'item-1',
  String itemName = 'Test item',
}) => ChartObservation(
  source: ChartSourceRef(recordId: record, revision: 1),
  personId: 'me',
  itemId: item,
  itemName: itemName,
  amount: amount,
  unit: unit,
  occurredAt: at,
);

ChartObservation productObservation({
  String record = 'record-1',
  String item = 'item-1',
  String itemName = 'Test product',
  required String volume,
  required Iterable<ProductComponent> components,
  DateTime? at,
}) => chartObservation(
  record: record,
  item: item,
  itemName: itemName,
  amount: volume,
  unit: 'ml',
  at: at,
  product: productSnapshot(volume: volume, components: components, item: item),
);

void main() {
  final day19 = DateTime.utc(2026, 10, 19);
  final day22 = DateTime.utc(2026, 10, 22);
  final at19 = DateTime.utc(2026, 10, 19, 8);
  final at20 = DateTime.utc(2026, 10, 20, 8);

  group('exact folding', () {
    test('fractions fold exactly in buckets and in the whole total', () {
      final model = chartModel(
        batch: chartBatch(
          observations: [
            exactObservation(
              record: 'record-1',
              amount: fraction(1, 3),
              at: at19,
            ),
            exactObservation(
              record: 'record-2',
              amount: fraction(1, 6),
              at: at19.add(const Duration(hours: 1)),
            ),
            exactObservation(
              record: 'record-3',
              amount: fraction(1, 7),
              at: at20,
            ),
          ],
        ),
      );

      final series = model.series.single;
      expect(series.buckets.length, 2);
      expect(series.buckets.first.amount, fraction(1, 2));
      expect(series.buckets.first.contributionCount, 2);
      expect(series.buckets.last.amount, fraction(1, 7));
      expect(series.total.exactTotal, fraction(1, 2) + fraction(1, 7));
      expect(series.total.knownContributions, 3);
      expect(series.total.unknownContributions, 0);
      expect(series.total.complete, isTrue);
      expect(series.total.isKnownTotal, isTrue);
      expect(series.total.hasUnknownContributions, isFalse);
    });

    test('an unknown ingredient piece keeps a known subtotal, not a total', () {
      final model = chartModel(
        batch: chartBatch(
          observations: [
            productObservation(
              record: 'record-1',
              volume: '10',
              components: [
                productComponent('ingredient-a', 'Ingredient A', mgPerMl: '2'),
                productComponent('ingredient-b', 'Ingredient B', mgPerMl: '1'),
              ],
              at: at19,
            ),
            productObservation(
              record: 'record-2',
              item: 'item-2',
              itemName: 'Second product',
              volume: '5',
              components: [
                productComponent('ingredient-a', 'Ingredient A'),
                productComponent('ingredient-b', 'Ingredient B', mgPerMl: '1'),
              ],
              at: at20,
            ),
          ],
        ),
      );

      final ingredientA = model.seriesFor(
        ChartSeriesKey(
          personId: 'me',
          subject: ChartSubject.ingredient('ingredient-a'),
          unit: 'mg',
        ),
      )!;
      expect(ingredientA.total.knownSubtotal, ExactAmount.parseEntry('20'));
      expect(ingredientA.total.exactTotal, isNull);
      expect(ingredientA.total.isKnownTotal, isFalse);
      expect(ingredientA.total.hasUnknownContributions, isTrue);
      expect(ingredientA.total.complete, isFalse);
      // The unknown administration contributes no zero point for its bucket.
      expect(ingredientA.buckets.length, 1);
      expect(ingredientA.segments.whereType<ChartGap>().length, 2);
      expect(
        ingredientA.buckets.every((bucket) => bucket.amount > ExactAmount.zero),
        isTrue,
      );

      final ingredientB = model.seriesFor(
        ChartSeriesKey(
          personId: 'me',
          subject: ChartSubject.ingredient('ingredient-b'),
          unit: 'mg',
        ),
      )!;
      expect(ingredientB.total.isKnownTotal, isTrue);
      expect(ingredientB.total.exactTotal, ExactAmount.parseEntry('15'));
      expect(ingredientB.total.hasUnknownContributions, isFalse);
    });

    test('9e9-scale entries keep exact rational precision', () {
      final big = ExactAmount.parseEntry('9000000000');
      final micro = fraction(1, 1000000);
      final model = chartModel(
        batch: chartBatch(
          observations: [
            exactObservation(record: 'record-1', amount: big, at: at19),
            exactObservation(record: 'record-2', amount: micro, at: at19),
          ],
        ),
      );

      expect(
        model.series.single.total.exactTotal,
        ExactAmount(BigInt.from(9000000000000001), BigInt.from(1000000)),
      );
    });

    test('an unrepresentable exact total is a typed failure', () {
      expect(
        () => chartModel(
          batch: chartBatch(
            observations: [
              exactObservation(
                record: 'record-1',
                amount: ExactAmount(BigInt.one, BigInt.two.pow(70000)),
                at: at19,
              ),
            ],
          ),
        ),
        chartRangeError('exact_total_limit'),
      );
    });

    test('a bucket with no records is never a zero point', () {
      final model = chartModel(
        batch: chartBatch(
          observations: [
            chartObservation(record: 'record-1', amount: '2', at: at19),
          ],
        ),
      );

      final series = model.series.single;
      expect(series.buckets.single.amount, ExactAmount.parseEntry('2'));
      expect(
        series.buckets.any((bucket) => bucket.amount == ExactAmount.zero),
        isFalse,
      );
      expect(series.segments.whereType<ChartGap>().length, 2);
      expect(series.total.knownContributions, 1);
      expect(series.total.unknownContributions, 0);
    });

    test('a missing bucket is an explicit gap, not zero', () {
      final model = chartModel(
        batch: chartBatch(
          observations: [
            chartObservation(record: 'record-1', at: at19),
            chartObservation(
              record: 'record-2',
              at: at20.add(const Duration(days: 1)),
            ),
          ],
        ),
      );

      final series = model.series.single;
      expect(series.buckets.length, 2);
      expect(series.total.exactTotal, ExactAmount.parseEntry('2'));
      expect(series.segments.length, 3);
      expect(series.segments[0], isA<ChartBucket>());
      expect(series.segments[1], isA<ChartGap>());
      expect(series.segments[2], isA<ChartBucket>());
      final gap = series.segments[1] as ChartGap;
      expect(gap.bounds.civilStart.toString(), '2026-10-20');
      expect(gap.bounds.duration, const Duration(days: 1));
    });
  });

  group('separation of identities', () {
    test('mg, ml and count series never share a total', () {
      final model = chartModel(
        batch: chartBatch(
          observations: [
            chartObservation(record: 'record-1', amount: '2', unit: 'mg'),
            chartObservation(record: 'record-2', amount: '3', unit: 'ml'),
            chartObservation(record: 'record-3', amount: '4', unit: 'count'),
          ],
        ),
      );

      expect(model.series.length, 3);
      expect(model.series.map((series) => series.key.unit).toSet(), {
        'mg',
        'ml',
        'count',
      });
      expect(model.series.map((series) => series.total.exactTotal).toSet(), {
        ExactAmount.parseEntry('2'),
        ExactAmount.parseEntry('3'),
        ExactAmount.parseEntry('4'),
      });
    });

    test('a product contributes volume and ingredients separately', () {
      final model = chartModel(
        batch: chartBatch(
          observations: [
            productObservation(
              volume: '10',
              components: [
                productComponent('ingredient-a', 'Ingredient A', mgPerMl: '2'),
                productComponent('ingredient-b', 'Ingredient B'),
              ],
              at: at19,
            ),
          ],
        ),
      );

      expect(model.series.length, 3);
      final volume = model.seriesFor(
        ChartSeriesKey(
          personId: 'me',
          subject: ChartSubject.item('item-1'),
          unit: 'ml',
        ),
      )!;
      final knownIngredient = model.seriesFor(
        ChartSeriesKey(
          personId: 'me',
          subject: ChartSubject.ingredient('ingredient-a'),
          unit: 'mg',
        ),
      )!;
      final unknownIngredient = model.seriesFor(
        ChartSeriesKey(
          personId: 'me',
          subject: ChartSubject.ingredient('ingredient-b'),
          unit: 'mg',
        ),
      )!;

      expect(volume.total.exactTotal, ExactAmount.parseEntry('10'));
      expect(knownIngredient.total.exactTotal, ExactAmount.parseEntry('20'));
      expect(knownIngredient.label, 'Ingredient A');
      expect(unknownIngredient.buckets, isEmpty);
      expect(unknownIngredient.total.exactTotal, isNull);
      expect(unknownIngredient.total.knownSubtotal, ExactAmount.zero);
      expect(unknownIngredient.total.unknownContributions, 1);
      expect(unknownIngredient.total.complete, isFalse);
      expect(unknownIngredient.label, 'Ingredient B');
    });

    test(
      'the same ingredient across products folds only within one person',
      () {
        final model = chartModel(
          batch: chartBatch(
            observations: [
              productObservation(
                record: 'record-1',
                item: 'item-1',
                volume: '10',
                components: [
                  productComponent(
                    'ingredient-a',
                    'Ingredient A',
                    mgPerMl: '2',
                  ),
                  productComponent('ingredient-b', 'Ingredient B'),
                ],
                at: at19,
              ),
              productObservation(
                record: 'record-2',
                item: 'item-2',
                itemName: 'Second product',
                volume: '10',
                components: [
                  productComponent(
                    'ingredient-a',
                    'Ingredient A',
                    mgPerMl: '0.5',
                  ),
                  productComponent('ingredient-c', 'Ingredient C'),
                ],
                at: at20,
              ),
            ],
          ),
        );

        final ingredientA = model.seriesFor(
          ChartSeriesKey(
            personId: 'me',
            subject: ChartSubject.ingredient('ingredient-a'),
            unit: 'mg',
          ),
        )!;
        expect(ingredientA.total.exactTotal, ExactAmount.parseEntry('25'));
        expect(ingredientA.key.personId, 'me');
        expect(
          model.series.where((series) => series.key.unit == 'ml').length,
          2,
        );
      },
    );

    test('a chart query cannot focus another person', () {
      expect(
        () => ChartQuery(
          personId: 'me',
          viewport: chartViewport(),
          focus: ChartSeriesKey(
            personId: 'other',
            subject: ChartSubject.item('item-1'),
            unit: 'mg',
          ),
        ),
        chartModelError('chart_focus_owner'),
      );
    });

    test('a batch cannot mix people', () {
      expect(
        () => ChartModel.build(
          query: chartQuery(person: 'me'),
          batch: chartBatch(
            person: 'other',
            observations: [chartObservation()],
          ),
          generation: 1,
        ),
        chartModelError('cross_person_chart'),
      );
    });
  });

  group('voided and bounded input', () {
    test('voided administrations are counted but never charted', () {
      final model = chartModel(
        batch: chartBatch(
          observations: [
            chartObservation(record: 'record-1', amount: '2'),
            chartObservation(record: 'record-2', amount: '5', voided: true),
          ],
        ),
      );

      expect(model.observationCount, 2);
      expect(model.voidedObservationCount, 1);
      expect(model.series.single.total.exactTotal, ExactAmount.parseEntry('2'));
      expect(model.series.single.total.knownContributions, 1);
    });

    test('a range above the source-row bound is a typed failure', () {
      expect(
        () => ChartModel.build(
          query: chartQuery(),
          batch: chartBatch(
            observations: [chartObservation()],
            truncated: true,
          ),
          generation: 1,
        ),
        chartRangeError('range_too_large'),
      );
    });

    test('a batch must match the exact query range', () {
      expect(
        () => ChartModel.build(
          query: chartQuery(
            viewport: chartViewport(
              from: day19,
              before: DateTime.utc(2026, 10, 21),
            ),
          ),
          batch: chartBatch(from: day19, before: day22),
          generation: 1,
        ),
        chartModelError('batch_range'),
      );
    });
  });

  group('focus and determinism', () {
    test('focus narrows the model without changing the selected series', () {
      final focus = ChartSeriesKey(
        personId: 'me',
        subject: ChartSubject.item('item-1'),
        unit: 'mg',
      );
      final model = chartModel(
        query: chartQuery(focus: focus),
        batch: chartBatch(
          observations: [
            chartObservation(record: 'record-1', amount: '2', unit: 'mg'),
            chartObservation(record: 'record-2', amount: '3', unit: 'ml'),
          ],
        ),
      );

      expect(model.series.length, 1);
      expect(model.series.single.key, focus);
      expect(model.series.single.total.exactTotal, ExactAmount.parseEntry('2'));
    });

    test('shuffled identical input folds to the same model', () {
      ChartObservation observation(
        String record,
        String item,
        String unit,
        String amount,
        String name,
        DateTime at,
      ) => chartObservation(
        record: record,
        item: item,
        itemName: name,
        unit: unit,
        amount: amount,
        at: at,
      );

      final observations = [
        observation('record-1', 'item-1', 'mg', '1.5', 'Old name', at19),
        observation(
          'record-2',
          'item-1',
          'mg',
          '2.25',
          'New name',
          at19.add(const Duration(minutes: 5)),
        ),
        observation('record-3', 'item-1', 'ml', '3', 'Volume item', at20),
        observation('record-4', 'item-2', 'mg', '4', 'Other item', at20),
      ];

      final first = chartModel(batch: chartBatch(observations: observations));
      final second = chartModel(
        batch: chartBatch(observations: observations.reversed),
      );

      expect(describeModel(first), describeModel(second));
      final itemMg = first.series.firstWhere(
        (series) =>
            series.key.unit == 'mg' && series.key.subject.id == 'item-1',
      );
      expect(itemMg.label, 'New name');
    });

    test('the total does not depend on the visible bucket count', () {
      final observations = List.generate(
        10000,
        (index) => exactObservation(
          record: 'record-$index',
          amount: fraction(1, 3),
          at: day19.add(Duration(seconds: index)),
        ),
      );
      final model = chartModel(batch: chartBatch(observations: observations));

      final series = model.series.single;
      expect(series.bucketCount, 1);
      expect(series.buckets.single.contributionCount, 10000);
      expect(series.buckets.single.amount, fraction(10000, 3));
      expect(series.total.exactTotal, fraction(10000, 3));
    });

    test('annotations never alter a point', () {
      final model = chartModel(
        batch: chartBatch(observations: [chartObservation()]),
        annotations: [
          ChartAnnotation(
            kind: ChartAnnotationKind.eventStart,
            sourceId: 'event-1',
            personId: 'me',
            at: ChartAnnotationDate.exact(DateTime.utc(2026, 10, 20)),
            label: 'Event one',
          ),
        ],
      );

      expect(model.series.single.total.exactTotal, ExactAmount.parseEntry('1'));
      expect(model.annotations.visible.length, 1);
      expect(model.annotations.isComplete, isTrue);
    });
  });
}
