import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/charts/charts.dart';
import 'package:true_grit_vital/domain/history/timeline_query.dart';

import 'chart_test_data.dart';

void main() {
  final from = DateTime.utc(2026, 10, 19);
  final before = DateTime.utc(2026, 10, 22);
  final itemKey = ChartSeriesKey(
    personId: 'me',
    subject: ChartSubject.item('item-1'),
    unit: 'mg',
  );
  final ingredientKey = ChartSeriesKey(
    personId: 'me',
    subject: ChartSubject.ingredient('item-1'),
    unit: 'mg',
  );

  group('drill-down query identity', () {
    ChartDrilldownRequest request(ChartSeriesKey key) => ChartDrilldownRequest(
      series: key,
      fromInstant: from,
      beforeInstant: before,
      displayZone: 'UTC',
    );

    test('an item drill-down reuses the History filter exactly', () {
      final value = request(itemKey);

      expect(value.requiresIngredientPredicate, isFalse);
      expect(value.timelineQuery.filter.scope.personId, 'me');
      expect(value.timelineQuery.filter.fromInstant, from);
      expect(value.timelineQuery.filter.beforeInstant, before);
      expect(value.timelineQuery.filter.itemId, 'item-1');
      expect(value.timelineQuery.filter.actualUnit, 'mg');
      expect(value.timelineQuery.filter.status, TimelineStatus.all);
      expect(value.timelineQuery.limit, ChartLimits.defaultDrilldownPageSize);
      expect(value.timelineQuery.cursor, isNull);
    });

    test('an ingredient drill-down marks its extra membership predicate', () {
      final value = request(ingredientKey);

      expect(value.requiresIngredientPredicate, isTrue);
      expect(value.timelineQuery.filter.itemId, isNull);
      // The ingredient unit is derived from the label, not the source row's
      // saved actual unit. Product source rows are in ml, so filtering by the
      // derived mg unit would return no rows.
      expect(value.timelineQuery.filter.actualUnit, isNull);
      expect(request(itemKey).timelineQuery.filter.actualUnit, 'mg');
      expect(value.series.subject.kind, ChartSubjectKind.ingredient);
    });

    test(
      'identity covers kind, unit, range, zone and status but not limit',
      () {
        final base = request(itemKey);
        final largerPage = ChartDrilldownRequest(
          series: itemKey,
          fromInstant: from,
          beforeInstant: before,
          displayZone: 'UTC',
          limit: 50,
        );
        final otherUnit = request(
          ChartSeriesKey(
            personId: 'me',
            subject: ChartSubject.item('item-1'),
            unit: 'ml',
          ),
        );
        final otherStatus = ChartDrilldownRequest(
          series: itemKey,
          fromInstant: from,
          beforeInstant: before,
          displayZone: 'UTC',
          status: TimelineStatus.voided,
        );
        final otherRange = ChartDrilldownRequest(
          series: itemKey,
          fromInstant: from,
          beforeInstant: DateTime.utc(2026, 10, 20),
          displayZone: 'UTC',
        );

        expect(largerPage.identity, base.identity);
        expect(request(ingredientKey).identity, isNot(base.identity));
        expect(otherUnit.identity, isNot(base.identity));
        expect(otherStatus.identity, isNot(base.identity));
        expect(otherRange.identity, isNot(base.identity));
        expect(request(itemKey).identity, matches(RegExp(r'^[0-9a-f]{64}$')));
      },
    );

    test('the drill-down cursor contract is the History cursor contract', () {
      final query = request(itemKey).timelineQuery;
      final cursor = TimelineCursor.at(
        occurredAt: DateTime.utc(2026, 10, 19, 8),
        sortKey: 'r:record-1',
        query: query,
        schemaVersion: 17,
        datasetGeneration: 'generation-1',
      );

      expect(query.withCursor(cursor).cursor, cursor);
      expect(
        cursor.isValidFor(
          query: query,
          schemaVersion: 17,
          datasetGeneration: 'generation-1',
        ),
        isTrue,
      );
      expect(
        cursor.isValidFor(
          query: request(ingredientKey).timelineQuery,
          schemaVersion: 17,
          datasetGeneration: 'generation-1',
        ),
        isFalse,
      );
      expect(
        cursor.isValidFor(
          query: query,
          schemaVersion: 18,
          datasetGeneration: 'generation-1',
        ),
        isFalse,
      );
    });

    test('invalid drill-down bounds are typed failures', () {
      expect(
        () => ChartDrilldownRequest(
          series: itemKey,
          fromInstant: before,
          beforeInstant: from,
          displayZone: 'UTC',
        ),
        chartRangeError('invalid_range'),
      );
      expect(
        () => ChartDrilldownRequest(
          series: itemKey,
          fromInstant: from,
          beforeInstant: before,
          displayZone: 'UTC',
          limit: 51,
        ),
        chartModelError('invalid_limit'),
      );
    });

    test('a bucket drill-down points at the exact bucket range', () {
      final model = chartModel(
        batch: chartBatch(observations: [chartObservation()]),
      );
      final series = model.series.single;
      final value = series.drilldown(series.buckets.single);

      expect(value.fromInstant, series.buckets.single.bounds.fromInstant);
      expect(value.beforeInstant, series.buckets.single.bounds.beforeExclusive);
      expect(value.series, series.key);
      expect(value.displayZone, 'UTC');
    });
  });

  group('chart query identity', () {
    test('covers person, range, bucket size, zone and focus', () {
      final base = chartQuery();
      final otherRange = chartQuery(
        viewport: chartViewport(from: from, before: DateTime.utc(2026, 10, 21)),
      );
      final otherBucket = chartQuery(
        viewport: chartViewport(size: ChartBucketSize.week),
      );
      final otherZone = chartQuery(
        viewport: chartViewport(zone: 'Europe/London'),
      );
      final focused = chartQuery(focus: itemKey);

      expect(base.identity, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(otherRange.identity, isNot(base.identity));
      expect(otherBucket.identity, isNot(base.identity));
      expect(otherZone.identity, isNot(base.identity));
      expect(focused.identity, isNot(base.identity));
      expect(chartQuery(person: 'other').identity, isNot(base.identity));
      expect(base.sourceRequest.personId, 'me');
      expect(base.sourceRequest.fromInstant, base.viewport.fromInstant);
    });
  });

  group('stale generation guard', () {
    test('applies only the newest matching result', () {
      final initial = ChartRequestState.initial();
      final first = chartQuery();
      final firstState = initial.restart(first);
      final firstModel = chartModel(query: first, generation: 1);

      expect(initial.hasQuery, isFalse);
      expect(initial.accepts(firstModel.token), isFalse);
      expect(firstState.hasQuery, isTrue);
      expect(firstState.generation, 1);
      expect(firstState.accepts(firstModel.token), isTrue);

      final secondState = firstState.restart(first);
      expect(secondState.generation, 2);
      expect(secondState.accepts(firstModel.token), isFalse);

      final secondModel = chartModel(query: first, generation: 2);
      expect(secondState.accepts(secondModel.token), isTrue);
    });

    test(
      'a late result from an older range cannot overwrite a newer range',
      () {
        final first = chartQuery();
        final zoomed = chartQuery(
          viewport: chartViewport(
            from: from,
            before: DateTime.utc(2026, 10, 21),
          ),
        );
        final state = ChartRequestState.initial()
            .restart(first)
            .restart(zoomed);
        final stale = ChartModel.build(
          query: first,
          batch: chartBatch(observations: [chartObservation()]),
          generation: 1,
        );
        final current = ChartModel.build(
          query: zoomed,
          batch: chartBatch(
            from: zoomed.viewport.fromInstant,
            before: zoomed.viewport.beforeInstant,
            observations: [chartObservation(record: 'record-2')],
          ),
          generation: 2,
        );

        expect(state.accepts(stale.token), isFalse);
        expect(state.accepts(current.token), isTrue);
      },
    );

    test('schema and dataset generation must match when expected', () {
      final query = chartQuery();
      final state = ChartRequestState.initial().restart(
        query,
        schemaVersion: 17,
        datasetGeneration: 'generation-1',
      );
      final model = chartModel(query: query, generation: 1);
      final otherSchema = state.restart(
        query,
        schemaVersion: 18,
        datasetGeneration: 'generation-1',
      );
      final otherDataset = state.restart(
        query,
        schemaVersion: 17,
        datasetGeneration: 'generation-2',
      );
      final generationTwo = chartModel(query: query, generation: 2);

      expect(state.accepts(model.token), isTrue);
      expect(otherSchema.accepts(generationTwo.token), isFalse);
      expect(otherDataset.accepts(generationTwo.token), isFalse);
    });

    test('a token must carry a valid identity and generation', () {
      expect(
        () => ChartResultToken(
          generation: -1,
          queryIdentity: chartQuery().identity,
          schemaVersion: 17,
          datasetGeneration: 'generation-1',
        ),
        chartModelError('result_generation'),
      );
      expect(
        () => ChartResultToken(
          generation: 1,
          queryIdentity: 'not-a-hash',
          schemaVersion: 17,
          datasetGeneration: 'generation-1',
        ),
        chartModelError('result_identity'),
      );
    });
  });
}
