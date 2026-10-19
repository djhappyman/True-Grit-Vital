import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/features/events/event_pages.dart'
    show EventDetailPage;
import 'package:true_grit_vital/platform/storage_bootstrap.dart';

import 'stock_flow_test.dart' as stock;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'protected event membership, use history, dismissal and encrypted reopen',
    (tester) async {
      const bootstrap = AndroidStorageBootstrap();
      final location = await bootstrap.prepare();
      final store = await RecordStore.open(
        path: location.path,
        key: location.key,
        isNew: location.isNew,
      );
      addTearDown(store.close);
      await bootstrap.activate(location);
      final me = (await store.profileById(meId))!;
      if (!me.adultConfirmed) {
        await store.editProfile(
          commandId: newCommandId(),
          personId: meId,
          expectedRevision: me.revision,
          name: me.name,
          adultConfirmed: true,
        );
      }
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final owner = await store.createProfile(
        commandId: newCommandId(),
        name: 'Synthetic event adult $suffix',
        adultConfirmed: true,
      );
      final item = await store.createItem(
        commandId: newCommandId(),
        personId: owner.id,
        expectedPersonRevision: owner.revision,
        name: 'Synthetic event source $suffix',
        form: 'Tablet',
        unit: 'count',
        type: 'Test',
      );
      final actual = await store.record(
        commandId: newCommandId(),
        itemId: item.id,
        personId: owner.id,
        expectedPersonRevision: owner.revision,
        amount: '1',
        actualAt: DateTime.utc(2026, 10, 9, 12),
      );
      final event = EventRecord(
        id: newCommandId(),
        personId: owner.id,
        name: 'Synthetic event $suffix',
        eventType: 'prescription',
        zoneId: 'Europe/London',
        revision: 1,
        plannedEnd: EventDate.day(CivilDate(2026, 10, 25)),
        memberships: [
          EventMembership(
            id: newCommandId(),
            itemId: item.id,
            personId: owner.id,
            effectiveFrom: DateTime.utc(2026, 10, 10),
            revision: 1,
          ),
        ],
      );
      await store.saveEvent(
        SaveEventCommand(
          commandId: newCommandId(),
          generation: store.generation,
          expectedPersonRevision: owner.revision,
          expectedRevision: null,
          event: event,
        ),
      );
      final providers = ProviderContainer(
        overrides: [storeLoaderProvider.overrideWithValue(() async => store)],
      );
      addTearDown(providers.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: providers,
          child: const VitalApp(),
        ),
      );
      await stock.waitFor(tester, find.text('Substances'));
      providers.read(routerProvider).go('/event/${event.id}/edit');
      final start = find.descendant(
        of: find.widgetWithText(LabelledInput, 'Membership start'),
        matching: find.byType(TextField),
      );
      await stock.waitFor(tester, start);
      await stock.reveal(tester, start);
      await tester.enterText(start, '2026-10-08T00:00:00Z');
      await stock.tap(tester, find.text('Review'));
      await stock.waitFor(tester, find.text('Records included: 1'));
      expect(await store.eventActuals([event.id]), isEmpty);
      await stock.tap(tester, find.text('Save'));
      await stock.waitFor(tester, find.byType(EventDetailPage));
      expect((await store.eventActuals([event.id])).single.id, actual.id);
      providers.read(routerProvider).go('/use/${owner.id}/${item.id}/edit');
      final useStart = find.descendant(
        of: find.widgetWithText(LabelledInput, 'Recorded start'),
        matching: find.byType(TextField),
      );
      await stock.waitFor(tester, useStart);
      await stock.reveal(tester, useStart);
      await tester.enterText(useStart, 'Unknown');
      await stock.tap(tester, find.text('Save'));
      await stock.waitFor(tester, find.text('Use history'));
      providers.read(routerProvider).go('/event/${event.id}/decision');
      await stock.waitFor(tester, find.text('Dismiss'));
      await stock.tap(tester, find.text('Dismiss'));
      await stock.waitFor(tester, find.byType(EventDetailPage));
      final reopened = await RecordStore.open(
        path: location.path,
        key: location.key,
        isNew: false,
      );
      try {
        expect((await reopened.eventById(event.id))!.endReviewDismissed, true);
        expect((await reopened.eventHistory(event.id)).length, 3);
        expect(
          (await reopened.usePeriods(
            personId: owner.id,
            itemId: item.id,
          )).single.start.precision,
          EventDatePrecision.unknown,
        );
        expect((await reopened.records(personId: owner.id)).length, 1);
        expect((await reopened.history(actual.id)).length, 1);
        expect(await reopened.dailyPlans(itemId: item.id), isEmpty);
      } finally {
        await reopened.close();
      }
    },
  );
}
