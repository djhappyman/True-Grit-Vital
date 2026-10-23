import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/display_preferences.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/history/history_pages.dart';
import 'package:true_grit_vital/features/plans/plan_timing_fields.dart';

import 'design_system_test.dart' show host;
import 'screen_settings_hub_test.dart' show loadFonts;

void main() {
  setUpAll(loadFonts);
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets(
      'captured timing labels fit narrow large text in ${brightness.name}',
      (tester) async {
        final p = DailyPlanVersion(
          personId: meId,
          planId: 'p',
          itemId: 'i',
          versionId: 'v',
          start: CivilDate(2026, 10, 23),
          zoneBasis: FixedHome('UTC'),
          timingPolicy: PlanTimingPolicy(allowanceMinutes: 15),
          timing: DailySlots([
            DailySlot(
              id: 'am',
              time: WallTime(8, 0),
              reminderEnabled: true,
              amount: PlannedAmount(
                quantity: ExactQuantity.parse('1'),
                unit: 'count',
              ),
            ),
          ]),
        );
        final expected = DailyResolver()
            .resolveDate(p, CivilDate(2026, 10, 23), observedZone: 'UTC')
            .single;
        final record = UseRecord(
          id: 'r',
          personId: meId,
          itemId: 'i',
          name: 'Synthetic medicine',
          form: 'Tablet',
          unit: 'count',
          type: 'Medicine',
          enteredAmount: '1',
          actualAt: DateTime.utc(2026, 10, 23, 8, 10),
          enteredAt: DateTime.utc(2026, 10, 23, 8, 11),
          revision: 1,
          isVoided: false,
        );
        final entry = RecordTimelineEntry(
          record: record,
          planContext: TimelinePlanContext(expectation: expected),
        );
        tester.view.physicalSize = const Size(320, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final key = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            child: host(
              Builder(
                builder: (context) => RepaintBoundary(
                  key: key,
                  child: ColoredBox(
                    color: brightness == Brightness.light
                        ? const Color(0xffffffff)
                        : const Color(0xff0e1714),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            HistoryEntryCard(
                              entry: entry,
                              formatter: displayFormatter(
                                context,
                                const DisplayPreferences().timeFormat,
                              ),
                              zone: 'UTC',
                              onInspect: () {},
                            ),
                            const SizedBox(height: 16),
                            PlanTimingSummary(policy: p.timingPolicy),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              brightness: brightness,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Within your window'), findsOneWidget);
        expect(tester.takeException(), isNull);
        const output = String.fromEnvironment('VITAL_TIMING_CAPTURES');
        if (output.isNotEmpty) {
          await tester.runAsync(() async {
            final image =
                await (key.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            try {
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                '$output/${brightness.name}-history-320-2x.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
      },
    );
  }

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('timing controls fit 320 pixels at 2x in ${brightness.name}', (
      tester,
    ) async {
      final fields = PlanTimingFields()
        ..load(PlanTimingPolicy(allowanceMinutes: 15, followUpMinutes: 30));
      addTearDown(fields.dispose);
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final key = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          child: host(
            SingleChildScrollView(
              child: RepaintBoundary(
                key: key,
                child: ColoredBox(
                  color: brightness == Brightness.light
                      ? const Color(0xffffffff)
                      : const Color(0xff0e1714),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: StatefulBuilder(
                      builder: (context, setState) => PlanTimingEditor(
                        fields: fields,
                        enabled: true,
                        onChanged: () => setState(() {}),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            brightness: brightness,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Timing'));
      await tester.pumpAndSettle();
      expect(find.text('Allowance (minutes)'), findsOneWidget);
      expect(find.text('Delay (minutes)'), findsOneWidget);
      expect(tester.takeException(), isNull);
      const output = String.fromEnvironment('VITAL_TIMING_CAPTURES');
      if (output.isNotEmpty) {
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('$output/${brightness.name}-editor-320-2x.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }
    });
  }
  test('timing form draft preserves off values and requires deliberate re-enabling', () {
    final fields = PlanTimingFields();
    addTearDown(fields.dispose);
    fields.allowance.text = '15';
    fields.delay.text = '30';
    expect(fields.candidate(), isNull);
    fields.labels = true;
    fields.followUp = true;
    final restored = PlanTimingFields();
    addTearDown(restored.dispose);
    restored.restore(fields.capture());
    expect(restored.candidate()!.toJson(), {'allowance': 15, 'followUp': 30});
    restored.followUp = false;
    expect(restored.candidate()!.followUpMinutes, isNull);
    expect(restored.delay.text, '30');
  });
}
