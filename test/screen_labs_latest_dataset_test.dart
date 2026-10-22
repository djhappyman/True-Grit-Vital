import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/supporting/screen_labs_latest.dart';

final class _TestLock extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: false);
  void lockNow() => state = const AppLockState(ready: true, locked: true);
  void unlockNow() => state = const AppLockState(ready: true, locked: false);
}

SupportingProvenance _source({
  String laboratoryId = 'lab-a',
  String methodId = 'method-a',
  String specimenId = 'specimen-a',
}) => SupportingProvenance(
  mode: SupportingProvenanceMode.manualTranscription,
  laboratoryId: laboratoryId,
  laboratoryName: 'Laboratory $laboratoryId',
  methodId: methodId,
  methodText: 'Method $methodId',
  specimenId: specimenId,
  specimenText: 'Specimen $specimenId',
);

LabResultSnapshot _result(
  String id, {
  required String metric,
  required String name,
  String? value,
  String? unit = 'mg/L',
  String? text,
}) => LabResultSnapshot(
  id: id,
  metricId: metric,
  markerName: name,
  value: value != null
      ? SupportingValue.numeric(value)
      : text != null
      ? SupportingValue.qualitative(text)
      : SupportingValue.missing(),
  unit: unit,
);

LabPanelSnapshot _panel({
  required String id,
  required CivilDate day,
  required List<LabResultSnapshot> results,
  String? title,
  SupportingProvenance? provenance,
  List<SupportingContextLink> links = const [],
}) => LabPanelSnapshot(
  id: SupportingRecordId(id: id, personId: meId),
  title: title ?? 'Panel $id',
  collectionDate: SupportingDate.day(day),
  reportDate: SupportingDate.day(day),
  provenance: provenance ?? _source(),
  results: results,
  contextLinks: links,
);

Future<SupportingRevision> _savePanel(
  RecordStore store,
  LabPanelSnapshot panel, {
  int? expectedRevision,
}) async {
  final person = (await store.profileById(meId))!;
  return store.saveLabPanel(
    SaveLabPanelCommand(
      commandId: 'save-${panel.id.id}-${expectedRevision ?? 0}',
      generation: store.generation,
      expectedPersonRevision: person.revision,
      expectedRevision: expectedRevision,
      panel: panel,
    ),
  );
}

Future<SupportingRevision> _saveObservation(
  RecordStore store, {
  required String id,
  required CivilDate day,
  required List<LabResultSnapshot> results,
  List<SupportingContextLink> links = const [],
}) async {
  final person = (await store.profileById(meId))!;
  return store.saveObservation(
    SaveObservationCommand(
      commandId: 'save-observation-$id',
      generation: store.generation,
      expectedPersonRevision: person.revision,
      observation: ObservationSnapshot(
        id: SupportingRecordId(id: id, personId: meId),
        title: 'Observation $id',
        measuredDate: SupportingDate.day(day),
        provenance: SupportingProvenance(
          mode: SupportingProvenanceMode.manualObservation,
        ),
        components: results,
        contextLinks: links,
      ),
    ),
  );
}

Future<SubstanceItem> _item(RecordStore store) => store.createItem(
  commandId: 'latest-item',
  name: 'Linked item',
  form: 'tablet',
  unit: 'count',
  type: 'medicine',
);

Future<EventRecord> _event(RecordStore store) async {
  final person = (await store.profileById(meId))!;
  final event = EventRecord(
    id: 'linked-event',
    personId: meId,
    name: 'Linked event',
    eventType: 'course',
    zoneId: 'Europe/London',
    revision: 1,
    plannedStart: EventDate.day(CivilDate(2026, 1, 1)),
    plannedEnd: EventDate.day(CivilDate(2026, 2, 1)),
  );
  final command = SaveEventCommand(
    commandId: 'latest-event',
    generation: store.generation,
    expectedRevision: null,
    expectedPersonRevision: person.revision,
    event: event,
  );
  return store.saveEvent(
    command,
    membershipReview: await store.previewEventMembership(command),
  );
}

