import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/charts/charts.dart';
import 'package:true_grit_vital/domain/stock/exact_amount.dart';

import 'chart_test_data.dart';

void main() {
  group('series identity separation', () {
    ChartSeriesKey key(String person, ChartSubject subject, String unit) =>
        ChartSeriesKey(personId: person, subject: subject, unit: unit);

    test('person, subject kind and saved actual unit are all identity', () {
      final itemMg = key('me', ChartSubject.item('item-1'), 'mg');
      final itemMl = key('me', ChartSubject.item('item-1'), 'ml');
      final ingredientMg = key('me', ChartSubject.ingredient('item-1'), 'mg');
      final otherAdultMg = key('other', ChartSubject.item('item-1'), 'mg');

      expect({itemMg, itemMl, ingredientMg, otherAdultMg}.length, 4);
      expect(itemMg == itemMl, isFalse);
      expect(itemMg == ingredientMg, isFalse);
      expect(itemMg == otherAdultMg, isFalse);
    });

    test(
      'series keys sort deterministically by person, kind, subject, unit',
      () {
        final keys = [
          key('b', ChartSubject.item('a'), 'mg'),
          key('a', ChartSubject.ingredient('a'), 'mg'),
          key('a', ChartSubject.item('b'), 'ml'),
          key('a', ChartSubject.item('a'), 'ml'),
        ]..sort();

        expect(keys.map((value) => value.toString()).toList(), [
          '{"person":"a","kind":"item","subject":"a","unit":"ml"}',
          '{"person":"a","kind":"item","subject":"b","unit":"ml"}',
          '{"person":"a","kind":"ingredient","subject":"a","unit":"mg"}',
          '{"person":"b","kind":"item","subject":"a","unit":"mg"}',
        ]);
      },
    );

    test('empty identities are rejected', () {
      expect(() => ChartSubject.item(' '), chartModelError('chart_subject'));
      expect(
        () => ChartSeriesKey(
          personId: '',
          subject: ChartSubject.item('item-1'),
          unit: 'mg',
        ),
        chartModelError('chart_owner'),
      );
      expect(
        () => ChartSeriesKey(
          personId: 'me',
          subject: ChartSubject.item('item-1'),
          unit: '',
        ),
        chartModelError('chart_unit'),
      );
    });
  });

  group('observation validation', () {
    test('exact actual and entered original unit stay separate', () {
      final observation = chartObservation(
        amount: '0.5',
        unit: 'mg',
        enteredAmount: '5',
        enteredUnit: 'count',
      );

      expect(observation.amount, ExactAmount.parseEntry('0.5'));
      expect(observation.unit, 'mg');
      expect(observation.enteredAmountText, '5');
      expect(observation.enteredUnit, 'count');
    });

    test('non-positive exact amounts are rejected', () {
      expect(
        () => ChartObservation(
          source: ChartSourceRef(recordId: 'record-1', revision: 1),
          personId: 'me',
          itemId: 'item-1',
          itemName: 'Test item',
          amount: ExactAmount.zero,
          unit: 'mg',
          occurredAt: DateTime.utc(2026, 10, 19, 8),
        ),
        chartModelError('chart_amount'),
      );
    });

    test('original entry must be a canonical positive amount', () {
      expect(
        () => chartObservation(
          amount: '1',
          enteredAmount: '0.1234567',
          enteredUnit: 'mg',
        ),
        chartModelError('chart_entered_amount'),
      );
      expect(
        () => chartObservation(amount: '1', enteredAmount: '1'),
        chartModelError('chart_entered_pair'),
      );
      expect(
        () => chartObservation(
          amount: '1',
          enteredAmount: '9000000001',
          enteredUnit: 'mg',
        ),
        chartModelError('chart_entered_amount'),
      );
    });

    test('non-UTC occurrence is rejected', () {
      expect(
        () => chartObservation(at: DateTime(2026, 10, 19, 8)),
        chartRangeError('observation_range'),
      );
    });

    test('product volume and label must match the observation exactly', () {
      final components = [
        productComponent('a', 'Ingredient A', mgPerMl: '2'),
        productComponent('b', 'Ingredient B'),
      ];

      expect(
        () => chartObservation(
          amount: '9',
          unit: 'ml',
          product: productSnapshot(volume: '10', components: components),
        ),
        chartModelError('chart_product_volume'),
      );
      expect(
        () => chartObservation(
          amount: '10',
          unit: 'mg',
          product: productSnapshot(volume: '10', components: components),
        ),
        chartModelError('chart_product_unit'),
      );
      expect(
        () => chartObservation(
          person: 'me',
          amount: '10',
          unit: 'ml',
          product: productSnapshot(
            person: 'other',
            volume: '10',
            components: components,
          ),
        ),
        chartModelError('chart_product_owner'),
      );
    });
  });

  group('bounded observation batch', () {
    test('is immutable and reports truncation', () {
      final batch = chartBatch(
        observations: [chartObservation()],
        truncated: true,
      );

      expect(batch.isEmpty, isFalse);
      expect(batch.observationCount, 1);
      expect(batch.truncated, isTrue);
      expect(
        () => batch.observations.add(chartObservation(record: 'other')),
        throwsUnsupportedError,
      );
    });

    test('combined components carry group context without a parent row', () {
      final batch = chartBatch(
        observations: [
          chartObservation(record: 'record-1', combinedActionId: 'combined-1'),
          chartObservation(record: 'record-2', combinedActionId: 'combined-1'),
        ],
      );

      expect(batch.observationCount, 2);
      expect(
        batch.observations
            .map((observation) => observation.source.combinedActionId)
            .toList(),
        ['combined-1', 'combined-1'],
      );
    });

    test('rejects more than the source-row bound', () {
      final observations = List.generate(
        10001,
        (index) => chartObservation(record: 'record-$index'),
      );

      expect(
        () => chartBatch(observations: observations),
        chartModelError('source_rows'),
      );
    });

    test('rejects a cross-person row, not only in the query', () {
      expect(
        () => chartBatch(
          person: 'me',
          observations: [chartObservation(person: 'other')],
        ),
        chartModelError('cross_person_chart'),
      );
    });

    test('rejects duplicate record identity across revisions', () {
      expect(
        () => chartBatch(
          observations: [
            chartObservation(record: 'record-1', revision: 1),
            chartObservation(record: 'record-1', revision: 2),
          ],
        ),
        chartModelError('duplicate_source'),
      );
    });

    test('rejects an observation outside the half-open range', () {
      expect(
        () => chartBatch(
          from: DateTime.utc(2026, 10, 19),
          before: DateTime.utc(2026, 10, 22),
          observations: [chartObservation(at: DateTime.utc(2026, 10, 22))],
        ),
        chartModelError('observation_range'),
      );
    });

    test('source request is bounded and half-open', () {
      final request = ChartSourceRequest(
        personId: 'me',
        fromInstant: DateTime.utc(2026, 10, 19),
        beforeInstant: DateTime.utc(2026, 10, 22),
      );

      expect(request.fromInstant.isUtc, isTrue);
      expect(
        () => ChartSourceRequest(
          personId: 'me',
          fromInstant: DateTime.utc(2026, 10, 22),
          beforeInstant: DateTime.utc(2026, 10, 22),
        ),
        chartRangeError('invalid_range'),
      );
    });
  });
}
