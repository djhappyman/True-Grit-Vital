import 'package:fl_chart/fl_chart.dart' as plot;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/domain/charts/charts.dart';
import 'package:true_grit_vital/domain/stock/exact_amount.dart';
import 'package:true_grit_vital/domain/scheduling/daily_plan.dart';
import 'package:true_grit_vital/features/charts/chart_plot.dart';
import 'package:true_grit_vital/l10n/app_localizations.dart';

import 'design_system_test.dart' show host;
import 'domain/charts/chart_test_data.dart';

void main() {
  testWidgets(
    'overlapping saved-zone date marker clamps to visible edge without changing amounts',
    (tester) async {
      final viewport = chartViewport(
        from: DateTime.utc(2026, 10, 19),
        before: DateTime.utc(2026, 10, 20),
      );
      final model = chartModel(
        query: chartQuery(viewport: viewport),
        batch: chartBatch(
          from: viewport.fromInstant,
          before: viewport.beforeInstant,
          observations: [chartObservation(at: DateTime.utc(2026, 10, 19, 8))],
        ),
      );
      final annotation = ChartAnnotation(
        kind: ChartAnnotationKind.eventEnd,
        sourceId: 'saved-event',
        personId: 'me',
        at: ChartAnnotationDate.dateOnly(
          date: CivilDate(2026, 10, 19),
          zoneId: 'Asia/Tokyo',
        ),
      );
      final bounded = ChartAnnotationSet.bounded(
        viewport: viewport,
        personId: 'me',
        annotations: [annotation],
      );
      expect(bounded.visible, hasLength(1));
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 360,
            child: ChartPlot(
              series: model.series.single,
              summary: 'Exact chart summary',
              annotations: bounded.visible,
              onBucket: (_) {},
            ),
          ),
        ),
      );
      final canvas = tester.widget<plot.LineChart>(find.byType(plot.LineChart));
      expect(canvas.data.extraLinesData.verticalLines.single.x, 0);
      expect(model.series.single.total.exactTotal, ExactAmount.parseEntry('1'));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'chart count messages distinguish doses, ingredient amounts and context',
    (tester) async {
      late AppLocalizations t;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) {
              t = AppLocalizations.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(t.chartDoseCount(1), '1 recorded dose');
      expect(t.chartDoseCount(2), '2 recorded doses');
      expect(t.chartIngredientCount(1), '1 ingredient amount');
      expect(t.chartIngredientCount(2), '2 ingredient amounts');
      expect(t.chartAnnotationOverflow(1), startsWith('1 more context entry.'));
      expect(
        t.chartAnnotationOverflow(2),
        startsWith('2 more context entries.'),
      );
    },
  );
}
