import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/history/history_pages.dart'
    show HistoryEntryCard;

import 'stock_ui_test.dart' show item;
import 'vital_app_test.dart' show appTest, launch, runIo, settle, tap;

void main() {
  appTest(
    'a History-linked chart series stays selected after narrowing the range',
    (tester) async {
      final f = await launch(tester);
      final revision = (await runIo(
        tester,
        () => f.store.profileById(meId),
      ))!.revision;
      final selected = (await runIo(
        tester,
        () => item(f.store, name: 'Selected medicine'),
      ))!;
      final other = (await runIo(
        tester,
        () => item(f.store, name: 'Other medicine'),
      ))!;
      await runIo(tester, () async {
        await f.store.record(
          commandId: 'selected-use',
          expectedPersonRevision: revision,
          itemId: selected.id,
          amount: '1',
          actualAt: DateTime.utc(2026, 10, 1, 12),
        );
        await f.store.record(
          commandId: 'other-use',
          expectedPersonRevision: revision,
          itemId: other.id,
          amount: '2',
          actualAt: DateTime.utc(2026, 10, 2, 12),
        );
      });
      f.container
          .read(routerProvider)
          .go(
            Uri(
              path: '/charts',
              queryParameters: {
                'scope': meId,
                'item': selected.id,
                'from': '2026-10-01T00:00:00Z',
                'before': '2026-10-05T00:00:00Z',
              },
            ).toString(),
          );
      await settle(tester);
      expect(find.text('Selected medicine · mg'), findsWidgets);
      expect(find.text('1 mg'), findsWidgets);

      await tap(tester, 'Narrow');
      expect(find.text('Selected medicine · mg'), findsWidgets);
      expect(find.text('Other medicine · mg'), findsNothing);
      expect(find.text('2 mg'), findsNothing);
      expect(find.text('No recorded use in this range.'), findsOneWidget);

      await tap(tester, 'View');
      expect(find.text('No recorded use in this range.'), findsOneWidget);
      expect(find.byType(HistoryEntryCard, skipOffstage: false), findsNothing);

      await tap(tester, 'Widen');
      expect(find.text('Selected medicine · mg'), findsWidgets);
      expect(find.text('1 mg'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  appTest(
    'a requested chart series with no points in range never charts another series',
    (tester) async {
      final f = await launch(tester);
      final revision = (await runIo(
        tester,
        () => f.store.profileById(meId),
      ))!.revision;
      final requested = (await runIo(
        tester,
        () => item(f.store, name: 'Requested medicine'),
      ))!;
      final other = (await runIo(
        tester,
        () => item(f.store, name: 'Other medicine'),
      ))!;
      await runIo(
        tester,
        () => f.store.record(
          commandId: 'other-use',
          expectedPersonRevision: revision,
          itemId: other.id,
          amount: '2',
          actualAt: DateTime.utc(2026, 10, 2, 12),
        ),
      );
      f.container
          .read(routerProvider)
          .go(
            Uri(
              path: '/charts',
              queryParameters: {
                'scope': meId,
                'subject': requested.id,
                'kind': 'item',
                'unit': 'mg',
                'from': '2026-10-01T00:00:00Z',
                'before': '2026-10-05T00:00:00Z',
              },
            ).toString(),
          );
      await settle(tester);
      expect(find.text('2 mg'), findsNothing);
      expect(find.textContaining('Other medicine'), findsNothing);
      expect(find.text('No recorded use in this range.'), findsOneWidget);
      // No saved name is available for a series with no rows in range, so the
      // exact requested subject stays visible rather than another series' name.
      expect(find.text('${requested.id} · mg'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  appTest('a malformed series seed is ignored instead of failing the chart', (
    tester,
  ) async {
    final f = await launch(tester);
    final revision = (await runIo(
      tester,
      () => f.store.profileById(meId),
    ))!.revision;
    final medicine = (await runIo(
      tester,
      () => item(f.store, name: 'Fallback medicine'),
    ))!;
    await runIo(
      tester,
      () => f.store.record(
        commandId: 'fallback-use',
        expectedPersonRevision: revision,
        itemId: medicine.id,
        amount: '1',
        actualAt: DateTime.utc(2026, 10, 2, 12),
      ),
    );
    f.container
        .read(routerProvider)
        .go(
          '/charts?scope=$meId&subject=&kind=item&unit=&from=2026-10-01T00:00:00Z&before=2026-10-05T00:00:00Z',
        );
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Fallback medicine · mg'), findsWidgets);
    expect(find.text('1 mg'), findsWidgets);
  });
}
