import '../test/fixtures/single_user.dart';

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/features/plans/daily_feed.dart';
import 'package:true_grit_vital/platform/storage_bootstrap.dart';

Future<void> waitFor(WidgetTester tester, Finder target) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (target.evaluate().isNotEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('Expected UI did not appear: $target');
}

Future<void> tapLabel(WidgetTester tester, String label) async {
  await waitFor(tester, find.text(label));
  final target = find.text(label).last;
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Run only on a dedicated synthetic test installation. No real records are
  // erased, and the uniquely named synthetic record remains as test evidence.
  testWidgets('native encrypted record, correction, Undo and reopen', (
    tester,
  ) async {
    const bootstrap = AndroidStorageBootstrap();
    final location = await bootstrap.prepare();
    final store = await RecordStore.open(
      path: location.path,
      key: location.key,
      isNew: location.isNew,
    );
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
    await store.saveBrowsingScope(const FeedScope.me());
    final container = ProviderContainer(
      overrides: [storeLoaderProvider.overrideWithValue(() async => store)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const VitalApp()),
    );
    await waitFor(tester, find.text('Substances'));
    await tapLabel(tester, 'Substances');
    await tapLabel(tester, 'Create');
    final name =
        'Synthetic native check ${DateTime.now().microsecondsSinceEpoch}';
    await tester.enterText(find.byType(TextField).at(0), name);
    await tester.enterText(find.byType(TextField).at(1), 'Tablet');
    await tapLabel(tester, 'mg');
    await tester.enterText(find.byType(TextField).at(2), 'Medicine');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Create'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tapLabel(tester, 'Create');
    await waitFor(tester, find.text(name));
    await tapLabel(tester, 'Record');
    await tester.enterText(find.byType(TextField).first, '0.125');
    await tapLabel(tester, 'Save');
    await waitFor(tester, find.text('Me: 0.125 mg'));
    await tapLabel(tester, 'Correct');
    await tester.enterText(find.byType(TextField).first, '0.5');
    await tapLabel(tester, 'Save');
    await waitFor(tester, find.text('Me: 0.5 mg'));
    await tapLabel(tester, 'Undo');
    await waitFor(tester, find.text('Voided'));

    final record = (await store.records()).singleWhere(
      (row) => row.name == name,
    );
    expect(record.personId, meId);
    expect(record.source, RecordSource.selfReported);
    expect(record.revision, 3);
    expect(record.isVoided, isTrue);
    expect((await store.history(record.id)).map((row) => row.enteredAmount), [
      '0.125',
      '0.5',
      '0.5',
    ]);
    final other = await store.configureOwnProfile(
      commandId: newCommandId(),
      name: 'Synthetic other adult',
      adultConfirmed: true,
    );
    final otherItem = await store.createItem(
      commandId: newCommandId(),
      personId: other.id,
      expectedPersonRevision: other.revision,
      name: '$name other',
      form: 'Tablet',
      unit: 'mg',
      type: 'Medicine',
    );
    await store.saveBrowsingScope(const FeedScope.everyone());
    container.read(routerProvider).go('/record/${otherItem.id}');
    await waitFor(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField).first, '0.25');
    await tapLabel(tester, 'Save');
    final otherCard = find.byWidgetPredicate(
      (widget) => widget is RecordCard && widget.record.personId == other.id,
    );
    await waitFor(tester, otherCard);
    final correction = find.descendant(
      of: otherCard,
      matching: find.text('Correct'),
    );
    await tester.ensureVisible(correction);
    await tester.tap(correction);
    await waitFor(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField).first, '0.75');
    await tapLabel(tester, 'Save');
    await waitFor(tester, otherCard);
    final undo = find.descendant(of: otherCard, matching: find.text('Undo'));
    await tester.ensureVisible(undo);
    await tester.tap(undo);
    await tester.pumpAndSettle();
    await waitFor(
      tester,
      find.descendant(of: otherCard, matching: find.text('Voided')),
    );
    final otherRecord = (await store.records(personId: other.id))
        .firstWhere((r) => r.itemId == otherItem.id);
    expect(otherRecord.revision, 3);
    expect(otherRecord.source, RecordSource.selfReported);
    expect(otherRecord.isVoided, isTrue);
    expect((await store.recordById(record.id))!.revision, 3);
    final planId = newCommandId();
    final today = CivilDate.fromDateTime(DateTime.now().toUtc());
    await store.saveDailyPlan(
      commandId: newCommandId(),
      expectedGeneration: store.generation,
      expectedPersonRevision: other.revision,
      plan: DailyPlanVersion(
        personId: other.id,
        planId: planId,
        itemId: otherItem.id,
        versionId: newCommandId(),
        start: today,
        timing: DailyCount(
          2,
          PlannedAmount(
            quantity: ExactQuantity.parse('0.125'),
            enteredText: '0.125',
            unit: 'mg',
          ),
        ),
        zoneBasis: FixedHome('Etc/UTC'),
      ),
    );
    await tapLabel(tester, 'Today');
    final plannedCard = find.byWidgetPredicate(
      (widget) =>
          widget is DailyRowCard &&
          widget.row.expectation.identity.planId == planId,
    );
    await waitFor(tester, plannedCard);
    Future<void> planAction(String label) async {
      final button = find.descendant(
        of: plannedCard,
        matching: find.text(label),
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    Future<void> progress(String label) => waitFor(
      tester,
      find.descendant(of: plannedCard, matching: find.text(label)),
    );
    await planAction('Taken');
    await progress('1 recorded, 0 skipped, 2 planned');
    await planAction('Skip');
    await progress('1 recorded, 1 skipped, 2 planned');
    await planAction('Undo');
    await progress('1 recorded, 0 skipped, 2 planned');
    final captured = (await store.capturedDailyRows(
      scope: FeedScope.person(other.id),
    )).rows.singleWhere((row) => row.expectation.identity.planId == planId);
    expect(captured.takenCount, 1);
    expect(captured.skippedCount, 0);
    expect(captured.expectation.instant, isNull);
    final plannedActual = (await store.records(personId: other.id))
        .singleWhere((row) => !row.isVoided);
    expect(plannedActual.enteredAmount, '0.125');
    expect(plannedActual.source, RecordSource.selfReported);
    final again = await bootstrap.prepare();
    expect(again.isNew, isFalse);
    expect(again.key, location.key);
    final reopened = await RecordStore.open(
      path: again.path,
      key: again.key,
      isNew: false,
    );
    try {
      expect(
        (await reopened.records())
            .singleWhere((row) => row.id == record.id)
            .revision,
        3,
      );
      expect(
        (await reopened.recordById(otherRecord.id, personId: other.id))!.source,
        RecordSource.selfReported,
      );
      final reopenedPlan = (await reopened.capturedDailyRows(
        scope: FeedScope.person(other.id),
      )).rows.singleWhere((row) => row.expectation.identity.planId == planId);
      expect(reopenedPlan.takenCount, 1);
      expect(reopenedPlan.skippedCount, 0);
    } finally {
      await reopened.close();
    }
    final header = await File(location.path).open();
    try {
      expect(
        String.fromCharCodes(await header.read(16)),
        isNot('SQLite format 3\u0000'),
      );
    } finally {
      await header.close();
    }
    expect(tester.takeException(), isNull);
  });
}
