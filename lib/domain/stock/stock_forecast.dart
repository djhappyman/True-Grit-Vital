import 'stored_stock.dart';
import '../scheduling/daily_plan.dart';
import '../scheduling/daily_resolver.dart';
import '../scheduling/iana_clock.dart';
import '../scheduling/phase_plan.dart';

/// Why a schedule-based run-out estimate is not shown.
///
/// Each reason is a factual boundary, never a guessed date. The UI maps it to
/// one complete localised message.
enum StockForecastReason {
  asNeeded,
  unscheduled,
  paused,
  unknownBalance,
  deficit,
  emptyBalance,
  aggregateLimit,
  missingAmount,
  incompatibleUnits,
  unresolvedZone,
  unresolvedClock,
  unsupportedSchedule,
  intervalSchedule,
  planEndsFirst,
  completeAfterHorizon,
  noPlannedUse,
}

/// One conditional run-out projection.
///
/// It assumes this container supplies every planned dose for the substance.
/// No dose is shared across containers and no actual-use average is inferred.
final class StockRunOutForecast {
  const StockRunOutForecast.available({
    required this.date,
    required this.days,
    required this.plannedThrough,
  }) : reason = null,
       throughDate = null;
  const StockRunOutForecast.unavailable(this.reason, {this.throughDate})
    : date = null,
      days = null,
      plannedThrough = null;

  final CivilDate? date;
  final int? days;
  final StockForecastReason? reason;
  final CivilDate? throughDate;
  final CivilDate? plannedThrough;

  bool get isAvailable => date != null;
}

/// Default bounded calculation window. The UI never prints this number as a
/// promise; passing the bound is reported as "more than a year".
const stockForecastHorizonDays = 366;

/// Bounded fixed-interval occurrence work for one projection.
///
/// A schedule with more occurrences inside the window stays explicitly
/// unavailable rather than returning a silently truncated or guessed date.
const stockForecastMaxIntervalOccurrences = 50000;

/// A resolver issue that prevents a truthful run-out day.
StockForecastReason _forecastExpansionReason(DailyCalculationIssue? issue) =>
    switch (issue) {
      DailyCalculationIssue.unsupportedTimezoneRange ||
      DailyCalculationIssue.observedZoneUnavailable =>
        StockForecastReason.unresolvedZone,
      DailyCalculationIssue.intervalNoAnchor =>
        StockForecastReason.intervalSchedule,
      _ => StockForecastReason.unsupportedSchedule,
    };

