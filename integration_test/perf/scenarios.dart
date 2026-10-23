import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/domain/records.dart' show meId;

/// The four bounded measurement scenarios. Behaviour mirrors the real flows
/// the owner highlighted for validation: shell page swiping on Today, long
/// History and stock browsing and the interactive record flow. The helpers
/// follow the fixtures that already run on the dedicated Android emulator
/// (integration_test/stock_flow_test.dart and record_flow_test.dart).

/// Waits until [target] appears under bounded repeated pumps, then settles.
/// A timeout surfaces as [PerfScenarioError]; the harness turns it into an
/// unsupported scenario with a truthful reason rather than pretending.
Future<void> perfWaitFor(WidgetTester tester, Finder target) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (target.evaluate().isNotEmpty) {
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      return;
    }
  }
  throw PerfScenarioError('target_not_appeared');
}

/// The frame budget the SDK's summarizer counts jank against. The pinned SDK
/// exposes the mutable global `kBuildBudget` for exactly this purpose
/// (flutter_test/src/frame_timing_summarizer.dart, upstream TODO #61958), so
/// the fixture sets it from the actually reported display rate instead of
/// keeping a universal 16 ms assertion.
Duration perfFrameBudget(double? refreshRateHz) {
  if (refreshRateHz == null) return const Duration(milliseconds: 16);
  return Duration(microseconds: (1e6 / refreshRateHz).round());
}

/// Logical viewport of the primary test view in device-independent pixels.
Size perfViewLogicalSize(WidgetTester tester) {
  final view = tester.view;
  return Size(
    view.physicalSize.width / view.devicePixelRatio,
    view.physicalSize.height / view.devicePixelRatio,
  );
}

/// Repeated balanced vertical drags over the app's central scrollable: one
/// down-and-back-up cycle per pass.
Future<void> perfScrollPasses(WidgetTester tester, int passes) async {
  final size = perfViewLogicalSize(tester);
  for (var i = 0; i < passes; i++) {
    await tester.dragFrom(
      Offset(size.width / 2, size.height * 0.7),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 150));
    await tester.dragFrom(
      Offset(size.width / 2, size.height * 0.4),
      const Offset(0, 400),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 150));
  }
}

/// Repeated alternating horizontal drags across the shell pager so each pass
/// moves off Today and back, exercising the composed chrome while moving.
Future<void> perfTodaySwipePasses(WidgetTester tester, int passes) async {
  final size = perfViewLogicalSize(tester);
  for (var i = 0; i < passes; i++) {
    final offset = i.isEven ? -size.width * 0.75 : size.width * 0.75;
    await tester.dragFrom(
      Offset(size.width / 2, size.height * 0.6),
      Offset(offset, 0),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 150));
  }
}

/// One interactive record flow through the real dose form, then an Undo so
/// repeated runs do not accumulate thousands of fresh records mid-run.
Future<void> perfRecordOnce(WidgetTester tester, int amount) async {
  await perfWaitFor(tester, find.byType(TextField));
  await tester.enterText(find.byType(TextField).first, '$amount');
  FocusManager.instance.primaryFocus?.unfocus();
  await perfWaitFor(tester, find.text('Save'));
  await tester.ensureVisible(find.text('Save').first);
  await tester.tap(find.text('Save').first);
  await tester.pumpAndSettle(const Duration(milliseconds: 150));
  await perfWaitFor(tester, find.text('Undo'));
  await tester.ensureVisible(find.text('Undo').first);
  await tester.tap(find.text('Undo').first);
  await tester.pumpAndSettle(const Duration(milliseconds: 150));
}

/// Measured workloads per scenario key. The fixture looks these up inside
/// `watchPerformance` while the binding collects engine FrameTimings; each
/// workload only performs real interactive work. [navigate] drives the real
/// router so stateful multi-step scenarios can restart between passes.
typedef PerfScenarioWorkload = Future<void> Function(
  WidgetTester tester,
  int repeats,
  void Function(String route) navigate,
);

/// The workload for one scenario key. Unknown keys fail closed — the job
/// decoder already rejects them, so an unknown key here is a contract bug.
PerfScenarioWorkload perfScenarioWorkload({
  required String key,
  required String itemId,
}) => switch (key) {
  'today_swipe' => (tester, repeats, _) => perfTodaySwipePasses(
    tester,
    repeats,
  ),
  'history_scroll' => (tester, repeats, _) => perfScrollPasses(tester, repeats),
  'stock_scroll' => (tester, repeats, _) => perfScrollPasses(tester, repeats),
  'record_save' => (tester, repeats, navigate) => _recordSaveRepeats(
    tester,
    repeats,
    navigate,
    '/record/$itemId',
  ),
  _ => throw PerfScenarioError('unknown_scenario:$key'),
};

/// One navigation, record and undo per repeat: the dose form starts from its
/// settled route the same way each pass, so samples stay comparable.
Future<void> _recordSaveRepeats(
  WidgetTester tester,
  int repeats,
  void Function(String route) navigate,
  String recordRoute,
) async {
  for (var i = 0; i < repeats; i++) {
    navigate(recordRoute);
    await perfRecordOnce(tester, 2);
  }
}

/// Scenario routes and their surface landmarks. The landmark finders use the
/// established English literals from the existing fixtures; every key has
/// one route and one landmark so a missing surface is a truthful unsupported,
/// never a guess.
Map<String, String> perfScenarioRoutes(String itemId) => {
  'today_swipe': '/today',
  'history_scroll': '/history?view=list',
  'stock_scroll': '/stock/$meId',
  'record_save': '/record/$itemId',
};

/// Returns the scenario's landmark finder for the prepared surface.
Finder perfScenarioLandmark(String key, String itemId) => switch (key) {
  'today_swipe' => find.text('Today'),
  'history_scroll' => find.text('History'),
  'stock_scroll' => find.text('Stock'),
  'record_save' => find.byType(TextField),
  _ => throw PerfScenarioError('unknown_scenario:$key'),
};

final class PerfScenarioError implements Exception {
  const PerfScenarioError(this.code);
  final String code;
  @override
  String toString() => 'PerfScenarioError($code)';
}
