import "dart:math" as math;
import "dart:ui" show Tristate;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart' as material show showDialog;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/vital_theme.dart';
import 'package:true_grit_vital/l10n/app_localizations.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

Widget host(Widget child, {Brightness brightness = Brightness.light}) =>
    ShadcnApp(
      theme: vitalTheme(brightness),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', 'GB')],
      home: VitalComponentThemes(child: Center(child: child)),
    );

Widget dialogLauncher({
  required String title,
  required String body,
  required String cancelLabel,
  required String confirmLabel,
  required double scale,
  required VoidCallback onConfirm,
}) => host(
  Builder(
    builder: (context) => VitalButton(
      onPressed: () => material.showDialog<void>(
        context: context,
        builder: (dialogContext) => MediaQuery(
          data: MediaQuery.of(dialogContext)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: VitalDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              VitalButton.secondary(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(cancelLabel),
              ),
              VitalButton(
                onPressed: () {
                  onConfirm();
                  Navigator.pop(dialogContext);
                },
                child: Text(confirmLabel),
              ),
            ],
          ),
        ),
      ),
      child: const Text('Open'),
    ),
  ),
);

double contrastRatio(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('short labels stay centred with icons in $brightness', (
      tester,
    ) async {
      var presses = 0;
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 280,
            child: VitalButton.secondary(
              leading: const Icon(LucideIcons.plus),
              onPressed: () => presses++,
              child: const Text('Create'),
            ),
          ),
          brightness: brightness,
        ),
      );
      final button = find.byType(Button);
      final rect = tester.getRect(button);
      final label = tester.getRect(find.text('Create'));
      expect(rect.height, closeTo(48, 1));
      expect(rect.width, greaterThanOrEqualTo(48));
      expect(label.center.dx, closeTo(rect.center.dx, .01));
      expect(label.center.dy, closeTo(rect.center.dy, .01));
      await tester.tap(button);
      expect(presses, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'loading preserves centred label and disables duplicate actions',
    (tester) async {
      var presses = 0;
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 280,
            child: VitalButton(
              isLoading: true,
              onPressed: () => presses++,
              child: const Text('Save'),
            ),
          ),
        ),
      );
      final rect = tester.getRect(find.byType(Button));
      expect(tester.getCenter(find.text('Save')), rect.center);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(Button));
      expect(presses, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('descriptive choices retain start alignment and can grow', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: SizedBox(
            width: 280,
            child: VitalButton.secondary(
              multiline: true,
              onPressed: () {},
              child: const Text(
                'A longer descriptive choice with its full quantity',
              ),
            ),
          ),
        ),
      ),
    );
    final button = tester.getRect(find.byType(Button));
    final label = tester.getRect(
      find.text('A longer descriptive choice with its full quantity'),
    );
    expect(label.left, closeTo(button.left + 20, .01));
    expect(button.height, greaterThan(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('page body keeps the shared readable width on a desktop', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      host(
        const VitalPageBody(
          child: SizedBox(
            key: Key('content'),
            width: double.infinity,
            height: 100,
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(const Key('content'))).width, 608);
    expect(tester.getCenter(find.byKey(const Key('content'))).dx, 600);
  });

  testWidgets('shared segments expose selection and keyboard activation', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var selected = 'List';
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => SizedBox(
            width: 320,
            child: VitalSegments<String>(
              values: const ['List', 'Calendar'],
              selected: selected,
              onChanged: (value) => setState(() => selected = value),
              label: (value) => value,
            ),
          ),
        ),
        brightness: Brightness.dark,
      ),
    );
    expect(
      tester.getSemantics(find.text('List')).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(
      tester.getSemantics(find.text('List')).flagsCollection.isButton,
      isTrue,
    );
    expect(
      tester.getSemantics(find.text('Calendar')).flagsCollection.isSelected,
      Tristate.isFalse,
    );
    expect(
      tester.getSemantics(find.text('Calendar')).flagsCollection.isButton,
      isTrue,
    );
    for (final text in ['List', 'Calendar']) {
      final button = find
          .ancestor(of: find.text(text), matching: find.byType(Button))
          .first;
      expect(tester.getCenter(find.text(text)), tester.getCenter(button));
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      final clickable = tester.widget<Clickable>(
        find.descendant(of: button, matching: find.byType(Clickable)).first,
      );
      final expectedFill = text == 'List'
          ? vitalTheme(Brightness.dark).colorScheme.primary
          : vitalTheme(Brightness.dark).colorScheme.secondary;
      final decoration = clickable.decoration!.resolve({}) as BoxDecoration;
      expect(decoration.color, expectedFill);
      expect(decoration.borderRadius, BorderRadius.circular(999));
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 'Calendar');
    expect(
      tester.getSemantics(find.text('Calendar')).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('segments wrap safely on a small phone with large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 667));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      host(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(3)),
          child: SizedBox(
            width: 335,
            child: VitalSegments<String>(
              values: const ['List', 'Calendar'],
              selected: 'List',
              onChanged: (_) {},
              label: (value) => value,
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getRect(find.text('Calendar')).top,
      greaterThan(tester.getRect(find.text('List')).bottom),
    );
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'enabled destructive fill stays opaque and readable on every surface in $brightness',
      (tester) async {
        var presses = 0;
        await tester.pumpWidget(
          host(
            VitalButton.destructive(
              onPressed: () => presses++,
              child: const Text('Delete'),
            ),
            brightness: brightness,
          ),
        );
        final clickable = tester.widget<Clickable>(find.byType(Clickable));
        final colors = vitalTheme(brightness).colorScheme;
        for (final states in <Set<WidgetState>>[
          {},
          {WidgetState.hovered},
          {WidgetState.pressed},
        ]) {
          final fill =
              (clickable.decoration!.resolve(states) as BoxDecoration).color!;
          expect(fill.a, 1.0);
          if (states.isEmpty) {
            expect(fill, colors.destructive);
          }
          final foreground = clickable.textStyle!.resolve(states)!.color!;
          expect(foreground, Colors.white);
          for (final surface in [colors.background, colors.card]) {
            expect(
              contrastRatio(foreground, Color.alphaBlend(fill, surface)),
              greaterThanOrEqualTo(4.5),
            );
          }
        }
        await tester.tap(find.text('Delete'));
        expect(presses, 1);
      },
    );
  }

  for (final brightness in Brightness.values) {
    for (final variant in VitalButtonVariant.values) {
      VitalButton makeButton({bool loading = false}) => switch (variant) {
        VitalButtonVariant.primary => VitalButton(
          isLoading: loading,
          child: const Text('Save'),
        ),
        VitalButtonVariant.secondary => VitalButton.secondary(
          isLoading: loading,
          child: const Text('Save'),
        ),
        VitalButtonVariant.destructive => VitalButton.destructive(
          isLoading: loading,
          child: const Text('Save'),
        ),
      };
      testWidgets(
        'disabled $variant retains tonal shape and readable text in $brightness',
        (tester) async {
          await tester.pumpWidget(host(makeButton(), brightness: brightness));
          final clickable = tester.widget<Clickable>(find.byType(Clickable));
          final decoration = clickable.decoration!.resolve({
            WidgetState.disabled,
          }) as BoxDecoration;
          final text = clickable.textStyle!.resolve({WidgetState.disabled})!;
          final colors = vitalTheme(brightness).colorScheme;
          expect(decoration.color, colors.secondary);
          expect(decoration.border, isNotNull);
          expect(text.color, colors.mutedForeground);
          final a = text.color!.computeLuminance(),
              b = decoration.color!.computeLuminance();
          expect(
            (a > b ? a + .05 : b + .05) / (a > b ? b + .05 : a + .05),
            greaterThanOrEqualTo(4.5),
          );
          expect(tester.getSize(find.byType(Button)).height, closeTo(48, 1));
        },
      );
      testWidgets(
        'loading $variant contrasts and announces working in $brightness',
        (tester) async {
          final semantics = tester.ensureSemantics();
          await tester.pumpWidget(
            host(makeButton(loading: true), brightness: brightness),
          );
          final clickable = tester.widget<Clickable>(find.byType(Clickable));
          final fill = (clickable.decoration!.resolve({
            WidgetState.disabled,
          }) as BoxDecoration).color!;
          final spinner = tester.widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          );
          final a = spinner.theme!.color!.computeLuminance(),
              b = fill.computeLuminance();
          expect(
            (a > b ? a + .05 : b + .05) / (a > b ? b + .05 : a + .05),
            greaterThanOrEqualTo(3),
          );
          final node = tester.getSemantics(find.text('Save'));
          expect(node.value, 'Working…');
          expect(node.flagsCollection.isLiveRegion, isTrue);
          expect(node.flagsCollection.isEnabled, Tristate.isFalse);
          semantics.dispose();
        },
      );
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'disabled primary leading icon contrasts with its fill in $brightness',
      (tester) async {
        await tester.pumpWidget(
          host(
            SizedBox(
              width: 280,
              child: VitalButton(
                onPressed: null,
                leading: const Icon(LucideIcons.plus),
                child: const Text('Save'),
              ),
            ),
            brightness: brightness,
          ),
        );
        final colors = vitalTheme(brightness).colorScheme;
        final clickable = tester.widget<Clickable>(find.byType(Clickable));
        final fill = (clickable.decoration!.resolve({
          WidgetState.disabled,
        }) as BoxDecoration).color!;
        final icon = find.byIcon(LucideIcons.plus);
        final iconColor = IconTheme.of(tester.element(icon)).color!;
        expect(iconColor, colors.mutedForeground);
        for (final surface in [colors.background, colors.card]) {
          expect(
            contrastRatio(iconColor, Color.alphaBlend(fill, surface)),
            greaterThanOrEqualTo(3),
          );
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'disabled secondary keeps a visible neutral boundary on a card in $brightness',
      (tester) async {
        await tester.pumpWidget(
          host(
            SizedBox(
              width: 300,
              child: VitalSurface(
                child: VitalButton.secondary(
                  onPressed: null,
                  child: const Text('Save'),
                ),
              ),
            ),
            brightness: brightness,
          ),
        );
        final colors = vitalTheme(brightness).colorScheme;
        final clickable = tester.widget<Clickable>(find.byType(Clickable));
        final decoration = clickable.decoration!.resolve({
          WidgetState.disabled,
        }) as BoxDecoration;
        final border = decoration.border! as Border;
        expect(decoration.color, colors.secondary);
        expect(border.top.color, colors.mutedForeground);
        for (final surface in [colors.card, colors.background]) {
          expect(
            contrastRatio(border.top.color, surface),
            greaterThanOrEqualTo(3),
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'trailing-only descriptive choices keep the shared start gutter',
    (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 335,
            child: VitalButton.secondary(
              multiline: true,
              trailing: const Icon(LucideIcons.chevronDown),
              onPressed: () {},
              child: const Text('Sam Taylor'),
            ),
          ),
        ),
      );
      final button = tester.getRect(find.byType(Button));
      final label = tester.getRect(find.text('Sam Taylor'));
      expect(label.left, closeTo(button.left + 20, .01));
      expect(button.height, closeTo(48, 1));
    },
  );

  const phoneHeight = 667.0;
  const longPerson = 'Alexandra Montgomery-Winslow';
  final localisations = lookupAppLocalizations(const Locale('en', 'GB'));
  for (final width in [320.0, 375.0]) {
    for (final scale in [2.0, 3.0]) {
      for (final kind in ['archive', 'delete']) {
        testWidgets(
          'real $kind dialog keeps actions reachable at width $width scale $scale',
          (tester) async {
            tester.view.devicePixelRatio = 3;
            tester.view.physicalSize = Size(width * 3, phoneHeight * 3);
            addTearDown(tester.view.reset);
            final archive = kind == 'archive';
            final title = archive
                ? localisations.archivePerson
                : localisations.deletePerson;
            final body = archive
                ? localisations.archiveBody(longPerson)
                : localisations.deleteProfileBody(longPerson);
            final confirmLabel = archive
                ? localisations.archive
                : localisations.delete;
            var confirmed = false;
            await tester.pumpWidget(
              dialogLauncher(
                title: title,
                body: body,
                cancelLabel: localisations.cancel,
                confirmLabel: confirmLabel,
                scale: scale,
                onConfirm: () => confirmed = true,
              ),
            );
            await tester.tap(find.text('Open'));
            await tester.pumpAndSettle();

            final dialogContext = tester.element(find.byType(VitalDialog));
            expect(MediaQuery.sizeOf(dialogContext), Size(width, phoneHeight));
            final scrollFinder = find.descendant(
              of: find.byType(VitalDialog),
              matching: find.byType(SingleChildScrollView),
            );
            expect(scrollFinder, findsOneWidget);
            final scrollable = tester.state<ScrollableState>(
              find
                  .descendant(
                    of: scrollFinder,
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            final maxExtent = scrollable.position.maxScrollExtent;
            expect(maxExtent, greaterThanOrEqualTo(0));
            if (scale == 3) {
              expect(maxExtent, greaterThan(0));
            }
            if (maxExtent > 0) {
              await tester.drag(
                scrollFinder,
                Offset(0, -math.min(maxExtent, 240.0)),
              );
              await tester.pumpAndSettle();
              expect(scrollable.position.pixels, greaterThan(0));
            }
            for (final label in [localisations.cancel, confirmLabel]) {
              final bounds = tester.getRect(
                find.ancestor(
                  of: find.text(label),
                  matching: find.byType(Button),
                ),
              );
              final textBounds = tester.getRect(find.text(label));
              expect(bounds.left, greaterThanOrEqualTo(0));
              expect(bounds.right, lessThanOrEqualTo(width + .01));
              expect(bounds.top, greaterThanOrEqualTo(0));
              expect(bounds.bottom, lessThanOrEqualTo(phoneHeight + .01));
              expect(bounds.height, greaterThanOrEqualTo(48));
              expect(textBounds.left, greaterThanOrEqualTo(bounds.left));
              expect(textBounds.right, lessThanOrEqualTo(bounds.right + .01));
            }
            expect(tester.takeException(), isNull);
            await tester.tap(find.text(confirmLabel));
            await tester.pumpAndSettle();
            expect(confirmed, isTrue);
          },
        );
      }
    }
  }

  testWidgets('dialog is a content-fit card on a 375x667 phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(375 * 3, phoneHeight * 3);
    addTearDown(tester.view.reset);
    var confirmed = false;
    await tester.pumpWidget(
      dialogLauncher(
        title: localisations.archivePerson,
        body: localisations.archiveBody(longPerson),
        cancelLabel: localisations.cancel,
        confirmLabel: localisations.archive,
        scale: 1,
        onConfirm: () => confirmed = true,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final titleStyle = DefaultTextStyle.of(
      tester.element(find.text(localisations.archivePerson)),
    ).style;
    expect(
      titleStyle.color,
      vitalTheme(Brightness.light).colorScheme.foreground,
    );
    final card = tester.getRect(find.byType(AlertDialog));
    expect(card.top, greaterThan(0));
    expect(card.bottom, lessThan(phoneHeight));
    expect(card.left, greaterThan(0));
    expect(card.right, lessThan(375));
    expect(card.height, lessThan(phoneHeight));
    for (final label in [localisations.cancel, localisations.archive]) {
      final bounds = tester.getRect(
        find.ancestor(of: find.text(label), matching: find.byType(Button)),
      );
      expect(bounds.top, greaterThanOrEqualTo(card.top));
      expect(bounds.bottom, lessThanOrEqualTo(card.bottom));
    }
    await tester.tap(find.text(localisations.archive));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });

  testWidgets(
    'dialog keeps a caller scroll view as the only scrollable at scale 3',
    (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(375 * 3, phoneHeight * 3);
      addTearDown(tester.view.reset);
      var done = false;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => VitalButton(
              onPressed: () => material.showDialog<void>(
                context: context,
                builder: (dialogContext) => MediaQuery(
                  data: MediaQuery.of(dialogContext)
                      .copyWith(textScaler: const TextScaler.linear(3)),
                  child: VitalDialog(
                    title: const Text('Review'),
                    content: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < 40; i++)
                            Text('Record $i with its full quantity'),
                        ],
                      ),
                    ),
                    actions: [
                      VitalButton.secondary(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Cancel'),
                      ),
                      VitalButton(
                        onPressed: () {
                          done = true;
                          Navigator.pop(dialogContext);
                        },
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final scrollables = find.byType(Scrollable);
      expect(scrollables, findsOneWidget);
      final scrollable = tester.state<ScrollableState>(scrollables);
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, greaterThan(0));
      for (final label in ['Cancel', 'Done']) {
        final bounds = tester.getRect(
          find.ancestor(of: find.text(label), matching: find.byType(Button)),
        );
        expect(bounds.top, greaterThanOrEqualTo(0));
        expect(bounds.bottom, lessThanOrEqualTo(phoneHeight + .01));
      }
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(done, isTrue);
    },
  );

  testWidgets('dialog actions stay above the keyboard at 375x667 scale 3', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(375 * 3, phoneHeight * 3);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280 * 3);
    addTearDown(tester.view.reset);
    var confirmed = false;
    await tester.pumpWidget(
      dialogLauncher(
        title: localisations.archivePerson,
        body: localisations.archiveBody(longPerson),
        cancelLabel: localisations.cancel,
        confirmLabel: localisations.archive,
        scale: 3,
        onConfirm: () => confirmed = true,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final dialogContext = tester.element(find.byType(VitalDialog));
    expect(MediaQuery.viewInsetsOf(dialogContext).bottom, 280);
    for (final label in [localisations.cancel, localisations.archive]) {
      final bounds = tester.getRect(
        find.ancestor(of: find.text(label), matching: find.byType(Button)),
      );
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.bottom, lessThanOrEqualTo(phoneHeight - 280 + .01));
    }
    expect(tester.takeException(), isNull);
    await tester.tap(find.text(localisations.archive));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });

  test('light and dark text and action fills retain readable contrast', () {
    for (final brightness in Brightness.values) {
      final colors = vitalTheme(brightness).colorScheme;
      expect(
        contrastRatio(colors.foreground, colors.background),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(colors.mutedForeground, colors.card),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(colors.primaryForeground, colors.primary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(colors.secondaryForeground, colors.secondary),
        greaterThanOrEqualTo(4.5),
      );
    }
    expect(
      vitalTheme(Brightness.light).colorScheme.background,
      const Color(0xFFFFFFFF),
    );
    expect(
      vitalTheme(Brightness.dark).colorScheme.background,
      const Color(0xFF101715),
    );
    expect(
      vitalTheme(Brightness.dark).colorScheme.secondary,
      const Color(0xFF101B17),
    );
  });
}
