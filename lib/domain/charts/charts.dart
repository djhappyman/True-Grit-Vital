/// Pure exact chart domain for ticket 18.
///
/// Exposes bounded viewport buckets, per-person/per-unit/licensed-ingredient
/// series identity, exact totals, explicit gaps, factual annotations, paged
/// drill-down references and stale-result sequencing.
///
/// No SQL, widget, plotting-engine or app-copy dependency is exported here.
library;

export 'chart_annotations.dart';
export 'chart_drilldown.dart';
export 'chart_limits.dart';
export 'chart_model.dart';
export 'chart_query.dart';
export 'chart_series.dart';
export 'chart_viewport.dart';
