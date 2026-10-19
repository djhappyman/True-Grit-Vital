import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../history/timeline_query.dart';
import '../records.dart' show FeedScope;
import 'chart_limits.dart';
import 'chart_series.dart';
import 'chart_support.dart';

/// Exact, paged source reference for one bucket of one series.
///
/// The request reuses the History `TimelineQuery` contract for scope, half-open
/// range, saved unit and status. An item series filters by its saved actual
/// unit. An ingredient series cannot be expressed by `TimelineFilter` alone, so
/// [requiresIngredientPredicate] tells the future reader to restrict rows to
/// that ingredient using each administration's saved product label snapshot
/// before paging. The chart model never recomputes totals from the visible
/// page.
///
/// `TimelineQuery` cannot encode the ingredient predicate, so a History cursor
/// identifies only the shared timeline query. Paging state must also retain
/// this request's [identity] and reject a page whose request identity changed;
/// a cursor from another ingredient series is not interchangeable.
final class ChartDrilldownRequest {
  factory ChartDrilldownRequest({
    required ChartSeriesKey series,
    required DateTime fromInstant,
    required DateTime beforeInstant,
    required String displayZone,
    TimelineStatus status = TimelineStatus.all,
    int limit = ChartLimits.defaultDrilldownPageSize,
  }) {
    chartRequireUtc(fromInstant, 'invalid_range');
    chartRequireUtc(beforeInstant, 'invalid_range');
    if (!beforeInstant.isAfter(fromInstant)) {
      throw const ChartRangeException('invalid_range');
    }
    chartRequireText(displayZone, 'invalid_zone');
    if (limit < 1 || limit > ChartLimits.maxDrilldownPageSize) {
      throw const ChartModelException('invalid_limit');
    }
    return ChartDrilldownRequest._(
      series: series,
      fromInstant: fromInstant,
      beforeInstant: beforeInstant,
      displayZone: displayZone,
      status: status,
      limit: limit,
    );
  }

  ChartDrilldownRequest._({
    required this.series,
    required this.fromInstant,
    required this.beforeInstant,
    required this.displayZone,
    required this.status,
    required this.limit,
  });

  final ChartSeriesKey series;
  final DateTime fromInstant, beforeInstant;
  final String displayZone;
  final TimelineStatus status;
  final int limit;

  bool get requiresIngredientPredicate =>
      series.subject.kind == ChartSubjectKind.ingredient;

  /// First page of the History query for this drill-down.
  ///
  /// Callers page with `TimelineQuery.withCursor(...)` and the returned cursor.
  /// For an ingredient series the reader must additionally restrict rows to
  /// [ChartSeriesKey.subject] using each administration's saved product label
  /// snapshot, before applying the page limit. The current label of the item at
  /// read time is not evidence that a past administration contained it.
  ///
  /// An ingredient series unit is derived from the saved product label, not
  /// from the source administration's saved actual unit. The source rows of a
  /// product ingredient are the product administrations in `ml`, so filtering
  /// them by the derived `mg` unit would return no rows. Ingredient drill-down
  /// therefore leaves [TimelineFilter.actualUnit] unset and relies on the
  /// required ingredient predicate; an item series still filters by its own
  /// saved actual unit.
  TimelineQuery get timelineQuery => TimelineQuery(
    filter: TimelineFilter(
      scope: FeedScope.person(series.personId),
      fromInstant: fromInstant,
      beforeInstant: beforeInstant,
      itemId: series.subject.kind == ChartSubjectKind.item
          ? series.subject.id
          : null,
      actualUnit: series.subject.kind == ChartSubjectKind.item
          ? series.unit
          : null,
      status: status,
    ),
    displayZone: displayZone,
    limit: limit,
  );

  /// Stable identity of the exact drill-down, including the ingredient
  /// subject that `TimelineQuery.identity` cannot express.
  late final String identity = sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'contract': 'vital.chart.drilldown',
            'version': 1,
            'series': {
              'person': series.personId,
              'kind': series.subject.kind.name,
              'subject': series.subject.id,
              'unit': series.unit,
            },
            'from': fromInstant.microsecondsSinceEpoch,
            'before': beforeInstant.microsecondsSinceEpoch,
            'zone': displayZone,
            'status': status.name,
          }),
        ),
      )
      .toString();
}
