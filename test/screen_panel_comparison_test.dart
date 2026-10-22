import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/display_preferences.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/supporting/screen_panel_widgets.dart';

import 'design_system_test.dart' show host;
import 'supporting_categories_comparison_test.dart' show point;
import 'supporting_ui_test.dart' show SupportingOpenLock;
import 'vital_app_test.dart' show appTest, launch, runIo, waitForText;

void main() {
  testWidgets('incompatible and incomplete comparisons state their reason', (
    tester,
  ) async {
    final viewed = point('viewed', 15, value: '2');
    final request = (
      personId: meId,
      id: 'viewed',
      revision: 1,
      resultId: 'result-viewed',
      displayZone: 'UTC',
    );
    Future<void> show(SupportingEarlierComparison comparison) async {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            appLockProvider.overrideWith(SupportingOpenLock.new),
            displayZoneProvider.overrideWithValue('UTC'),
            screenPanelEarlierProvider(request)
                .overrideWith((ref) => Stream.value(comparison)),
          ],
          child: host(
            SizedBox(
              width: 320,
              child: ScreenPanelComparison(
                viewed: viewed,
                result: viewed.snapshot.results.single,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(
      const SupportingEarlierComparison(
        status: SupportingEarlierStatus.incompatible,
      ),
    );
    expect(
      find.text(
        'Comparison needs an exact or qualitative value and matching units, '
        'laboratory, method and specimen.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Checks every saved result before this panel.'),
      findsNothing,
    );

    await show(
      const SupportingEarlierComparison(
        status: SupportingEarlierStatus.incomplete,
      ),
    );
    expect(
      find.text(
        'Collection dates do not establish an unambiguous previous result.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  appTest('panel prior comparison follows correction, void and restore', (
    tester,
  ) async {
    final f = await launch(tester);
    for (final row in [
      point('prior', 1, value: '1.25'),
      point('viewed', 15, value: '2.0'),
    ]) {
      await runIo(
        tester,
        () => f.store.saveLabPanel(
          SaveLabPanelCommand(
            commandId: 'seed-${row.id.id}',
            generation: f.store.generation,
            expectedPersonRevision: 2,
            panel: row.snapshot as LabPanelSnapshot,
          ),
        ),
      );
    }
    f.container.read(routerProvider).go('/supporting/me/viewed');
    await waitForText(tester, 'Change: +0.75.');
    expect(
      find.text('Checks every saved result before this panel.'),
      findsOneWidget,
    );

    await runIo(
      tester,
      () => f.store.saveLabPanel(
        SaveLabPanelCommand(
          commandId: 'correct-prior',
          generation: f.store.generation,
          expectedPersonRevision: 2,
          expectedRevision: 1,
          panel: point('prior', 1, value: '1.5').snapshot as LabPanelSnapshot,
        ),
      ),
    );
    await waitForText(tester, 'Change: +0.5.');

    final prior = (await runIo(
      tester,
      () => f.store.supportingRecord(meId, 'prior'),
    ))!;
    final voided = (await runIo(
      tester,
      () => f.store.voidSupportingRecord(
        VoidSupportingRecordCommand(
          commandId: 'void-prior',
          generation: f.store.generation,
          personId: meId,
          id: 'prior',
          expectedPersonRevision: 2,
          expectedRevision: prior.revision,
        ),
      ),
    ))!;
    await waitForText(tester, 'No comparable earlier result.');

    await runIo(
      tester,
      () => f.store.voidSupportingRecord(
        VoidSupportingRecordCommand(
          commandId: 'restore-prior',
          generation: f.store.generation,
          personId: meId,
          id: 'prior',
          expectedPersonRevision: 2,
          expectedRevision: voided.revision,
          isVoided: false,
        ),
      ),
    );
    await waitForText(tester, 'Change: +0.5.');
    expect(tester.takeException(), isNull);
  });
}
