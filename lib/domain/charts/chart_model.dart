import '../history/timeline_query.dart' show TimelineStatus;
import '../scheduling/iana_clock.dart';
import '../stock/exact_amount.dart';
import 'chart_annotations.dart';
import 'chart_drilldown.dart';
import 'chart_limits.dart';
import 'chart_query.dart';
import 'chart_series.dart';
import 'chart_viewport.dart';

/// One plot-position inside a viewport: an exact bucket amount or a gap.
///
/// A gap carries no amount. Nothing in this model represents a missing bucket
/// as zero.
sealed class ChartSegment {
  const ChartSegment(this.bounds);

  final ChartBucketBounds bounds;
}

/// One non-empty bucket. [amount] is an exact fold of the known contributions
/// in [bounds]; [contributionCount] is the number of counted administrations,
/// not a display sample.
final class ChartBucket extends ChartSegment {
  const ChartBucket({
    required ChartBucketBounds bounds,
    required this.series,
    required this.amount,
    required this.contributionCount,
  }) : super(bounds);

  final ChartSeriesKey series;
  final ExactAmount amount;
  final int contributionCount;
}

/// One bucket with no contributions. Explicitly distinct from zero.
final class ChartGap extends ChartSegment {
  const ChartGap(super.bounds);
}

/// Exact whole-range total for one series.
///
/// [knownSubtotal] is the exact sum of known contributions. [exactTotal] is
/// available only when every contribution was known. An incomplete product
/// ingredient therefore has no claimed total, only a known subtotal.
final class ChartSeriesTotal {
  const ChartSeriesTotal._({
    required this.exactTotal,
    required this.knownSubtotal,
    required this.knownContributions,
    required this.unknownContributions,
  });

  final ExactAmount? exactTotal;
  final ExactAmount knownSubtotal;
  final int knownContributions, unknownContributions;

  bool get complete => exactTotal != null;

  /// True only when every contribution was known, so [exactTotal] is the
  /// authoritative whole-range total. False when at least one contribution is
  /// unknown; [knownSubtotal] then holds the exact known part and must not be
  /// presented as the total.
  bool get isKnownTotal => exactTotal != null;

  /// True when at least one contribution had no exact amount. The UI labels
  /// this state with the approved `Known total` copy.
  bool get hasUnknownContributions => unknownContributions > 0;
}

/// One series over the whole viewport, plus its exact authoritative total.
final class ChartSeriesWindow {
  ChartSeriesWindow._({
    required this.key,
    required this.label,
    required this.viewport,
    required Iterable<ChartBucket> buckets,
    required this.total,
  }) : buckets = List.unmodifiable(buckets);

  final ChartSeriesKey key;

  /// Saved item or ingredient name. Not app copy.
  final String? label;

  final ChartViewport viewport;

  /// Non-empty buckets only, ascending. Never contains a zero placeholder.
  final List<ChartBucket> buckets;

  /// Folded from every contribution in the viewport, independently of how a
  /// widget later draws or pages points.
  final ChartSeriesTotal total;

  bool get isEmpty => buckets.isEmpty;

  int get bucketCount => buckets.length;

  /// Every viewport bucket in order, with explicit gaps.
  late final List<ChartSegment> segments = _buildSegments();

  /// Paged source request for one bucket, reusing the History cursor contract.
  ChartDrilldownRequest drilldown(
    ChartBucket bucket, {
    TimelineStatus status = TimelineStatus.all,
    int limit = ChartLimits.defaultDrilldownPageSize,
  }) => ChartDrilldownRequest(
    series: key,
    fromInstant: bucket.bounds.fromInstant,
    beforeInstant: bucket.bounds.beforeExclusive,
    displayZone: viewport.displayZone,
    status: status,
    limit: limit,
  );

