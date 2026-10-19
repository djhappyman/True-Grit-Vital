import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'chart_limits.dart';
import 'chart_series.dart';
import 'chart_support.dart';
import 'chart_viewport.dart';

/// One exact chart view: person, bounded viewport and optional series focus.
///
/// The query identity is the stale-result key. It covers the person, exact UTC
/// range, bucket size, requested display zone and focused series. Page size is
/// not part of it.
final class ChartQuery {
  factory ChartQuery({
    required String personId,
    required ChartViewport viewport,
    ChartSeriesKey? focus,
  }) {
    chartRequireText(personId, 'chart_owner');
    if (focus != null && focus.personId != personId) {
      throw const ChartModelException('chart_focus_owner');
    }
    return ChartQuery._(personId: personId, viewport: viewport, focus: focus);
  }

  ChartQuery._({
    required this.personId,
    required this.viewport,
    required this.focus,
  });

  final String personId;
  final ChartViewport viewport;

  /// Null means every compatible series for the person. A focused series must
  /// belong to the same person; an all-adults chart is not representable.
  final ChartSeriesKey? focus;

  bool get hasFocus => focus != null;

  /// Stable SHA-256 identity of the exact chart view.
  late final String identity = sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'contract': 'vital.chart.query',
            'version': 1,
            'person': personId,
            'from': viewport.fromInstant.microsecondsSinceEpoch,
            'before': viewport.beforeInstant.microsecondsSinceEpoch,
            'bucket': viewport.bucketSize.name,
            'zone': viewport.displayZone,
            'focus': focus?.identity,
          }),
        ),
      )
      .toString();

  ChartSourceRequest get sourceRequest => ChartSourceRequest(
    personId: personId,
    fromInstant: viewport.fromInstant,
    beforeInstant: viewport.beforeInstant,
  );
}

/// Identity of one completed chart read.
///
/// The UI applies a result only when its token matches the current
/// [ChartRequestState]. A late completion from an older generation never wins.
final class ChartResultToken {
  factory ChartResultToken({
    required int generation,
    required String queryIdentity,
    required int schemaVersion,
    required String datasetGeneration,
  }) {
    if (generation < 0) {
      throw const ChartModelException('result_generation');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(queryIdentity)) {
      throw const ChartModelException('result_identity');
    }
    if (schemaVersion < 1) {
      throw const ChartModelException('result_schema');
    }
    chartRequireText(datasetGeneration, 'result_generation');
    return ChartResultToken._(
      generation: generation,
      queryIdentity: queryIdentity,
      schemaVersion: schemaVersion,
      datasetGeneration: datasetGeneration,
    );
  }

  const ChartResultToken._({
    required this.generation,
    required this.queryIdentity,
    required this.schemaVersion,
    required this.datasetGeneration,
  });

  final int generation;
  final String queryIdentity;
  final int schemaVersion;
  final String datasetGeneration;
}

/// Immutable request sequencing for rapid range, budget, person and unit
/// changes.
///
/// Calling [restart] for each new view increments the generation and replaces
/// the identity. A completion is applied only when [accepts] returns true for
/// its token, so an older read that finishes later cannot overwrite a newer
/// chart.
final class ChartRequestState {
  const ChartRequestState._({
    required this.generation,
    required this.queryIdentity,
    this.schemaVersion,
    this.datasetGeneration,
  });

  factory ChartRequestState.initial() =>
      const ChartRequestState._(generation: 0, queryIdentity: '');

  final int generation;
  final String queryIdentity;

  /// Expected reader schema and dataset generation, when known.
  final int? schemaVersion;
  final String? datasetGeneration;

  bool get hasQuery => queryIdentity.isNotEmpty;

  ChartRequestState restart(
    ChartQuery query, {
    int? schemaVersion,
    String? datasetGeneration,
  }) {
    if (schemaVersion != null && schemaVersion < 1) {
      throw const ChartModelException('result_schema');
    }
    chartRequireOptionalText(datasetGeneration, 'result_generation');
    return ChartRequestState._(
      generation: generation + 1,
      queryIdentity: query.identity,
      schemaVersion: schemaVersion,
      datasetGeneration: datasetGeneration,
    );
  }

  bool accepts(ChartResultToken token) {
    if (!hasQuery) return false;
    if (token.generation != generation) return false;
    if (token.queryIdentity != queryIdentity) return false;
    final schema = schemaVersion;
    if (schema != null && token.schemaVersion != schema) return false;
    final dataset = datasetGeneration;
    if (dataset != null && token.datasetGeneration != dataset) return false;
    return true;
  }
}
