import '../history/display_time.dart';
import '../scheduling/daily_plan.dart';
import '../scheduling/iana_clock.dart';
import 'chart_limits.dart';
import 'chart_support.dart';
import 'chart_viewport.dart';

/// Factual boundary kinds a chart may annotate.
///
/// These are saved boundaries only. The chart domain never infers adherence,
/// a missed dose, a clinical reason or advice from an annotation.
enum ChartAnnotationKind {
  eventStart,
  eventEnd,
  planChanged,
  pauseStart,
  pauseEnd,
  phaseStart,
  phaseEnd,
  planEnd,
}

/// Exact instant or saved date-only position of an annotation.
///
/// A date-only end keeps its saved civil date and zone. It is never converted
/// to a fabricated midnight instant for display; [position] exists only to
/// order markers inside the bounded viewport.
final class ChartAnnotationDate {
  factory ChartAnnotationDate.exact(DateTime instant) {
    chartRequireUtc(instant, 'annotation_date');
    return ChartAnnotationDate._(
      instant: instant,
      civilDate: null,
      zoneId: null,
    );
  }

  factory ChartAnnotationDate.dateOnly({
    required CivilDate date,
    required String zoneId,
  }) {
    chartRequireText(zoneId, 'annotation_zone');
    return ChartAnnotationDate._(
      instant: null,
      civilDate: date,
      zoneId: zoneId,
    );
  }

  const ChartAnnotationDate._({
    required this.instant,
    required this.civilDate,
    required this.zoneId,
  });

  final DateTime? instant;
  final CivilDate? civilDate;
  final String? zoneId;

  bool get isDateOnly => instant == null;

  /// Ordering position. A date-only annotation resolves to the first instant
  /// of its saved civil date in its saved zone.
  DateTime position(IanaClock clock) {
    final exact = instant;
    if (exact != null) return exact;
    final date = civilDate;
    final zone = zoneId;
    if (date == null || zone == null) {
      throw const ChartModelException('annotation_date');
    }
    final bounds = DisplayTime(clock: clock).dayBounds(date, zone);
    if (bounds.isEmpty) {
      throw const ChartModelException('annotation_date');
    }
    return bounds.start;
  }
}

/// One factual event, plan, pause, phase or finite-end boundary.
///
/// [sourceId] is the saved event/plan/version identity. [label] retains the
/// saved name; authored app copy such as `Plan changed` belongs to the UI.
/// [sourceRevision] is optional because some plan boundaries have no revision.
final class ChartAnnotation {
  factory ChartAnnotation({
    required ChartAnnotationKind kind,
    required String sourceId,
    required String personId,
    required ChartAnnotationDate at,
    String? label,
    int? sourceRevision,
  }) {
    chartRequireText(sourceId, 'annotation_source');
    chartRequireText(personId, 'annotation_owner');
    chartRequireOptionalText(label, 'annotation_label', maxLength: 500);
    if (sourceRevision != null && sourceRevision < 1) {
      throw const ChartModelException('annotation_revision');
    }
    return ChartAnnotation._(
      kind: kind,
      sourceId: sourceId,
      personId: personId,
      at: at,
      label: label,
      sourceRevision: sourceRevision,
    );
  }

  const ChartAnnotation._({
    required this.kind,
    required this.sourceId,
    required this.personId,
    required this.at,
    required this.label,
    required this.sourceRevision,
  });

  final ChartAnnotationKind kind;
  final String sourceId;
  final String personId;
  final ChartAnnotationDate at;
  final String? label;
  final int? sourceRevision;

  DateTime position(IanaClock clock) => at.position(clock);
}

/// Annotations visible in one viewport, bounded and deterministically ordered.
///
/// When more than [ChartLimits.maxAnnotations] boundaries fall in the range,
/// the remainder is counted in [hiddenCount]. No annotation is allowed to change
/// a point value.
final class ChartAnnotationSet {
  const ChartAnnotationSet._({
    required this.visible,
    required this.hiddenCount,
    required this.consideredCount,
  });

  factory ChartAnnotationSet.bounded({
    required ChartViewport viewport,
    required String personId,
    required Iterable<ChartAnnotation> annotations,
    int maximum = ChartLimits.maxAnnotations,
    IanaClock? clock,
  }) {
    if (maximum < 1 || maximum > ChartLimits.maxAnnotations) {
      throw const ChartModelException('annotation_limit');
    }
    final resolvedClock = clock ?? IanaClock();
    final display = DisplayTime(clock: resolvedClock);
    final matching = <_PositionedAnnotation>[];
    final identities = <String>{};
    for (final annotation in annotations) {
      if (annotation.personId != personId) {
        throw const ChartModelException('annotation_owner');
      }
      if (!identities.add('${annotation.kind.name}|${annotation.sourceId}')) {
        throw const ChartModelException('annotation_duplicate');
      }
      final position = annotation.position(resolvedClock);
      final bool overlaps;
      if (annotation.at.isDateOnly) {
        final date = annotation.at.civilDate!;
        final zone = annotation.at.zoneId!;
        final bounds = display.dayBounds(date, zone);
        overlaps =
            !bounds.isEmpty &&
            bounds.start.isBefore(viewport.beforeInstant) &&
            bounds.endExclusive.isAfter(viewport.fromInstant);
      } else {
        overlaps = viewport.contains(position);
      }
      if (overlaps) {
        matching.add(_PositionedAnnotation(annotation, position));
      }
    }
    matching.sort((a, b) {
      final byInstant = a.position.compareTo(b.position);
      if (byInstant != 0) return byInstant;
      final byKind = a.annotation.kind.index.compareTo(b.annotation.kind.index);
      if (byKind != 0) return byKind;
      return a.annotation.sourceId.compareTo(b.annotation.sourceId);
    });
    final visible = matching.length > maximum
        ? matching.sublist(0, maximum)
        : matching;
    return ChartAnnotationSet._(
      visible: List.unmodifiable(visible.map((entry) => entry.annotation)),
      hiddenCount: matching.length - visible.length,
      consideredCount: matching.length,
    );
  }

  final List<ChartAnnotation> visible;
  final int hiddenCount;
  final int consideredCount;

  bool get isEmpty => visible.isEmpty;

  bool get isComplete => hiddenCount == 0;
}

final class _PositionedAnnotation {
  const _PositionedAnnotation(this.annotation, this.position);

  final ChartAnnotation annotation;
  final DateTime position;
}
