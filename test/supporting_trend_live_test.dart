import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/artifact_transfer.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/supporting.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/supporting/supporting_pages.dart';
import 'package:true_grit_vital/features/supporting/supporting_trends.dart';
import 'package:true_grit_vital/platform/artifact_transfer.dart';
import 'package:true_grit_vital/platform/device_zone.dart';

import 'vital_app_test.dart' show appTest, launch, runIo, settle, tap;

LabPanelSnapshot panel(
  String id, {
  required String title,
  required String labId,
  required String labName,
  required String unit,
  required String value,
  required SupportingDate collection,
}) => LabPanelSnapshot(
  id: SupportingRecordId(id: id, personId: meId),
  title: title,
  collectionDate: collection,
  reportDate: SupportingDate.day(CivilDate(2026, 10, 20)),
  provenance: SupportingProvenance(
    mode: SupportingProvenanceMode.manualTranscription,
    laboratoryId: labId,
    laboratoryName: labName,
    methodId: 'method-a',
    methodText: 'Method A',
    specimenId: 'specimen-a',
    specimenText: 'Serum',
  ),
  results: [
    LabResultSnapshot(
      id: 'result-$id',
      metricId: 'metric',
      markerName: 'Marker',
      originalMarkerText: 'Marker',
      value: SupportingValue.numeric(value),
      unit: unit,
      referenceRange: SourceReferenceRange(originalText: '3 to 7'),
    ),
  ],
);

Future<SupportingRevision> savePanel(
  WidgetTester tester,
  RecordStore store,
  LabPanelSnapshot snapshot, {
  required String command,
  int? expectedRevision,
}) async {
  final person = (await runIo(tester, () => store.profileById(meId)))!;
  return (await runIo(
    tester,
    () => store.saveLabPanel(
      SaveLabPanelCommand(
        commandId: command,
        generation: store.generation,
        expectedPersonRevision: person.revision,
        expectedRevision: expectedRevision,
        panel: snapshot,
      ),
    ),
  ))!;
}

Future<SupportingRevision> setVoided(
  WidgetTester tester,
  RecordStore store,
  SupportingRevision revision, {
  required String command,
  required bool voided,
}) async {
  final person = (await runIo(tester, () => store.profileById(meId)))!;
  return (await runIo(
    tester,
    () => store.voidSupportingRecord(
      VoidSupportingRecordCommand(
        commandId: command,
        generation: store.generation,
        personId: meId,
        id: revision.id.id,
        expectedPersonRevision: person.revision,
        expectedRevision: revision.revision,
        isVoided: voided,
      ),
    ),
  ))!;
}

String identityOf(SupportingRevision revision) =>
    SupportingComparisonKey.forResult(
      revision,
      revision.snapshot.results.single,
    ).identity;

SupportingTrendGroup selectedGroup(WidgetTester tester) =>
    tester.widget<SupportingPlot>(find.byType(SupportingPlot)).group;

Future<void> selectGroup(WidgetTester tester, String unit) async {
  final target = find.textContaining('Unit: $unit').first;
  await tester.ensureVisible(target);
  await settle(tester);
  await tester.tap(target);
  await settle(tester);
}

