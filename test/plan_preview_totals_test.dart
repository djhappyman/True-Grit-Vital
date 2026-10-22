import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/display_preferences.dart';
import 'package:true_grit_vital/app/vital_theme.dart';
import 'package:true_grit_vital/domain/history/display_time.dart';
import 'package:true_grit_vital/domain/records.dart';
import 'package:true_grit_vital/domain/scheduling/daily_plan.dart';
import 'package:true_grit_vital/features/plans/plan_form.dart';
import 'package:true_grit_vital/features/plans/plan_preview_totals.dart';
import 'package:true_grit_vital/l10n/app_localizations.dart';

const captureDirectory = String.fromEnvironment('VITAL_T11_CAPTURES');

final start = CivilDate.fromDateTime(DateTime.now().toUtc());

class PreviewDisplayPreferences extends DisplayPreferencesController {
  @override
  DisplayPreferences build() =>
      const DisplayPreferences(timeFormat: TimeFormat.h24);
}

DailyPlanVersion makePlan(
  DailyTiming timing, {
  CivilDate? from,
  CivilDate? endExclusive,
  String zone = 'UTC',
  bool followLocal = false,
  Iterable<PlanPause> pauses = const [],
  CalendarPattern calendar = const EveryDay(),
}) => DailyPlanVersion(
  personId: 'p',
  itemId: 'i',
  planId: 'plan',
  versionId: 'v',
  start: from ?? start,
  endExclusive: endExclusive,
  timing: timing,
  zoneBasis: followLocal ? const FollowingLocal() : FixedHome(zone),
  calendar: calendar,
  pauses: pauses,
);

DailySlots repeatedSlots(
  int count, {
  String unit = 'mg',
  String amount = '0.125',
}) => DailySlots([
  for (var i = 0; i < count; i++)
    DailySlot(
      id: 'slot-$i',
      time: WallTime(i % 24, (i ~/ 24) * 5),
      amount: PlannedAmount(
        quantity: ExactQuantity.parse(amount),
        unit: unit,
        enteredText: amount,
      ),
      reminderEnabled: false,
    ),
]);

final dosesKey = find.byKey(const ValueKey('plan-preview-total-doses'));
Finder unitKey(String unit) =>
    find.byKey(ValueKey('plan-preview-total-unit-$unit'));

Widget previewHost(
  DailyPlanVersion plan, {
  String zone = 'UTC',
  ThemeMode mode = ThemeMode.light,
  Size size = const Size(390, 844),
  double textScale = 1,
  GlobalKey? boundaryKey,
}) {
  final preview = PlanPreview(plan: plan, observedZone: zone);
  return ProviderScope(
    overrides: [
      displayPreferencesProvider.overrideWith(PreviewDisplayPreferences.new),
    ],
    child: ShadcnApp(
      theme: vitalTheme(
        mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
      ),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', 'GB')],
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: RepaintBoundary(
          key: boundaryKey,
          child: Scaffold(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: preview,
            ),
          ),
        ),
      ),
    ),
  );
}

Widget summaryHost(
  PlanPreviewTotals totals, {
  ThemeMode mode = ThemeMode.light,
  Size size = const Size(390, 844),
  double textScale = 1,
}) => ShadcnApp(
  theme: vitalTheme(
    mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
  ),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
  ],
  supportedLocales: const [Locale('en', 'GB')],
  home: MediaQuery(
    data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
    child: Scaffold(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: PlanPreviewTotalsSummary(totals: totals),
      ),
    ),
  ),
);

Future<void> show(
  WidgetTester tester,
  DailyPlanVersion plan, {
  String zone = 'UTC',
  ThemeMode mode = ThemeMode.light,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    previewHost(plan, zone: zone, mode: mode, size: size, textScale: textScale),
  );
  await tester.pumpAndSettle();
}

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

