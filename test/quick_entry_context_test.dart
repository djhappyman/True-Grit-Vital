import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/scheduling/daily_plan.dart';
import 'package:true_grit_vital/features/recording/quick_entry_context.dart';

void main() {
  group('quick-entry day parsing', () {
    test('accepts exact civil dates and round trips their spelling', () {
      expect(parseQuickEntryDay('2026-10-22'), CivilDate(2026, 10, 22));
      expect(parseQuickEntryDay('2024-02-29'), CivilDate(2024, 2, 29));
      expect(parseQuickEntryDay('9999-12-31'), CivilDate(9999, 12, 31));
      expect(parseQuickEntryDay('0001-01-01'), CivilDate(1, 1, 1));
    });

    test('rejects dates DateTime.tryParse would normalise', () {
      expect(DateTime.tryParse('2026-02-30'), isNotNull);
      expect(parseQuickEntryDay('2026-02-30'), isNull);
      expect(parseQuickEntryDay('2026-02-29'), isNull);
      expect(parseQuickEntryDay('2026-04-31'), isNull);
      expect(parseQuickEntryDay('2026-13-01'), isNull);
      expect(parseQuickEntryDay('0000-01-01'), isNull);
      expect(parseQuickEntryDay('9999-12-32'), isNull);
      expect(parseQuickEntryDay('2026-2-3'), isNull);
      expect(parseQuickEntryDay('2026-02-03T00:00:00Z'), isNull);
      expect(parseQuickEntryDay(' 2026-02-03'), isNull);
    });

    test('absent day retains the existing default without an issue', () {
      final entry = QuickEntryContext.parse('/unplanned?new=1');
      expect(entry.day, isNull);
      expect(entry.issues, isEmpty);
    });
  });

  group('quick-entry time parsing', () {
    test('accepts exact 24-hour wall times', () {
      expect(parseQuickEntryTime('08:00'), '08:00');
      expect(parseQuickEntryTime('00:00'), '00:00');
      expect(parseQuickEntryTime('23:59'), '23:59');
    });

    test('rejects malformed or out-of-range times', () {
      expect(parseQuickEntryTime('8:00'), isNull);
      expect(parseQuickEntryTime('24:00'), isNull);
      expect(parseQuickEntryTime('08:60'), isNull);
      expect(parseQuickEntryTime('08:00:00'), isNull);
      expect(parseQuickEntryTime('0800'), isNull);
      expect(parseQuickEntryTime('08:00Z'), isNull);
    });

    test('a supplied time is retained only for planning', () {
      final plan = QuickEntryContext.parse(
        '/unplanned?new=1&plan=1&day=2026-10-22&time=08:00',
      );
      expect(plan.time, '08:00');
      expect(plan.issues, isEmpty);

      final record = QuickEntryContext.parse(
        '/unplanned?new=1&day=2026-10-22&time=08:00',
      );
      expect(record.time, isNull);
      expect(record.issues, [QuickEntryIssue.timeWithoutPlan]);
    });
  });

  group('quick-entry task combinations', () {
    test('new planning keeps its day and suggested time', () {
      final entry = QuickEntryContext.parse(
        '/unplanned?new=1&plan=1&day=2024-02-29&time=08:00',
      );
      expect(entry.createNew, isTrue);
      expect(entry.plan, isTrue);
      expect(entry.needsChoice, isFalse);
      expect(entry.issues, isEmpty);
      expect(
        quickEntryCreateLocation(entry),
        '/unplanned?new=1&plan=1&day=2024-02-29&time=08%3A00',
      );
    });

    test('existing item keeps its day and plan time', () {
      final entry = QuickEntryContext.parse(
        '/unplanned?item=item-1&plan=1&day=2026-10-23&time=20:00',
      );
      expect(entry.needsChoice, isTrue);
      expect(entry.issues, [QuickEntryIssue.planAndItem]);
      expect(
        quickEntryPlanLocation(entry),
        '/schedule/item-1?start=2026-10-23&time=20%3A00',
      );
      expect(
        quickEntryRecordLocation(entry),
        '/unplanned?item=item-1&day=2026-10-23',
      );
    });

    test('item plus new asks instead of silently creating', () {
      final entry = QuickEntryContext.parse(
        '/unplanned?new=1&item=item-1&day=2026-10-23',
      );
      expect(entry.needsChoice, isTrue);
      expect(entry.issues, [QuickEntryIssue.newAndItem]);
      expect(
        quickEntryCreateLocation(entry),
        '/unplanned?new=1&day=2026-10-23',
      );
      expect(
        quickEntryRecordLocation(entry),
        '/unplanned?item=item-1&day=2026-10-23',
      );
    });

    test('invalid flags and item values recover explicitly', () {
      expect(QuickEntryContext.parse('/unplanned?new=yes').issues, [
        QuickEntryIssue.invalidNewFlag,
      ]);
      expect(QuickEntryContext.parse('/unplanned?plan=yes').issues, [
        QuickEntryIssue.invalidPlanFlag,
      ]);
      for (final item in ['', '%20', ' item-1', 'item-1 ']) {
        final entry = QuickEntryContext.parse('/unplanned?item=$item');
        expect(entry.itemId, isNull);
        expect(entry.issues, contains(QuickEntryIssue.invalidItem));
      }
      expect(
        QuickEntryContext.parse('/unplanned?item=item-1').itemId,
        'item-1',
      );
    });

    test('repeated parameters are ambiguous', () {
      expect(
        QuickEntryContext.parse('/unplanned?day=2026-10-22&day=2026-10-23')
            .issues,
        [QuickEntryIssue.duplicateDay],
      );
      expect(QuickEntryContext.parse('/unplanned?item=one&item=two').issues, [
        QuickEntryIssue.duplicateItem,
      ]);
      expect(QuickEntryContext.parse('/unplanned?new=1&new=0').issues, [
        QuickEntryIssue.invalidNewFlag,
      ]);
    });

    test('all three supplied tasks preserve a valid day and ask', () {
      final entry = QuickEntryContext.parse(
        '/unplanned?new=1&plan=1&item=item-1&day=9999-12-31&time=12:00',
      );
      expect(entry.issues, [
        QuickEntryIssue.newAndItem,
        QuickEntryIssue.planAndItem,
      ]);
      expect(entry.day, CivilDate(9999, 12, 31));
      expect(entry.time, '12:00');
      expect(
        quickEntryCreateLocation(entry),
        '/unplanned?new=1&plan=1&day=9999-12-31&time=12%3A00',
      );
    });
  });

  test('chooser query and page seed from the route', () {
    final seed = quickEntryListSeed(
      Uri.parse('/unplanned?q=Magnesium&offset=50'),
    );
    expect(seed.query, 'Magnesium');
    expect(seed.offset, 50);
    expect(quickEntryListSeed(Uri.parse('/unplanned')).offset, 0);
    expect(quickEntryListSeed(Uri.parse('/unplanned?offset=-4')).offset, 0);
    expect(quickEntryListSeed(Uri.parse('/unplanned?offset=nope')).offset, 0);
  });
}
