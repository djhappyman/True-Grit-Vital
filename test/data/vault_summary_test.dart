import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/reports/report_period.dart';

import '../attachments/attachment_controller_test.dart' show seedFile;

void main() {
  late Directory directory;
  late RecordStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-vault-counts-');
    store = await RecordStore.open(
      path: '${directory.path}/records.db',
      key: List.generate(32, (i) => i + 1),
      isNew: true,
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  Future<SubstanceItem> item() => store.createItem(
    commandId: newCommandId(),
    expectedPersonRevision: 1,
    name: 'Full synthetic substance',
    form: 'Tablet',
    unit: 'mg',
    type: 'Medicine',
  );

  test(
    'empty vault counts are genuine zero and size measures the database',
    () async {
      final result = await store.vaultSummary();
      expect(
        [
          result.substances,
          result.doses,
          result.files,
          result.supportingRecords,
        ],
        [0, 0, 0, 0],
      );
      expect(result.generation, store.generation);
      expect(
        result.databaseBytes,
        greaterThanOrEqualTo(await File(store.databasePath).length()),
      );
      expect(result.databaseBytes, greaterThan(0));
    },
  );

  test('counts cover the whole collection and count current records, not revisions', () async {
    final substance = await item();
    late UseRecord first;
    for (var i = 0; i < 55; i++) {
      final record = await store.record(
        commandId: newCommandId(),
        itemId: substance.id,
        amount: '1',
        actualAt: DateTime.utc(2026, 10, 1, 12, i),
        expectedPersonRevision: 1,
      );
      if (i == 0) first = record;
    }
    final corrected = await store.correct(
      commandId: newCommandId(),
      recordId: first.id,
      expectedRevision: first.revision,
      personId: meId,
      expectedPersonRevision: 1,
      amount: '2',
        actualAt: first.actualAt,
    );
    expect((await store.vaultSummary()).doses, 55);
    await store.voidRecord(
      commandId: newCommandId(),
      recordId: corrected.id,
      expectedRevision: corrected.revision,
      personId: meId,
      expectedPersonRevision: 1,
    );
    final result = await store.vaultSummary();
    expect(result.substances, 1);
    expect(result.doses, 54);
    expect(await store.history(first.id), hasLength(3));
  });

  test('file count follows ready files and drops after deletion', () async {
    final substance = await item();
    final file = await seedFile(
      store,
      substance,
      Uint8List.fromList([1, 2, 3]),
    );
    expect((await store.vaultSummary()).files, 1);
    await store.deleteAttachment(
      commandId: newCommandId(),
      attachment: file,
      expectedPersonRevision: 1,
    );
    expect((await store.vaultSummary()).files, 0);
  });

  test('watch updates on a committed item and stops cleanly', () async {
    final values = <VaultSummary>[];
    final subscription = store.watchVaultSummary().listen(values.add);
    final loaded = Stopwatch()..start();
    while (values.isEmpty && loaded.elapsed.inSeconds < 10) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(values.single.substances, 0);
    await item();
    while (values.last.substances != 1 && loaded.elapsed.inSeconds < 10) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(values.last.substances, 1);
    await subscription.cancel();
  });

  test('locked store does not expose a fresh vault read', () async {
    store.suspendWrites(true);
    await expectLater(store.vaultSummary(), throwsA(isA<CommandConflict>()));
    store.suspendWrites(false);
  });

  test('report shortcuts retain inclusive civil days across leap and year boundaries', () {
    final leap = reportPeriodDates(
      CivilDate(2024, 3, 1),
      ReportPeriod.thirtyDays,
    );
    expect(leap.from, CivilDate(2024, 2, 1));
    expect(leap.before, CivilDate(2024, 3, 2));
    final ninety = reportPeriodDates(
      CivilDate(2026, 1, 1),
      ReportPeriod.ninetyDays,
    );
    expect(ninety.from, CivilDate(2025, 10, 4));
    expect(ninety.before, CivilDate(2026, 1, 2));
    final year = reportPeriodDates(CivilDate(2026, 1, 1), ReportPeriod.year);
    expect(year.from, CivilDate(2026, 1, 1));
    expect(year.before, CivilDate(2026, 1, 2));
  });
}