/// Live refresh crosses the store watcher and a provider rebuild, which can
/// take longer than one [settle]. Wait for a positive on-screen signal instead
/// of asserting against the previous model.
Future<void> waitForWidget(WidgetTester tester, Finder finder) async {
  final elapsed = Stopwatch()..start();
  while (finder.evaluate().isEmpty) {
    if (elapsed.elapsed > const Duration(seconds: 10)) {
      throw TestFailure('Expected widget did not appear: $finder');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();
  }
}

final class _TrendSubscription {
  _TrendSubscription(this.query, this.requestGeneration, this._watcher);
  final SupportingTrendQuery query;
  final int requestGeneration;
  final _WatcherCounters _watcher;
  late final StreamController<SupportingTrendPage> controller =
      StreamController<SupportingTrendPage>(
        onListen: () => _watcher.listens++,
        onCancel: () => _watcher.cancels++,
      );
}

final class _WatcherCounters {
  int listens = 0, cancels = 0;
}

/// A controlled handle on the bounded watcher seam so a widget test can prove
/// when the page subscribes, detaches and resubscribes.
final class _ControlledTrendWatcher {
  final subscriptions = <_TrendSubscription>[];
  final _counters = _WatcherCounters();
  int get listens => _counters.listens;
  int get cancels => _counters.cancels;
  int get active => listens - cancels;
  _TrendSubscription get latest => subscriptions.last;

  Stream<SupportingTrendPage> call(
    SupportingTrendQuery query, {
    int requestGeneration = 0,
  }) {
    final subscription = _TrendSubscription(
      query,
      requestGeneration,
      _counters,
    );
    subscriptions.add(subscription);
    return subscription.controller.stream;
  }
}

/// Mirrors the shared launch helper with one extra override so the controlled
/// watcher replaces the real store stream for the whole session.
Future<({RecordStore store, ProviderContainer container})> _launchWithWatcher(
  WidgetTester tester,
  _ControlledTrendWatcher watcher,
) async {
  final directory = (await runIo(
    tester,
    () => Directory.systemTemp.createTemp('vital-trend-live-'),
  ))!;
  final key = List.generate(32, (i) => i + 1);
  final store = (await runIo(
    tester,
    () => RecordStore.open(
      path: '${directory.path}/test.db',
      key: key,
      isNew: true,
    ),
  ))!;
  await runIo(tester, () async {
    final me = (await store.profileById(meId))!;
    await store.editProfile(
      commandId: 'fixture-adult',
      personId: meId,
      expectedRevision: me.revision,
      name: 'Me',
      adultConfirmed: true,
    );
    await store.saveBrowsingScope(const FeedScope.me());
  });
  final container = ProviderContainer(
    overrides: [
      observedDeviceZoneProvider.overrideWith(
        (ref) => Stream.value(DeviceZoneObservation.fromId('Europe/London')),
      ),
      storeLoaderProvider.overrideWithValue(() => Future.value(store)),
      artifactTransferGatewayProvider.overrideWithValue(
        const UnsupportedArtifactTransfer(),
      ),
      supportingTrendWatcherProvider.overrideWithValue(watcher.call),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await store.close();
    await directory.delete(recursive: true);
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const VitalApp()),
  );
  await settle(tester);
  return (store: store, container: container);
}

void main() {
  appTest('a trend opened while inactive waits for resume', (tester) async {
    final watcher = _ControlledTrendWatcher();
    final f = await _launchWithWatcher(tester, watcher);
    try {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await settle(tester);
      f.container
          .read(routerProvider)
          .go('/supporting/$meId/trends?metric=metric');
      await settle(tester);
      expect(watcher.subscriptions, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(watcher.subscriptions, hasLength(1));
      expect(watcher.active, 1);
    } finally {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
  });

  appTest(
    'a visible trend adopts saved corrected and voided records without invalidation',
    (tester) async {
      final f = await launch(tester);
      final a = await savePanel(
        tester,
        f.store,
        panel(
          'a',
          title: 'Lab one',
          labId: 'lab-a',
          labName: 'Lab One',
          unit: 'mg/L',
          value: '1',
          collection: SupportingDate.day(CivilDate(2026, 10, 5)),
        ),
        command: 'save-a',
      );
      f.container
          .read(routerProvider)
          .go('/supporting/$meId/trends?metric=metric');
      await waitForWidget(tester, find.textContaining('Unit: mg/L'));

      // A save in another flow updates this view in place.
      final b = await savePanel(
        tester,
        f.store,
        panel(
          'b',
          title: 'Lab two',
          labId: 'lab-b',
          labName: 'Lab Two',
          unit: 'g/L',
          value: '2',
          collection: SupportingDate.day(CivilDate(2026, 10, 10)),
        ),
        command: 'save-b',
      );
      await waitForWidget(tester, find.textContaining('Unit: g/L'));
      await settle(tester);
      expect(find.text('Lab two'), findsWidgets);
      await selectGroup(tester, 'g/L');
      expect(selectedGroup(tester).key.identity, identityOf(b));

      // A correction of the chosen record is reflected without a new query,
      // and its exact comparison identity stays selected.
      final corrected = await savePanel(
        tester,
        f.store,
        panel(
          'b',
          title: 'Lab two',
          labId: 'lab-b',
          labName: 'Lab Two',
          unit: 'g/L',
          value: '2.5',
          collection: SupportingDate.day(CivilDate(2026, 9, 1)),
        ),
        command: 'correct-b',
        expectedRevision: b.revision,
      );
      await waitForWidget(tester, find.textContaining('2.5 g/L'));
      await settle(tester);
      expect(selectedGroup(tester).key.identity, identityOf(corrected));
      expect(
        find.textContaining('Group 1 of 2. Marker. Unit: g/L'),
        findsWidgets,
      );

      // A void removes the points while the chosen identity remains named.
      final voided = await setVoided(
        tester,
        f.store,
        corrected,
        command: 'void-b',
        voided: true,
      );
      await waitForWidget(
        tester,
        find.text(
          'This group has no results in the selected dates. '
          'Choose another group or change the dates.',
        ),
      );
      await settle(tester);
      expect(find.byType(SupportingPlot), findsNothing);
      expect(find.textContaining('Unit: g/L'), findsOneWidget);
      expect(find.textContaining('2.5 g/L'), findsNothing);

      // Restoring the same identity brings its points back in place.
      final restored = await setVoided(
        tester,
        f.store,
        voided,
        command: 'restore-b',
        voided: false,
      );
      await waitForWidget(tester, find.byType(SupportingPlot));
      await settle(tester);
      expect(selectedGroup(tester).key.identity, identityOf(restored));
      expect(
        selectedGroup(tester).entries.single.record.snapshot.title,
        'Lab two',
      );
      expect(identityOf(a), isNot(identityOf(restored)));
    },
  );

  appTest(
    'returning from a record re-reads the current query without changing the selection',
    (tester) async {
      final f = await launch(tester);
      final a = await savePanel(
        tester,
        f.store,
        panel(
          'a',
          title: 'Lab one',
          labId: 'lab-a',
          labName: 'Lab One',
          unit: 'mg/L',
          value: '1',
          collection: SupportingDate.day(CivilDate(2026, 10, 5)),
        ),
        command: 'save-a',
      );
      final b = await savePanel(
        tester,
        f.store,
        panel(
          'b',
          title: 'Lab two',
          labId: 'lab-b',
          labName: 'Lab Two',
          unit: 'g/L',
          value: '2',
          collection: SupportingDate.day(CivilDate(2026, 10, 10)),
        ),
        command: 'save-b',
      );
      f.container
          .read(routerProvider)
          .go('/supporting/$meId/trends?metric=metric');
      await waitForWidget(tester, find.textContaining('Unit: g/L'));
      await settle(tester);
      await selectGroup(tester, 'g/L');
      expect(selectedGroup(tester).key.identity, identityOf(b));

      await tap(tester, 'Open');
      expect(find.byType(SupportingDetailPage), findsOneWidget);

      // The covered trend page must not show this record, but its own fresh
      // read on return must.
      final c = await savePanel(
        tester,
        f.store,
        panel(
          'c',
          title: 'Earlier lab three',
          labId: 'lab-c',
          labName: 'Lab Three',
          unit: 'umol/L',
          value: '3',
          collection: SupportingDate.day(CivilDate(2026, 10, 1)),
        ),
        command: 'save-c',
      );
      f.container.read(routerProvider).pop();
      await waitForWidget(tester, find.text('Earlier lab three'));
      await settle(tester);
      expect(selectedGroup(tester).key.identity, identityOf(b));
      expect(
        selectedGroup(tester).entries.single.record.snapshot.title,
        'Lab two',
      );
      expect(identityOf(c), isNot(identityOf(b)));
      expect(identityOf(a), isNot(identityOf(b)));
    },
  );

  appTest(
    'a covered or hidden trend detaches and reattaches once without publishing late work',
    (tester) async {
      final watcher = _ControlledTrendWatcher();
      final f = await _launchWithWatcher(tester, watcher);
      final a = await savePanel(
        tester,
        f.store,
        panel(
          'a',
          title: 'Lab one',
          labId: 'lab-a',
          labName: 'Lab One',
          unit: 'mg/L',
          value: '1',
          collection: SupportingDate.day(CivilDate(2026, 10, 5)),
        ),
        command: 'save-a',
      );
      final b = await savePanel(
        tester,
        f.store,
        panel(
          'b',
          title: 'Lab two',
          labId: 'lab-b',
          labName: 'Lab Two',
          unit: 'g/L',
          value: '2',
          collection: SupportingDate.day(CivilDate(2026, 10, 10)),
        ),
        command: 'save-b',
      );
      void emit(
        _TrendSubscription subscription,
        List<SupportingRevision> rows,
      ) {
        subscription.controller.add(
          SupportingTrendPage.build(
            query: subscription.query,
            records: rows,
            schemaVersion: 21,
            datasetGeneration: f.store.generation,
            requestGeneration: subscription.requestGeneration,
          ),
        );
      }

      f.container
          .read(routerProvider)
          .go('/supporting/$meId/trends?metric=metric');
      await settle(tester);
      expect(watcher.listens, 1);
      expect(watcher.active, 1);
      emit(watcher.latest, [a, b]);
      await waitForWidget(tester, find.textContaining('Unit: g/L'));
      await settle(tester);
      await selectGroup(tester, 'g/L');
      expect(selectedGroup(tester).key.identity, identityOf(b));
      final queryIdentity = watcher.latest.query.identity;

      // Opening a record covers the page, which lets the provider dispose and
      // cancels the only store subscription.
      await tap(tester, 'Open');
      expect(find.byType(SupportingDetailPage), findsOneWidget);
      await settle(tester);
      expect(watcher.cancels, 1);
      expect(watcher.active, 0);
      final detached = watcher.subscriptions.first;

      // A result that arrives for the retired subscription must not surface.
      final c = await savePanel(
        tester,
        f.store,
        panel(
          'c',
          title: 'Earlier lab three',
          labId: 'lab-c',
          labName: 'Lab Three',
          unit: 'umol/L',
          value: '3',
          collection: SupportingDate.day(CivilDate(2026, 10, 1)),
        ),
        command: 'save-c',
      );
      emit(detached, [a, b, c]);
      await settle(tester);
      expect(find.text('Earlier lab three'), findsNothing);

      // Returning reattaches once for the unchanged query and adopts its read.
      f.container.read(routerProvider).pop();
      await settle(tester);
      expect(watcher.subscriptions.length, 2);
      expect(watcher.active, 1);
      expect(watcher.latest.query.identity, queryIdentity);
      emit(watcher.latest, [a, b, c]);
      await waitForWidget(tester, find.text('Earlier lab three'));
      await settle(tester);
      expect(selectedGroup(tester).key.identity, identityOf(b));

      // Losing the foreground detaches too, and returning reattaches once.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await settle(tester);
      expect(watcher.cancels, 2);
      expect(watcher.active, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(watcher.subscriptions.length, 3);
      expect(watcher.active, 1);
      emit(watcher.latest, [a, b, c]);
      await waitForWidget(tester, find.text('Earlier lab three'));
      await settle(tester);
      expect(selectedGroup(tester).key.identity, identityOf(b));
    },
  );
}