  List<ChartSegment> _buildSegments() {
    final byIndex = <int, ChartBucket>{};
    for (final bucket in buckets) {
      final index = viewport.indexOf(bucket.bounds.fromInstant);
      if (index >= 0) byIndex[index] = bucket;
    }
    return List.unmodifiable([
      for (var index = 0; index < viewport.buckets.length; index++)
        byIndex[index] ?? ChartGap(viewport.buckets[index]),
    ]);
  }
}

/// One immutable, exact chart model for one person and bounded viewport.
///
/// The model contains no SQL, widget, plotting-engine or copy dependency. It
/// never sums across people, units, or item and ingredient subjects.
final class ChartModel {
  factory ChartModel.build({
    required ChartQuery query,
    required ChartObservationBatch batch,
    required int generation,
    Iterable<ChartAnnotation> annotations = const [],
    IanaClock? clock,
  }) {
    if (batch.truncated) {
      throw const ChartRangeException('range_too_large');
    }
    if (batch.personId != query.personId) {
      throw const ChartModelException('cross_person_chart');
    }
    if (batch.fromInstant != query.viewport.fromInstant ||
        batch.beforeInstant != query.viewport.beforeInstant) {
      throw const ChartModelException('batch_range');
    }
    final resolvedClock = clock ?? IanaClock();
    final accumulators = <String, _SeriesAccumulator>{};
    var voided = 0;

    void add({
      required ChartSeriesKey key,
      required ExactAmount amount,
      required String label,
      required ChartSourceRef source,
      required DateTime occurredAt,
    }) {
      if (query.focus != null && query.focus != key) return;
      final accumulator = accumulators.putIfAbsent(
        key.identity,
        () => _SeriesAccumulator(key),
      );
      accumulator.add(
        viewport: query.viewport,
        occurredAt: occurredAt,
        amount: amount,
        label: label,
        source: source,
      );
    }

    void markUnknown({
      required ChartSeriesKey key,
      required String label,
      required ChartSourceRef source,
      required DateTime occurredAt,
    }) {
      if (query.focus != null && query.focus != key) return;
      final accumulator = accumulators.putIfAbsent(
        key.identity,
        () => _SeriesAccumulator(key),
      );
      accumulator.markUnknown(
        label: label,
        source: source,
        occurredAt: occurredAt,
      );
    }

    for (final observation in batch.observations) {
      if (observation.isVoided) {
        voided++;
        continue;
      }
      add(
        key: ChartSeriesKey(
          personId: observation.personId,
          subject: ChartSubject.item(observation.itemId),
          unit: observation.unit,
        ),
        amount: observation.amount,
        label: observation.itemName,
        source: observation.source,
        occurredAt: observation.occurredAt,
      );
      final product = observation.product;
      if (product == null) continue;
      for (final componentAmount in product.components) {
        final component = componentAmount.component;
        final amount = componentAmount.amount;
        final key = ChartSeriesKey(
          personId: observation.personId,
          subject: ChartSubject.ingredient(component.ingredientId),
          unit: amount == null ? component.massUnit : 'mg',
        );
        if (amount == null) {
          markUnknown(
            key: key,
            label: component.name,
            source: observation.source,
            occurredAt: observation.occurredAt,
          );
        } else {
          add(
            key: key,
            amount: amount,
            label: component.name,
            source: observation.source,
            occurredAt: observation.occurredAt,
          );
        }
      }
    }
    final series =
        accumulators.values
            .map((accumulator) => accumulator.build(query.viewport))
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    final annotationSet = ChartAnnotationSet.bounded(
      viewport: query.viewport,
      personId: query.personId,
      annotations: annotations,
      clock: resolvedClock,
    );
    return ChartModel._(
      query: query,
      series: series,
      annotations: annotationSet,
      observationCount: batch.observationCount,
      voidedObservationCount: voided,
      token: ChartResultToken(
        generation: generation,
        queryIdentity: query.identity,
        schemaVersion: batch.schemaVersion,
        datasetGeneration: batch.datasetGeneration,
      ),
    );
  }