void main() {
  group('seven-day plan preview totals', () {
    test('counts every planned entry before the 20-row display limit', () {
      final totals = planPreviewTotals(
        makePlan(repeatedSlots(4)),
        from: start,
        observedZone: 'UTC',
      );
      expect(totals.status, PlanPreviewTotalsStatus.complete);
      expect(totals.doses, 28);
      expect(totals.units.single.unit, 'mg');
      expect(totals.units.single.exact, '3.5');
    });

    test('keeps exact fractions without rounding or double arithmetic', () {
      final totals = planPreviewTotals(
        makePlan(repeatedSlots(3, amount: '0.333333')),
        from: start,
        observedZone: 'UTC',
      );
      expect(totals.doses, 21);
      expect(totals.units.single.exact, '6.999993');
    });

    test('never adds different units together', () {
      final totals = planPreviewTotals(
        makePlan(
          DailySlots([
            DailySlot(
              id: 'mg',
              time: WallTime(8, 0),
              amount: PlannedAmount(
                quantity: ExactQuantity.parse('2'),
                unit: 'mg',
              ),
              reminderEnabled: false,
            ),
            DailySlot(
              id: 'tablet',
              time: WallTime(20, 0),
              amount: PlannedAmount(
                quantity: ExactQuantity.parse('3'),
                unit: 'tablet',
              ),
              reminderEnabled: false,
            ),
          ]),
        ),
        from: start,
        observedZone: 'UTC',
      );
      expect(totals.doses, 14);
      expect(
        [for (final unit in totals.units) '${unit.exact} ${unit.unit}'],
        ['14 mg', '21 tablet'],
      );
    });

    test('counts an untimed daily count without inventing times', () {
      final totals = planPreviewTotals(
        makePlan(
          DailyCount(
            3,
            PlannedAmount(quantity: ExactQuantity.parse('0.5'), unit: 'mg'),
          ),
        ),
        from: start,
        observedZone: 'UTC',
      );
      expect(totals.doses, 21);
      expect(totals.units.single.exact, '10.5');
    });

    test('has no fixed total for as-needed plans', () {
      final totals = planPreviewTotals(
        makePlan(const AsNeeded()),
        from: start,
        observedZone: 'UTC',
      );
      expect(totals.status, PlanPreviewTotalsStatus.asNeeded);
      expect(totals.doses, 0);
      expect(totals.units, isEmpty);
    });

    test('a finite plan counts only its definite seven-day entries', () {
      final totals = planPreviewTotals(
        makePlan(
          DailyCount(
            1,
            PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
          ),
          endExclusive: start.addDays(3),
        ),
        from: start,
        observedZone: 'UTC',
      );
      expect(totals.status, PlanPreviewTotalsStatus.complete);
      expect(totals.doses, 3);
      expect(totals.units.single.exact, '3');
    });

    test('a fully paused week has a definite empty total', () {
      final totals = planPreviewTotals(
        makePlan(
          repeatedSlots(4),
          pauses: [
            PlanPause(
              start: DateTime.utc(start.year, start.month, start.day),
              resume: DateTime.utc(
                start.year,
                start.month,
                start.day,
              ).add(const Duration(days: 8)),
            ),
          ],
        ),
        from: start,
        observedZone: 'UTC',
      );
      expect(totals.status, PlanPreviewTotalsStatus.complete);
      expect(totals.doses, 0);
      expect(totals.units, isEmpty);
    });

    test('an incomplete seven-day expansion exposes no partial total', () {
      final totals = planPreviewTotals(
        makePlan(repeatedSlots(4)),
        from: start,
        observedZone: 'UTC',
        maxRows: 10,
      );
      expect(totals.status, PlanPreviewTotalsStatus.incomplete);
      expect(totals.doses, 0);
      expect(totals.units, isEmpty);
    });

    test('an unresolved zone fails even when no date falls in the window', () {
      expect(
        () => planPreviewTotals(
          makePlan(
            repeatedSlots(1),
            followLocal: true,
            calendar: EveryNDays(anchor: start.addDays(1000), interval: 2000),
          ),
          from: start,
          observedZone: 'Not/AZone',
        ),
        throwsA(anything),
      );
    });

    test('an unsupported calendar composition exposes no estimate', () {
      final totals = planPreviewTotals(
        makePlan(
          repeatedSlots(4),
          calendar: const UnsupportedCalendarPattern('test'),
        ),
        from: start,
        observedZone: 'UTC',
      );
      expect(totals.status, PlanPreviewTotalsStatus.incomplete);
      expect(totals.doses, 0);
      expect(totals.units, isEmpty);
    });

    test('an unresolved zone fails rather than guessing totals', () {
      expect(
        () => planPreviewTotals(
          makePlan(repeatedSlots(1), followLocal: true),
          from: start,
          observedZone: 'Not/AZone',
        ),
        throwsA(anything),
      );
    });
  });

  testWidgets('shows exact totals from rows beyond the display limit', (
    tester,
  ) async {
    await show(tester, makePlan(repeatedSlots(4)));
    expect(find.text('Seven-day total'), findsOneWidget);
    expect(find.text('28 planned doses'), findsOneWidget);
    expect(dosesKey, findsOneWidget);
    expect(find.text('3.5 mg planned'), findsOneWidget);
    expect(unitKey('mg'), findsOneWidget);
    expect(find.textContaining('The first 20 planned doses'), findsOneWidget);
    expect(
      find.textContaining('This is not a record of doses taken'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('untimed counts show a planned total without invented times', (
    tester,
  ) async {
    await show(
      tester,
      makePlan(
        DailyCount(
          3,
          PlannedAmount(
            quantity: ExactQuantity.parse('0.5'),
            unit: 'mg',
            enteredText: '0.5',
          ),
        ),
      ),
    );
    expect(
      find.textContaining('3 planned, 0.5 mg each, untimed'),
      findsWidgets,
    );
    expect(find.text('21 planned doses'), findsOneWidget);
    expect(dosesKey, findsOneWidget);
    expect(find.text('10.5 mg planned'), findsOneWidget);
    expect(unitKey('mg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a paused week shows the explicit empty total', (tester) async {
    await show(
      tester,
      makePlan(
        repeatedSlots(4),
        pauses: [
          PlanPause(
            start: DateTime.utc(start.year, start.month, start.day),
            resume: DateTime.utc(
              start.year,
              start.month,
              start.day,
            ).add(const Duration(days: 8)),
          ),
        ],
      ),
    );
    expect(find.text('Seven-day total'), findsOneWidget);
    expect(find.text('No planned doses in these seven days.'), findsOneWidget);
    expect(dosesKey, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('as-needed plans show the explicit no-total state', (
    tester,
  ) async {
    await show(tester, makePlan(const AsNeeded()));
    expect(
      find.text(
        'Record use when needed. There are no expected times or missed doses.',
      ),
      findsOneWidget,
    );
    expect(find.text('No planned times or fixed total.'), findsOneWidget);
    expect(dosesKey, findsNothing);
    expect(unitKey('mg'), findsNothing);
  });

  testWidgets('an unresolved zone keeps the calculation issue and no total', (
    tester,
  ) async {
    await show(
      tester,
      makePlan(repeatedSlots(1), followLocal: true),
      zone: 'Not/AZone',
    );
    expect(
      find.text(
        'Some dates cannot be calculated with the available time zone data. Review this plan.',
      ),
      findsOneWidget,
    );
    expect(find.text('Seven-day total'), findsNothing);
    expect(dosesKey, findsNothing);
  });

  testWidgets('an incomplete seven-day calculation shows no partial total', (
    tester,
  ) async {
    final totals = planPreviewTotals(
      makePlan(repeatedSlots(4)),
      from: start,
      observedZone: 'UTC',
      maxRows: 10,
    );
    expect(totals.status, PlanPreviewTotalsStatus.incomplete);
    await tester.pumpWidget(summaryHost(totals));
    await tester.pumpAndSettle();
    expect(find.text('Seven-day total'), findsOneWidget);
    expect(
      find.text('Totals unavailable. The seven-day calculation is incomplete.'),
      findsOneWidget,
    );
    expect(dosesKey, findsNothing);
    expect(unitKey('mg'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps definite weekly totals when the wider view is limited', (
    tester,
  ) async {
    await show(tester, makePlan(repeatedSlots(60)));
    expect(
      find.text('The calculation limit was reached. This view is incomplete.'),
      findsOneWidget,
    );
    expect(find.textContaining('The first 20 planned doses'), findsOneWidget);
    expect(find.text('420 planned doses'), findsOneWidget);
    expect(dosesKey, findsOneWidget);
    expect(find.text('52.5 mg planned'), findsOneWidget);
    expect(unitKey('mg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unresolved local time keeps the planned quantity exact', (
    tester,
  ) async {
    final plan = makePlan(
      DailySlots([
        DailySlot(
          id: 'gap',
          time: WallTime(1, 30),
          amount: PlannedAmount(
            quantity: ExactQuantity.parse('1'),
            unit: 'mg',
            enteredText: '1',
          ),
          reminderEnabled: false,
        ),
      ]),
      from: CivilDate(2027, 3, 28),
      zone: 'Europe/London',
    );
    await show(tester, plan, zone: 'Europe/London');
    expect(find.textContaining('This local time does not exist'), findsWidgets);
    expect(find.text('7 planned doses'), findsOneWidget);
    expect(dosesKey, findsOneWidget);
    expect(find.text('7 mg planned'), findsOneWidget);
    expect(unitKey('mg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'totals stay readable at 320px and double text in ${mode.name}',
      (tester) async {
        await show(
          tester,
          makePlan(repeatedSlots(4)),
          mode: mode,
          size: const Size(320, 740),
          textScale: 2,
        );
        expect(find.text('Seven-day total'), findsOneWidget);
        expect(find.text('28 planned doses'), findsOneWidget);
        expect(dosesKey, findsOneWidget);
        expect(find.text('3.5 mg planned'), findsOneWidget);
        expect(unitKey('mg'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('captures both themes at wide and narrow double text', (
    tester,
  ) async {
    if (captureDirectory.isEmpty) return;
    await loadFonts();
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final narrow in [false, true]) {
        final key = GlobalKey();
        final size = narrow ? const Size(320, 740) : const Size(390, 844);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          previewHost(
            makePlan(repeatedSlots(4)),
            mode: mode,
            size: size,
            textScale: narrow ? 2 : 1,
            boundaryKey: key,
          ),
        );
        await tester.pumpAndSettle();
        await capture(
          tester,
          key,
          '${mode.name}-plan-preview-totals${narrow ? '-narrow-double-text' : ''}',
        );
      }
    }
    tester.view.reset();
  });
}

Future<void> loadFonts() async {
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
}
