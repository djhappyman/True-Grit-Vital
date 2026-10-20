import '../test/fixtures/single_user.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/platform/storage_bootstrap.dart';

import 'stock_flow_test.dart' as stock;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native combined group, atomic Undo and encrypted reopen', (
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
    final token = DateTime.now().microsecondsSinceEpoch;
    final adult = await store.configureOwnProfile(
      commandId: newCommandId(),
      name: 'Synthetic combined adult $token',
      adultConfirmed: true,
    );
    final items = <SubstanceItem>[];
    for (var i = 0; i < 2; i++) {
      items.add(
        await store.createItem(
          commandId: newCommandId(),
          personId: adult.id,
          expectedPersonRevision: adult.revision,
          name: 'Synthetic combined source $i $token',
          form: 'Tablet',
          unit: 'count',
          type: 'Test',
        ),
      );
    }
    final providers = ProviderContainer(
      overrides: [storeLoaderProvider.overrideWithValue(() async => store)],
    );
    addTearDown(providers.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: providers, child: const VitalApp()),
    );
    await stock.waitFor(tester, find.text('Substances'));
    providers.read(routerProvider).go('/combined/${adult.id}');
    await stock.waitFor(tester, find.text('Combined entry'));
    for (final item in items) {
      await stock.tap(tester, find.text('Add'));
      await stock.tap(tester, find.byKey(ValueKey('combine-add-${item.id}')));
    }
    for (var i = 0; i < 2; i++) {
      final field = find.descendant(
        of: find.widgetWithText(LabelledInput, 'Amount').at(i),
        matching: find.byType(TextField),
      );
      await stock.reveal(tester, field);
      await tester.enterText(field, '1');
    }
    await stock.tap(tester, find.text('Review'));
    await stock.tap(tester, find.text('Save'));
    await stock.waitFor(
      tester,
      find.text(
        'Correct or undo every source together. Each source retains its own history.',
      ),
    );
    final records = await store.records(personId: adult.id);
    expect(records.length, 2);
    expect(records.map((r) => r.combinedActionId).toSet().length, 1);
    providers
        .read(routerProvider)
        .go(
          '/combined/${adult.id}/edit/${records.first.combinedActionId}?undo=true',
        );
    await stock.waitFor(tester, find.text('Correct entry'));
    await stock.tap(tester, find.text('Review'));
    await stock.tap(tester, find.text('Save'));
    await stock.waitFor(tester, find.text('Voided'));
    final reopened = await RecordStore.open(
      path: location.path,
      key: location.key,
      isNew: false,
    );
    try {
      final saved = await reopened.records(personId: adult.id);
      expect(saved.length, 2);
      expect(saved.every((r) => r.isVoided), true);
      for (final r in saved) {
        expect((await reopened.history(r.id)).length, 2);
      }
    } finally {
      await reopened.close();
    }
  });
}
