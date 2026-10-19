import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/charts/charts.dart';
import 'package:true_grit_vital/domain/stock/exact_amount.dart';

import 'chart_test_data.dart';

/// Host-only synthetic evidence for ticket 18.
///
/// This is not a device, frame, memory or thermal measurement. It exercises
/// 100,000 exact observations across ten bounded reads, proves the source-row
/// bound and records wall-clock decoding/folding time on this host.
void main() {
  final amounts = [
    ExactAmount(BigInt.one, BigInt.from(3)),
    ExactAmount(BigInt.one, BigInt.from(7)),
    ExactAmount(BigInt.one, BigInt.from(11)),
  ];
  const batchSize = 10000;
  const batches = 10;

  List<ChartObservation> observationsFor(DateTime start) => [
    for (var index = 0; index < batchSize; index++)
      ChartObservation(
        source: ChartSourceRef(recordId: 'record-$index', revision: 1),
        personId: 'me',
        itemId: 'item-1',
        itemName: 'Synthetic item',
        amount: amounts[index % amounts.length],
        unit: 'mg',
        occurredAt: start.add(Duration(seconds: index)),
        enteredAmountText: '1',
        enteredUnit: 'count',
      ),
  ];

  test('100k host observations fold exactly with bounded reads', () {
    final stopwatch = Stopwatch()..start();
    var folded = 0;

    for (var batchIndex = 0; batchIndex < batches; batchIndex++) {
      final start = DateTime.utc(2026, 1, 1 + batchIndex * 3);
      final before = start.add(const Duration(days: 2));
      final observations = observationsFor(start);
      var expected = ExactAmount.zero;
      for (final observation in observations) {
        expected = expected + observation.amount;
      }
      final model = ChartModel.build(
        query: ChartQuery(
          personId: 'me',
          viewport: ChartViewport(
            fromInstant: start,
            beforeInstant: before,
            displayZone: 'UTC',
          ),
        ),
        batch: ChartObservationBatch(
          personId: 'me',
          fromInstant: start,
          beforeInstant: before,
          schemaVersion: 17,
          datasetGeneration: 'generation-host',
          observations: observations,
        ),
        generation: batchIndex + 1,
      );

      final series = model.series.single;
      expect(series.total.exactTotal, expected);
      expect(series.total.knownContributions, batchSize);
      expect(series.buckets.single.contributionCount, batchSize);
      expect(series.segments.length, 2);
      expect(series.segments.last, isA<ChartGap>());
      folded += batchSize;
    }

    stopwatch.stop();
    expect(folded, 100000);
    // ignore: avoid_print
    print(
      'chart-host-100k observations=$folded batches=$batches '
      'elapsedMs=${stopwatch.elapsedMilliseconds} '
      '(host synthetic only; not a device or frame budget)',
    );
  });

  test('the source read is capped at 10,000 rows and refuses to sample', () {
    final start = DateTime.utc(2026, 2, 1);
    final observations = observationsFor(start);

    expect(
      () => ChartModel.build(
        query: ChartQuery(
          personId: 'me',
          viewport: ChartViewport(
            fromInstant: start,
            beforeInstant: start.add(const Duration(days: 2)),
            displayZone: 'UTC',
          ),
        ),
        batch: ChartObservationBatch(
          personId: 'me',
          fromInstant: start,
          beforeInstant: start.add(const Duration(days: 2)),
          schemaVersion: 17,
          datasetGeneration: 'generation-host',
          observations: observations,
          truncated: true,
        ),
        generation: 1,
      ),
      chartRangeError('range_too_large'),
    );
    expect(
      () => ChartObservationBatch(
        personId: 'me',
        fromInstant: start,
        beforeInstant: start.add(const Duration(days: 2)),
        schemaVersion: 17,
        datasetGeneration: 'generation-host',
        observations: [
          ...observations,
          ChartObservation(
            source: ChartSourceRef(recordId: 'record-extra', revision: 1),
            personId: 'me',
            itemId: 'item-1',
            itemName: 'Synthetic item',
            amount: amounts.first,
            unit: 'mg',
            occurredAt: start,
          ),
        ],
      ),
      chartModelError('source_rows'),
    );
  });
}