Future<ScreenLabsLatest> _latest(
  RecordStore store, {
  SupportingRecordKind? kind,
  String? itemId,
  String? eventId,
  CivilDate? fromDate,
  CivilDate? beforeDate,
  int markerLimit = 100,
}) async {
  final page = await store.supportingLatest(
    SupportingLatestQuery(
      personId: meId,
      kind: kind,
      fromDate: fromDate,
      beforeDate: beforeDate,
      itemId: itemId,
      eventId: eventId,
      markerLimit: markerLimit,
    ),
  );
  return screenLabsProjectLatest(page, displayZone: 'UTC');
}

ScreenLabsLatestRequest _request({int markerLimit = 100}) => (
  personId: meId,
  displayZone: 'UTC',
  kind: null,
  itemId: null,
  eventId: null,
  fromDate: null,
  beforeDate: null,
  markerLimit: markerLimit,
  markerOffset: 0,
);

Future<ScreenLabsLatest> _waitFor(
  ProviderContainer container,
  StreamProvider<ScreenLabsLatest> provider,
  bool Function(ScreenLabsLatest latest) matches,
) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < const Duration(seconds: 10)) {
    final latest = container.read(provider).value;
    if (latest != null && matches(latest)) return latest;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw TestFailure('Latest-value provider did not reach the expected state.');
}

