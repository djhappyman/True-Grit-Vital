import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/data/record_store.dart';

import 'vital_app_test.dart'
    show launch, settle, tap, appTest, runIo, waitForText;

void main() {
  appTest('Everyone selects named owner and scope survives detail Back', (
    tester,
  ) async {
    final f = await launch(tester);
    final people = await runIo(tester, () async {
      final a = await f.store.createProfile(
        commandId: 'adult-a',
        name: 'Alex Taylor',
        adultConfirmed: true,
      );
      final b = await f.store.createProfile(
        commandId: 'adult-b',
        name: 'Alex Taylor',
        adultConfirmed: true,
      );
      await f.store.createItem(
        commandId: 'item-a',
        personId: a.id,
        name: 'Alex A item',
        form: 'Tablet',
        unit: 'mg',
        type: 'Supplement',
      );
      await f.store.createItem(
        commandId: 'item-b',
        personId: b.id,
        name: 'Alex B item',
        form: 'Tablet',
        unit: 'mg',
        type: 'Supplement',
      );
      await f.store.saveBrowsingScope(const FeedScope.everyone());
      return [a, b];
    });
    await settle(tester);
    await tap(tester, 'Substances');
    expect(find.text('Alex A item'), findsOneWidget);
    expect(find.text('Alex B item'), findsOneWidget);
    expect(find.textContaining('Profile ${people![0].id}'), findsWidgets);
    await tap(tester, 'Create');
    expect(find.text('Choose person'), findsOneWidget);
    await tap(tester, 'Alex Taylor. Profile ${people[0].id}');
    expect(
      find.textContaining('Person: Alex Taylor. Profile ${people[0].id}'),
      findsOneWidget,
    );
    await tap(tester, 'Back');
    expect(find.text('Everyone'), findsOneWidget);
    await tap(tester, 'Scope');
    await tap(tester, 'Alex Taylor. Profile ${people[1].id}');
    expect(find.text('Alex A item'), findsNothing);
    expect(find.text('Alex B item'), findsOneWidget);
    expect(
      (await runIo(tester, f.store.readBrowsingScope))!.personId,
      people[1].id,
    );
  });

  appTest('archiving a captured owner rejects draft and retains history', (
    tester,
  ) async {
    final f = await launch(tester);
    final adult = await runIo(tester, () async {
      final a = await f.store.createProfile(
        commandId: 'adult',
        name: 'Morgan Sample',
        adultConfirmed: true,
      );
      await f.store.createItem(
        commandId: 'item',
        personId: a.id,
        name: 'Morgan item',
        form: 'Tablet',
        unit: 'mg',
        type: 'Supplement',
      );
      await f.store.saveBrowsingScope(FeedScope.person(a.id));
      return a;
    });
    await settle(tester);
    await tap(tester, 'Substances');
    await tap(tester, 'Record');
    await tester.enterText(find.byType(TextField).at(0), '2');
    await settle(tester);
    await runIo(
      tester,
      () => f.store.archiveProfile(
        commandId: 'archive',
        personId: adult!.id,
        expectedRevision: adult.revision,
      ),
    );
    await settle(tester);
    await tap(tester, 'Save');
    expect(find.textContaining('This record has changed'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3));
    expect(
      (await runIo(
        tester,
        () => f.store.records(scope: FeedScope.person(adult!.id)),
      ))!,
      isEmpty,
    );
    await tap(tester, 'Back');
    await tap(tester, 'Discard');
    expect(find.text('Morgan item'), findsNothing);
    expect(find.text('Everyone'), findsOneWidget);
    await tap(tester, 'People');
    await tap(tester, 'Edit');
    expect(find.text('Archived'), findsNothing);
    await tap(tester, 'Reactivate');
    await tap(tester, 'Reactivate');
    expect(
      (await runIo(tester, () => f.store.profileById(adult!.id)))!.isArchived,
      isFalse,
    );
  });

  appTest('profile setup stays short and requires adult confirmation', (
    tester,
  ) async {
    tester.view.resetPhysicalSize();
    final f = await launch(tester);
    await tap(tester, 'People');
    await tap(tester, 'Add');
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Casey Sample');
    await tap(tester, 'Save');
    expect(
      find.textContaining('confirm this person is an adult'),
      findsOneWidget,
    );
    await tester.tap(find.text('Adult confirmed'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tap(tester, 'Save');
    expect(
      (await runIo(
        tester,
        f.store.profiles,
      ))!.any((p) => p.name == 'Casey Sample' && p.adultConfirmed),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
  appTest('Me setup requires adult confirmation at large text', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await launch(tester, completeSetup: false);
    expect(find.text('Edit person'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Main Adult Full Name');
    await tap(tester, 'Adult confirmed');
    await tap(tester, 'Save');
    expect(find.text('Today'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  appTest(
    'Undo retry preserves owner epoch after lost reply and profile edit',
    (tester) async {
      var attempts = 0;
      final ids = <String>[];
      final epochs = <int?>[];
      final f = await launch(
        tester,
        voidWriter: (store, input) async {
          ids.add(input.commandId);
          epochs.add(input.expectedPersonRevision);
          final result = await store.voidRecord(
            commandId: input.commandId,
            recordId: input.recordId,
            expectedRevision: input.expectedRevision,
            personId: input.personId,
            expectedPersonRevision: input.expectedPersonRevision,
          );
          if (attempts++ == 0) throw StateError('synthetic lost reply');
          return result;
        },
      );
      await runIo(tester, () async {
        final item = await f.store.createItem(
          commandId: 'retry-item',
          name: 'Retry item',
          form: 'Tablet',
          unit: 'mg',
          type: 'Supplement',
          expectedPersonRevision: 2,
        );
        await f.store.record(
          commandId: 'retry-record',
          itemId: item.id,
          amount: '1',
          actualAt: DateTime.now(),
          expectedPersonRevision: 2,
        );
      });
      final original = (await runIo(tester, f.store.records))!.single;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: ShadcnApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en', 'GB')],
            home: Scaffold(
              child: PageContent(children: [RecordCard(record: original)]),
            ),
          ),
        ),
      );
      await settle(tester);
      await tap(tester, 'Undo');
      await runIo(tester, () async {
        final me = (await f.store.profileById(meId))!;
        await f.store.editProfile(
          commandId: 'rename-after-commit',
          personId: meId,
          expectedRevision: me.revision,
          name: 'Renamed adult',
          adultConfirmed: true,
        );
      });
      await settle(tester);
      await tap(tester, 'Undo');
      final rows = (await runIo(tester, f.store.records))!;
      expect(rows.single.isVoided, isTrue);
      expect(rows.single.revision, 2);
      expect(ids, hasLength(2));
      expect(ids.first, ids.last);
      expect(epochs, [2, 2]);
    },
  );
  appTest('another adult records and corrects twice with captured ownership', (
    tester,
  ) async {
    final f = await launch(tester);
    final adult = await runIo(tester, () async {
      final a = await f.store.createProfile(
        commandId: 'correction-adult',
        name: 'Alex Full Name',
        adultConfirmed: true,
      );
      await f.store.createItem(
        commandId: 'correction-item',
        personId: a.id,
        name: 'Alex owned item',
        form: 'Tablet',
        unit: 'mg',
        type: 'Supplement',
      );
      await f.store.saveBrowsingScope(const FeedScope.everyone());
      return a;
    });
    await settle(tester);
    await tap(tester, 'Substances');
    await tap(tester, 'Record');
    await tester.enterText(find.byType(TextField).at(0), '1');
    await tap(tester, 'Save');
    await waitForText(tester, 'Alex Full Name: 1 mg');
    expect(find.text('Alex Full Name: 1 mg'), findsOneWidget);
    await tap(tester, 'Correct');
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
      '1',
    );
    await runIo(tester, () => f.store.saveBrowsingScope(const FeedScope.me()));
    await settle(tester);
    expect(
      find.textContaining('Correct actual use for Alex Full Name'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField).at(0), '2');
    await tap(tester, 'Save');
    expect(find.text('Alex Full Name: 2 mg'), findsOneWidget);
    await runIo(
      tester,
      () => f.store.saveBrowsingScope(const FeedScope.everyone()),
    );
    await settle(tester);
    await tap(tester, 'Correct');
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
      '2',
    );
    await tester.enterText(find.byType(TextField).at(0), '3');
    await tap(tester, 'Save');
    await waitForText(tester, 'Alex Full Name: 3 mg');
    expect(find.text('Alex Full Name: 3 mg'), findsOneWidget);
    await tap(tester, 'Undo');
    final rows = (await runIo(
      tester,
      () => f.store.records(personId: adult!.id),
    ))!;
    expect(rows.single.revision, 4);
    expect(rows.single.isVoided, isTrue);
    expect(rows.single.personId, adult!.id);
    expect(rows.single.source, RecordSource.recordedOnBehalf);
    expect((await runIo(tester, f.store.records))!, isEmpty);
  });
}
