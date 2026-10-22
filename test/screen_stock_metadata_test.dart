import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/features/stock/stock_pages.dart';
import 'package:true_grit_vital/features/stock/stock_providers.dart';
import 'package:true_grit_vital/app/display_preferences.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/platform/device_zone.dart';
import 'package:true_grit_vital/features/stock/stock_widgets.dart';

import 'app_lock_controller_test.dart' show ControlledAuth;
import 'design_system_test.dart' show host;

import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart'
    show LabelledInput;

import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

Finder field(String label) => find.descendant(
  of: find.widgetWithText(LabelledInput, label),
  matching: find.byType(TextField),
);

const metadataCaptures = String.fromEnvironment('VITAL_METADATA_CAPTURES');

Future<void> saveMetadataCapture(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$metadataCaptures/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

final class _Unlocked extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: false);
}

final class _Locked extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: true);
}

Future<void> openMetadataSnapshot(WidgetTester tester, int revision) async {
  final disclosure = find.byKey(ValueKey('stock-metadata-snapshot-$revision'));
  await tester.ensureVisible(disclosure);
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: disclosure, matching: find.text('Saved details')),
  );
  await tester.pumpAndSettle();
}

StoredStockMetadataRevision metadataRow(
  int revision, {
  String source = 'edited',
  String? lot,
  CivilDate? expiry,
  ExactAmount? capacity,
}) => StoredStockMetadataRevision(
  containerId: 'container',
  revision: revision,
  recordedAt: source == 'migrated'
      ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
      : DateTime.utc(2026, 10, 22),
  source: source,
  lot: lot,
  expiryDate: expiry,
  capacity: capacity,
);

Future<int> profileRevision(RecordStore store) async =>
    (await store.profileById(meId))!.revision;

Future<SubstanceItem> makeItem(
  RecordStore store,
  String name, {
  String unit = 'ml',
}) async => store.createItem(
  commandId: newCommandId(),
  expectedPersonRevision: await profileRevision(store),
  name: name,
  form: 'liquid',
  unit: unit,
  type: 'medicine',
);

Future<StoredStockContainer> makeContainer(
  RecordStore store,
  SubstanceItem item, {
  required String label,
  String opening = '3',
  String? lot,
  CivilDate? expiry,
  String? capacity,
  ExactAmount? capacityExact,
}) async => store.createStockContainer(
  commandId: newCommandId(),
  personId: meId,
  expectedPersonRevision: await profileRevision(store),
  expectedGeneration: store.generation,
  itemId: item.id,
  label: label,
  unit: item.unit,
  strength: LabelledStrength(
    ingredientId: item.id,
    label: '10 mg/ml',
    mgPerMl: ExactAmount.parseEntry('10'),
  ),
  opening: ExactAmount.parseEntry(opening),
  lot: lot,
  expiryDate: expiry,
  capacity:
      capacityExact ??
      (capacity == null ? null : ExactAmount.parseEntry(capacity)),
);

Future<void> makePlan(
  RecordStore store,
  SubstanceItem item, {
  bool paused = false,
}) async => store.saveDailyPlan(
  commandId: newCommandId(),
  expectedPersonRevision: await profileRevision(store),
  expectedGeneration: store.generation,
  plan: DailyPlanVersion(
    personId: meId,
    planId: 'plan-${item.id}',
    itemId: item.id,
    versionId: 'version-${item.id}',
    start: CivilDate(2020, 1, 1),
    timing: DailyCount(
      1,
      PlannedAmount(
        quantity: ExactQuantity.parse('1'),
        enteredText: '1',
        unit: item.unit,
      ),
    ),
    zoneBasis: const FollowingLocal(),
    pauses: paused ? [PlanPause(start: DateTime.utc(2020, 1, 2))] : const [],
  ),
);

