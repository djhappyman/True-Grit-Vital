import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';

class _Cancel implements ReportCancellation {
  @override
  bool get isCancelled => true;
}

Future<RecordStore> _open(Directory directory) => RecordStore.open(
  path: '${directory.path}/report.db',
  key: List.generate(32, (index) => index + 1),
  isNew: true,
);

Future<SubstanceItem> _item(
  RecordStore store, {
  required String command,
  required String name,
  required String type,
  required String unit,
}) async {
  final profile = (await store.profileById(meId))!;
  return store.createItem(
    commandId: command,
    name: name,
    form: 'Tablet',
    unit: unit,
    type: type,
    expectedPersonRevision: profile.revision,
  );
}

Future<UseRecord> _record(
  RecordStore store, {
  required String command,
  required SubstanceItem item,
  required String amount,
  required DateTime at,
}) async {
  final profile = (await store.profileById(meId))!;
  return store.record(
    commandId: command,
    itemId: item.id,
    amount: amount,
    actualAt: at,
    expectedPersonRevision: profile.revision,
  );
}

void main() {
  late Directory directory;
  late RecordStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-report-data-');
    store = await _open(directory);
    final me = (await store.profileById(meId))!;
    await store.editProfile(
      commandId: 'profile',
      personId: meId,
      expectedRevision: me.revision,
      name: 'Synthetic Person',
      adultConfirmed: true,
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  ReportSelection selection({Set<String> items = const {}}) => ReportSelection(
    personId: meId,
    fromDate: CivilDate(2026, 10, 1),
    beforeDate: CivilDate(2026, 11, 1),
    displayZone: 'UTC',
    includeAttachments: true,
    itemIds: items,
  );

  test(
    'capture is a coherent cutoff with exact totals and item scope',
    () async {
      final first = await _item(
        store,
        command: 'item-one',
        name: 'First item',
        type: 'Medicine',
        unit: 'mg',
      );
      final second = await _item(
        store,
        command: 'item-two',
        name: 'Second item',
        type: 'Supplement',
        unit: 'count',
      );
      final insideOne = await _record(
        store,
        command: 'record-one',
        item: first,
        amount: '0.125',
        at: DateTime.utc(2026, 10, 5, 9),
      );
      await _record(
        store,
        command: 'record-two',
        item: first,
        amount: '0.375',
        at: DateTime.utc(2026, 10, 6, 9),
      );
      await _record(
        store,
        command: 'record-three',
        item: second,
        amount: '2',
        at: DateTime.utc(2026, 10, 7, 9),
      );
      await _record(
        store,
        command: 'outside',
        item: second,
        amount: '9',
        at: DateTime.utc(2026, 11, 5, 9),
      );
      final profile = (await store.profileById(meId))!;
      await store.voidRecord(
        commandId: 'void-inside',
        recordId: insideOne.id,
        expectedRevision: insideOne.revision,
        expectedPersonRevision: profile.revision,
      );

      final now = DateTime.utc(2026, 10, 20, 12);
      final capture = await store.captureReport(
        selection: selection(),
        now: () => now,
      );
      final snapshot = capture.snapshot;
      expect(capture.pins, isEmpty);
      expect(snapshot.records.length, 2);
      expect(snapshot.records.map((record) => record.amount), [
        ExactAmount.parseEntry('0.375'),
        ExactAmount.parseEntry('2'),
      ]);
      expect(snapshot.cutoff.generatedAt, now);
      expect(snapshot.cutoff.datasetGeneration, store.generation);
      expect(snapshot.person.name, 'Synthetic Person');
      expect(snapshot.totals.recordCount, 2);
      expect(snapshot.totals.groups.map((group) => group.type), [
        'Medicine',
        'Supplement',
      ]);
      expect(
        snapshot.totals.groups
            .singleWhere((group) => group.type == 'Medicine')
            .items
            .single
            .total,
        ExactAmount.parseEntry('0.375'),
      );

      await _record(
        store,
        command: 'record-later',
        item: second,
        amount: '3',
        at: DateTime.utc(2026, 10, 8, 9),
      );
      expect(snapshot.records.length, 2);
      final later = await store.captureReport(
        selection: selection(),
        now: () => now,
      );
      expect(later.snapshot.records.length, 3);

      final scoped = await store.captureReport(
        selection: selection(items: {first.id}),
        now: () => now,
      );
      expect(scoped.snapshot.records.length, 1);
      expect(scoped.snapshot.records.single.itemId, first.id);
    },
  );

  test(
    'source limits, cancellation and archived adults fail truthfully',
    () async {
      final item = await _item(
        store,
        command: 'item-limit',
        name: 'Limit item',
        type: 'Medicine',
        unit: 'mg',
      );
      await _record(
        store,
        command: 'limit-one',
        item: item,
        amount: '1',
        at: DateTime.utc(2026, 10, 5, 9),
      );
      await _record(
        store,
        command: 'limit-two',
        item: item,
        amount: '1',
        at: DateTime.utc(2026, 10, 6, 9),
      );
      await expectLater(
        store.captureReport(
          selection: selection(),
          now: () => DateTime.utc(2026, 10, 20),
          maxRecords: 1,
        ),
        throwsA(
          isA<ReportSelectionFailure>().having(
            (error) => error.code,
            'code',
            'report_source_limit',
          ),
        ),
      );
      await expectLater(
        store.captureReport(
          selection: selection(),
          now: () => DateTime.utc(2026, 10, 20),
          cancellation: _Cancel(),
        ),
        throwsA(isA<ReportCancelled>()),
      );
      final other = await store.createProfile(
        commandId: 'other-adult',
        name: 'Other adult',
        adultConfirmed: true,
      );
      await store.archiveProfile(
        commandId: 'archive',
        personId: other.id,
        expectedRevision: other.revision,
      );
      await expectLater(
        store.captureReport(
          selection: ReportSelection(
            personId: other.id,
            fromDate: CivilDate(2026, 10, 1),
            beforeDate: CivilDate(2026, 11, 1),
            displayZone: 'UTC',
          ),
          now: () => DateTime.utc(2026, 10, 20),
        ),
        throwsA(
          isA<ReportSelectionFailure>().having(
            (error) => error.code,
            'code',
            'report_person_archived',
          ),
        ),
      );
    },
  );

  test('a different person cannot use another owner snapshot', () async {
    await expectLater(
      store.captureReport(
        selection: ReportSelection(
          personId: 'someone-else',
          fromDate: CivilDate(2026, 10, 1),
          beforeDate: CivilDate(2026, 11, 1),
          displayZone: 'UTC',
        ),
        now: () => DateTime.utc(2026, 10, 20),
      ),
      throwsA(
        isA<ReportSelectionFailure>().having(
          (error) => error.code,
          'code',
          'report_person_missing',
        ),
      ),
    );
  });
}
