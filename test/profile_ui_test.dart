import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/data/record_store.dart';

import 'vital_app_test.dart' show launch, settle, tap, appTest, runIo;

void main() {
  appTest('Me setup requires adult confirmation at large text', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await launch(tester, completeSetup: false);
    expect(find.text('Profile'), findsOneWidget);
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
}
