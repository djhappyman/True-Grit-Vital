import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/platform/device_zone.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'design_substance_summary_fixture.dart';
import 'vital_app_test.dart' show appTest;

CivilDate daysFromNow(int offset) =>
    CivilDate.fromDateTime(DateTime.now().toUtc().add(Duration(days: offset)));

void main() {
  appTest('everyday plan renders schedule zone next and exact stock', (
    tester,
  ) async {
    final fixture = await openSummaryFixture(tester);
    await fixture.plan('main', DailyCount(2, dose('1', 'mg')));
    await fixture.stock(opening: '8');
    await fixture.mount();
    await fixture.waitText('Planned 2 times a day, 1 mg each');
    expect(find.text('Time zone: Europe/London'), findsOneWidget);
    expect(find.textContaining('Next planned dose: 1 mg on'), findsOneWidget);
    expect(find.textContaining(' untimed (Europe/London)'), findsOneWidget);
    expect(find.text('Synthetic vial · 8 mg'), findsOneWidget);
    expect(find.text('Labelled strength: 2 mg/ml'), findsOneWidget);
    expect(find.text('No schedule recorded.'), findsNothing);
  });

  appTest('as-needed use names guidance and never implies a next dose', (
    tester,
  ) async {
    final fixture = await openSummaryFixture(tester);
    await fixture.plan('prn', const AsNeeded());
    await fixture.mount();
    await fixture.waitText('As needed');
    expect(find.textContaining('Record use when needed.'), findsOneWidget);
    expect(find.textContaining('Next planned dose:'), findsNothing);
    expect(find.text('No stock recorded.'), findsOneWidget);
  });

  appTest('paused plan stays truthful while recording stays available', (
    tester,
  ) async {
    final fixture = await openSummaryFixture(tester);
    await fixture.plan('paused', DailyCount(1, dose('1', 'mg')));
    await fixture.pause('paused');
    await fixture.stock(opening: '4');
    await fixture.mount(detailed: true);
    await fixture.waitText('Paused');
    expect(
      find.text('Record actual use separately while this plan is paused.'),
      findsOneWidget,
    );
    expect(find.text('This schedule has ended.'), findsNothing);
    expect(find.text('Not started.'), findsNothing);
  });

  appTest('ended plan is explicit and never invents a next date', (
    tester,
  ) async {
    final fixture = await openSummaryFixture(tester);
    await fixture.plan(
      'ended',
      DailyCount(1, dose('1', 'mg')),
      start: daysFromNow(-12),
      endExclusive: daysFromNow(-2),
    );
    await fixture.mount();
    await fixture.waitText('This schedule has ended.');
    expect(find.text('No next planned date within this plan.'), findsOneWidget);
  });

  appTest('future plan shows its stored start state without a past claim', (
    tester,
  ) async {
    final fixture = await openSummaryFixture(tester);
    await fixture.plan(
      'future',
      DailyCount(1, dose('1', 'mg')),
      start: daysFromNow(3),
    );
    await fixture.mount();
    await fixture.waitText('Not started.');
  });

  appTest('unknown balances low stock and mixed units stay separate', (
    tester,
  ) async {
    final fixture = await openSummaryFixture(tester);
    await fixture.stock(label: 'Unknown vial', opening: null);
    await fixture.stock(label: 'Low vial', opening: '1', threshold: '3');
    await fixture.stock(
      label: 'Pool stock',
      unit: 'count',
      strength: '3 bottles',
      opening: '12',
    );
    await fixture.mount();
    await fixture.waitText('Unknown vial · Unknown');
    expect(find.text('Unknown vial · Unknown'), findsOneWidget);
    expect(find.text('Low vial · 1 mg'), findsOneWidget);
    expect(find.text('Pool stock · 12 count'), findsOneWidget);
    expect(find.text('Low stock'), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget);
    // No fabricated total across unknown, mg and count containers.
    expect(find.text('13 mg'), findsNothing);
    expect(find.text('13 count'), findsNothing);
  });

  appTest('deficit stock states the deficit below zero truthfully', (
    tester,
  ) async {
    final fixture = await openSummaryFixture(tester);
    final container = await fixture.stock(opening: '2');
    await fixture.adjust(container, StockMovementKind.waste, '3');
    await fixture.mount(detailed: true);
    await fixture.waitText('Deficit');
    expect(
      find.text('Stock deficit. The recorded balance is below zero.'),
      findsOneWidget,
    );
  });

  appTest('a mixed plan splits chosen slots and the untimed remainder', (
    tester,
  ) async {
    final fixture = await openSummaryFixture(tester);
    await fixture.plan(
      'mixed',
      MixedDailyCount(
        count: 4,
        amount: dose('2', 'mg'),
        slots: [
          DailySlot(
            id: 'morning',
            time: WallTime(8, 0),
            amount: dose('1', 'mg'),
            reminderEnabled: false,
          ),
        ],
      ),
    );
    await fixture.mount();
    await fixture.waitTextContaining('8:00 1 mg');
    await fixture.waitTextContaining(' plus 3 untimed slots (2 mg each)');
  });

  appTest('unavailable zone keeps follows-local plans partial with retry', (
    tester,
  ) async {
    final fixture = await openSummaryFixture(
      tester,
      zone: const Stream<DeviceZoneObservation>.empty(),
    );
    await fixture.plan('main', DailyCount(1, dose('1', 'mg')));
    await fixture.mount();
    await fixture.waitText('Time zone: Follow local');
    // The explanation renders beside a one-word Retry, never as a button label.
    final explanation = find.textContaining(
      'The device time zone is unavailable. Retry or choose a named home zone.',
    );
    await fixture.waitTextContaining(
      'The device time zone is unavailable. Retry or choose a named home zone.',
    );
    expect(
      find.descendant(of: find.byType(VitalButton), matching: explanation),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(VitalButton),
        matching: find.text('Retry'),
      ),
      findsOneWidget,
    );
  });

  appTest('the streamed container page stays disclosed at its bound', (
    tester,
  ) async {
    final fixture = await openSummaryFixture(tester);
    for (var i = 1; i <= 51; i++) {
      await fixture.stock(label: 'Vial $i');
    }
    await fixture.mount(detailed: true);
    // Detailed renders the streamed page: fifty of the fifty-one containers.
    // The single unrendered container stays disclosed by the Stock sentinel.
    final labels = find.textContaining(RegExp(r'^Vial \d+$'));
    await fixture.waitCount(labels, 50);
    expect(labels, findsNWidgets(50));
    expect(
      find.text('More containers are available. Open Stock to review them.'),
      findsOneWidget,
    );
  });

  appTest('detailed view names slots weekdays bounds and stock detail', (
    tester,
  ) async {
    final fixture = await openSummaryFixture(tester);
    final start = daysFromNow(-7);
    await fixture.plan(
      'slotted',
      DailySlots([
        DailySlot(
          id: 'morning',
          time: WallTime(8, 0),
          amount: dose('1', 'mg'),
          reminderEnabled: false,
        ),
        DailySlot(
          id: 'evening',
          time: WallTime(20, 0),
          amount: dose('2', 'mg'),
          reminderEnabled: false,
        ),
      ]),
      start: start,
      calendar: SelectedWeekdays(const [1, 3]),
    );
    await fixture.stock(opening: '6', threshold: '2');
    await fixture.mount(detailed: true);
    await fixture.waitText('Schedules');
    expect(find.textContaining('Planned times:'), findsOneWidget);
    expect(find.text('Days of week: M, W'), findsOneWidget);
    expect(find.textContaining('From '), findsOneWidget);
    expect(find.textContaining(start.toString()), findsOneWidget);
    expect(find.text('Stock'), findsOneWidget);
    expect(find.text('Synthetic vial'), findsOneWidget);
    expect(find.text('Labelled strength: 2 mg/ml'), findsOneWidget);
  });

  appTest('compact keeps a disclosed page and detailed grows beyond it', (
    tester,
  ) async {
    final fixture = await openSummaryFixture(tester);
    for (var i = 1; i <= 6; i++) {
      await fixture.stock(label: 'Vial $i', opening: '$i');
    }
    await fixture.mount();
    // The store orders containers by record id, so the page size is what
    // stays bounded: exactly four balance rows plus the counted disclosure.
    final entries = find.textContaining(RegExp(r'^Vial \d+ · \d+ mg$'));
    await fixture.waitCount(entries, 4);
    expect(entries, findsNWidgets(4));
    expect(find.text('2 more containers.'), findsOneWidget);
    // Detailed keeps every container in its own row with its own unit.
    await fixture.mount(detailed: true);
    final labels = find.textContaining(RegExp(r'^Vial \d+$'));
    await fixture.waitCount(labels, 6);
    for (var i = 1; i <= 6; i++) {
      expect(find.text('Vial $i'), findsOneWidget);
    }
    expect(find.text('2 more containers.'), findsNothing);
  });

  appTest('interval plans restate stored hours without made-up times', (
    tester,
  ) async {
    final fixture = await openSummaryFixture(tester);
    final anchor = DateTime.utc(
      daysFromNow(-3).year,
      daysFromNow(-3).month,
      daysFromNow(-3).day,
    );
    await fixture.plan(
      'interval',
      ElapsedInterval(
        segmentId: 'interval',
        duration: ExactElapsed.parseHours('8'),
        mode: IntervalMode.fixedPlanned,
        plannedAnchor: anchor,
        amount: dose('1', 'mg'),
      ),
    );
    await fixture.mount();
    await fixture.waitText('Every 8 h, 1 mg each');
  });

  appTest('a failing read keeps the bounded retry without fake progress', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        storeLoaderProvider.overrideWithValue(
          () => throw StateError('fixture-broken-store'),
        ),
        observedDeviceZoneProvider.overrideWith(
          (ref) => const Stream<DeviceZoneObservation>.empty(),
        ),
      ],
    );
    addTearDown(container.dispose);
    const synthetic = SubstanceItem(
      id: 'synthetic-item',
      personId: meId,
      name: 'Synthetic broken item',
      form: 'Tablet',
      unit: 'mg',
      type: 'Medicine',
    );
    await mountOn(tester, container, synthetic);
    final elapsed = Stopwatch()..start();
    while (find
        .textContaining('The substance summary could not be loaded.')
        .evaluate()
        .isEmpty) {
      if (elapsed.elapsed > const Duration(seconds: 10)) {
        throw TestFailure('Expected the failure notice to render.');
      }
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(find.text('Retry'), findsOneWidget);
  });
}
