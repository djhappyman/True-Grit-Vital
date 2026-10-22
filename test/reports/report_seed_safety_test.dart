import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/reports.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/platform/device_zone.dart';
import 'package:true_grit_vital/features/reports/reports_page.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart'
    show LabelledInput;
import 'package:true_grit_vital/ui/vital_ui.dart';
import 'package:true_grit_vital/l10n/app_localizations.dart';
import 'package:true_grit_vital/features/profiles/profile_pages.dart'
    show profilesProvider;

import '../vital_app_test.dart' show appTest, launch, settle, tap;

const captureDirectory = String.fromEnvironment('VITAL_REPORT_SEED_CAPTURE');

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  if (captureDirectory.isEmpty) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$captureDirectory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

class _BeforeSeed extends StatelessWidget {
  const _BeforeSeed({required this.onFrame});
  final VoidCallback onFrame;
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => onFrame());
    return const ReportsPage(from: '2026-01-01', before: '2026-02-01');
  }
}

void main() {
  setUpAll(() async {
    if (captureDirectory.isEmpty) return;
    await (FontLoader('StitchSans')
          ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-Medium.ttf'))
          ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-SemiBold.ttf'))
          ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-Bold.ttf')))
        .load();
    await (FontLoader('NotoSans')
          ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf')))
        .load();
    await (FontLoader('packages/shadcn_flutter/LucideIcons')..addFont(
          rootBundle.load('packages/shadcn_flutter/lib/icons/LucideIcons.ttf'),
        ))
        .load();
  });
  for (final template in ['summary', 'history', 'event']) {
    for (final range in [
      'from=2026-02-30&before=2026-03-02',
      'from=2026-01-01&before=',
      'from=2026-03-02&before=2026-03-01',
      'from=2026-01-01&before=0001-01-01',
    ]) {
      appTest('$template rejects $range through a rebuild', (tester) async {
        final f = await launch(tester);
        f.container
            .read(routerProvider)
            .push('/reports?template=$template&$range');
        await settle(tester);
        expect(f.container.read(reportControllerProvider).selection, isNull);
        expect(find.text('Preview'), findsNothing);
        f.container.read(appearanceProvider.notifier).setMode(ThemeMode.dark);
        await settle(tester);
        expect(f.container.read(reportControllerProvider).selection, isNull);
        expect(find.text('Preview'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final (name, template) in [
    ('summary', ReportTemplateId.r01SubstanceSummary),
    ('history', ReportTemplateId.r02DetailedHistory),
    ('event', ReportTemplateId.r03EventReview),
  ]) {
    appTest('$name keeps an explicit leap-day range and template', (
      tester,
    ) async {
      final f = await launch(tester);
      f.container
          .read(routerProvider)
          .push('/reports?template=$name&from=2024-02-29&before=2024-03-01');
      await settle(tester);
      final selection = f.container.read(reportControllerProvider).selection!;
      expect(selection.template, template);
      expect(selection.fromDate, CivilDate(2024, 2, 29));
      expect(selection.beforeDate, CivilDate(2024, 3, 1));
      expect(selection.includeNotes, isFalse);
      expect(selection.includeAttachments, isFalse);
      expect(selection.itemIds, isEmpty);
    });
  }

  appTest('opening another report never edits the active draft', (
    tester,
  ) async {
    final f = await launch(tester);
    final subscription = f.container.listen(
      reportControllerProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);
    final active = ReportSelection(
      personId: 'me',
      fromDate: CivilDate(2024, 2, 29),
      beforeDate: CivilDate(2024, 3, 2),
      displayZone: 'UTC',
      reportName: 'Reviewed name',
      includeNotes: true,
      includeAttachments: true,
      itemIds: ['exact-item'],
    );
    f.container.read(reportControllerProvider.notifier).select(active);
    f.container
        .read(routerProvider)
        .push('/reports?template=history&from=2026-01-01&before=2026-03-01');
    await settle(tester);
    expect(f.container.read(reportControllerProvider).selection, active);
    expect(find.text('Reviewed name'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final template in ['summary', 'history', 'event']) {
    appTest('$template never seeds from an unavailable device zone', (
      tester,
    ) async {
      final f = await launch(
        tester,
        zoneObservation: const DeviceZoneObservation.unavailable(),
      );
      f.container.read(routerProvider).push('/reports?template=$template');
      await settle(tester);
      expect(f.container.read(reportControllerProvider).selection, isNull);
      expect(find.text('Preview'), findsNothing);
      expect(
        find.text(
          'The time zone is unavailable. Choose the device time zone, then try again.',
        ),
        findsOneWidget,
      );
    });
  }

  appTest(
    'final-year manual through overflow cannot generate or change scope',
    (tester) async {
      final f = await launch(tester);
      f.container
          .read(routerProvider)
          .push('/reports?from=2026-01-01&before=2026-02-01');
      await settle(tester);
      final controller = f.container.read(reportControllerProvider.notifier);
      controller.setItems(['only-this-item']);
      controller.setIncludeNotes(true);
      final selection = f.container.read(reportControllerProvider).selection!;
      final through = tester.widget<LabelledInput>(
        find.byWidgetPredicate(
          (w) => w is LabelledInput && w.label == 'Through',
        ),
      );
      through.controller.text = '9999-12-31';
      await settle(tester);
      await tap(tester, 'Preview');
      expect(f.container.read(reportControllerProvider).selection, selection);
      expect(f.container.read(reportControllerProvider).artifact, isNull);
      expect(
        find.text('Enter valid dates with the end on or after the start.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  appTest(
    'a draft arriving before the seed callback keeps exact private scope',
    (tester) async {
      final f = await launch(tester);
      final sub = f.container.listen(reportControllerProvider, (_, _) {});
      addTearDown(sub.close);
      final arriving = ReportSelection(
        personId: 'me',
        fromDate: CivilDate(2024, 2, 29),
        beforeDate: CivilDate(2024, 3, 1),
        displayZone: 'UTC',
        itemIds: ['only-this-item'],
        includeNotes: true,
        includeAttachments: true,
      );
      var intercepted = false;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: ShadcnApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: _BeforeSeed(
              onFrame: () {
                expect(find.byType(LabelledInput), findsWidgets);
                expect(
                  f.container.read(reportControllerProvider).selection,
                  isNull,
                );
                intercepted = true;
                f.container
                    .read(reportControllerProvider.notifier)
                    .select(arriving);
              },
            ),
          ),
        ),
      );
      await settle(tester);
      expect(intercepted, isTrue);
      expect(f.container.read(reportControllerProvider).selection, arriving);
      expect(find.text('Replace'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  appTest('a stale Replace callback cannot overwrite a newer draft', (
    tester,
  ) async {
    final f = await launch(tester);
    final sub = f.container.listen(reportControllerProvider, (_, _) {});
    addTearDown(sub.close);
    final controller = f.container.read(reportControllerProvider.notifier);
    final original = ReportSelection(
      personId: 'me',
      fromDate: CivilDate(2024, 2, 29),
      beforeDate: CivilDate(2024, 3, 1),
      displayZone: 'UTC',
      itemIds: ['original'],
    );
    controller.select(original);
    f.container
        .read(routerProvider)
        .push('/reports?template=history&from=2026-01-01&before=2026-02-01');
    await settle(tester);
    final replace = tester
        .widget<VitalButton>(
          find.byWidgetPredicate(
            (w) =>
                w is VitalButton &&
                w.child is Text &&
                (w.child as Text).data == 'Replace',
          ),
        )
        .onPressed!;
    final newer = original.copyWith(itemIds: ['newer'], includeNotes: true);
    controller.select(newer);
    replace();
    await settle(tester);
    expect(f.container.read(reportControllerProvider).selection, newer);
    await tap(tester, 'Replace');
    final replaced = f.container.read(reportControllerProvider).selection!;
    expect(replaced.template, ReportTemplateId.r02DetailedHistory);
    expect(replaced.fromDate, CivilDate(2026, 1, 1));
    expect(replaced.beforeDate, CivilDate(2026, 2, 1));
    expect(replaced.includeNotes, isFalse);
    expect(replaced.itemIds, isEmpty);
  });
  appTest('a stale Replace callback cannot apply a changed route seed', (
    tester,
  ) async {
    final f = await launch(tester);
    final sub = f.container.listen(reportControllerProvider, (_, _) {});
    addTearDown(sub.close);
    final original = ReportSelection(
      personId: 'me',
      fromDate: CivilDate(2024, 2, 29),
      beforeDate: CivilDate(2024, 3, 1),
      displayZone: 'UTC',
      itemIds: ['exact'],
      includeNotes: true,
    );
    f.container.read(reportControllerProvider.notifier).select(original);
    final router = f.container.read(routerProvider);
    router.go('/reports?template=history&from=2026-01-01&before=2026-02-01');
    await settle(tester);
    final replace = tester
        .widget<VitalButton>(
          find.byWidgetPredicate(
            (w) =>
                w is VitalButton &&
                w.child is Text &&
                (w.child as Text).data == 'Replace',
          ),
        )
        .onPressed!;
    router.go('/reports?template=history&from=2027-01-01&before=2027-02-01');
    await settle(tester);
    replace();
    await settle(tester);
    expect(f.container.read(reportControllerProvider).selection, original);
    await tap(tester, 'Replace');
    expect(
      f.container.read(reportControllerProvider).selection!.fromDate,
      CivilDate(2027, 1, 1),
    );
    expect(tester.takeException(), isNull);
  });

  appTest(
    'an invalid link and profile lookup rebuild preserve the active private draft',
    (tester) async {
      final f = await launch(tester);
      final sub = f.container.listen(reportControllerProvider, (_, _) {});
      addTearDown(sub.close);
      final original = ReportSelection(
        personId: 'me',
        fromDate: CivilDate(2024, 2, 29),
        beforeDate: CivilDate(2024, 3, 1),
        displayZone: 'UTC',
        itemIds: ['exact'],
        includeNotes: true,
        includeAttachments: true,
        includeSupporting: true,
      );
      f.container.read(reportControllerProvider.notifier).select(original);
      f.container
          .read(routerProvider)
          .go('/reports?template=history&from=2026-02-30');
      await settle(tester);
      f.container.invalidate(profilesProvider);
      await settle(tester);
      expect(f.container.read(reportControllerProvider).selection, original);
      expect(find.text('Replace'), findsNothing);
      expect(find.text('Preview'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    appTest('date recovery and replacement remain usable in ${mode.name}', (
      tester,
    ) async {
      final key = GlobalKey();
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final f = await launch(tester);
      f.container.read(appearanceProvider.notifier).setMode(mode);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: RepaintBoundary(key: key, child: const VitalApp()),
        ),
      );
      f.container
          .read(routerProvider)
          .go('/reports?template=history&from=2026-02-30');
      await settle(tester);
      for (final width in [320.0, 390.0, 430.0]) {
        tester.view.physicalSize = Size(width, 844);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await settle(tester);
        expect(
          find.text(
            'The report dates are unavailable. Check the link, then try again.',
          ),
          findsOneWidget,
        );
        expect(find.text('Preview'), findsNothing);
        expect(tester.takeException(), isNull);
        if (width == 320) {
          await capture(tester, key, '${mode.name}-invalid-range-narrow');
        }
      }
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.view.physicalSize = const Size(390, 844);
      final controller = f.container.read(reportControllerProvider.notifier);
      controller.select(
        ReportSelection(
          personId: 'me',
          fromDate: CivilDate(2024, 2, 29),
          beforeDate: CivilDate(2024, 3, 1),
          displayZone: 'UTC',
          includeNotes: true,
          includeAttachments: true,
        ),
      );
      f.container
          .read(routerProvider)
          .go('/reports?template=history&from=2026-01-01&before=2026-02-01');
      await settle(tester);
      expect(find.text('Report selected'), findsOneWidget);
      await capture(tester, key, '${mode.name}-replacement');
      for (final width in [320.0, 390.0, 430.0]) {
        tester.view.physicalSize = Size(width, 844);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await settle(tester);
        expect(find.text('Replace').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (width == 320) {
          await capture(tester, key, '${mode.name}-replacement-narrow');
        }
      }
    });
  }
}
