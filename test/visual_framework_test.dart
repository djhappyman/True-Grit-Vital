import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/plans/daily_feed.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'vital_app_test.dart' show appTest, launch, runIo, settle, waitForText;

const snapshots = String.fromEnvironment('VITAL_UI_SNAPSHOTS');
const snapshotRoutes = String.fromEnvironment('VITAL_UI_ROUTES');

void main() {
  setUpAll(() async {
    final loader = FontLoader('NotoSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    await loader.load();
    await (FontLoader('packages/shadcn_flutter/LucideIcons')..addFont(
          rootBundle.load('packages/shadcn_flutter/lib/icons/LucideIcons.ttf'),
        ))
        .load();
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    appTest(
      'existing screens use the framework and device safe areas in ${mode.name}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
        tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
        addTearDown(tester.view.reset);
        final fixture = await launch(tester);
        final items = (await runIo(tester, () async {
          final items = <SubstanceItem>[];
          for (final name in [
            'Telmisartan',
            'Vitamin D3 + K2',
            'Magnesium Glycinate',
          ]) {
            final item = await fixture.store.createItem(
              commandId: newCommandId(),
              expectedPersonRevision: 2,
              name: name,
              form: 'Tablet',
              unit: 'mg',
              type: 'Supplement',
            );
            items.add(item);
            final now = DateTime.now();
            await fixture.store.saveDailyPlan(
              commandId: newCommandId(),
              expectedPersonRevision: 2,
              expectedGeneration: fixture.store.generation,
              plan: DailyPlanVersion(
                personId: meId,
                planId: newCommandId(),
                itemId: item.id,
                versionId: newCommandId(),
                start: CivilDate(now.year, now.month, now.day),
                timing: DailyCount(
                  1,
                  PlannedAmount(
                    quantity: ExactQuantity.parse('1'),
                    enteredText: '1',
                    unit: 'mg',
                  ),
                ),
                zoneBasis: const FollowingLocal(),
                calendar: const EveryDay(),
              ),
            );
          }
          await fixture.store.record(
            commandId: newCommandId(),
            expectedPersonRevision: 2,
            itemId: items.first.id,
            amount: '1',
            actualAt: DateTime.now().toUtc(),
          );
          return items;
        }))!;
        fixture.container.read(appearanceProvider.notifier).setMode(mode);
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: fixture.container,
            child: RepaintBoundary(key: boundaryKey, child: const VitalApp()),
          ),
        );
        await settle(tester);
        final router = fixture.container.read(routerProvider);
        final routes = <String, String>{
          'today': '/today',
          'substances': '/substances',
          'events': '/events',
          'history': '/history',
          'settings': '/settings',
          'appearance': '/appearance',
          'create': '/create',
          'record': '/record/${items.first.id}',
          'schedule': '/schedule/${items.first.id}',
          'stock': '/stock/$meId?item=${items.first.id}',
          'supporting': '/supporting',
          'reports': '/reports',
          'export': '/exports',
          'backup': '/backup',
          'restore': '/restore',
          'profile': '/profile',
          'privacy': '/settings/privacy',
          'help': '/settings/help',
          'charts': '/charts',
          'event-create': '/event-create',
          'types': '/types/$meId',
          'combined': '/combined/$meId?item=${items.first.id}',
          'pause': '/pause/${items.first.id}',
          'phases': '/phases/${items.first.id}',
          'product-label': '/products/$meId/label/${items.first.id}',
          'stock-create': '/stock/$meId/create?item=${items.first.id}',
          'use-history': '/use/$meId/${items.first.id}',
          'supporting-add-panel': '/supporting/$meId/add-panel',
          'reminders': '/reminders',
          'diagnostics': '/settings/diagnostics',
          'licences': '/settings/licences',
          'recorded': '/recorded',
          'item-history': '/item/${items.first.id}',
          'substance-overview': '/substance/${items.first.id}',
        };
        final selectedRoutes = snapshotRoutes.isEmpty
            ? routes.keys.toSet()
            : snapshotRoutes.split(',').toSet();
        expect(selectedRoutes.difference(routes.keys.toSet()), isEmpty);
        for (final route in routes.entries.where(
          (route) => selectedRoutes.contains(route.key),
        )) {
          debugPrint('Visual check: ${mode.name} ${route.key}');
          router.go(route.value);
          await settle(tester);
          if (route.key == 'today') {
            final loaded = Stopwatch()..start();
            while (find.byType(DailyRowCard).evaluate().length < items.length) {
              if (loaded.elapsed > const Duration(seconds: 10)) {
                throw TestFailure('Today rows did not finish loading.');
              }
              await runIo(
                tester,
                () => Future<void>.delayed(const Duration(milliseconds: 5)),
              );
              await tester.pumpAndSettle();
            }
          }
          if (route.key == 'substance-overview') {
            await waitForText(tester, items.first.name);
            await waitForText(tester, 'Planned once a day, 1 mg each');
          }
          if (route.key == 'substances') {
            await waitForText(tester, 'Magnesium Glycinate');
            await waitForText(tester, 'No stock recorded.');
            final loaded = Stopwatch()..start();
            while (find.text('No stock recorded.').evaluate().length <
                items.length) {
              if (loaded.elapsed > const Duration(seconds: 10)) {
                throw TestFailure(
                  'Substance summaries did not finish loading.',
                );
              }
              await runIo(
                tester,
                () => Future<void>.delayed(const Duration(milliseconds: 5)),
              );
              await tester.pumpAndSettle();
            }
          }
          expect(
            tester.takeException(),
            isNull,
            reason: '${mode.name}: ${route.value}',
          );
          final scaffold = find.byType(Scaffold).last;
          final rect = tester.getRect(scaffold);
          expect(rect.top, greaterThanOrEqualTo(28), reason: route.key);
          expect(rect.bottom, lessThanOrEqualTo(820), reason: route.key);
          if (snapshots.isNotEmpty) {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File('$snapshots/${mode.name}-${route.key}.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        }
      },
    );
  }

  appTest('bottom dock stays fixed through scrolling and primary navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fixture = await launch(tester);
    final router = fixture.container.read(routerProvider);
    for (final route in ['/today', '/substances', '/events', '/history']) {
      router.go(route);
      await settle(tester);
      final before = tester.getRect(find.byType(ShellNavigation));
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await settle(tester);
      expect(tester.getRect(find.byType(ShellNavigation)), before);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'framework panels keep long names and actions readable at large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ShadcnApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 740),
              textScaler: TextScaler.linear(2),
            ),
            child: VitalPage(
              title: 'Substances',
              children: [
                VitalPanel(
                  title: 'Recorded dose',
                  children: [
                    const VitalRecordHeader(
                      title: 'Full substance name with an exact strength',
                      subtitle: '0.125 mg',
                    ),
                    VitalActions(
                      children: [
                        VitalButton(
                          onPressed: () {},
                          child: const Text('Record'),
                        ),
                        VitalButton.secondary(
                          onPressed: () {},
                          child: const Text('Review'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Review'));
      expect(find.text('0.125 mg'), findsOneWidget);
      expect(
        find.text('Full substance name with an exact strength'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a standalone page respects all four landscape safe areas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(740, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ShadcnApp(
        builder: (context, child) => MediaQuery(
          data: const MediaQueryData(
            size: Size(740, 390),
            padding: EdgeInsets.fromLTRB(28, 18, 32, 20),
          ),
          child: child!,
        ),
        home: const VitalPage(
          title: 'Stock',
          children: [
            VitalPanel(children: [Text('Recorded container')]),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byType(Scaffold));
    expect(rect.left, 28);
    expect(rect.top, 18);
    expect(rect.right, 708);
    expect(rect.bottom, 370);
    expect(tester.takeException(), isNull);
  });
}
