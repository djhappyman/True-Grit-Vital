import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:true_grit_vital/domain/history/history.dart';
import 'package:true_grit_vital/domain/scheduling/daily_plan.dart';
import 'package:true_grit_vital/domain/scheduling/iana_clock.dart';

void main() {
  group('TimeFormat', () {
    test('resolves system, 12-hour and 24-hour choices', () {
      expect(
        TimeFormat.system.resolvesTo24Hour(systemUses24Hour: true),
        isTrue,
      );
      expect(
        TimeFormat.system.resolvesTo24Hour(systemUses24Hour: false),
        isFalse,
      );
      expect(TimeFormat.h12.resolvesTo24Hour(systemUses24Hour: true), isFalse);
      expect(TimeFormat.h24.resolvesTo24Hour(systemUses24Hour: false), isTrue);
    });

    test('stores and restores the shared display preference', () {
      expect(TimeFormat.system.storageValue, 'system');
      expect(TimeFormat.h12.storageValue, 'h12');
      expect(TimeFormat.h24.storageValue, 'h24');
      expect(timeFormatFromStorage('system'), TimeFormat.system);
      expect(timeFormatFromStorage('h12'), TimeFormat.h12);
      expect(timeFormatFromStorage('h24'), TimeFormat.h24);
      expect(timeFormatFromStorage(null), TimeFormat.system);
      expect(timeFormatFromStorage('unknown'), TimeFormat.system);
    });
  });

  group('DisplayZone', () {
    test('keeps UTC and valid IANA zones', () {
      final clock = IanaClock();
      expect(DisplayZone.resolve('UTC', clock).zoneId, 'UTC');
      expect(DisplayZone.resolve('UTC', clock).isFallback, isFalse);
      expect(
        DisplayZone.resolve('Europe/London', clock).zoneId,
        'Europe/London',
      );
      expect(DisplayZone.resolve('Europe/London', clock).isFallback, isFalse);
    });

    test('falls back to UTC for an unavailable zone', () {
      final zone = DisplayZone.resolve('Not/AZone', IanaClock());
      expect(zone.zoneId, 'UTC');
      expect(zone.isFallback, isTrue);
    });
  });

  group('DisplayInstant', () {
    final display = DisplayTime();
    final instant = DateTime.utc(2026, 7, 1, 12, 30, 45, 123, 456);

    test('projects the shown civil fields without changing the instant', () {
      final value = display.instant(instant, 'Europe/London');

      expect(value.instant, instant);
      expect(value.instant.isUtc, isTrue);
      expect(value.zoneId, 'Europe/London');
      expect(value.zoneFallback, isFalse);
      expect(value.civilDate, CivilDate(2026, 7, 1));
      expect(value.dateText, '2026-07-01');
      expect(value.hour, 13);
      expect(value.minute, 30);
      expect(value.second, 45);
      expect(value.millisecond, 123);
      expect(value.microsecond, 456);
      expect(value.time24, '13:30');
      expect(value.time24WithSeconds, '13:30:45');
      expect(value.instantIso8601, instant.toIso8601String());
      expect(value.wallValue, DateTime.utc(2026, 7, 1, 13, 30, 45, 123, 456));
    });

    test('keeps the exact UTC instant on an unavailable zone', () {
      final value = display.instant(instant, 'Not/AZone');

      expect(value.instant, instant);
      expect(value.zoneId, 'UTC');
      expect(value.zoneFallback, isTrue);
      expect(value.hour, 12);
      expect(value.minute, 30);
      expect(value.civilDate, CivilDate(2026, 7, 1));
    });

    test('falls back to UTC outside the verified clock range', () {
      final old = DateTime.utc(1800, 7, 1, 12, 30);
      final value = display.instant(old, 'Europe/London');

      expect(value.instant, old);
      expect(value.zoneId, 'UTC');
      expect(value.zoneFallback, isTrue);
      expect(value.hour, 12);
      expect(value.civilDate, CivilDate(1800, 7, 1));
    });

    test('rejects an instant outside the civil-date model', () {
      expect(
        () => display.instant(DateTime.utc(0, 1, 1), 'UTC'),
        throwsArgumentError,
      );
    });

    test('distinguishes both passes through a repeated clock', () {
      final first = display.instant(
        DateTime.utc(2026, 10, 25, 0, 30),
        'Europe/London',
      );
      final second = display.instant(
        DateTime.utc(2026, 10, 25, 1, 30),
        'Europe/London',
      );

      expect(first.hour, 1);
      expect(first.minute, 30);
      expect(first.instant, DateTime.utc(2026, 10, 25, 0, 30));
      expect(second.hour, 1);
      expect(second.minute, 30);
      expect(second.instant, DateTime.utc(2026, 10, 25, 1, 30));
      expect(second.instant, isNot(first.instant));
    });
  });

  group('DisplayTimeFormatter', () {
    final display = DisplayTime();
    final value = display.instant(
      DateTime.utc(2026, 7, 1, 12, 30, 45),
      'Europe/London',
    );

    test('explicit 12-hour choice overrides the UK locale default', () async {
      final localizations = await GlobalMaterialLocalizations.delegate.load(
        const Locale('en', 'GB'),
      );
      final formatter = DisplayTimeFormatter(
        localizations: localizations,
        preference: TimeFormat.h12,
        systemUses24Hour: true,
      );
      expect(
        formatter.time(value),
        '1:30 ${localizations.postMeridiemAbbreviation}',
      );
      final system = DisplayTimeFormatter(
        localizations: localizations,
        preference: TimeFormat.system,
        systemUses24Hour: false,
      );
      expect(system.time(value), '13:30');
      expect(system.timeWithSeconds(value), '13:30:45');
      for (final hour in [0, 12]) {
        final noonOrMidnight = display.instant(
          DateTime.utc(2026, 7, 1, hour),
          'UTC',
        );
        final period = hour == 0
            ? localizations.anteMeridiemAbbreviation
            : localizations.postMeridiemAbbreviation;
        expect(formatter.time(noonOrMidnight), '12:00 $period');
      }
    });

    test('renders the chosen 24-hour format with the exact date and zone', () {
      final formatter = DisplayTimeFormatter(
        localizations: const DefaultMaterialLocalizations(),
        preference: TimeFormat.h24,
        systemUses24Hour: false,
      );

      expect(formatter.use24Hour, isTrue);
      expect(formatter.date(value), 'Wed, Jul 1');
      expect(formatter.date(value, full: true), 'Wednesday, July 1, 2026');
      expect(formatter.time(value), '13:30');
      expect(formatter.timeWithSeconds(value), '13:30:45');
      expect(formatter.zone(value), 'Europe/London');
      expect(
        formatter.format(value),
        'Wednesday, July 1, 2026, 13:30, Europe/London',
      );
      expect(
        formatter.format(value, includeSeconds: true),
        'Wednesday, July 1, 2026, 13:30:45, Europe/London',
      );
    });

    test('renders the chosen 12-hour format', () {
      final formatter = DisplayTimeFormatter(
        localizations: const DefaultMaterialLocalizations(),
        preference: TimeFormat.h12,
        systemUses24Hour: true,
      );

      expect(formatter.use24Hour, isFalse);
      expect(formatter.time(value), '1:30 PM');
      expect(formatter.timeWithSeconds(value), '1:30:45 PM');
      expect(
        formatter.format(value),
        'Wednesday, July 1, 2026, 1:30 PM, Europe/London',
      );
    });

    test('follows the system flag only for the system choice', () {
      DisplayTimeFormatter formatter({required bool system}) =>
          DisplayTimeFormatter(
            localizations: const DefaultMaterialLocalizations(),
            preference: TimeFormat.system,
            systemUses24Hour: system,
          );

      expect(formatter(system: true).use24Hour, isTrue);
      expect(formatter(system: true).time(value), '13:30');
      expect(formatter(system: false).use24Hour, isFalse);
      expect(formatter(system: false).time(value), '1:30 PM');
    });

    test('does not mutate the displayed instant or its zone', () {
      final before = value.instant;
      final formatter = DisplayTimeFormatter(
        localizations: const DefaultMaterialLocalizations(),
        preference: TimeFormat.h12,
        systemUses24Hour: false,
      );

      formatter.format(value, includeSeconds: true);
      expect(value.instant, before);
      expect(value.zoneId, 'Europe/London');
      expect(value.civilDate, CivilDate(2026, 7, 1));
    });

    test('shows UTC in the formatted string on fallback', () {
      final fallback = display.instant(
        DateTime.utc(1800, 7, 1, 12, 30),
        'Europe/London',
      );
      final formatter = DisplayTimeFormatter(
        localizations: const DefaultMaterialLocalizations(),
        preference: TimeFormat.h24,
        systemUses24Hour: false,
      );

      expect(formatter.format(fallback), 'Tuesday, July 1, 1800, 12:30, UTC');
      expect(fallback.zoneFallback, isTrue);
    });
  });

  group('DisplayDayBounds', () {
    final display = DisplayTime();

    test('uses half-open UTC bounds for a normal UTC day', () {
      final bounds = display.dayBounds(CivilDate(2026, 10, 19), 'UTC');

      expect(bounds.zoneId, 'UTC');
      expect(bounds.zoneFallback, isFalse);
      expect(bounds.start, DateTime.utc(2026, 10, 19));
      expect(bounds.endExclusive, DateTime.utc(2026, 10, 20));
      expect(bounds.duration, const Duration(hours: 24));
      expect(bounds.isEmpty, isFalse);
      expect(bounds.contains(DateTime.utc(2026, 10, 19)), isTrue);
      expect(bounds.contains(DateTime.utc(2026, 10, 20)), isFalse);
    });

    test('resolves a 23-hour London day', () {
      final bounds = display.dayBounds(CivilDate(2026, 3, 29), 'Europe/London');

      expect(bounds.start, DateTime.utc(2026, 3, 29));
      expect(bounds.endExclusive, DateTime.utc(2026, 3, 29, 23));
      expect(bounds.duration, const Duration(hours: 23));
      expect(bounds.isEmpty, isFalse);
      expect(bounds.contains(DateTime.utc(2026, 3, 29, 22, 59)), isTrue);
      expect(bounds.contains(DateTime.utc(2026, 3, 29, 23)), isFalse);
    });

    test('resolves a 25-hour London day', () {
      final bounds = display.dayBounds(
        CivilDate(2026, 10, 25),
        'Europe/London',
      );

      expect(bounds.start, DateTime.utc(2026, 10, 24, 23));
      expect(bounds.endExclusive, DateTime.utc(2026, 10, 26));
      expect(bounds.duration, const Duration(hours: 25));
      expect(bounds.isEmpty, isFalse);
      expect(bounds.contains(DateTime.utc(2026, 10, 24, 22, 59)), isFalse);
      expect(bounds.contains(DateTime.utc(2026, 10, 24, 23)), isTrue);
      expect(bounds.contains(DateTime.utc(2026, 10, 26)), isFalse);
    });

    test('starts a Santiago day at the first valid minute after a skipped midnight', () {
      final bounds = display.dayBounds(
        CivilDate(2026, 9, 6),
        'America/Santiago',
      );
      final local = IanaClock().timeAt(bounds.start, 'America/Santiago');

      expect(bounds.start, DateTime.utc(2026, 9, 6, 4));
      expect(bounds.endExclusive, DateTime.utc(2026, 9, 7, 3));
      expect(bounds.duration, const Duration(hours: 23));
      expect(local.hour, 1);
      expect(local.minute, 0);
      expect(bounds.isEmpty, isFalse);
    });

    test('reports a missing civil day as an empty range', () {
      final bounds = display.dayBounds(CivilDate(2011, 12, 30), 'Pacific/Apia');

      expect(bounds.isEmpty, isTrue);
      expect(bounds.duration, Duration.zero);
      expect(bounds.start, bounds.endExclusive);
      expect(bounds.contains(bounds.start), isFalse);
    });

    test('falls back to UTC day bounds for an unavailable zone', () {
      final bounds = display.dayBounds(CivilDate(2026, 10, 19), 'Not/AZone');

      expect(bounds.zoneId, 'UTC');
      expect(bounds.zoneFallback, isTrue);
      expect(bounds.start, DateTime.utc(2026, 10, 19));
      expect(bounds.endExclusive, DateTime.utc(2026, 10, 20));
    });
  });
}