void main() {
  late Directory directory;
  late RecordStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-latest-dataset-');
    store = await RecordStore.open(
      path: '${directory.path}/records.db',
      key: List.generate(32, (index) => index + 1),
      isNew: true,
    );
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'duplicate comparable results in one prior panel remain ambiguous',
    () async {
      await _savePanel(
        store,
        _panel(
          id: 'prior-duplicates',
          day: CivilDate(2026, 1, 1),
          results: [
            _result(
              'prior-a',
              metric: 'same-marker',
              name: 'Same marker',
              value: '1',
            ),
            _result(
              'prior-b',
              metric: 'same-marker',
              name: 'Same marker',
              value: '2',
            ),
          ],
        ),
      );
      await _savePanel(
        store,
        _panel(
          id: 'latest',
          day: CivilDate(2026, 1, 3),
          results: [
            _result(
              'latest',
              metric: 'same-marker',
              name: 'Same marker',
              value: '3',
            ),
          ],
        ),
      );
      final latest = (await _latest(store)).values.single;
      expect(latest.result.value.originalText, '3');
      expect(latest.previousResult, isNull);
    },
  );

  test(
    'a candidate boundary never supplies a partially read prior panel',
    () async {
      final start = CivilDate(2026, 1, 1);
      await _savePanel(
        store,
        _panel(
          id: 'boundary',
          day: start,
          results: [
            _result(
              'boundary-a',
              metric: 'same-marker',
              name: 'Same marker',
              value: '1',
            ),
            _result(
              'boundary-b',
              metric: 'same-marker',
              name: 'Same marker',
              value: '2',
            ),
          ],
        ),
      );
      for (var i = 1; i <= 46; i++) {
        await _savePanel(
          store,
          _panel(
            id: 'different-$i',
            day: start.addDays(i),
            provenance: _source(laboratoryId: 'different'),
            results: [
              _result(
                'different-$i',
                metric: 'same-marker',
                name: 'Same marker',
                value: '5',
              ),
            ],
          ),
        );
      }
      await _savePanel(
        store,
        _panel(
          id: 'latest',
          day: start.addDays(47),
          results: [
            _result(
              'latest',
              metric: 'same-marker',
              name: 'Same marker',
              value: '3',
            ),
          ],
        ),
      );
      final latest = (await _latest(store)).values.single;
      expect(latest.result.value.originalText, '3');
      expect(latest.previousResult, isNull);
    },
  );

  test('an old marker and more than sixty markers stay reachable', () async {
    final start = CivilDate(2026, 1, 1);
    for (var index = 0; index < 80; index++) {
      await _savePanel(
        store,
        _panel(
          id: 'r${index.toString().padLeft(2, '0')}',
          day: start.addDays(index),
          results: [
            _result(
              'result-$index',
              metric: 'metric-$index',
              name: 'Marker ${index.toString().padLeft(2, '0')}',
              value: '$index',
            ),
          ],
        ),
      );
    }

    final page = await store.supportingLatest(
      SupportingLatestQuery(personId: meId, markerLimit: 24),
    );
    expect(page.recordCount, 80);
    expect(page.markerCount, 80);
    expect(page.markers, hasLength(24));
    final seen = <String>{};
    for (var offset = 0; offset < 80; offset += 24) {
      final next = await store.supportingLatest(
        SupportingLatestQuery(
          personId: meId,
          markerLimit: 24,
          markerOffset: offset,
        ),
      );
      expect(next.markerOffset, offset);
      expect(next.markers.length, lessThanOrEqualTo(24));
      for (final marker in next.markers) {
        expect(seen.add(marker.latest.result.metricId), isTrue);
      }
    }
    expect(seen, hasLength(80));
    expect(
      () => SupportingLatestQuery(personId: meId, markerLimit: 101),
      throwsA(isA<SupportingLimitException>()),
    );
    expect(
      () => SupportingLatestQuery(personId: meId, markerOffset: -1),
      throwsA(isA<SupportingLimitException>()),
    );

    final all = await _latest(store);
    expect(all.markerCount, 80);
    expect(all.values, hasLength(80));
    expect(all.hasMoreMarkers, isFalse);
    final oldest = all.values.singleWhere(
      (value) => value.metricId == 'metric-0',
    );
    expect(oldest.record.id.id, 'r00');
    expect(oldest.result.value.originalText, '0');
    expect(oldest.result.unit, 'mg/L');
  });

  test(
    'kind, item and event filters stay explicit and latest missing wins',
    () async {
      final item = await _item(store), event = await _event(store);
      await _savePanel(
        store,
        _panel(
          id: 'alpha-old',
          day: CivilDate(2026, 1, 1),
          results: [
            _result(
              'alpha-old-result',
              metric: 'alpha',
              name: 'Alpha',
              value: '1',
            ),
          ],
          provenance: _source(laboratoryId: 'lab-old'),
        ),
      );
      await _savePanel(
        store,
        _panel(
          id: 'alpha',
          day: CivilDate(2026, 1, 2),
          results: [
            _result(
              'alpha-result',
              metric: 'alpha',
              name: 'Alpha',
              value: '10',
            ),
          ],
          links: [
            SupportingContextLink(
              id: item.id,
              personId: meId,
              kind: SupportingContextKind.item,
            ),
          ],
        ),
      );
      await _savePanel(
        store,
        _panel(
          id: 'beta-old',
          day: CivilDate(2026, 1, 2),
          results: [
            _result(
              'beta-old-result',
              metric: 'beta',
              name: 'Beta',
              value: '5',
            ),
          ],
        ),
      );
      await _savePanel(
        store,
        _panel(
          id: 'beta',
          day: CivilDate(2026, 1, 3),
          results: [
            _result('beta-result', metric: 'beta', name: 'Beta', value: '20'),
          ],
          links: [
            SupportingContextLink(
              id: event.id,
              personId: meId,
              kind: SupportingContextKind.event,
            ),
          ],
        ),
      );
      await _saveObservation(
        store,
        id: 'gamma',
        day: CivilDate(2026, 1, 4),
        results: [
          _result(
            'gamma-result',
            metric: 'gamma',
            name: 'Gamma',
            value: '30',
            unit: 'bpm',
          ),
        ],
        links: [
          SupportingContextLink(
            id: item.id,
            personId: meId,
            kind: SupportingContextKind.item,
          ),
        ],
      );

      expect(
        (await _latest(
          store,
          kind: SupportingRecordKind.labPanel,
        )).values.map((v) => v.metricId),
        ['alpha', 'beta'],
      );
      expect(
        (await _latest(
          store,
          kind: SupportingRecordKind.observation,
        )).values.map((v) => v.metricId),
        ['gamma'],
      );
      expect(
        (await _latest(store, itemId: item.id)).values.map((v) => v.metricId),
        ['alpha', 'gamma'],
      );
      expect(
        (await _latest(store, eventId: event.id)).values.map((v) => v.metricId),
        ['beta'],
      );
      expect(
        (await _latest(
          store,
          fromDate: CivilDate(2026, 1, 3),
        )).values.map((v) => v.metricId),
        ['beta', 'gamma'],
      );
      expect(
        (await _latest(
          store,
          beforeDate: CivilDate(2026, 1, 2),
        )).values.map((v) => v.metricId),
        ['alpha'],
      );

      final beta = await _savePanel(
        store,
        _panel(
          id: 'beta',
          day: CivilDate(2026, 1, 3),
          results: [
            _result('beta-result', metric: 'beta', name: 'Beta', unit: null),
          ],
          links: [
            SupportingContextLink(
              id: event.id,
              personId: meId,
              kind: SupportingContextKind.event,
            ),
          ],
        ),
        expectedRevision: 1,
      );
      final missing = (await _latest(store)).values
          .singleWhere((value) => value.metricId == 'beta');
      expect(missing.result.value.kind, SupportingValueKind.missing);
      expect(missing.result.unit, isNull);
      expect(missing.previousResult, isNull);

      final corrected = await _savePanel(
        store,
        _panel(
          id: 'beta',
          day: CivilDate(2026, 1, 3),
          results: [
            _result('beta-result', metric: 'beta', name: 'Beta', value: '25'),
          ],
          links: [
            SupportingContextLink(
              id: event.id,
              personId: meId,
              kind: SupportingContextKind.event,
            ),
          ],
        ),
        expectedRevision: beta.revision,
      );
      expect(
        (await _latest(store)).values
            .singleWhere((value) => value.metricId == 'beta')
            .result
            .value
            .originalText,
        '25',
      );

      final person = (await store.profileById(meId))!;
      await store.voidSupportingRecord(
        VoidSupportingRecordCommand(
          commandId: 'void-beta',
          generation: store.generation,
          personId: meId,
          id: corrected.id.id,
          expectedPersonRevision: person.revision,
          expectedRevision: corrected.revision,
        ),
      );
      final afterVoid = (await _latest(store)).values
          .singleWhere((value) => value.metricId == 'beta');
      expect(afterVoid.result.value.originalText, '5');
      expect(afterVoid.record.id.id, 'beta-old');
    },
  );

  test(
    'comparison keeps exact source identity and breaks the sparkline',
    () async {
      await _savePanel(
        store,
        _panel(
          id: 'old',
          day: CivilDate(2026, 1, 1),
          results: [
            _result('old-result', metric: 'crp', name: 'hs-CRP', value: '0.55'),
          ],
        ),
      );
      await _savePanel(
        store,
        _panel(
          id: 'other-lab',
          day: CivilDate(2026, 1, 2),
          results: [
            _result(
              'other-result',
              metric: 'crp',
              name: 'hs-CRP',
              value: '0.50',
            ),
          ],
          provenance: _source(laboratoryId: 'lab-b'),
        ),
      );
      await _savePanel(
        store,
        _panel(
          id: 'qualified',
          day: CivilDate(2026, 1, 3),
          results: [
            _result(
              'qualified-result',
              metric: 'crp',
              name: 'hs-CRP',
              value: '<0.45',
            ),
          ],
        ),
      );
      await _savePanel(
        store,
        _panel(
          id: 'new',
          day: CivilDate(2026, 1, 4),
          results: [
            _result('new-result', metric: 'crp', name: 'hs-CRP', value: '0.45'),
          ],
        ),
      );

      final value = (await _latest(store)).values.single;
      expect(value.record.id.id, 'new');
      expect(value.result.unit, 'mg/L');
      expect(value.record.snapshot.provenance.laboratoryId, 'lab-a');
      expect(value.previousRecord?.id.id, 'old');
      expect(value.previousResult?.value.originalText, '0.55');
      expect(value.sparkline!.segments.map((segment) => segment.length), [
        1,
        1,
      ]);
    },
  );

  test(
    'live latest values refresh, lock and follow a restored generation',
    () async {
      final first = _panel(
        id: 'first',
        day: CivilDate(2026, 2, 1),
        results: [
          _result(
            'first-result',
            metric: 'marker-a',
            name: 'Marker A',
            value: '10',
          ),
        ],
      );
      await _savePanel(store, first);
      var active = store;
      final container = ProviderContainer(
        overrides: [
          storeLoaderProvider.overrideWithValue(() => Future.value(active)),
          appLockProvider.overrideWith(_TestLock.new),
        ],
      );
      addTearDown(container.dispose);
      final request = _request();
      final provider = screenLabsLatestProvider(request);
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(recordStoreProvider.future);

      var latest = await _waitFor(
        container,
        provider,
        (value) => value.values.any((row) => row.metricId == 'marker-a'),
      );
      expect(latest.values.single.result.value.originalText, '10');

      await _savePanel(
        store,
        _panel(
          id: 'second',
          day: CivilDate(2026, 2, 2),
          results: [
            _result(
              'second-result',
              metric: 'marker-a',
              name: 'Marker A',
              value: '20',
            ),
          ],
        ),
      );
      latest = await _waitFor(
        container,
        provider,
        (value) =>
            value.values
                .singleWhere((row) => row.metricId == 'marker-a')
                .result
                .value
                .originalText ==
            '20',
      );
      expect(latest.values.single.record.id.id, 'second');

      final second = await store.supportingRecord(meId, 'second');
      final person = (await store.profileById(meId))!;
      await store.voidSupportingRecord(
        VoidSupportingRecordCommand(
          commandId: 'void-second',
          generation: store.generation,
          personId: meId,
          id: 'second',
          expectedPersonRevision: person.revision,
          expectedRevision: second!.revision,
        ),
      );
      latest = await _waitFor(
        container,
        provider,
        (value) =>
            value.values
                .singleWhere((row) => row.metricId == 'marker-a')
                .result
                .value
                .originalText ==
            '10',
      );
      expect(latest.values.single.record.id.id, 'first');

      (container.read(appLockProvider.notifier) as _TestLock).lockNow();
      await _waitFor(container, provider, (value) => value.values.isEmpty);
      (container.read(appLockProvider.notifier) as _TestLock).unlockNow();
      await _waitFor(
        container,
        provider,
        (value) => value.values.any((row) => row.metricId == 'marker-a'),
      );

      final restoredDirectory = await Directory.systemTemp.createTemp(
        'vital-latest-restored-',
      );
      addTearDown(() => restoredDirectory.delete(recursive: true));
      final restored = await RecordStore.open(
        path: '${restoredDirectory.path}/records.db',
        key: List.generate(32, (index) => index + 2),
        isNew: true,
      );
      await _savePanel(
        restored,
        _panel(
          id: 'restored',
          day: CivilDate(2026, 3, 1),
          results: [
            _result(
              'restored-result',
              metric: 'marker-b',
              name: 'Marker B',
              value: '99',
            ),
          ],
        ),
      );
      active = restored;
      container.invalidate(recordStoreProvider);
      await container.read(recordStoreProvider.future);
      await _waitFor(
        container,
        provider,
        (value) => value.values.any((row) => row.metricId == 'marker-b'),
      );
      expect(
        container.read(provider).value!.values.single.result.value.originalText,
        '99',
      );
    },
  );
}
