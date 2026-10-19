import '../history/display_time.dart';
import '../scheduling/daily_plan.dart';
import '../scheduling/iana_clock.dart';
import 'chart_limits.dart';
import 'chart_support.dart';

/// Bucket granularity in the display zone. There is no implicit downsampling:
/// a wider range uses an explicitly coarser size or a shorter range.
enum ChartBucketSize { day, week, month }

/// Half-open UTC bounds of one chart bucket and its civil label range.
///
/// [zoneId] is the zone actually used. An unavailable requested zone shows UTC
/// and sets [zoneFallback], matching the shared display-time policy.
final class ChartBucketBounds {
  const ChartBucketBounds._({
    required this.fromInstant,
    required this.beforeExclusive,
    required this.civilStart,
    required this.civilEndInclusive,
    required this.zoneId,
    required this.zoneFallback,
  });

  /// Inclusive UTC start.
  final DateTime fromInstant;

  /// Exclusive UTC end.
  final DateTime beforeExclusive;

  /// First civil date of the bucket in the shown zone.
  final CivilDate civilStart;

  /// Last civil date of the bucket in the shown zone. Inclusive.
  final CivilDate civilEndInclusive;

  final String zoneId;
  final bool zoneFallback;

  Duration get duration => beforeExclusive.difference(fromInstant);

  bool get isEmpty => !beforeExclusive.isAfter(fromInstant);

  bool get isSingleCivilDate => civilStart == civilEndInclusive;

  bool contains(DateTime instant) {
    final utc = instant.toUtc();
    return !utc.isBefore(fromInstant) && utc.isBefore(beforeExclusive);
  }

  @override
  String toString() =>
      '${civilStart.toString()}..${civilEndInclusive.toString()} '
      '[$fromInstant, $beforeExclusive) $zoneId';
}

/// One bounded, explicit viewport.
///
/// Buckets are contiguous half-open ranges that exactly cover
/// `[fromInstant, beforeInstant)`. The first and last buckets may be partial
/// civil periods; a gap inside the range is represented by the model, never by
/// a zero amount.
///
/// [zoneId]/[zoneFallback] describe the requested zone resolution. A bucket's
/// own [ChartBucketBounds.zoneId]/[ChartBucketBounds.zoneFallback] describe the
/// zone actually used for that bucket: an instant outside the verified clock
/// range falls back to UTC for that bucket even when the zone id is valid.
final class ChartViewport {
  factory ChartViewport({
    required DateTime fromInstant,
    required DateTime beforeInstant,
    required String displayZone,
    ChartBucketSize bucketSize = ChartBucketSize.day,
    IanaClock? clock,
  }) {
    chartRequireUtc(fromInstant, 'invalid_range');
    chartRequireUtc(beforeInstant, 'invalid_range');
    if (!beforeInstant.isAfter(fromInstant)) {
      throw const ChartRangeException('invalid_range');
    }
    if (displayZone.isEmpty ||
        displayZone.trim().isEmpty ||
        displayZone.length > 256) {
      throw const ChartRangeException('invalid_zone');
    }
    final resolvedClock = clock ?? IanaClock();
    final display = DisplayTime(clock: resolvedClock);
    final zone = display.resolveZone(displayZone);
    _checkRoughDuration(fromInstant, beforeInstant, bucketSize);
    final buckets = _buildBuckets(
      display: display,
      zone: zone,
      fromInstant: fromInstant,
      beforeInstant: beforeInstant,
      bucketSize: bucketSize,
    );
    if (buckets.isEmpty) {
      throw const ChartRangeException('invalid_range');
    }
    return ChartViewport._(
      fromInstant: fromInstant,
      beforeInstant: beforeInstant,
      displayZone: displayZone,
      bucketSize: bucketSize,
      zoneId: zone.zoneId,
      zoneFallback: zone.isFallback,
      buckets: buckets,
      clock: resolvedClock,
    );
  }

  const ChartViewport._({
    required this.fromInstant,
    required this.beforeInstant,
    required this.displayZone,
    required this.bucketSize,
    required this.zoneId,
    required this.zoneFallback,
    required this.buckets,
    required this._clock,
  });

  final DateTime fromInstant, beforeInstant;

  /// Requested IANA id, retained for query identity.
  final String displayZone;

  final ChartBucketSize bucketSize;

  /// Zone actually used for civil labels.
  final String zoneId;

  final bool zoneFallback;

  final List<ChartBucketBounds> buckets;

  final IanaClock _clock;

  int get bucketCount => buckets.length;

  bool contains(DateTime instant) {
    final utc = instant.toUtc();
    return !utc.isBefore(fromInstant) && utc.isBefore(beforeInstant);
  }