void main() {
  testWidgets(
    'pack expiry uses the inventory snapshot day and stays neutral without a zone',
    (tester) async {
      final pack = StoredStockContainer(
        id: 'pack',
        personId: meId,
        itemId: 'item',
        label: 'Pack',
        unit: 'ml',
        strength: LabelledStrength(ingredientId: 'item', label: 'Unknown'),
        revision: 1,
        sequence: 1,
        balance: const StockBalance(null),
        refillEnabled: false,
        expiryDate: CivilDate(2026, 10, 22),
      );
      await tester.pumpWidget(
        host(
          StockPackFacts(container: pack, expiryDay: CivilDate(2026, 10, 23)),
        ),
      );
      expect(find.text('Expired 2026-10-22'), findsOneWidget);
      await tester.pumpWidget(
        host(
          StockPackFacts(container: pack, expiryDay: CivilDate(2026, 10, 22)),
        ),
      );
      expect(find.text('Expires today'), findsOneWidget);
      await tester.pumpWidget(
        host(StockPackFacts(container: pack, expiryUnavailable: true)),
      );
      expect(find.text('Expires 2026-10-22'), findsOneWidget);
      expect(find.text('Expired 2026-10-22'), findsNothing);
      expect(find.text('Expires today'), findsNothing);
    },
  );

  setUpAll(() async {
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

  testWidgets(
    'a failed forecast offers Retry and replaces its error after a successful read',
    (tester) async {
      var reads = 0;
      final container = StoredStockContainer(
        id: 'container',
        personId: meId,
        itemId: 'item',
        label: 'Bottle',
        unit: 'ml',
        strength: LabelledStrength(ingredientId: 'item', label: '10 mg/ml'),
        revision: 1,
        sequence: 1,
        balance: StockBalance(ExactAmount(BigInt.from(10))),
        refillEnabled: false,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            observedDeviceZoneProvider.overrideWith(
              (ref) => const Stream<DeviceZoneObservation>.empty(),
            ),
            stockForecastProvider.overrideWith((ref, query) async* {
              if (reads++ == 0) throw StateError('synthetic read failure');
              yield StockRunOutForecast.available(
                date: CivilDate(2026, 10, 25),
                days: 3,
                plannedThrough: CivilDate(2026, 10, 25),
              );
            }),
          ],
          child: host(
            SizedBox(
              width: 320,
              child: StockForecastLine(container: container),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Run-out unavailable'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Around 2026-10-25'), findsOneWidget);
      expect(find.text('Run-out unavailable'), findsNothing);
      expect(reads, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'details history explains changes and keeps full versions behind disclosure',
    (tester) async {
      final third = ExactAmount(BigInt.one, BigInt.from(3));
      final rows = [
        metadataRow(
          6,
          expiry: CivilDate(2027, 2, 28),
          capacity: ExactAmount(BigInt.from(12)),
        ),
        metadataRow(
          5,
          expiry: CivilDate(2027, 2, 28),
          capacity: ExactAmount(BigInt.from(12)),
        ),
        metadataRow(
          4,
          lot: 'OLD-LOT',
          expiry: CivilDate(2027, 1, 31),
          capacity: third,
        ),
        metadataRow(3, capacity: third),
        metadataRow(2),
        metadataRow(1, source: 'migrated'),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            displayZoneProvider.overrideWithValue('UTC'),
            appLockProvider.overrideWith(_Unlocked.new),
            stockMetadataHistoryProvider.overrideWith((ref, q) async* {
              yield rows.skip(q.offset).take(22).toList();
            }),
          ],
          child: host(
            const SizedBox(
              width: 320,
              child: SingleChildScrollView(
                child: StockMetadataHistory(
                  personId: meId,
                  containerId: 'container',
                  unit: 'ml',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lot or batch cleared. Was OLD-LOT.'), findsOneWidget);
      expect(
        find.text('Expiry date: 2027-01-31, now 2027-02-28'),
        findsOneWidget,
      );
      expect(find.text('Pack capacity: 1/3 ml, now 12 ml'), findsOneWidget);
      expect(find.text('Lot or batch: OLD-LOT (added)'), findsOneWidget);
      expect(find.text('Expiry date: 2027-01-31 (added)'), findsOneWidget);
      expect(find.text('Pack capacity: 1/3 ml (added)'), findsOneWidget);
      expect(find.text('No details changed.'), findsOneWidget);
      expect(
        find.text(
          'The previous version was carried forward. Its details were not recorded.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Carried forward, version 1. Time not recorded.'),
        findsOneWidget,
      );
      expect(find.text('First saved version.'), findsNothing);
      // Full saved versions stay closed until asked for.
      expect(find.text('Lot: OLD-LOT'), findsNothing);
      expect(find.text('Capacity: 12 ml'), findsNothing);

      await openMetadataSnapshot(tester, 5);
      expect(find.text('Lot or batch: not set'), findsOneWidget);
      expect(find.text('Expiry date: 2027-02-28'), findsOneWidget);
      expect(find.text('Capacity: 12 ml'), findsOneWidget);

      await openMetadataSnapshot(tester, 4);
      expect(find.text('Lot: OLD-LOT'), findsOneWidget);
      expect(find.text('Expiry date: 2027-01-31'), findsOneWidget);
      expect(find.text('Capacity: 1/3 ml'), findsOneWidget);

      await openMetadataSnapshot(tester, 1);
      expect(find.text('Lot or batch: not recorded'), findsOneWidget);
      expect(find.text('Expiry date: not recorded'), findsOneWidget);
      expect(find.text('Pack capacity: not recorded'), findsOneWidget);
      expect(find.textContaining('1970'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'details history does not bridge a missing revision or guess an old value',
    (tester) async {
      final rows = [
        metadataRow(6, lot: 'LOT-6'),
        metadataRow(5, lot: 'LOT-5'),
        metadataRow(3, lot: 'LOT-3'),
        metadataRow(2, lot: 'LOT-2'),
        metadataRow(1, source: 'migrated'),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            displayZoneProvider.overrideWithValue('UTC'),
            appLockProvider.overrideWith(_Unlocked.new),
            stockMetadataHistoryProvider.overrideWith((ref, q) async* {
              yield rows.skip(q.offset).take(22).toList();
            }),
          ],
          child: host(
            const SizedBox(
              width: 390,
              child: SingleChildScrollView(
                child: StockMetadataHistory(
                  personId: meId,
                  containerId: 'container',
                  unit: 'ml',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lot or batch: LOT-5, now LOT-6'), findsOneWidget);
      expect(
        find.text('Previous version unavailable, so changes are not shown.'),
        findsOneWidget,
      );
      expect(find.text('Lot or batch: LOT-2, now LOT-3'), findsOneWidget);
      expect(find.text('Lot or batch: LOT-2 (first recorded)'), findsOneWidget);
      expect(find.text('No details changed.'), findsNothing);
      expect(find.textContaining('LOT-4'), findsNothing);
      expect(
        find.text(
          'The previous version was carried forward. Its details were not recorded.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Carried forward, version 1. Time not recorded.'),
        findsOneWidget,
      );
      await openMetadataSnapshot(tester, 5);
      expect(find.text('Lot: LOT-5'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'details history compares the lookahead across both 20-row page boundaries',
    (tester) async {
      final third = ExactAmount(BigInt.one, BigInt.from(3));
      final rows = [
        for (var revision = 45; revision > 0; revision--)
          metadataRow(
            revision,
            source: revision == 1 ? 'migrated' : 'edited',
            lot: 'LOT-$revision',
            capacity: third,
          ),
      ];
      final offsets = <int>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            displayZoneProvider.overrideWithValue('UTC'),
            appLockProvider.overrideWith(_Unlocked.new),
            stockMetadataHistoryProvider.overrideWith((ref, q) async* {
              offsets.add(q.offset);
              yield rows.skip(q.offset).take(22).toList();
            }),
          ],
          child: host(
            const SizedBox(
              width: 430,
              child: SingleChildScrollView(
                child: StockMetadataHistory(
                  personId: meId,
                  containerId: 'container',
                  unit: 'ml',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lot or batch: LOT-44, now LOT-45'), findsOneWidget);
      expect(find.text('Lot or batch: LOT-25, now LOT-26'), findsOneWidget);
      await tester.ensureVisible(find.text('More'));
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(offsets, containsAllInOrder([0, 20]));
      expect(find.text('Lot or batch: LOT-24, now LOT-25'), findsOneWidget);
      expect(find.text('Lot or batch: LOT-5, now LOT-6'), findsOneWidget);
      await tester.ensureVisible(find.text('Previous'));
      await tester.tap(find.text('Previous'));
      await tester.pumpAndSettle();
      expect(find.text('Lot or batch: LOT-25, now LOT-26'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('details history keeps the final lookahead revision reachable', (
    tester,
  ) async {
    final rows = [
      for (var revision = 21; revision > 0; revision--)
        metadataRow(
          revision,
          source: revision == 1 ? 'created' : 'edited',
          lot: 'LOT-$revision',
        ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          displayZoneProvider.overrideWithValue('UTC'),
          appLockProvider.overrideWith(_Unlocked.new),
          stockMetadataHistoryProvider.overrideWith((ref, q) async* {
            yield rows.skip(q.offset).take(22).toList();
          }),
        ],
        child: host(
          const SizedBox(
            width: 390,
            child: SingleChildScrollView(
              child: StockMetadataHistory(
                personId: meId,
                containerId: 'container',
                unit: 'ml',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lot or batch: LOT-1, now LOT-2'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    await tester.ensureVisible(find.text('More'));
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('First saved version.'), findsOneWidget);
    expect(find.text('More'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'details history recovers from a failed read and keeps expanded content across live data',
    (tester) async {
      final controller = StreamController<List<StoredStockMetadataRevision>>();
      addTearDown(controller.close);
      var reads = 0;
      final initial = [
        metadataRow(2, lot: 'LOT-B'),
        metadataRow(1, source: 'created', lot: 'LOT-A'),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            displayZoneProvider.overrideWithValue('UTC'),
            appLockProvider.overrideWith(_Unlocked.new),
            stockMetadataHistoryProvider.overrideWith((ref, q) async* {
              reads++;
              if (reads == 1) throw StateError('synthetic read failure');
              yield* controller.stream;
            }),
          ],
          child: host(
            const SizedBox(
              width: 390,
              child: SingleChildScrollView(
                child: StockMetadataHistory(
                  personId: meId,
                  containerId: 'container',
                  unit: 'ml',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      controller.add(initial);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.text('Lot or batch: LOT-A, now LOT-B'), findsOneWidget);
      expect(find.text('First saved version.'), findsOneWidget);

      await openMetadataSnapshot(tester, 2);
      expect(find.text('Lot: LOT-B'), findsOneWidget);
      controller.add([metadataRow(3, lot: 'LOT-C'), ...initial]);
      await tester.pumpAndSettle();
      expect(find.text('Lot or batch: LOT-B, now LOT-C'), findsOneWidget);
      expect(find.text('Lot: LOT-B'), findsOneWidget);
      expect(find.text('Lot: LOT-C'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('details history hides while the app is locked', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          displayZoneProvider.overrideWithValue('UTC'),
          appLockProvider.overrideWith(_Locked.new),
          stockMetadataHistoryProvider.overrideWith((ref, q) async* {
            yield [
              metadataRow(2, lot: 'LOT-B'),
              metadataRow(1, source: 'created', lot: 'LOT-A'),
            ];
          }),
        ],
        child: host(
          const SizedBox(
            width: 390,
            child: SingleChildScrollView(
              child: StockMetadataHistory(
                personId: meId,
                containerId: 'container',
                unit: 'ml',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Saved details'), findsNothing);
    expect(find.textContaining('now LOT'), findsNothing);
    expect(find.text('No saved details versions.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'details history fits 320, 390 and 430 at double text in both themes',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final rows = [
        metadataRow(
          2,
          lot: 'LOT-B',
          expiry: CivilDate(2027, 2, 28),
          capacity: ExactAmount(BigInt.from(12)),
        ),
        metadataRow(1, source: 'created', lot: 'LOT-A'),
      ];
      for (final brightness in Brightness.values) {
        for (final width in [320.0, 390.0, 430.0]) {
          final boundaryKey = GlobalKey();
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                displayZoneProvider.overrideWithValue('UTC'),
                appLockProvider.overrideWith(_Unlocked.new),
                stockMetadataHistoryProvider.overrideWith((ref, q) async* {
                  yield rows;
                }),
              ],
              child: host(
                Builder(
                  builder: (context) => RepaintBoundary(
                    key: boundaryKey,
                    child: SizedBox(
                      width: width,
                      child: ColoredBox(
                        color: Theme.of(context).colorScheme.background,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: const SingleChildScrollView(
                            child: StockMetadataHistory(
                              personId: meId,
                              containerId: 'container',
                              unit: 'ml',
                            ),
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
          expect(
            tester.takeException(),
            isNull,
            reason: '${brightness.name} at $width and double text',
          );
          expect(find.text('Lot or batch: LOT-A, now LOT-B'), findsOneWidget);
          if (metadataCaptures.isNotEmpty) {
            await saveMetadataCapture(
              tester,
              boundaryKey,
              '${brightness.name}-${width.toInt()}-double-text',
            );
          }
          if (width == 320) {
            await openMetadataSnapshot(tester, 2);
            expect(tester.takeException(), isNull);
            if (metadataCaptures.isNotEmpty) {
              await saveMetadataCapture(
                tester,
                boundaryKey,
                '${brightness.name}-320-double-text-expanded',
              );
            }
          }
        }
      }
    },
  );

  appTest('metadata details save through the guarded stock editor', (
    tester,
  ) async {
    final f = await launch(tester, auth: ControlledAuth());
    final item = (await runIo(tester, () => makeItem(f.store, 'Telmisartan')))!;
    final container = (await runIo(
      tester,
      () => makeContainer(
        f.store,
        item,
        label: 'Amber bottle',
        lot: 'OLD-LOT',
        expiry: CivilDate(2027, 1, 31),
        capacity: '10',
      ),
    ))!;
    f.container.read(routerProvider).go('/stock/$meId');
    await settle(tester);
    await waitForText(tester, 'Lot: OLD-LOT');
    await tester.ensureVisible(
      find.byKey(ValueKey('stock-details-${container.id}')),
    );
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('stock-details-${container.id}')));
    await settle(tester);
    await waitForText(tester, 'Container details');
    await tester.enterText(field('Lot or batch'), 'NEW-LOT');
    await tester.enterText(field('Expiry date'), '2027-02-28');
    await tester.enterText(field('Pack capacity'), '12');
    await settle(tester);
    await tap(tester, 'Save');
    await waitForText(tester, 'Lot: NEW-LOT');
    expect(find.text('Expires 2027-02-28'), findsWidgets);
    expect(find.textContaining('12 ml'), findsWidgets);
    await runIo(tester, () async {
      final saved = (await f.store.stockContainerById(
        personId: meId,
        containerId: container.id,
      ))!;
      expect(saved.lot, 'NEW-LOT');
      expect(saved.expiryDate, CivilDate(2027, 2, 28));
      expect(saved.capacity, ExactAmount.parseEntry('12'));
      final history = await f.store.stockMetadataHistory(
        personId: meId,
        containerId: container.id,
      );
      expect(history.map((row) => row.lot), ['NEW-LOT', 'OLD-LOT']);
    });
    await runIo(
      tester,
      () => f.container.read(appLockProvider.notifier).setEnabled(true),
    );
    f.container.read(appLockProvider.notifier).lock();
    await settle(tester);
    expect(find.text('Lot: NEW-LOT'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  appTest('details editor guards unfinished changes and restores focus', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () => makeItem(f.store, 'Iron')))!;
    final container = (await runIo(
      tester,
      () => makeContainer(f.store, item, label: 'Iron bottle'),
    ))!;
    f.container
        .read(routerProvider)
        .go('/stock/$meId/adjust/${container.id}?details=true');
    await settle(tester);
    await waitForText(tester, 'Container details');
    await tester.enterText(field('Lot or batch'), 'UNSAVED');
    await settle(tester);
    await tester.binding.handlePopRoute();
    await settle(tester);
    await waitForText(tester, 'Unsaved changes');
    await tap(tester, 'Keep');
    await settle(tester);
    expect(field('Lot or batch'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settle(tester);
    await tap(tester, 'Discard');
    await settle(tester);
    expect(find.text('Unsaved changes'), findsNothing);
    expect(field('Lot or batch'), findsNothing);
  });

  appTest('unchanged exact capacity survives edits and draft restore', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(
      tester,
      () => makeItem(f.store, 'Exact capacity item'),
    ))!;
    final container = (await runIo(
      tester,
      () => makeContainer(
        f.store,
        item,
        label: 'Third vial',
        capacityExact: ExactAmount(BigInt.one, BigInt.from(3)),
      ),
    ))!;
    f.container
        .read(routerProvider)
        .go('/stock/$meId/adjust/${container.id}?details=true');
    await settle(tester);
    await waitForText(tester, 'Container details');
    expect(
      tester.widget<TextField>(field('Pack capacity')).controller!.text,
      '1/3',
    );
    await tester.enterText(field('Lot or batch'), 'EXACT-EDIT');
    await settle(tester);
    f.container.read(routerProvider).go('/today');
    await settle(tester);
    f.container
        .read(routerProvider)
        .go('/stock/$meId/adjust/${container.id}?details=true');
    await settle(tester);
    await waitForText(tester, 'Container details');
    expect(
      tester.widget<TextField>(field('Lot or batch')).controller!.text,
      'EXACT-EDIT',
    );
    expect(
      tester.widget<TextField>(field('Pack capacity')).controller!.text,
      '1/3',
    );
    await tap(tester, 'Save');
    await settle(tester);
    await runIo(tester, () async {
      final saved = (await f.store.stockContainerById(
        personId: meId,
        containerId: container.id,
      ))!;
      expect(saved.lot, 'EXACT-EDIT');
      expect(saved.capacity, ExactAmount(BigInt.one, BigInt.from(3)));
    });
  });

  appTest('details and quantity edits keep separate draft identities', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () => makeItem(f.store, 'Draft split')))!;
    final container = (await runIo(
      tester,
      () => makeContainer(f.store, item, label: 'Draft split bottle'),
    ))!;
    f.container
        .read(routerProvider)
        .go('/stock/$meId/adjust/${container.id}?details=true');
    await settle(tester);
    await waitForText(tester, 'Container details');
    await tester.enterText(field('Lot or batch'), 'DETAILS-DRAFT');
    await settle(tester);
    f.container.read(routerProvider).go('/today');
    await settle(tester);
    f.container.read(routerProvider).go('/stock/$meId/adjust/${container.id}');
    await settle(tester);
    await waitForText(tester, 'Adjust stock');
    final restock = find.widgetWithText(VitalButton, 'Restock');
    await tester.ensureVisible(restock);
    await tester.tap(restock);
    await settle(tester);
    await tester.enterText(field('Amount'), '4');
    await settle(tester);
    f.container.read(routerProvider).go('/today');
    await settle(tester);
    final drafts = (await runIo(
      tester,
      f.store.drafts,
    ))!.where((draft) => draft.kind == DraftKind.stockAdjustment).toList();
    expect(drafts, hasLength(2));
    final details = drafts.singleWhere(
      (draft) => draft.fields['kind'] == 'details',
    );
    final quantity = drafts.singleWhere(
      (draft) => draft.fields['kind'] == 'restock',
    );
    expect(details.id, 'stockAdjustment:$meId:${container.id}:details');
    expect(details.route, '/stock/$meId/adjust/${container.id}?details=true');
    expect(details.fields['lot'], 'DETAILS-DRAFT');
    expect(quantity.id, 'stockAdjustment:$meId:${container.id}');
    expect(quantity.fields['amount'], '4');
    f.container
        .read(routerProvider)
        .go('/stock/$meId/adjust/${container.id}?details=true');
    await settle(tester);
    await waitForText(tester, 'Container details');
    expect(
      tester.widget<TextField>(field('Lot or batch')).controller!.text,
      'DETAILS-DRAFT',
    );
    expect(find.text('4'), findsNothing);
  });

  appTest('whole-collection filters and search reach later cards', (
    tester,
  ) async {
    final f = await launch(tester);
    final (pausedItem, lastItem) = (await runIo(tester, () async {
      final paused = await makeItem(f.store, 'Zzz paused item');
      final last = await makeItem(f.store, 'Zzz cabinet item');
      for (var index = 0; index < 55; index++) {
        final row = await makeItem(f.store, 'A item $index');
        await makeContainer(
          f.store,
          row,
          label: 'Bottle $index',
          opening: '40',
        );
      }
      await makeContainer(
        f.store,
        paused,
        label: 'Paused bottle',
        opening: '40',
      );
      await makePlan(f.store, paused, paused: true);
      await makeContainer(
        f.store,
        last,
        label: 'Cabinet bottle',
        opening: '40',
      );
      return (paused, last);
    }))!;
    f.container.read(routerProvider).go('/stock/$meId');
    await settle(tester);
    await waitForText(tester, 'Bottle 0');
    expect(find.text('Paused bottle'), findsNothing);

    await tester.tap(find.byIcon(LucideIcons.listFilter).first);
    await settle(tester);
    expect(find.text('Stock filters'), findsWidgets);
    await tap(tester, 'Done');
    await settle(tester);
    await tester.tap(find.text('Paused (1)'));
    await settle(tester);
    await waitForText(tester, 'Paused bottle');
    expect(find.text('Bottle 0'), findsNothing);
    expect(find.text('Plan paused'), findsWidgets);
    await runIo(tester, () async {
      final snapshot = await f.store.stockInventory(
        personId: meId,
        now: DateTime.utc(2026, 10, 22, 12),
        observedZone: 'UTC',
        filter: StockInventoryFilter.paused,
      );
      expect(snapshot.containers.single.itemId, pausedItem.id);
    });

    await tester.tap(find.text('All (57)'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, 'cabinet');
    await settle(tester);
    await waitForText(tester, 'Cabinet bottle');
    expect(find.text('Paused bottle'), findsNothing);
    expect(lastItem.name, 'Zzz cabinet item');
  });

  appTest('exact capacity and conditional run-out share the card', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () async {
      final item = await makeItem(f.store, 'Vitamin D3 + K2');
      await makePlan(f.store, item);
      return item;
    }))!;
    await runIo(
      tester,
      () => makeContainer(
        f.store,
        item,
        label: 'Vitamin bottle',
        opening: '3',
        capacity: '10',
      ),
    );
    f.container.read(routerProvider).go('/stock/$meId');
    await settle(tester);
    await waitForText(tester, 'Pack capacity');
    expect(find.text('3 ml'), findsWidgets);
    expect(find.text('10 ml'), findsWidgets);
    await waitForText(tester, 'Run-out');
    expect(find.textContaining('Around '), findsOneWidget);
    expect(
      find.text(
        'Planned doses only. Starts tomorrow, so today\'s remaining planned use is excluded. Assumes this container supplies all of them.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  appTest('stock details and forecast survive 320px double text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final f = await launch(tester);
    final item = (await runIo(tester, () async {
      final item = await makeItem(
        f.store,
        'Magnesium Glycinate Extra Strength',
      );
      await makePlan(f.store, item);
      return item;
    }))!;
    final container = (await runIo(
      tester,
      () => makeContainer(
        f.store,
        item,
        label: 'Original amber bottle from the pharmacy cabinet',
        opening: '3',
        lot: 'LOT-320-NARROW',
        expiry: CivilDate(2027, 12, 31),
        capacity: '10',
      ),
    ))!;
    f.container.read(routerProvider).go('/stock/$meId');
    await settle(tester);
    await waitForText(tester, 'Lot: LOT-320-NARROW');
    for (final width in [320.0, 390.0, 430.0]) {
      tester.view.physicalSize = Size(width, 740);
      await settle(tester);
      expect(tester.takeException(), isNull, reason: '$width at double text');
      expect(
        find.text('Original amber bottle from the pharmacy cabinet'),
        findsWidgets,
      );
    }
    await tester.ensureVisible(
      find.byKey(ValueKey('stock-details-${container.id}')),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
  });
}
