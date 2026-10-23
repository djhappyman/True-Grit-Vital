part of 'record_store.dart';

extension ScheduleStopStore on RecordStore {
  /// Resolve only recorded facts. Forecast depletion never ends a schedule.
  Future<PlanEnd?> _scheduleStop(DailyPlanVersion plan) async {
    final rule = plan.stopCondition;
    if (rule == null) return null;
    DateTime? reached;
    if (rule.total case final target?) {
      final rows = await _rows(
        '${RecordStore._current} WHERE a.person=? AND a.item=? AND r.voided=0 AND r.actual>=? ORDER BY r.actual,a.id LIMIT 100001',
        [plan.personId, plan.itemId, rule.from.microsecondsSinceEpoch],
      );
      if (rows.length > 100000) throw const CommandConflict('daily_read_bound');
      var sum = ExactAmount.zero;
      for (final row in rows) {
        final record = _record(row);
        final value = convertScheduleAmount(
          record.actualAmount,
          record.actualUnit,
          rule.unit!,
          record.labelledStrength ?? rule.strength,
        );
        if (value == null) throw const CommandConflict('course_amount_unknown');
        sum = sum + value;
        if (sum.numerator.bitLength > 65536 ||
            sum.denominator.bitLength > 65536) {
          throw const CommandConflict('daily_read_bound');
        }
        if (sum.compareTo(target) >= 0) {
          reached = record.actualAt.add(const Duration(microseconds: 1));
          break;
        }
      }
    } else {
      final source = await stockContainerById(
        personId: plan.personId,
        containerId: rule.containerId!,
      );
      if (source == null || source.itemId != plan.itemId) {
        throw const CommandConflict('stock_container');
      }
      final rows = await _rows(
        '${StockRecordStore._movementSelect} WHERE m.person=? AND m.container=? ORDER BY m.sequence LIMIT 100001',
        [plan.personId, source.id],
      );
      if (rows.length > 100000) throw const CommandConflict('daily_read_bound');
      ExactAmount? balance;
      var epoch = 0;
      final epochs = <String, int>{};
      for (final row in rows) {
        final movement = _stockMovement(row);
        if (!movement.recordedAt.isBefore(rule.from) &&
            balance != null &&
            balance <= ExactAmount.zero) {
          reached = rule.from;
          break;
        }
        if (movement.kind == StockMovementKind.reconciliation) epoch++;
        epochs[movement.id] = epoch;
        if (movement.reversesId != null &&
            epochs[movement.reversesId] != epoch) {
          continue;
        }
        balance = movement.kind == StockMovementKind.reconciliation
            ? movement.amount
            : balance == null || movement.amount == null
            ? null
            : balance + movement.amount!;
        if (balance != null &&
            (balance.numerator.bitLength > 65536 ||
                balance.denominator.bitLength > 65536)) {
          throw const CommandConflict('daily_read_bound');
        }
        if (!movement.recordedAt.isBefore(rule.from) &&
            balance != null &&
            balance <= ExactAmount.zero) {
          reached = movement.recordedAt.add(const Duration(microseconds: 1));
          break;
        }
      }
      if (reached == null && balance != null && balance <= ExactAmount.zero) {
        reached = rule.from;
      }
    }
    return reached == null
        ? null
        : PlanEnd(zoneId: rule.zone, exclusiveInstant: reached);
  }
}
