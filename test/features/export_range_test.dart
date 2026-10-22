import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/reports/report_period.dart';
import 'package:true_grit_vital/domain/scheduling/daily_plan.dart';
import 'package:true_grit_vital/features/exports/export_range.dart';

void main() {
  group('export shortcut ranges', () {
    final today = CivilDate(2026, 10, 22);

    test('30 and 90 days include today and keep Before exclusive', () {
      final thirty = exportShortcutRange(today, ExportRangeShortcut.thirtyDays);
      expect(thirty.from, CivilDate(2026, 9, 23));
      expect(thirty.before, CivilDate(2026, 10, 23));
      expect(
        thirty.before.calendarValue
            .difference(thirty.from.calendarValue)
            .inDays,
        30,
      );

      final ninety = exportShortcutRange(today, ExportRangeShortcut.ninetyDays);
      expect(ninety.from, CivilDate(2026, 7, 25));
      expect(ninety.before, CivilDate(2026, 10, 23));
      expect(
        ninety.before.calendarValue
            .difference(ninety.from.calendarValue)
            .inDays,
        90,
      );
    });

    test('year starts on 1 January and includes today', () {
      final range = exportShortcutRange(today, ExportRangeShortcut.year);
      expect(range.from, CivilDate(2026, 1, 1));
      expect(range.before, CivilDate(2026, 10, 23));
    });

    test('leap day stays inside the exact civil range', () {
      final onLeapDay = exportShortcutRange(
        CivilDate(2024, 2, 29),
        ExportRangeShortcut.year,
      );
      expect(onLeapDay.from, CivilDate(2024, 1, 1));
      expect(onLeapDay.before, CivilDate(2024, 3, 1));

      final afterLeapDay = exportShortcutRange(
        CivilDate(2024, 3, 1),
        ExportRangeShortcut.thirtyDays,
      );
      expect(afterLeapDay.from, CivilDate(2024, 2, 1));
      expect(afterLeapDay.before, CivilDate(2024, 3, 2));
      expect(
        CivilDate(2024, 2, 29).compareTo(afterLeapDay.from) >= 0,
        isTrue,
        reason: '29 February is included',
      );
      expect(
        CivilDate(2024, 3, 1).compareTo(afterLeapDay.before) < 0,
        isTrue,
        reason: 'today is included',
      );
    });

    test('daylight saving does not change the count of civil days', () {
      for (final day in [CivilDate(2026, 3, 29), CivilDate(2026, 10, 25)]) {
        final range = exportShortcutRange(day, ExportRangeShortcut.thirtyDays);
        expect(
          range.before.calendarValue
              .difference(range.from.calendarValue)
              .inDays,
          30,
          reason: 'range around $day',
        );
        expect(range.before, day.addDays(1));
      }
    });
  });

  group('display civil day', () {
    test('London and New York DST boundaries use the shown zone', () {
      // 00:30 UTC is still 29 March in London before the spring change.
      expect(
        exportCivilToday(DateTime.utc(2026, 3, 29, 0, 30), 'Europe/London'),
        CivilDate(2026, 3, 29),
      );
      // 23:30 UTC is already 30 March in London after the clocks change.
      expect(
        exportCivilToday(DateTime.utc(2026, 3, 29, 23, 30), 'Europe/London'),
        CivilDate(2026, 3, 30),
      );
      // 04:30 UTC is still 7 March in New York.
      expect(
        exportCivilToday(DateTime.utc(2026, 3, 8, 4, 30), 'America/New_York'),
        CivilDate(2026, 3, 7),
      );
      expect(
        exportCivilToday(DateTime.utc(2026, 3, 8, 5, 30), 'America/New_York'),
        CivilDate(2026, 3, 8),
      );
    });

    test('unavailable or empty zone fails instead of using UTC', () {
      for (final zone in ['Not/AZone', '', '   ']) {
        expect(
          () => exportCivilToday(DateTime.utc(2026, 10, 22, 12), zone),
          throwsA(
            isA<ExportRangeException>().having(
              (error) => error.failure,
              'failure',
              ExportRangeFailure.zoneUnavailable,
            ),
          ),
          reason: 'zone $zone',
        );
      }
    });

    test('a clock outside the civil-date range is a range failure', () {
      expect(
        () => exportCivilToday(DateTime.utc(10000, 1, 1), 'UTC'),
        throwsA(
          isA<ExportRangeException>().having(
            (error) => error.failure,
            'failure',
            ExportRangeFailure.rangeUnavailable,
          ),
        ),
      );
    });
  });

  group('representability', () {
    test('an underflowing start fails instead of clamping to year 1', () {
      expect(
        () => exportShortcutRange(
          CivilDate(1, 1, 15),
          ExportRangeShortcut.thirtyDays,
        ),
        throwsA(
          isA<ExportRangeException>().having(
            (error) => error.failure,
            'failure',
            ExportRangeFailure.rangeUnavailable,
          ),
        ),
      );
      expect(
        () => exportShortcutRange(
          CivilDate(1, 1, 15),
          ExportRangeShortcut.ninetyDays,
        ),
        throwsA(isA<ExportRangeException>()),
      );
    });

    test('the earliest year still supports the year shortcut', () {
      final range = exportShortcutRange(
        CivilDate(1, 1, 1),
        ExportRangeShortcut.year,
      );
      expect(range.from, CivilDate(1, 1, 1));
      expect(range.before, CivilDate(1, 1, 2));
    });

    test('every ordinary range matches the Settings report shortcut', () {
      const pairs = {
        ExportRangeShortcut.thirtyDays: ReportPeriod.thirtyDays,
        ExportRangeShortcut.ninetyDays: ReportPeriod.ninetyDays,
        ExportRangeShortcut.year: ReportPeriod.year,
      };
      for (final day in [
        CivilDate(2026, 1, 1),
        CivilDate(2026, 3, 29),
        CivilDate(2024, 2, 29),
        CivilDate(2026, 10, 25),
        CivilDate(2026, 12, 31),
      ]) {
        for (final MapEntry(key: shortcut, value: period) in pairs.entries) {
          final settings = reportPeriodDates(day, period);
          final export = exportShortcutRange(day, shortcut);
          expect(export.from, settings.from, reason: '$shortcut on $day');
          expect(export.before, settings.before, reason: '$shortcut on $day');
        }
      }
    });

    test('an unrepresentable exclusive end fails', () {
      for (final shortcut in ExportRangeShortcut.values) {
        expect(
          () => exportShortcutRange(CivilDate(9999, 12, 31), shortcut),
          throwsA(
            isA<ExportRangeException>().having(
              (error) => error.failure,
              'failure',
              ExportRangeFailure.rangeUnavailable,
            ),
          ),
          reason: '$shortcut',
        );
      }
    });
  });
}
