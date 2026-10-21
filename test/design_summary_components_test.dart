import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/vital_theme.dart';
import 'package:true_grit_vital/l10n/app_localizations.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

Widget host(
  Widget child, {
  Brightness brightness = Brightness.light,
  double scale = 1,
}) => ShadcnApp(
  theme: vitalTheme(brightness),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
  ],
  supportedLocales: const [Locale('en', 'GB')],
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Center(child: child),
  ),
);

const longName = 'Levonorgestrel and Ethinylestradiol Combination Oral Course';
const longSubtitle = 'Coated Tablet, 0.15 mg per 0.03 mg labelled strength';
const longDetail = 'Daily at 08:00 with breakfast, Morning protocol';

/// Large-text flow tests need a taller logical surface than the default
/// 800x600 window so wrapped text can grow without overflowing the test view.
Future<void> withTallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(320, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'interactive compact row is one labelled action in $brightness',
      (tester) async {
        final semantics = tester.ensureSemantics();
        var presses = 0;
        await tester.pumpWidget(
          host(
            SizedBox(
              width: 320,
              child: VitalCompactRow(
                title: 'Telmisartan',
                subtitle: 'Oral Tablet, 40 mg',
                detail: 'Daily at 08:00, Morning protocol',
                icon: LucideIcons.pill,
                trailing: const VitalBadge('Prescription'),
                onPressed: () => presses++,
              ),
            ),
            brightness: brightness,
          ),
        );
        final node = tester.getSemantics(find.text('Telmisartan'));
        expect(node.flagsCollection.isButton, isTrue);
        expect(node.label, contains('Telmisartan'));
        expect(node.label, contains('Oral Tablet, 40 mg'));
        final row = tester.getRect(find.byType(VitalCompactRow));
        expect(row.height, greaterThanOrEqualTo(48));
        await tester.tap(find.text('Telmisartan'));
        expect(presses, 1);
        semantics.dispose();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('compact row keyboard activation works in $brightness', (
      tester,
    ) async {
      var presses = 0;
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: VitalCompactRow(
              title: 'Omega 3',
              subtitle: 'Marine Oil, 2000 mg',
              onPressed: () => presses++,
            ),
          ),
          brightness: brightness,
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(presses, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(presses, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'metric prints the labelled value with tabular figures in $brightness',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          host(
            SizedBox(
              width: 320,
              child: VitalMetric(
                label: 'Labelled strength',
                value: '40 mg',
                detail: 'Per tablet as entered',
              ),
            ),
            brightness: brightness,
          ),
        );
        expect(
          tester.widget<Text>(find.text('40 mg')).style,
          VitalType.quantity,
        );
        final node = tester.getSemantics(find.text('Labelled strength'));
        expect(node.label, contains('Labelled strength'));
        expect(node.label, contains('40 mg'));
        expect(node.label, contains('Per tablet as entered'));
        semantics.dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('metric with an unknown value says Unknown instead of zero', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 320,
          child: VitalMetric(
            label: 'Stock balance',
            detail: 'Tablets in the current container',
          ),
        ),
        brightness: Brightness.dark,
      ),
    );
    expect(find.text('Unknown'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      tester.widget<Text>(find.text('Unknown')).style!.color,
      vitalTheme(Brightness.dark).colorScheme.mutedForeground,
    );
    final node = tester.getSemantics(find.text('Stock balance'));
    expect(node.label, contains('Unknown'));
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('static compact row keeps text merged without a button role', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 320,
          child: VitalCompactRow(
            title: 'Zinc Picolinate',
            subtitle: 'Capsule, 22 mg',
          ),
        ),
      ),
    );
    expect(find.byType(Clickable), findsNothing);
    expect(
      tester
          .getSemantics(find.text('Zinc Picolinate'))
          .flagsCollection
          .isButton,
      isFalse,
    );
    expect(
      tester.getSemantics(find.text('Zinc Picolinate')).label,
      contains('Capsule, 22 mg'),
    );
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 3.0]) {
    testWidgets(
      'long compact row text wraps fully at 320px and scale $scale without shrinking',
      (tester) async {
        await withTallSurface(tester);
        await tester.pumpWidget(
          host(
            SizedBox(
              width: 320,
              child: VitalCompactRow(
                title: longName,
                subtitle: longSubtitle,
                detail: longDetail,
                icon: LucideIcons.pill,
                trailing: const VitalBadge('Supplement'),
              ),
            ),
            scale: scale,
          ),
        );
        final row = tester.getRect(find.byType(VitalCompactRow));
        expect(row.width, lessThanOrEqualTo(320.01));
        for (final text in [longName, longSubtitle, longDetail]) {
          final rect = tester.getRect(find.text(text));
          expect(rect.left, greaterThanOrEqualTo(row.left - .01));
          expect(rect.right, lessThanOrEqualTo(row.right + .01));
          expect(rect.height, greaterThan(0));
        }
        final taller = row.height;
        expect(taller, greaterThan(48));
        expect(taller, greaterThan(scale == 1 ? 120 : 260));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('progress draws the real fraction beside truthful numbers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 320,
          child: VitalProgress(
            label: 'Recorded doses',
            valueText: '2',
            totalText: 'of 3 planned doses',
            fraction: 2 / 3,
            annotation: '1 dose left today',
          ),
        ),
      ),
    );
    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, closeTo(2 / 3, .0001));
    expect(find.text('2'), findsOneWidget);
    expect(find.text('of 3 planned doses'), findsOneWidget);
    expect(find.text('1 dose left today'), findsOneWidget);
    final node = tester.getSemantics(find.text('Recorded doses'));
    expect(node.label, contains('2'));
    expect(node.label, contains('of 3 planned doses'));
    expect(node.label, contains('1 dose left today'));
    expect(node.value, isNot(contains('100%')));
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a zero value with a real total stays unmistakably empty', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 320,
          child: VitalProgress(
            label: 'Recorded doses',
            valueText: '0',
            totalText: 'of 2 planned doses',
            fraction: 0,
          ),
        ),
      ),
    );
    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, 0.0);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('of 2 planned doses'), findsOneWidget);
    final node = tester.getSemantics(find.text('Recorded doses'));
    expect(node.label, contains('0'));
    expect(node.label, contains('of 2 planned doses'));
    expect(node.value, isNot(contains('100%')));
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  for (final state in ['noTotal', 'unknown']) {
    testWidgets('the $state progress state shows no bar and its own line', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      const label = 'Recorded doses';
      final annotation = state == 'noTotal'
          ? 'No planned doses today'
          : 'Balance unknown. Measure the remaining amount.';
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: state == 'noTotal'
                ? VitalProgress.noTotal(label: label, annotation: annotation)
                : VitalProgress.unknown(label: label, annotation: annotation),
          ),
        ),
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text(annotation), findsOneWidget);
      expect(find.text('0'), findsNothing);
      final node = tester.getSemantics(find.text(label));
      expect(node.label, contains(annotation));
      semantics.dispose();
      expect(tester.takeException(), isNull);
    });
  }

  for (final form in ['measured', 'noTotal']) {
    testWidgets(
      'progress stays readable at 320px and scale 3 in the $form form',
      (tester) async {
        await withTallSurface(tester);
        await tester.pumpWidget(
          host(
            SizedBox(
              width: 320,
              child: form == 'measured'
                  ? VitalProgress(
                      label: longDetail,
                      valueText: '17',
                      totalText: 'of 30 remaining tablets',
                      fraction: 17 / 30,
                      annotation: 'A refill is due soon.',
                    )
                  : const VitalProgress.noTotal(
                      label: longDetail,
                      annotation: 'No planned doses today',
                    ),
            ),
            scale: 3,
          ),
        );
        if (form == 'measured') {
          final progress = tester.getRect(find.byType(VitalProgress));
          final indicator = tester.widget<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          );
          expect(indicator.value, closeTo(17 / 30, .0001));
          for (final text in [
            '17',
            'of 30 remaining tablets',
            'A refill is due soon.',
          ]) {
            final rect = tester.getRect(find.text(text));
            expect(rect.height, greaterThan(0));
            expect(rect.right, lessThanOrEqualTo(progress.right + .01));
          }
        } else {
          final progress = tester.getRect(find.byType(VitalProgress));
          final rect = tester.getRect(find.text('No planned doses today'));
          expect(rect.height, greaterThan(0));
          expect(rect.right, lessThanOrEqualTo(progress.right + .01));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('metric value wraps fully at 320px with scale 3', (tester) async {
    await withTallSurface(tester);
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 320,
          child: VitalMetric(
            label: longSubtitle,
            value: '0.15 mg per 0.03 mg labelled equivalent amount found',
            detail: 'Two named parts on one continuous course',
          ),
        ),
        scale: 3,
      ),
    );
    final metric = tester.getRect(find.byType(VitalMetric));
    final label = tester.getRect(find.text(longSubtitle));
    final value = tester.getRect(
      find.text('0.15 mg per 0.03 mg labelled equivalent amount found'),
    );
    expect(label.height, greaterThan(0));
    expect(value.height, greaterThan(0));
    expect(value.bottom, lessThanOrEqualTo(metric.bottom + .01));
    for (final rect in [label, value]) {
      expect(rect.right, lessThanOrEqualTo(metric.right + .01));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a composed substance row survives narrow widths and scale 3', (
    tester,
  ) async {
    await withTallSurface(tester);
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: VitalSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  VitalCompactRow(
                    title: longName,
                    subtitle: longSubtitle,
                    detail: longDetail,
                    icon: LucideIcons.pill,
                    trailing: const VitalBadge('Supplement'),
                  ),
                  VitalProgress(
                    label: 'Container stock',
                    valueText: '3',
                    totalText: 'of 30 remaining tablets',
                    fraction: 0.1,
                    annotation: 'A refill is due soon.',
                  ),
                ],
              ),
            ),
          ),
        ),
        scale: 3,
      ),
    );
    final surface = tester.getRect(find.byType(VitalSurface));
    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, closeTo(0.1, .0001));
    final bar = tester.getRect(find.byType(LinearProgressIndicator));
    expect(bar.left, greaterThanOrEqualTo(surface.left));
    expect(bar.right, lessThanOrEqualTo(surface.right + .01));
    final progress = tester.getRect(find.byType(VitalProgress));
    expect(progress.bottom, lessThanOrEqualTo(surface.bottom + .01));
    for (final text in [longName, longSubtitle, longDetail]) {
      final rect = tester.getRect(find.text(text));
      expect(rect.left, greaterThanOrEqualTo(surface.left));
      expect(rect.right, lessThanOrEqualTo(surface.right + .01));
      expect(rect.height, greaterThan(0));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('progress respects a reduced-effects request', (tester) async {
    await tester.pumpWidget(
      ShadcnApp(
        theme: vitalTheme(Brightness.light),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', 'GB')],
        home: MediaQuery(
          data: const MediaQueryData(
            disableAnimations: true,
            textScaler: TextScaler.linear(1),
          ),
          child: VitalProgress(
            label: 'Recorded doses',
            valueText: '2',
            totalText: 'of 3 planned doses',
            fraction: 2 / 3,
          ),
        ),
      ),
    );
    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.theme?.disableAnimation, isTrue);
    expect(tester.takeException(), isNull);
  });
}
