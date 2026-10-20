import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/reports.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';

import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

void main() {
  appTest('one feed and direct creation replace the people and scope screens', (
    tester,
  ) async {
    final f = await launch(tester);
    await runIo(tester, f.store.enableSingleUser);
    for (final label in ['Everyone', 'Scope', 'People']) {
      expect(find.text(label), findsNothing);
    }
    await tap(tester, 'Substances');
    await tap(tester, 'Create');
    expect(find.byType(TextField), findsWidgets);
    expect(find.text('Choose person'), findsNothing);
    f.container.read(routerProvider).go('/event-create');
    await settle(tester);
    expect(find.text('Choose person'), findsNothing);
    expect(find.byType(TextField), findsWidgets);
    f.container.read(routerProvider).go('/scope');
    await settle(tester);
    expect(
      f.container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/today',
    );
    f.container.read(routerProvider).go('/people/add');
    await settle(tester);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Add person'), findsNothing);
    expect((await runIo(tester, f.store.profiles))!.single.id, meId);
  });

  appTest('reports and exports open for your records without a person picker', (
    tester,
  ) async {
    final f = await launch(tester);
    await runIo(tester, f.store.enableSingleUser);
    f.container.read(routerProvider).go('/reports');
    await settle(tester);
    expect(
      f.container.read(reportControllerProvider).selection!.personId,
      meId,
    );
    expect(find.text('Choose person'), findsNothing);
    f.container.read(routerProvider).go('/exports');
    await settle(tester);
    expect(
      find.text(
        'Choose a date range and the content to include. The preview is the exact file you can save.',
      ),
      findsOneWidget,
    );
    expect(find.text('Person'), findsNothing);
    f.container.read(routerProvider).go('/files/another-person/item/unknown');
    await settle(tester);
    expect(
      f.container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/today',
    );
  });

  appTest('delete removes your records and leaves the profile usable', (
    tester,
  ) async {
    final f = await launch(tester);
    await runIo(tester, () async {
      await f.store.enableSingleUser();
      final item = await f.store.createItem(
        commandId: 'mine',
        name: 'Synthetic',
        form: 'Tablet',
        unit: 'mg',
        type: 'Medicine',
        expectedPersonRevision: 2,
      );
      await f.store.record(
        commandId: 'dose',
        itemId: item.id,
        amount: '1',
        actualAt: DateTime.now().toUtc(),
        expectedPersonRevision: 2,
      );
    });
    await tap(tester, 'Settings');
    await tap(tester, 'Privacy');
    expect(find.text('Archive'), findsNothing);
    await tap(tester, 'Delete');
    expect(
      find.text(
        'Delete all your saved records, files and drafts? This cannot be undone. Saved or shared copies outside Vital remain.',
      ),
      findsOneWidget,
    );
    await tap(tester, 'Delete');
    await waitForText(
      tester,
      'Records deleted. Your profile is still available.',
    );
    expect(
      find.text('Records deleted. Your profile is still available.'),
      findsOneWidget,
    );
    expect(await runIo(tester, f.store.records), isEmpty);
    expect((await runIo(tester, f.store.profiles))!.single.id, meId);
  });
}
