import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/platform/storage_bootstrap.dart';

import 'stock_flow_test.dart' as ui;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Only the root-owned protected Android snapshot harness may execute this.
  testWidgets(
    'finite phases preserve another adult and reopen encrypted bounds',
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
      final owner = await store.createProfile(
        commandId: newCommandId(),
        name: 'Synthetic phase adult',
        adultConfirmed: true,
      );
      final item = await store.createItem(
        commandId: newCommandId(),
        personId: owner.id,
        expectedPersonRevision: owner.revision,
        name: 'Synthetic phase substance',
        form: 'Tablet',
        unit: 'mg',
        type: 'Medicine',
      );
      final today = CivilDate.fromDateTime(DateTime.now().toUtc()),
          planId = newCommandId();
      await store.saveDailyPlan(
        commandId: newCommandId(),
        expectedPersonRevision: owner.revision,
        expectedGeneration: store.generation,
        plan: DailyPlanVersion(
          personId: owner.id,
          itemId: item.id,
          planId: planId,
          versionId: newCommandId(),
          start: today,
          zoneBasis: FixedHome('UTC'),
          timing: DailyCount(
            2,
            PlannedAmount(
              quantity: ExactQuantity.parse('1.2500'),
              enteredText: '1.2500',
              unit: 'mg',
            ),
          ),
        ),
      );
      await store.saveBrowsingScope(FeedScope.person(owner.id));
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
      await ui.waitFor(tester, find.text('Synthetic phase substance'));
      providers.read(routerProvider).push('/phases/${item.id}?plan=$planId');
      await ui.waitFor(tester, find.text('Last day'));
      expect(find.textContaining('Synthetic phase adult'), findsWidgets);
      await ui.tap(tester, find.text('Last day'));
      final end = find.descendant(
        of: find.byKey(const ValueKey('phaseEndValue')),
        matching: find.byType(TextField),
      );
      await ui.reveal(tester, end);
      await tester.enterText(end, today.addDays(2).toString());
      await ui.tap(tester, find.text('Preview'));
      await ui.tap(tester, find.text('Cancel'));
      expect(await store.phasePlan(planId: planId, personId: owner.id), isNull);
      await ui.tap(tester, find.text('Preview'));
      await ui.tap(tester, find.text('Save'));
      final saved = (await store.phasePlan(
        planId: planId,
        personId: owner.id,
      ))!;
      expect(saved.end!.lastDate, today.addDays(2));
      expect(saved.end!.zoneId, 'UTC');
      expect(saved.phases.single.personId, owner.id);
      providers.read(routerProvider).push('/phases/${item.id}?plan=$planId');
      await ui.waitFor(tester, find.byKey(const ValueKey('phaseEndValue')));
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('phaseEndValue')),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        today.addDays(2).toString(),
      );
    },
  );
}
