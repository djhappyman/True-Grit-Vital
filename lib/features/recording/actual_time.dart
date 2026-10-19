/// Finds every instant represented by a local wall clock. The injected mapping
/// makes clock changes testable without changing the machine's timezone.
List<DateTime> actualTimeCandidates(
  DateTime wallClock, {
  DateTime Function(DateTime)? localize,
  Iterable<Duration>? offsets,
}) {
  final convert = localize ?? (instant) => instant.toLocal();
  final basis = DateTime.utc(
    wallClock.year,
    wallClock.month,
    wallClock.day,
    wallClock.hour,
    wallClock.minute,
  );
  final nearbyOffsets =
      offsets ??
      {
        for (var hours = -48; hours <= 48; hours += 6)
          convert(basis.add(Duration(hours: hours))).timeZoneOffset,
      };
  final candidates = <DateTime>[];
  for (final offset in nearbyOffsets) {
    final instant = basis.subtract(offset);
    final local = convert(instant);
    if (local.year == basis.year &&
        local.month == basis.month &&
        local.day == basis.day &&
        local.hour == basis.hour &&
        local.minute == basis.minute) {
      if (!candidates.any((c) => c.isAtSameMomentAs(instant))) {
        candidates.add(instant);
      }
    }
  }
  candidates.sort();
  return candidates;
}

String utcOffset(Duration offset) {
  final minutes = offset.inMinutes.abs();
  return 'UTC${offset.isNegative ? '-' : '+'}${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
}
