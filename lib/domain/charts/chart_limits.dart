/// Bounded chart limits.
///
/// Every bound is a typed failure at the domain boundary. A chart never
/// samples, smooths or silently truncates to fit one of these values.
abstract final class ChartLimits {
  /// Parent source rows one chart read may return. A read that would exceed
  /// this stops and reports `range_too_large` instead of approximating.
  static const maxSourceRows = 10000;

  /// Buckets one viewport may materialise. A wider range needs an explicitly
  /// coarser [ChartBucketSize], not automatic downsampling.
  static const maxBuckets = 400;

  /// Factual annotations shown per viewport. The remainder is counted, not
  /// discarded silently.
  static const maxAnnotations = 200;

  /// Rational bit bound for one folded total. A contribution that would exceed
  /// this is a typed failure, never a rounded or partial total.
  static const maxExactBits = 65536;

  static const defaultDrilldownPageSize = 25;
  static const maxDrilldownPageSize = 50;
}

/// A chart input or model invariant failed.
///
/// Codes are stable for the UI/data boundary. The reader must not weaken a
/// failure into a plausible-looking chart.
final class ChartModelException implements Exception {
  const ChartModelException(this.code);

  final String code;

  @override
  String toString() => 'ChartModelException($code)';
}

/// A bounded chart range, viewport or source read was rejected.
final class ChartRangeException implements Exception {
  const ChartRangeException(this.code);

  final String code;

  @override
  String toString() => 'ChartRangeException($code)';
}
