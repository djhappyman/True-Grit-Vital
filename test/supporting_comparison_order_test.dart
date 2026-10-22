import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/supporting/supporting.dart';

import 'supporting_categories_comparison_test.dart' show point;

void main() {
  final viewed = point('viewed', 6, value: '4');
  final first = point(
    'first',
    5,
    value: '1',
    date: SupportingDate.exact(
      DateTime.utc(2026, 10, 5, 8),
      zoneId: 'UTC',
      utcOffsetMinutes: 0,
    ),
  );
  final tied = point(
    'tied',
    5,
    value: '2',
    date: SupportingDate.exact(
      DateTime.utc(2026, 10, 5, 8),
      zoneId: 'UTC',
      utcOffsetMinutes: 0,
    ),
  );
  final latest = point(
    'latest',
    5,
    value: '3',
    date: SupportingDate.exact(
      DateTime.utc(2026, 10, 5, 13),
      zoneId: 'UTC',
      utcOffsetMinutes: 0,
    ),
  );

  Iterable<List<SupportingRevision>> orders(
    List<SupportingRevision> rows,
  ) sync* {
    for (var a = 0; a < 3; a++) {
      for (var b = 0; b < 3; b++) {
        if (a != b) yield [rows[a], rows[b], rows[3 - a - b]];
      }
    }
  }

  SupportingEarlierComparison compare(List<SupportingRevision> rows) =>
      supportingEarlierComparison(
        viewed: viewed,
        result: viewed.snapshot.results.single,
        candidates: rows,
        displayZone: 'UTC',
      );

  test('an unambiguous newer instant wins regardless of older tie order', () {
    for (final rows in orders([first, tied, latest])) {
      final result = compare(rows);
      expect(
        result.status,
        SupportingEarlierStatus.found,
        reason: rows.map((row) => row.id.id).join(','),
      );
      expect(result.earlier!.record.id.id, 'latest');
      expect(result.change, '+1');
    }
  });

  test('a day-only candidate keeps the same day ambiguous in every order', () {
    final undetermined = point('day-only', 5, value: '2');
    for (final rows in orders([first, undetermined, latest])) {
      expect(compare(rows).status, SupportingEarlierStatus.incomplete);
    }
  });
}
