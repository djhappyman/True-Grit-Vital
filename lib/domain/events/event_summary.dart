/// Whole-event current facts, independent of the visible history page.
final class EventUseSummary {
  const EventUseSummary({
    required this.generation,
    required this.eventRevision,
    required this.substances,
    this.recorded,
    this.skipped,
    this.skippedTimesNeedReview = false,
  });
  final String generation;
  final int eventRevision, substances;
  // Null means the stored event dates require review, never a fabricated zero.
  final int? recorded, skipped;
  final bool skippedTimesNeedReview;
  bool get boundsNeedReview => recorded == null;
}
