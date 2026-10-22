import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/history/display_time.dart';
import 'package:true_grit_vital/domain/scheduling/daily_plan.dart';
import 'package:true_grit_vital/features/reports/report_dates.dart';

void main() {
  final now = DateTime.utc(2026, 10, 22);
  test('explicit invalid or unordered dates never use defaults', () {
    for (final value in [
      '',
      'bad',
      '2025-02-29',
      '2026-02-30',
      '2026-13-01',
      '0000-01-01',
      '10000-01-01',
      ' 2026-01-01',
      '2026-01-01T00:00:00Z',
    ]) {
      expect(
        reportSeedRange(now: now, displayZone: 'UTC', from: value),
        isNull,
      );
      expect(
        reportSeedRange(now: now, displayZone: 'UTC', before: value),
        isNull,
      );
    }
    for (final before in ['2026-01-01', '2025-12-31', '0001-01-01']) {
      expect(
        reportSeedRange(
          now: now,
          displayZone: 'UTC',
          from: '2026-01-01',
          before: before,
        ),
        isNull,
      );
    }
  });
  test('valid leap day and exclusive civil year edges remain exact', () {
    for (final (from, before, through) in [
      ('2024-02-29', '2024-03-01', '2024-02-29'),
      ('0001-01-01', '0001-01-02', '0001-01-01'),
      ('9999-12-30', '9999-12-31', '9999-12-30'),
    ]) {
      final range = reportSeedRange(
        now: DateTime.utc(9999, 12, 31),
        displayZone: 'UTC',
        from: from,
        before: before,
      )!;
      expect(range.from.toString(), from);
      expect(range.before.toString(), before);
      expect(range.through.toString(), through);
    }
    expect(
      reportSeedRange(now: DateTime.utc(9999, 12, 31), displayZone: 'UTC'),
      isNull,
    );
    expect(reportThroughRange('9999-12-30', '9999-12-31'), isNull);
    expect(
      reportThroughRange('9999-12-30', '9999-12-30')!.before,
      CivilDate(9999, 12, 31),
    );
  });
  test('defaults use the display day across DST and a civil year boundary', () {
    for (final (instant, before) in [
      (DateTime.utc(2026, 3, 29, 23, 30), CivilDate(2026, 3, 31)),
      (DateTime.utc(2026, 10, 25, 23, 30), CivilDate(2026, 10, 26)),
    ]) {
      final range = reportSeedRange(
        now: instant,
        displayZone: 'Europe/London',
      )!;
      expect(range.before, before);
    }
    final year = reportSeedRange(
      now: DateTime.utc(2026, 12, 31, 12),
      displayZone: 'Pacific/Kiritimati',
    )!;
    expect(year.from, CivilDate(2027, 1, 1));
    expect(year.before, CivilDate(2027, 1, 2));
    expect(
      DisplayTime()
          .dayBounds(CivilDate(2026, 3, 29), 'Europe/London')
          .duration
          .inHours,
      23,
    );
    expect(
      DisplayTime()
          .dayBounds(CivilDate(2026, 10, 25), 'Europe/London')
          .duration
          .inHours,
      25,
    );
  });
  test('unavailable zone/current projection never guesses a range', () {
    expect(reportSeedRange(now: now, displayZone: 'No/SuchZone'), isNull);
    expect(
      reportSeedRange(
        now: DateTime.utc(9999, 1, 1),
        displayZone: 'Europe/London',
      ),
      isNull,
    );
    expect(
      reportSeedRange(now: DateTime.utc(10000, 1, 1), displayZone: 'UTC'),
      isNull,
    );
  });
}
