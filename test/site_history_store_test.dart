import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  late Directory dir;
  late RecordStore store;
  final key = List.generate(32, (i) => i + 1);
  final start = DateTime.utc(2026, 10, 1, 9);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vital-site-history-');
    store = await RecordStore.open(
      path: '${dir.path}/site-history.db',
      key: key,
      isNew: true,
    );
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  Future<int> personRevision() async =>
      (await store.profileById(meId))!.revision;

  Future<SubstanceItem> item() async => store.createItem(
    commandId: newCommandId(),
    expectedPersonRevision: await personRevision(),
    name: 'Synthetic site item',
    form: 'liquid',
    unit: 'ml',
    type: 'Medicine',
  );

  Future<UseRecord> record(
    SubstanceItem item,
    DateTime at, {
    String? site,
  }) async => store.record(
    commandId: newCommandId(),
    itemId: item.id,
    amount: '1',
    actualAt: at,
    siteLabel: site,
    expectedPersonRevision: await personRevision(),
  );

  Future<void> editSite(UseRecord record, String? site) async =>
      store.updateSite(
        commandId: newCommandId(),
        personId: meId,
        expectedPersonRevision: await personRevision(),
        expectedGeneration: store.generation,
        recordId: record.id,
        expectedRevision: record.revision,
        siteLabel: site,
      );

  test(
    'saved site history keeps latest labels, audit and dose order',
    () async {
      final source = await item();
      final first = await record(source, start, site: '  Left abdomen  ');
      final second = await record(
        source,
        start.add(const Duration(hours: 1)),
        site: 'Right thigh',
      );
      final third = await record(
        source,
        start.add(const Duration(hours: 2)),
        site: 'Left arm',
      );

      await editSite(first, 'Left thigh');

      var rows = await store.savedSiteHistory(personId: meId);
      expect(rows.map((row) => row.siteLabel), [
        'Left arm',
        'Right thigh',
        'Left thigh',
      ]);
      expect(rows.map((row) => row.recordId), [third.id, second.id, first.id]);
      expect(rows.map((row) => row.actualAt), [
        start.add(const Duration(hours: 2)),
        start.add(const Duration(hours: 1)),
        start,
      ]);
      final edited = rows.singleWhere((row) => row.recordId == first.id);
      expect(edited.earlierSiteLabel, '  Left abdomen  ');
      expect(edited.revision, 1, reason: 'a site edit is not a dose revision');
      expect(edited.isVoided, isFalse);
      expect(edited.itemName, 'Synthetic site item');

      // The distinct-label choices remain a separate, undated query.
      expect(await store.siteHistory(personId: meId), [
        'Left thigh',
        'Left arm',
        'Right thigh',
        '  Left abdomen  ',
      ]);
    },
  );

  test(
    'dose corrections and voids stay explicit without changing sites',
    () async {
      final source = await item();
      final corrected = await record(source, start, site: 'Left arm');
      final voided = await record(
        source,
        start.add(const Duration(hours: 1)),
        site: 'Right thigh',
      );
      await store.correct(
        commandId: newCommandId(),
        recordId: corrected.id,
        expectedRevision: corrected.revision,
        amount: '2',
        actualAt: start,
        expectedPersonRevision: await personRevision(),
      );
      await store.voidRecord(
        commandId: newCommandId(),
        recordId: voided.id,
        expectedRevision: voided.revision,
        expectedPersonRevision: await personRevision(),
      );

      final rows = await store.savedSiteHistory(personId: meId);
      final current = rows.singleWhere((row) => row.recordId == corrected.id);
      expect(current.revision, 2);
      expect(current.isVoided, isFalse);
      expect(current.siteLabel, 'Left arm');
      final removed = rows.singleWhere((row) => row.recordId == voided.id);
      expect(removed.revision, 2, reason: 'voiding creates a revision');
      expect(removed.isVoided, isTrue);
      expect(removed.siteLabel, 'Right thigh');
      expect(removed.earlierSiteLabel, isNull);
    },
  );

  test(
    'cleared sites leave history but retain the label choice audit',
    () async {
      final source = await item();
      final cleared = await record(source, start, site: 'Left arm');
      await editSite(cleared, 'Right thigh');
      await editSite(cleared, null);

      expect(await store.savedSiteHistory(personId: meId), isEmpty);
      expect(await store.siteHistory(personId: meId), [
        'Right thigh',
        'Left arm',
      ]);
    },
  );

  test(
    'combined components keep the canonical combined source identity',
    () async {
      final source = await item();
      final group = await store.recordCombined(
        CombinedUseCommand(
          commandId: newCommandId(),
          personId: meId,
          expectedGeneration: store.generation,
          expectedPersonRevision: await personRevision(),
          actualAt: start,
          components: [
            CombinedUseComponent(
              itemId: source.id,
              expectedItemRevision: source.revision,
              enteredAmount: '0.5',
              siteLabel: 'Left arm',
            ),
            CombinedUseComponent(
              itemId: source.id,
              expectedItemRevision: source.revision,
              enteredAmount: '0.5',
            ),
          ],
        ),
      );

      final rows = await store.savedSiteHistory(personId: meId);
      expect(rows, hasLength(1));
      expect(rows.single.recordId, group.records.first.id);
      expect(rows.single.combinedActionId, group.actionId);
      expect(rows.single.sourceKind, TimelineEntryKind.combined);
      expect(rows.single.sourceId, group.actionId);
      expect(rows.single.siteLabel, 'Left arm');
    },
  );

  test('stale site revisions reject without changing saved history', () async {
    final source = await item();
    final saved = await record(source, start, site: 'Left arm');

    await expectLater(
      store.updateSite(
        commandId: newCommandId(),
        personId: meId,
        expectedPersonRevision: await personRevision(),
        expectedGeneration: store.generation,
        recordId: saved.id,
        expectedRevision: saved.revision + 1,
        siteLabel: 'Right thigh',
      ),
      throwsA(isA<CommandConflict>()),
    );

    final rows = await store.savedSiteHistory(personId: meId);
    expect(rows.single.siteLabel, 'Left arm');
    expect(rows.single.revision, saved.revision);
    expect(rows.single.earlierSiteLabel, isNull);
  });

  test('paging is stable, bounded and ordered by saved actual time', () async {
    final source = await item();
    final created = <UseRecord>[];
    for (var index = 0; index < 25; index++) {
      created.add(
        await record(
          source,
          start.add(Duration(hours: index)),
          site: 'Site ${index + 1}',
        ),
      );
    }
    final firstPage = await store.savedSiteHistory(personId: meId, limit: 21);
    expect(firstPage, hasLength(21));
    expect(firstPage.first.siteLabel, 'Site 25');
    expect(firstPage.last.siteLabel, 'Site 5');
    final secondPage = await store.savedSiteHistory(
      personId: meId,
      limit: 21,
      offset: 20,
    );
    expect(secondPage, hasLength(5));
    expect(secondPage.first.siteLabel, 'Site 5');
    expect(secondPage.last.siteLabel, 'Site 1');
    expect(secondPage.first.recordId, created[4].id);

    final tieA = await record(
      source,
      start.add(const Duration(days: 2)),
      site: 'Tie A',
    );
    final tieB = await record(
      source,
      start.add(const Duration(days: 2)),
      site: 'Tie B',
    );
    final ties = (await store.savedSiteHistory(
      personId: meId,
      limit: 2,
    )).map((row) => row.recordId).toList();
    expect(ties.toSet(), {tieA.id, tieB.id});
    expect(ties, [...ties]..sort((a, b) => b.compareTo(a)));

    expect(
      () => store.savedSiteHistory(personId: meId, limit: 0),
      throwsA(isA<RangeError>()),
    );
    expect(
      () => store.savedSiteHistory(personId: meId, limit: 501),
      throwsA(isA<RangeError>()),
    );
    expect(
      () => store.savedSiteHistory(personId: meId, offset: -1),
      throwsA(isA<RangeError>()),
    );
  });
}
