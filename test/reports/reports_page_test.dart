import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/reports.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';

import '../vital_app_test.dart' show appTest, launch, settle, tap;

void main() {
  appTest('History report entry retains the person and half-open date window', (
    tester,
  ) async {
    final f = await launch(tester);
    f.container
        .read(routerProvider)
        .push('/reports?person=$meId&from=2026-10-01&before=2026-10-22');
    await settle(tester);
    final selection = f.container.read(reportControllerProvider).selection!;
    expect(selection.personId, meId);
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

  appTest('stock details start off and stay in the reviewed selection', (
    tester,
  ) async {
    final f = await launch(tester);
    f.container
        .read(routerProvider)
        .push('/reports?person=$meId&from=2026-10-01&before=2026-10-22');
    await settle(tester);
    final initial = f.container.read(reportControllerProvider).selection!;
    expect(initial.includeStock, isFalse);
    expect(find.text('Stock details'), findsOneWidget);
    expect(find.text('Stock details: not included'), findsOneWidget);

    await tap(tester, 'Stock details');
    final selected = f.container.read(reportControllerProvider).selection!;
    expect(selected.includeStock, isTrue);
    expect(selected.identity, isNot(initial.identity));
    expect(find.text('Stock details: included'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