/// Planned use from tomorrow in the plan's own zone. Today's remaining planned
/// use is deliberately excluded because already-recorded doses cannot be
/// separated from untimed once-daily plans without guessing.
StockRunOutForecast forecastStockRunOut({
  required StockBalance balance,
  required String unit,
  required LabelledStrength strength,
  required Iterable<PhasePlan> plans,
  required DateTime now,
  required String? observedZone,
  int horizonDays = stockForecastHorizonDays,
}) {
  if (horizonDays < 1) throw ArgumentError('stock_forecast_horizon');
  if (balance.limitReached) {
    return const StockRunOutForecast.unavailable(
      StockForecastReason.aggregateLimit,
    );
  }
  final remainingAtStart = balance.value;
  if (remainingAtStart == null) {
    return const StockRunOutForecast.unavailable(
      StockForecastReason.unknownBalance,
    );
  }
  if (remainingAtStart < ExactAmount.zero) {
    return const StockRunOutForecast.unavailable(StockForecastReason.deficit);
  }
  if (remainingAtStart == ExactAmount.zero) {
    return const StockRunOutForecast.unavailable(
      StockForecastReason.emptyBalance,
    );
  }
  if (plans.isEmpty) {
    return const StockRunOutForecast.unavailable(
      StockForecastReason.unscheduled,
    );
  }

  final scheduled = <PhasePlan>[];
  var anyAsNeeded = false;
  for (final plan in plans) {
    final timings = plan.phases.map((phase) => phase.timing).toList();
    if (timings.any(
      (timing) =>
          timing is ElapsedInterval &&
          timing.mode == IntervalMode.qualifyingActual,
    )) {
      // This projection has no captured future anchor. Deriving further doses
      // from the last actual would invent use the person never reported.
      return const StockRunOutForecast.unavailable(
        StockForecastReason.intervalSchedule,
      );
    }
    final hasScheduled = timings.any((timing) => timing is! AsNeeded);
    if (!hasScheduled) {
      anyAsNeeded = true;
      continue;
    }
    if (timings.any((timing) => timing is AsNeeded)) {
      // A plan that changes to as-needed use has no bounded future amount.
      // Returning a date would silently ignore that part of the schedule.
      return const StockRunOutForecast.unavailable(
        StockForecastReason.asNeeded,
      );
    }
    scheduled.add(plan);
  }
  if (scheduled.isEmpty) {
    return StockRunOutForecast.unavailable(
      anyAsNeeded
          ? StockForecastReason.asNeeded
          : StockForecastReason.unscheduled,
    );
  }

  if (anyAsNeeded) {
    return const StockRunOutForecast.unavailable(StockForecastReason.asNeeded);
  }

  final clock = IanaClock();
  String? zoneId;
  for (final plan in scheduled) {
    for (final phase in plan.phases) {
      final resolved = phase.zoneBasis.zoneFor(observedZone ?? '');
      if (resolved.isEmpty) {
        return const StockRunOutForecast.unavailable(
          StockForecastReason.unresolvedZone,
        );
      }
      try {
        clock.validateZone(resolved);
      } on Object {
        return const StockRunOutForecast.unavailable(
          StockForecastReason.unresolvedZone,
        );
      }
      if (zoneId == null) {
        zoneId = resolved;
      } else if (zoneId != resolved) {
        // A forecast spanning two zones cannot name one civil run-out day.
        return const StockRunOutForecast.unavailable(
          StockForecastReason.unsupportedSchedule,
        );
      }
    }
  }
  final zone = zoneId!;
  final CivilDate today;
  try {
    today = clock.dateAt(now, zone);
  } on Object {
    return const StockRunOutForecast.unavailable(
      StockForecastReason.unresolvedZone,
    );
  }

  for (final plan in scheduled) {
    for (final phase in plan.phases) {
      if (phase.includes(today) &&
          phase.includesInstant(now) &&
          phase.pauses.any(
            (pause) => pause.contains(now) && pause.resume == null,
          )) {
        return const StockRunOutForecast.unavailable(
          StockForecastReason.paused,
        );
      }
    }
  }

  CivilDate? latestPlanEnd;
  for (final plan in scheduled) {
    final end = plan.end;
    if (end == null) {
      latestPlanEnd = null;
      break;
    }
    final lastDate = clock.dateAt(
      end.exclusiveInstant.subtract(const Duration(microseconds: 1)),
      end.zoneId,
    );
    if (latestPlanEnd == null || lastDate.compareTo(latestPlanEnd) > 0) {
      latestPlanEnd = lastDate;
    }
  }

  final resolver = PhaseResolver(clock: clock);
  final horizonEnd = today.addDays(horizonDays);
  var remaining = remainingAtStart;
  var planned = false;
  var intervalOccurrences = 0;
  for (var day = 1; day <= horizonDays; day++) {
    final date = today.addDays(day);
    var dayTotal = ExactAmount.zero;
    for (final plan in scheduled) {
      List<DailyExpectation> rows;
      try {
        // The shared resolver owns phase dates, pauses, exact totals and
        // elapsed-interval arithmetic. Reading completeness avoids treating a
        // bounded or unsupported composition as a paused or empty day.
        final expansion = resolver.expand(
          plan,
          from: date,
          toExclusive: date.addDays(1),
          observedZone: zone,
          maxDates: 100000,
          // Bound expansion itself, before allocating the returned rows.
          maxRows:
              stockForecastMaxIntervalOccurrences - intervalOccurrences + 1,
          now: now,
        );
        if (!expansion.complete) {
          return StockRunOutForecast.unavailable(
            _forecastExpansionReason(expansion.issue),
          );
        }
        rows = expansion.rows;
      } on UnsupportedError {
        return const StockRunOutForecast.unavailable(
          StockForecastReason.unsupportedSchedule,
        );
      } on StateError {
        return const StockRunOutForecast.unavailable(
          StockForecastReason.unsupportedSchedule,
        );
      } on Object {
        return const StockRunOutForecast.unavailable(
          StockForecastReason.unresolvedZone,
        );
      }
      for (final row in rows) {
        if (row.identity.intervalSegmentId != null) {
          intervalOccurrences++;
          if (intervalOccurrences > stockForecastMaxIntervalOccurrences) {
            // The bound is disclosed instead of truncating the sequence or
            // pretending the remaining stock lasts forever.
            return const StockRunOutForecast.unavailable(
              StockForecastReason.unsupportedSchedule,
            );
          }
        }
        if (row.eligibilityConflict != null) {
          return const StockRunOutForecast.unavailable(
            StockForecastReason.unsupportedSchedule,
          );
        }
        if (row.resolution == DailyResolution.missingClock ||
            row.resolution == DailyResolution.repeatedClock) {
          return const StockRunOutForecast.unavailable(
            StockForecastReason.unresolvedClock,
          );
        }
        final quantity = ExactAmount(
          BigInt.from(row.amount.quantity.scaled),
          BigInt.from(1000000),
        );
        if (quantity <= ExactAmount.zero) {
          return const StockRunOutForecast.unavailable(
            StockForecastReason.missingAmount,
          );
        }
        final converted = strength.equivalent(
          quantity,
          from: row.amount.unit,
          to: unit,
        );
        if (converted == null) {
          return const StockRunOutForecast.unavailable(
            StockForecastReason.incompatibleUnits,
          );
        }
        final count = row.plannedCount ?? 1;
        dayTotal += converted * ExactAmount(BigInt.from(count));
      }
    }
    if (dayTotal <= ExactAmount.zero) continue;
    planned = true;
    remaining -= dayTotal;
    if (remaining <= ExactAmount.zero) {
      return StockRunOutForecast.available(
        date: date,
        days: day,
        plannedThrough: date,
      );
    }
  }
  if (!planned) {
    return const StockRunOutForecast.unavailable(
      StockForecastReason.noPlannedUse,
    );
  }
  if (latestPlanEnd != null && latestPlanEnd.compareTo(horizonEnd) <= 0) {
    return StockRunOutForecast.unavailable(
      StockForecastReason.planEndsFirst,
      throughDate: latestPlanEnd,
    );
  }
  return const StockRunOutForecast.unavailable(
    StockForecastReason.completeAfterHorizon,
  );
}
