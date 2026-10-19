import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/charts/charts.dart';
import 'package:true_grit_vital/domain/scheduling/daily_plan.dart';

import 'chart_test_data.dart';

void main() {
  final day19 = DateTime.utc(2026, 10, 19);
  final day22 = DateTime.utc(2026, 10, 22);

  group('day viewport', () {
    test('covers the range with contiguous half-open buckets', () {
      final viewport = chartViewport(from: day19, before: day22);

      expect(viewport.bucketCount, 3);
      expect(viewport.zoneId, 'UTC');
      expect(viewport.zoneFallback, isFalse);
      expect(viewport.buckets.first.fromInstant, day19);
      expect(viewport.buckets.last.beforeExclusive, day22);
      for (var index = 1; index < viewport.bucketCount; index++) {
        expect(
          viewport.buckets[index].fromInstant,
          viewport.buckets[index - 1].beforeExclusive,
        );
      }
      expect(viewport.buckets.first.civilStart, CivilDate(2026, 10, 19));
      expect(viewport.buckets.last.civilEndInclusive, CivilDate(2026, 10, 21));
    });

    test('keeps partial first and last buckets exact', () {
      final viewport = chartViewport(
        from: DateTime.utc(2026, 10, 19, 12),
        before: DateTime.utc(2026, 10, 21, 6),
      );

      expect(viewport.bucketCount, 3);
      expect(
        viewport.buckets.first.fromInstant,
        DateTime.utc(2026, 10, 19, 12),
      );
      expect(viewport.buckets.first.civilStart, CivilDate(2026, 10, 19));
      expect(viewport.buckets.first.civilEndInclusive, CivilDate(2026, 10, 19));
      expect(
        viewport.buckets.last.beforeExclusive,
        DateTime.utc(2026, 10, 21, 6),
      );
      expect(viewport.buckets.last.civilEndInclusive, CivilDate(2026, 10, 21));
    });

    test('23-hour and 25-hour London days keep exact bounds', () {
      final spring = chartViewport(
        from: DateTime.utc(2026, 3, 29),
        before: DateTime.utc(2026, 3, 29, 23),
        zone: 'Europe/London',
      );
      final autumn = chartViewport(
        from: DateTime.utc(2026, 10, 24, 23),
        before: DateTime.utc(2026, 10, 26),
        zone: 'Europe/London',
      );

      expect(spring.bucketCount, 1);
      expect(spring.buckets.single.duration, const Duration(hours: 23));
      expect(spring.buckets.single.civilStart, CivilDate(2026, 3, 29));
      expect(spring.buckets.single.civilEndInclusive, CivilDate(2026, 3, 29));
      expect(autumn.bucketCount, 1);
      expect(autumn.buckets.single.duration, const Duration(hours: 25));
      expect(autumn.buckets.single.civilStart, CivilDate(2026, 10, 25));
      expect(autumn.buckets.single.civilEndInclusive, CivilDate(2026, 10, 25));
    });

    test('an unavailable zone falls back to UTC, never throws', () {
      final viewport = chartViewport(zone: 'Mars/Olympus');

      expect(viewport.zoneId, 'UTC');
      expect(viewport.zoneFallback, isTrue);
      expect(viewport.bucketCount, 3);
    });
    test('an instant outside the verified clock range shows UTC buckets', () {
      final viewport = chartViewport(
        from: DateTime.utc(2050, 1, 1),
        before: DateTime.utc(2050, 1, 3),
        zone: 'Europe/London',
      );

      expect(viewport.bucketCount, 2);
      expect(
        viewport.buckets.every(
          (bucket) => bucket.zoneId == 'UTC' && bucket.zoneFallback,
        ),
        isTrue,
      );
    });
  });

  group('week and month viewports', () {
    test('week buckets start on Monday', () {
      final viewport = chartViewport(
        from: DateTime.utc(2026, 10, 21),
        before: DateTime.utc(2026, 11, 5),
        size: ChartBucketSize.week,
      );

      expect(viewport.bucketCount, 3);
      expect(viewport.buckets.first.civilStart, CivilDate(2026, 10, 21));
      expect(
        viewport.buckets.first.beforeExclusive,
        DateTime.utc(2026, 10, 26),
      );
      expect(viewport.buckets[1].civilStart, CivilDate(2026, 10, 26));
      expect(viewport.buckets[2].civilStart, CivilDate(2026, 11, 2));
      expect(viewport.buckets.last.beforeExclusive, DateTime.utc(2026, 11, 5));
    });

    test('month buckets follow civil months with partial ends', () {
      final viewport = chartViewport(
        from: DateTime.utc(2026, 10, 19),
        before: DateTime.utc(2027, 1, 10),
        size: ChartBucketSize.month,
      );

      expect(viewport.bucketCount, 4);
      expect(viewport.buckets.first.civilStart, CivilDate(2026, 10, 19));
      expect(viewport.buckets[1].civilStart, CivilDate(2026, 11, 1));
      expect(viewport.buckets[2].civilStart, CivilDate(2026, 12, 1));
      expect(viewport.buckets[3].civilStart, CivilDate(2027, 1, 1));
      expect(viewport.buckets[3].civilEndInclusive, CivilDate(2027, 1, 9));
    });

    test('coarsen is explicit and never silently samples', () {
      final daily = chartViewport(
        from: DateTime.utc(2026, 1, 1),
        before: DateTime.utc(2026, 6, 1),
      );
      final weekly = daily.coarsen();
      final monthly = weekly.coarsen();

      expect(daily.bucketCount, greaterThan(100));
      expect(weekly.bucketSize, ChartBucketSize.week);
      expect(weekly.bucketCount, lessThan(daily.bucketCount));
      expect(monthly.bucketSize, ChartBucketSize.month);
      expect(monthly.bucketCount, lessThan(weekly.bucketCount));
      expect(monthly.coarsen(), same(monthly));
      expect(monthly.fromInstant, daily.fromInstant);
      expect(monthly.beforeInstant, daily.beforeInstant);
    });
  });

  group('bounds', () {
    test('rejects an empty, inverted or non-UTC range', () {
      expect(
        () => chartViewport(from: day19, before: day19),
        chartRangeError('invalid_range'),
      );
      expect(
        () => chartViewport(from: day22, before: day19),
        chartRangeError('invalid_range'),
      );
      expect(
        () => ChartViewport(
          fromInstant: DateTime(2026, 10, 19),
          beforeInstant: day22,
          displayZone: 'UTC',
        ),
        chartRangeError('invalid_range'),
      );
    });

    test('rejects a range above the bucket bound instead of downsampling', () {
      expect(
        () => chartViewport(
          from: DateTime.utc(2026, 1, 1),
          before: DateTime.utc(2027, 6, 1),
        ),
        chartRangeError('too_many_buckets'),
      );
    });

    test('indexOf is half-open and exact at both edges', () {
      final viewport = chartViewport(from: day19, before: day22);

      expect(viewport.indexOf(day19), 0);
      expect(
        viewport.indexOf(day19.subtract(const Duration(microseconds: 1))),
        -1,
      );
      expect(
        viewport.indexOf(day22.subtract(const Duration(microseconds: 1))),
        2,
      );
      expect(viewport.indexOf(day22), -1);
    });

    test('a skipped civil date is omitted, not invented', () {
      final viewport = chartViewport(
        from: DateTime.utc(2011, 12, 29),
        before: DateTime.utc(2012, 1, 1),
        zone: 'Pacific/Apia',
      );

      expect(
        viewport.buckets.map((bucket) => bucket.civilStart).toList(),
        isNot(contains(CivilDate(2011, 12, 30))),
      );
      expect(viewport.buckets.any((bucket) => bucket.isEmpty), isFalse);
      expect(
        viewport.buckets
            .map((bucket) => bucket.duration)
            .fold(Duration.zero, (total, value) => total + value),
        const Duration(days: 3),
      );
    });
  });
}
