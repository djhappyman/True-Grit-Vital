import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/reports.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';

import '../vital_app_test.dart' show appTest, launch, runIo, settle, tap;

void main() {
  appTest('History report entry retains the person and half-open date window', (
    tester,
  ) async {
    final f = await launch(tester);
    final other = (await runIo(
      tester,
      () => f.store.createProfile(
        commandId: 'report-other',
        name: 'Alex Example',
        adultConfirmed: true,
      ),
    ))!;
    f.container
        .read(routerProvider)
        .push('/reports?person=${other.id}&from=2026-10-01&before=2026-10-22');
    await settle(tester);
    final selection = f.container.read(reportControllerProvider).selection!;
    expect(selection.personId, other.id);
    expect(selection.fromDate, CivilDate(2026, 10, 1));
    expect(selection.beforeDate, CivilDate(2026, 10, 22));
    expect(find.text('2026-10-21'), findsWidgets);
    await tap(tester, 'Detailed history');
    final history = f.container.read(reportControllerProvider).selection!;
    expect(history.template, ReportTemplateId.r02DetailedHistory);
    expect(history.includeSkipped, isTrue);
    expect(history.includeUnrecorded, isTrue);
    expect(find.text('Skipped entries'), findsOneWidget);
    expect(find.text('Unrecorded entries'), findsOneWidget);
  });

  appTest('a missing person link cannot silently generate for Me', (
    tester,
  ) async {
    final f = await launch(tester);
    f.container.read(routerProvider).push('/reports?person=missing-adult');
    await settle(tester);
    expect(f.container.read(reportControllerProvider).selection, isNull);
    expect(find.text('Preview'), findsNothing);
  });
}