  const ChartModel._({
    required this.query,
    required this.series,
    required this.annotations,
    required this.observationCount,
    required this.voidedObservationCount,
    required this.token,
  });

  final ChartQuery query;
  final List<ChartSeriesWindow> series;
  final ChartAnnotationSet annotations;
  final int observationCount, voidedObservationCount;
  final ChartResultToken token;

  ChartViewport get viewport => query.viewport;

  int get schemaVersion => token.schemaVersion;

  String get datasetGeneration => token.datasetGeneration;

  bool get isEmpty => series.isEmpty;

  bool get isNotEmpty => series.isNotEmpty;

  List<ChartSeriesKey> get seriesKeys =>
      List.unmodifiable(series.map((window) => window.key));

  ChartSeriesWindow? seriesFor(ChartSeriesKey key) {
    for (final window in series) {
      if (window.key == key) return window;
    }
    return null;
  }
}

final class _SeriesAccumulator {
  _SeriesAccumulator(this.key);

  final ChartSeriesKey key;
  final Map<int, ExactAmount> _bucketTotals = <int, ExactAmount>{};
  final Map<int, int> _bucketCounts = <int, int>{};
  ExactAmount _known = ExactAmount.zero;
  int _knownCount = 0, _unknownCount = 0;
  String? _label;
  DateTime? _labelAt;
  String? _labelSource;

  void add({
    required ChartViewport viewport,
    required DateTime occurredAt,
    required ExactAmount amount,
    required String label,
    required ChartSourceRef source,
  }) {
    final index = viewport.indexOf(occurredAt);
    if (index < 0) throw const ChartModelException('observation_range');
    final previous = _bucketTotals[index];
    final nextBucket = previous == null ? amount : previous + amount;
    final nextTotal = _known + amount;
    if (_exceedsExactBound(nextBucket) || _exceedsExactBound(nextTotal)) {
      throw const ChartRangeException('exact_total_limit');
    }
    _bucketTotals[index] = nextBucket;
    _bucketCounts[index] = (_bucketCounts[index] ?? 0) + 1;
    _known = nextTotal;
    _knownCount++;
    _chooseLabel(label, occurredAt, source);
  }

  void markUnknown({
    required String label,
    required ChartSourceRef source,
    required DateTime occurredAt,
  }) {
    _unknownCount++;
    _chooseLabel(label, occurredAt, source);
  }

  void _chooseLabel(String label, DateTime occurredAt, ChartSourceRef source) {
    final previousAt = _labelAt;
    if (previousAt == null) {
      _label = label;
      _labelAt = occurredAt;
      _labelSource = source.sortKey;
      return;
    }
    final byTime = occurredAt.compareTo(previousAt);
    if (byTime > 0 ||
        (byTime == 0 && source.sortKey.compareTo(_labelSource ?? '') >= 0)) {
      _label = label;
      _labelAt = occurredAt;
      _labelSource = source.sortKey;
    }
  }

  ChartSeriesWindow build(ChartViewport viewport) {
    final indices = _bucketTotals.keys.toList()..sort();
    final buckets = [
      for (final index in indices)
        ChartBucket(
          bounds: viewport.buckets[index],
          series: key,
          amount: _bucketTotals[index]!,
          contributionCount: _bucketCounts[index]!,
        ),
    ];
    final complete = _unknownCount == 0;
    return ChartSeriesWindow._(
      key: key,
      label: _label,
      viewport: viewport,
      buckets: buckets,
      total: ChartSeriesTotal._(
        exactTotal: complete ? _known : null,
        knownSubtotal: _known,
        knownContributions: _knownCount,
        unknownContributions: _unknownCount,
      ),
    );
  }
}

bool _exceedsExactBound(ExactAmount value) =>
    value.numerator.bitLength > ChartLimits.maxExactBits ||
    value.denominator.bitLength > ChartLimits.maxExactBits;