  /// Index of the bucket containing [instant], or -1 outside the viewport.
  int indexOf(DateTime instant) {
    final utc = instant.toUtc();
    if (!contains(utc)) return -1;
    var low = 0;
    var high = buckets.length - 1;
    while (low < high) {
      final middle = (low + high + 1) >> 1;
      if (!buckets[middle].fromInstant.isAfter(utc)) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return buckets[low].contains(utc) ? low : -1;
  }

  /// The next coarser explicit granularity for the same range.
  ///
  /// This is a caller choice, not an automatic reduction inside the model. The
  /// returned viewport still enforces [ChartLimits.maxBuckets].
  ChartViewport coarsen() => switch (bucketSize) {
    ChartBucketSize.day => withBucketSize(ChartBucketSize.week),
    ChartBucketSize.week => withBucketSize(ChartBucketSize.month),
    ChartBucketSize.month => this,
  };

  ChartViewport withBucketSize(ChartBucketSize value) => ChartViewport(
    fromInstant: fromInstant,
    beforeInstant: beforeInstant,
    displayZone: displayZone,
    bucketSize: value,
    clock: _clock,
  );

  static void _checkRoughDuration(
    DateTime fromInstant,
    DateTime beforeInstant,
    ChartBucketSize bucketSize,
  ) {
    final days = beforeInstant.difference(fromInstant).inDays + 1;
    final maximumDays = switch (bucketSize) {
      ChartBucketSize.day => ChartLimits.maxBuckets + 2,
      ChartBucketSize.week => ChartLimits.maxBuckets * 7 + 8,
      ChartBucketSize.month => ChartLimits.maxBuckets * 31 + 40,
    };
    if (days > maximumDays) {
      throw const ChartRangeException('too_many_buckets');
    }
  }

  static List<ChartBucketBounds> _buildBuckets({
    required DisplayTime display,
    required DisplayZone zone,
    required DateTime fromInstant,
    required DateTime beforeInstant,
    required ChartBucketSize bucketSize,
  }) {
    final buckets = <ChartBucketBounds>[];
    var cursor = fromInstant;
    while (cursor.isBefore(beforeInstant)) {
      final boundary = _nextBoundary(
        display: display,
        zone: zone,
        fromInstant: cursor,
        bucketSize: bucketSize,
      );
      final end = boundary.isBefore(beforeInstant) ? boundary : beforeInstant;
      if (!end.isAfter(cursor)) {
        throw const ChartRangeException('invalid_range');
      }
      final startInfo = display.instant(cursor, zone.zoneId);
      final lastInfo = display.instant(
        end.subtract(const Duration(microseconds: 1)),
        zone.zoneId,
      );
      buckets.add(
        ChartBucketBounds._(
          fromInstant: cursor,
          beforeExclusive: end,
          civilStart: startInfo.civilDate,
          civilEndInclusive: lastInfo.civilDate,
          zoneId: startInfo.zoneId,
          zoneFallback: startInfo.zoneFallback,
        ),
      );
      if (buckets.length > ChartLimits.maxBuckets) {
        throw const ChartRangeException('too_many_buckets');
      }
      cursor = end;
    }
    return List.unmodifiable(buckets);
  }

  static DateTime _nextBoundary({
    required DisplayTime display,
    required DisplayZone zone,
    required DateTime fromInstant,
    required ChartBucketSize bucketSize,
  }) {
    final date = display.instant(fromInstant, zone.zoneId).civilDate;
    final boundaryDate = switch (bucketSize) {
      ChartBucketSize.day => date.addDays(1),
      ChartBucketSize.week => _nextWeekStart(date),
      ChartBucketSize.month => _nextMonthStart(date),
    };
    // A civil date can be missing in a zone (for example Pacific/Apia on
    // 2011-12-30). Search the next dates rather than inventing a zero bucket.
    for (var offset = 0; offset <= 2; offset++) {
      final bounds = display.dayBounds(
        boundaryDate.addDays(offset),
        zone.zoneId,
      );
      if (!bounds.isEmpty && bounds.start.isAfter(fromInstant)) {
        return bounds.start;
      }
    }
    throw const ChartRangeException('invalid_range');
  }

  static CivilDate _nextWeekStart(CivilDate date) {
    var candidate = date.addDays(1);
    while (candidate.calendarValue.weekday != DateTime.monday) {
      candidate = candidate.addDays(1);
    }
    return candidate;
  }

  static CivilDate _nextMonthStart(CivilDate date) {
    if (date.year > 9999 || (date.year == 9999 && date.month == 12)) {
      throw const ChartRangeException('invalid_range');
    }
    return date.month == 12
        ? CivilDate(date.year + 1, 1, 1)
        : CivilDate(date.year, date.month + 1, 1);
  }
}
