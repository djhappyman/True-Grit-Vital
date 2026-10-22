import '../history/display_time.dart';
import '../scheduling/daily_plan.dart' show CivilDate;
import '../stock/exact_amount.dart';
import 'supporting_date.dart';
import 'supporting_record.dart';
import 'supporting_trend.dart';
import 'supporting_value.dart';

/// Why an earlier comparable value is or is not shown for a viewed result.
enum SupportingEarlierStatus {
  /// A comparable current result before the viewed collection date was found.
  found,

  /// The bounded window contained no comparable earlier result.
  none,

  /// The viewed collection date cannot be positioned, so no comparison is
  /// claimed.
  incomplete,

  /// The viewed result or its source identity cannot be compared without
  /// inventing missing information.
  incompatible,

  /// No earlier result was found inside the bounded window. Older records were
  /// not read, so the absence is not global.
  truncated,
}

final class SupportingEarlierValue {
  const SupportingEarlierValue({required this.record, required this.result});
  final SupportingRevision record;
  final LabResultSnapshot result;
}

final class SupportingEarlierComparison {
  const SupportingEarlierComparison({
    required this.status,
    this.earlier,
    this.change,
  });
  final SupportingEarlierStatus status;
  final SupportingEarlierValue? earlier;

  /// Exact short decimal change from the earlier value to the viewed value.
  /// Null when no earlier value exists or when the exact difference has no
  /// short terminating decimal form. It is never rounded.
  final String? change;

  bool get found => status == SupportingEarlierStatus.found;
  bool get changeUnavailable => found && change == null;
}

/// Finds the newest current result before [viewed]'s collection date with the
/// same comparison identity and comparable value kind.
///
/// [candidates] may contain the viewed record and newer records; both are
/// ignored. A same-day result is accepted only when both dates are exact and
/// the candidate instant is strictly earlier. A day-only date never supplies a
/// clock time, so a same-day pair stays ambiguous rather than guessed.
SupportingEarlierComparison supportingEarlierComparison({
  required SupportingRevision viewed,
  required LabResultSnapshot result,
  required Iterable<SupportingRevision> candidates,
  required String displayZone,
  bool windowLimited = false,
}) {
  final viewedDate = viewed.snapshot.collectionDate;
  final viewedDay = _positionDay(viewedDate, displayZone);
  if (viewedDay == null) {
    return const SupportingEarlierComparison(
      status: SupportingEarlierStatus.incomplete,
    );
  }
  final viewedKey = SupportingComparisonKey.forResult(viewed, result);
  final viewedValue = result.value;
  final exact = viewedValue.isExactNumeric;
  final qualitative = viewedValue.kind == SupportingValueKind.qualitative;
  if (!viewedKey.certain || !(exact || qualitative)) {
    return const SupportingEarlierComparison(
      status: SupportingEarlierStatus.incompatible,
    );
  }
  SupportingRevision? bestRecord;
  LabResultSnapshot? bestResult;
  CivilDate? bestDay;
  DateTime? bestInstant;
  final current = <String, SupportingRevision>{};
  for (final candidate in candidates) {
    final previous = current[candidate.id.id];
    if (previous == null || candidate.revision > previous.revision) {
      current[candidate.id.id] = candidate;
    }
  }
  var ambiguous = false;
  for (final candidate in current.values) {
    if (candidate.id.id == viewed.id.id || candidate.isVoided) continue;
    final date = candidate.snapshot.collectionDate;
    final day = _positionDay(date, displayZone);
    if (day == null) continue;
    if (!_strictlyEarlier(
      date: date,
      day: day,
      viewedDate: viewedDate,
      viewedDay: viewedDay,
    )) {
      continue;
    }
    for (final row in candidate.snapshot.results) {
      if (row.metricId != result.metricId) continue;
      final rowKey = SupportingComparisonKey.forResult(candidate, row);
      if (!rowKey.certain || rowKey != viewedKey) continue;
      final rowValue = row.value;
      if (exact
          ? !rowValue.isExactNumeric
          : rowValue.kind != SupportingValueKind.qualitative) {
        continue;
      }
      // Keep the newest qualifying point. A later exact instant wins inside one
      // displayed day; ties stay deterministic by record and result identity.
      final newer = bestDay == null || day.compareTo(bestDay) > 0;
      final sameDay = bestDay != null && day == bestDay;
      final laterInstant =
          sameDay &&
          date.instant != null &&
          (bestInstant == null || date.instant!.isAfter(bestInstant));
      final tied =
          sameDay &&
          date.instant == bestInstant &&
          (bestRecord == null ||
              candidate.id.id.compareTo(bestRecord.id.id) > 0);
      if (newer) ambiguous = false;
      if (sameDay &&
          (date.instant == null ||
              bestInstant == null ||
              date.instant == bestInstant)) {
        ambiguous = true;
      }
      if (newer || laterInstant || tied) {
        bestRecord = candidate;
        bestResult = row;
        bestDay = day;
        bestInstant = date.instant;
      }
    }
  }
  if (ambiguous) {
    return const SupportingEarlierComparison(
      status: SupportingEarlierStatus.incomplete,
    );
  }
  if (bestRecord == null || bestResult == null) {
    return SupportingEarlierComparison(
      status: windowLimited
          ? SupportingEarlierStatus.truncated
          : SupportingEarlierStatus.none,
    );
  }
  return SupportingEarlierComparison(
    status: SupportingEarlierStatus.found,
    earlier: SupportingEarlierValue(record: bestRecord, result: bestResult),
    change: exact
        ? supportingExactChange(
            result.value.exactAmount!,
            bestResult.value.exactAmount!,
          )
        : null,
  );
}

CivilDate? _positionDay(SupportingDate date, String displayZone) =>
    switch (date.precision) {
      SupportingDatePrecision.day => date.civilDate,
      SupportingDatePrecision.exact =>
        DisplayTime().instant(date.instant!, displayZone).civilDate,
      SupportingDatePrecision.unknown ||
      SupportingDatePrecision.partial => null,
    };

bool _strictlyEarlier({
  required SupportingDate date,
  required CivilDate day,
  required SupportingDate viewedDate,
  required CivilDate viewedDay,
}) {
  final byDay = day.compareTo(viewedDay);
  if (byDay != 0) return byDay < 0;
  return date.precision == SupportingDatePrecision.exact &&
      viewedDate.precision == SupportingDatePrecision.exact &&
      date.instant!.isBefore(viewedDate.instant!);
}

/// A change is shown only when it has an exact short decimal form. A repeating
/// or very long fraction is omitted rather than rounded into a false value.
String? supportingExactChange(ExactAmount latest, ExactAmount previous) {
  final change = latest - previous;
  if (change == ExactAmount.zero) return '0';
  var denominator = change.denominator;
  var twos = 0, fives = 0;
  while (denominator % BigInt.two == BigInt.zero) {
    denominator ~/= BigInt.two;
    twos++;
  }
  while (denominator % BigInt.from(5) == BigInt.zero) {
    denominator ~/= BigInt.from(5);
    fives++;
  }
  if (denominator != BigInt.one) return null;
  final places = twos > fives ? twos : fives;
  if (places > 6) return null;
  final text = change.roundedDecimal(places: places);
  return text.startsWith('-') ? text : '+$text';
}
