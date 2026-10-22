import 'dart:async';
import 'dart:io';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_theme.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/substances/substance_summary.dart';
import 'package:true_grit_vital/l10n/app_localizations.dart';
import 'package:true_grit_vital/platform/device_zone.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'vital_app_test.dart' show runIo, settle, waitForText;

ExactAmount whole(int value, [int denominator = 1]) =>
    ExactAmount(BigInt.from(value), BigInt.from(denominator));

/// Exact planned amount with the entered text used on screen.
PlannedAmount dose(String amount, String unit) => PlannedAmount(
  quantity: ExactQuantity.parse(amount),
  unit: unit,
  enteredText: amount,
);

/// A single-adult store with one item and the summary's own provider set.
class SummaryFixture {
  SummaryFixture(
    this._tester,
    this.store,
    this.item,
    this.directory, {
    this.onZoneObserve,
  }) {
    _container = ProviderContainer(
      overrides: [
        storeLoaderProvider.overrideWithValue(() async => store),
        observedDeviceZoneProvider.overrideWith((ref) {
          // Counts one build per (re)subscription so interactions prove the
          // retry re-requests a fresh observation rather than reusing state.
          onZoneObserve?.call();
          return zone ??
              Stream.value(DeviceZoneObservation.fromId('Europe/London'));
        }),
      ],
    );
    addTearDown(_container.dispose);
    addTearDown(() async {
      await store.close();
      await directory.delete(recursive: true);
    });
  }

  final WidgetTester _tester;
  final RecordStore store;
  final SubstanceItem item;
  final Directory directory;

  /// Optional observation-subscription counter for interaction assertions.
  final void Function()? onZoneObserve;

  /// Replacing the observed zone exercises named-zone and partial states.
  Stream<DeviceZoneObservation>? zone;
  late final ProviderContainer _container;

  ProviderContainer get container => _container;

  WidgetTester get tester => _tester;

  Future<void> waitText(String text) => waitForText(_tester, text);

  /// Bounded wait similar to waitText for value-bearing segments.
  Future<void> waitTextContaining(String text) async {
    final elapsed = Stopwatch()..start();
    while (find.textContaining(text).evaluate().isEmpty) {
      if (elapsed.elapsed > const Duration(seconds: 10)) {
        throw TestFailure('Expected rendered text did not appear: $text');
      }
      await settle(_tester);
    }
  }

  /// Bounded wait for a state decision that leaves an outcome empty.
  Future<void> waitDisappear(String text) async {
    final elapsed = Stopwatch()..start();
    while (find.text(text).evaluate().isNotEmpty) {
      if (elapsed.elapsed > const Duration(seconds: 20)) {
        throw TestFailure('Expected rendered text to disappear: $text');
      }
      await settle(_tester);
    }
  }

  /// Bounded wait until the finder matches at least [count] widgets.
  Future<void> waitCount(Finder finder, int count) async {
    final elapsed = Stopwatch()..start();
    while (finder.evaluate().length < count) {
      if (elapsed.elapsed > const Duration(seconds: 10)) {
        throw TestFailure('Expected $count widgets for $finder');
      }
      await settle(_tester);
    }
  }

  /// Watches the summary the collection mounts below the identity header.
  Future<void> mount({bool detailed = false}) async {
    _tester.pumpWidget(
      UncontrolledProviderScope(
        container: _container,
        child: ShadcnApp(
          theme: vitalTheme(Brightness.light),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', 'GB')],
          home: VitalComponentThemes(
            child: SingleChildScrollView(
              child: SubstanceSummary(item: item, detailed: detailed),
            ),
          ),
        ),
      ),
    );
    await settle(_tester);
  }

  /// Stores an exact container; an omitted opening stays factual unknown.
  Future<StoredStockContainer> stock({
    String label = 'Synthetic vial',
    String unit = 'mg',
    String strength = '2 mg/ml',
    String? opening,
    String? threshold,
  }) async {
    return (await runIo(
      _tester,
      () async => store.createStockContainer(
        commandId: newCommandId(),
        personId: meId,
        expectedPersonRevision: (await store.profileById(meId))!.revision,
        expectedGeneration: store.generation,
        itemId: item.id,
        label: label,
        unit: unit,
        strength: LabelledStrength(
          ingredientId: 'ingredient',
          label: strength,
          mgPerMl: unit == 'ml' ? whole(2) : null,
        ),
        opening: opening == null ? null : ExactAmount.parseEntry(opening),
        lowThreshold: threshold == null
            ? null
            : ExactAmount.parseEntry(threshold),
      ),
    ))!;
  }

