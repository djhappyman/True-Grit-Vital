import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/charts/charts.dart';
import 'package:true_grit_vital/domain/scheduling/daily_plan.dart';

import 'chart_test_data.dart';

ChartAnnotation annotation(
  ChartAnnotationKind kind,
  String sourceId,
  DateTime at, {
  String person = 'me',
  String? label,
}) => ChartAnnotation(
  kind: kind,
  sourceId: sourceId,
  personId: person,
  at: ChartAnnotationDate.exact(at),
  label: label,
);

void main() {
  final from = DateTime.utc(2026, 10, 19);
  final before = DateTime.utc(2026, 10, 22);
  final viewport = chartViewport(from: from, before: before);

  ChartAnnotationSet bounded(
    Iterable<ChartAnnotation> annotations, {
    int maximum = ChartLimits.maxAnnotations,
  }) => ChartAnnotationSet.bounded(
    viewport: viewport,
    personId: 'me',
    annotations: annotations,
    maximum: maximum,
  );

  test('the annotation model contains factual boundaries only', () {
    expect(ChartAnnotationKind.values, [
      ChartAnnotationKind.eventStart,
      ChartAnnotationKind.eventEnd,
      ChartAnnotationKind.planChanged,
      ChartAnnotationKind.pauseStart,
      ChartAnnotationKind.pauseEnd,
      ChartAnnotationKind.phaseStart,
      ChartAnnotationKind.phaseEnd,
      ChartAnnotationKind.planEnd,
    ]);
  });

  test('exact annotations are half-open at the viewport edges', () {
    final set = bounded([
      annotation(ChartAnnotationKind.eventStart, 'event-1', from),
      annotation(
        ChartAnnotationKind.eventEnd,
        'event-1',
        before.subtract(const Duration(microseconds: 1)),
      ),
      annotation(ChartAnnotationKind.eventEnd, 'event-2', before),
    ]);

    expect(set.visible.map((entry) => entry.sourceId).toList(), [
      'event-1',
      'event-1',
    ]);
    expect(set.visible.first.kind, ChartAnnotationKind.eventStart);
    expect(set.visible.last.kind, ChartAnnotationKind.eventEnd);
  });

  test('same-instant annotations order by kind then source identity', () {
    final set = bounded([
      annotation(ChartAnnotationKind.eventEnd, 'event-b', from),
      annotation(ChartAnnotationKind.eventStart, 'event-z', from),
      annotation(ChartAnnotationKind.eventStart, 'event-a', from),
    ]);

    expect(
      set.visible
          .map((entry) => '${entry.kind.name}:${entry.sourceId}')
          .toList(),
      ['eventStart:event-a', 'eventStart:event-z', 'eventEnd:event-b'],
    );
    expect(bounded(const []).isEmpty, isTrue);
  });

  test(
    'a saved date-only end keeps its date and is not fabricated midnight',
    () {
      final end = ChartAnnotation(
        kind: ChartAnnotationKind.eventEnd,
        sourceId: 'event-1',
        personId: 'me',
        at: ChartAnnotationDate.dateOnly(
          date: CivilDate(2026, 10, 21),
          zoneId: 'Europe/London',
        ),
        label: 'Course one',
      );
      final set = ChartAnnotationSet.bounded(
        viewport: viewport,
        personId: 'me',
        annotations: [end],
      );

      expect(end.at.isDateOnly, isTrue);
      expect(end.at.instant, isNull);
      expect(end.at.civilDate, CivilDate(2026, 10, 21));
      expect(end.at.zoneId, 'Europe/London');
      expect(set.visible.single.label, 'Course one');
      expect(
        ChartAnnotationSet.bounded(
          viewport: chartViewport(
            from: DateTime.utc(2026, 10, 22),
            before: DateTime.utc(2026, 10, 25),
          ),
          personId: 'me',
          annotations: [end],
        ).visible,
        isEmpty,
      );
    },
  );

  test('annotations are ordered deterministically and capped explicitly', () {
    final annotations = [
      for (var index = 249; index >= 0; index--)
        annotation(
          ChartAnnotationKind.eventStart,
          'event-$index',
          from.add(Duration(minutes: index)),
        ),
    ];
    final set = bounded(annotations);

    expect(set.consideredCount, 250);
    expect(set.visible.length, 200);
    expect(set.hiddenCount, 50);
    expect(set.isComplete, isFalse);
    expect(set.visible.first.sourceId, 'event-0');
    expect(set.visible.last.sourceId, 'event-199');
  });

  test('custom maximum below the cap is honoured', () {
    final set = bounded([
      for (var index = 0; index < 5; index++)
        annotation(
          ChartAnnotationKind.planChanged,
          'plan-$index',
          from.add(Duration(hours: index)),
        ),
    ], maximum: 2);

    expect(set.visible.length, 2);
    expect(set.hiddenCount, 3);
    expect(set.consideredCount, 5);
  });

  test('invalid limits, owners and duplicates are rejected', () {
    expect(
      () => bounded(const [], maximum: 0),
      chartModelError('annotation_limit'),
    );
    expect(
      () => bounded(const [], maximum: ChartLimits.maxAnnotations + 1),
      chartModelError('annotation_limit'),
    );
    expect(
      () => bounded([
        annotation(
          ChartAnnotationKind.eventStart,
          'event-1',
          from,
          person: 'other',
        ),
      ]),
      chartModelError('annotation_owner'),
    );
    expect(
      () => bounded([
        annotation(ChartAnnotationKind.eventStart, 'event-1', from),
        annotation(
          ChartAnnotationKind.eventStart,
          'event-1',
          from.add(const Duration(hours: 1)),
        ),
      ]),
      chartModelError('annotation_duplicate'),
    );
  });

  test('annotation instants must be exact UTC', () {
    expect(
      () => ChartAnnotationDate.exact(DateTime(2026, 10, 19, 8)),
      chartRangeError('annotation_date'),
    );
  });

  test('source revisions are optional but validated', () {
    expect(
      ChartAnnotation(
        kind: ChartAnnotationKind.phaseStart,
        sourceId: 'phase-1',
        personId: 'me',
        at: ChartAnnotationDate.exact(from),
        sourceRevision: 2,
      ).sourceRevision,
      2,
    );
    expect(
      () => ChartAnnotation(
        kind: ChartAnnotationKind.phaseStart,
        sourceId: 'phase-1',
        personId: 'me',
        at: ChartAnnotationDate.exact(from),
        sourceRevision: 0,
      ),
      chartModelError('annotation_revision'),
    );
  });
}
