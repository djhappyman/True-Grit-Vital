import '../test/fixtures/single_user.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/platform/storage_bootstrap.dart';

import 'stock_flow_test.dart' as ui;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Run only through the root-owned protected Android snapshot harness.
  testWidgets('pause, reject preview, preserve resume and encrypted reopen', (
    tester,
  ) async {
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
    final owner = await store.configureOwnProfile(
      commandId: newCommandId(),
      name: 'Synthetic pause adult',
      adultConfirmed: true,
    );
    final item = await store.createItem(
      commandId: newCommandId(),
      personId: owner.id,
      expectedPersonRevision: owner.revision,
      name: 'Synthetic repeating substance',
      form: 'Tablet',
      unit: 'mg',
      type: 'Medicine',
    );
    final now = DateTime.now().toUtc(),
        today = CivilDate.fromDateTime(DateTime.now().toUtc());
    final planId = newCommandId();
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
        onOff: OnOffPattern(anchor: today, onDays: 3, offDays: 2),
        timing: DailyCount(
          2,
          PlannedAmount(
            quantity: ExactQuantity.parse('1.25'),
            enteredText: '1.2500',
            unit: 'mg',
          ),
        ),
      ),
    );
    final initial = (await store.todayDailyRows(
      scope: FeedScope.person(owner.id),
      now: now,
      observedZone: 'UTC',
    )).rows.single;
    await store.actDaily(
      commandId: newCommandId(),
      row: initial,
      kind: DailyActionKind.taken,
      actualAt: now,
    );
    await store.saveBrowsingScope(FeedScope.person(owner.id));
    final providers = ProviderContainer(
      overrides: [storeLoaderProvider.overrideWithValue(() async => store)],
    );
    addTearDown(providers.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: providers, child: const VitalApp()),
    );
    await ui.waitFor(tester, find.text('Synthetic repeating substance'));
    providers.read(routerProvider).push('/pause/${item.id}?plan=$planId');
    await ui.waitFor(tester, find.text('Pause plan'));
    expect(find.textContaining('Synthetic pause adult'), findsWidgets);
    await ui.tap(tester, find.text('Preview'));
    await ui.tap(tester, find.text('Cancel'));
    expect(
      (await store.dailyPlans(itemId: item.id)).single.plan.pauses,
      isEmpty,
    );
    await ui.tap(tester, find.text('Preview'));
    await ui.tap(tester, find.text('Save'));
    await ui.waitFor(tester, find.text('Paused'));
    providers.read(routerProvider).push('/pause/${item.id}?plan=$planId');
    await ui.waitFor(tester, find.text('Resume plan'));
    await ui.tap(tester, find.text('Preserve'));
    await ui.tap(tester, find.text('Preview'));
    expect(find.textContaining('After:'), findsOneWidget);
    await ui.tap(tester, find.text('Save'));
    await ui.waitFor(tester, find.text('1 recorded, 0 skipped, 2 planned'));
    final reopened = await RecordStore.open(
      path: location.path,
      key: location.key,
      isNew: false,
    );
    try {
      final restored = (await reopened.dailyPlans(itemId: item.id)).single;
      expect(restored.plan.pauses.single.resume, isNotNull);
      expect(restored.plan.onOff!.anchor, today);
      final rows = (await reopened.todayDailyRows(
        scope: FeedScope.person(owner.id),
        now: DateTime.now().toUtc(),
        observedZone: 'UTC',
      )).rows;
      expect(rows.length, 1);
      expect(rows.single.takenCount, 1);
      expect(rows.single.expectation.identity, initial.expectation.identity);
      expect(rows.single.expectation.amount.enteredText, '1.2500');
      expect(
        (await reopened.records(scope: FeedScope.person(owner.id))).length,
        1,
      );
    } finally {
      await reopened.close();
    }
    expect(tester.takeException(), isNull);
  });
}