  /// Stores one plan; saving with the same planId creates a new version.
  ///
  /// The store keeps one routine per item; a second routine is rejected.
  Future<SavedDailyPlan> plan(
    String planId,
    DailyTiming timing, {
    CivilDate? start,
    CivilDate? endExclusive,
    Iterable<PlanPause> pauses = const [],
    CalendarPattern calendar = const EveryDay(),
    int? expectedPlanRevision,
    String instructions = '',
  }) async {
    final born = CivilDate.fromDateTime(
      DateTime.now().toUtc().subtract(const Duration(days: 7)),
    );
    return (await runIo(
      _tester,
      () async => store.saveDailyPlan(
        commandId: newCommandId(),
        plan: DailyPlanVersion(
          personId: meId,
          planId: planId,
          itemId: item.id,
          versionId: '$planId-${newCommandId()}',
          start: start ?? born,
          endExclusive: endExclusive,
          timing: timing,
          zoneBasis: const FollowingLocal(),
          calendar: calendar,
          pauses: pauses,
          instructions: instructions,
        ),
        expectedPersonRevision: (await store.profileById(meId))!.revision,
        expectedPlanRevision: expectedPlanRevision,
        expectedGeneration: store.generation,
      ),
    ))!;
  }

  /// Restocks an exact amount and returns the refreshed container row.
  Future<StoredStockContainer> restock(
    StoredStockContainer container,
    String amount,
  ) => adjust(container, StockMovementKind.restock, amount).then(
    (_) => (runIo(
      _tester,
      () => store.stockContainerById(personId: meId, containerId: container.id),
    )).then((value) => value!),
  );

  /// Applies any adjustment movement so deficit/low/unknown states arise.
  Future<void> adjust(
    StoredStockContainer container,
    StockMovementKind kind,
    String amount,
  ) => runIo(
    _tester,
    () async => store.addStockMovement(
      commandId: newCommandId(),
      personId: meId,
      expectedPersonRevision: (await store.profileById(meId))!.revision,
      expectedGeneration: store.generation,
      containerId: container.id,
      expectedContainerRevision: container.revision,
      kind: kind,
      amount: EnteredStockAmount(amount, container.unit),
    ),
  );

  /// Records one dose that consumes exact stock, as accumulator touchpoints do.
  Future<void> take(StoredStockContainer container, String amount) =>
      runIo(_tester, () async {
        final born = CivilDate.fromDateTime(
          DateTime.now().toUtc().subtract(const Duration(days: 3)),
        );
        final rows = (await store.dailyRows(
          from: born,
          toExclusive: born.addDays(9),
          observedZone: 'Europe/London',
        )).rows;
        // Take the latest appearance in the window; earlier recorded dates keep
        // their own identities without stock effects from today's record.
        final current = rows.reduce(
          (a, b) =>
              a.expectation.identity.originalDate.compareTo(
                    b.expectation.identity.originalDate,
                  ) >=
                  0
              ? a
              : b,
        );
        await store.actDaily(
          commandId: newCommandId(),
          row: current,
          kind: DailyActionKind.taken,
          actualAt: DateTime.now().toUtc(),
          stockUse: StockUseInput(
            expectedGeneration: store.generation,
            containerId: container.id,
            expectedContainerRevision: container.revision,
            entered: EnteredStockAmount(amount, container.unit),
          ),
        );
      });

  /// Replaces the stored plan version with one newly-renderable pause.
  Future<SavedDailyPlan> pause(String planId, {DateTime? resumeAt}) async {
    final now = DateTime.now().toUtc();
    final pause = PlanPause(
      start: now.subtract(const Duration(days: 1)),
      resume: resumeAt,
    );
    final existing = (await runIo(
      _tester,
      () => store.dailyPlans(scope: FeedScope.person(meId), itemId: item.id),
    ))!;
    final revision = existing
        .where((saved) => saved.plan.planId == planId)
        .map((saved) => saved.revision)
        .firstOrNull;
    return plan(
      planId,
      DailyCount(1, dose('1', 'mg')),
      pauses: [pause],
      expectedPlanRevision: revision,
    );
  }
}

/// Mounts any summary with any container: failure states mount without a store.
Future<void> mountOn(
  WidgetTester tester,
  ProviderContainer container,
  SubstanceItem item, {
  bool detailed = false,
}) async {
  tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: ShadcnApp(
        theme: vitalTheme(Brightness.light),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', 'GB')],
        home: VitalComponentThemes(
          child: SingleChildScrollView(
            child: SubstanceSummary(item: item, detailed: detailed),
          ),
        ),
      ),
    ),
  );
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  await settle(tester);
}

/// Opens the fixture with compact/detailed mounting left to the caller.
Future<SummaryFixture> openSummaryFixture(
  WidgetTester tester, {
  Stream<DeviceZoneObservation>? zone,
  void Function()? onZoneObserve,
}) async {
  final directory = (await runIo(
    tester,
    () => Directory.systemTemp.createTemp('vital-summary-'),
  ))!;
  final key = List.generate(32, (i) => i + 1);
  final store = (await runIo(
    tester,
    () => RecordStore.open(
      path: '${directory.path}/records.db',
      key: key,
      isNew: true,
    ),
  ))!;
  final item = (await runIo(
    tester,
    () => store.createItem(
      commandId: newCommandId(),
      name: 'Synthetic substance',
      form: 'Tablet',
      unit: 'mg',
      type: 'Medicine',
    ),
  ))!;
  final fixture = SummaryFixture(
    tester,
    store,
    item,
    directory,
    onZoneObserve: onZoneObserve,
  );
  if (zone != null) {
    fixture.zone = zone;
  }
  return fixture;
}
