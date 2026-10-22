import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/backup/backup_service.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/backup/backup.dart';
import 'package:true_grit_vital/domain/exports/exports.dart';
import 'package:true_grit_vital/restore/restore_activation.dart';

import 'fixtures/restore_fixture.dart';

void main() {
  late Directory directory;
  late RecordStore live;
  late String livePath;
  const password = 'synthetic protected stock facts';

  setUp(() async {
    directory = await createRestoreDataDirectory();
    livePath = '${directory.path}/data/records.sqlite';
    live = await RecordStore.open(
      path: livePath,
      key: restoreTestKey,
      isNew: true,
    );
    await live.editProfile(
      commandId: 'profile',
      personId: meId,
      expectedRevision: 1,
      name: 'Alex',
      adultConfirmed: true,
    );
  });

  tearDown(() async {
    try {
      await live.close();
    } catch (_) {
      // Already closed by activation.
    }
    await directory.delete(recursive: true);
  });

  test(
    'encrypted restore keeps exact lot expiry capacity and history',
    () async {
      final item = await live.createItem(
        commandId: 'item',
        expectedPersonRevision: 2,
        name: 'Synthetic protected vial',
        profile: SubstanceProfile(
          route: SubstanceRoute.injectable,
          form: SubstanceForm.powderToMix,
          halfLife: HalfLife(
            value: '12',
            unit: 'hours',
            context: 'Specific ingredient and formulation',
            source: 'Entered label',
          ),
        ),
        form: 'liquid',
        unit: 'ml',
        type: 'medicine',
      );
      var container = await live.createStockContainer(
        commandId: 'container',
        personId: meId,
        expectedPersonRevision: 2,
        expectedGeneration: live.generation,
        itemId: item.id,
        label: 'Amber vial',
        unit: 'ml',
        strength: LabelledStrength(
          ingredientId: item.id,
          label: '10 mg/ml',
          mgPerMl: ExactAmount(BigInt.from(10)),
          preparation: VialPreparation(
            powderAmount: '120',
            massUnit: 'mg',
            finalVolumeMl: '12',
            liquid: 'Entered mixing liquid',
            addedVolumeMl: '11.8',
            preparedOn: '2026-10-22',
          ),
        ),
        opening: ExactAmount(BigInt.from(6)),
        lot: 'LOT-RESTORE',
        expiryDate: CivilDate(2027, 5, 6),
        capacity: ExactAmount(BigInt.from(10)),
      );
      final recorded = await live.record(
        commandId: 'dose',
        itemId: item.id,
        amount: '1',
        actualAt: DateTime.utc(2026, 10, 22, 8),
        expectedPersonRevision: 2,
        stockUse: StockUseInput(
          expectedGeneration: live.generation,
          containerId: container.id,
          expectedContainerRevision: container.revision,
          entered: EnteredStockAmount('1', 'ml'),
        ),
      );
      container = (await live.stockContainerById(
        personId: meId,
        containerId: container.id,
      ))!;
      await live.updateStockMetadata(
        commandId: 'details',
        personId: meId,
        expectedPersonRevision: 2,
        expectedGeneration: live.generation,
        containerId: container.id,
        expectedContainerRevision: container.revision,
        lot: 'LOT-RESTORE-2',
        expiryDate: CivilDate(2027, 5, 7),
        capacity: ExactAmount(BigInt.from(12)),
      );

      final service = BackupService(
        recordStore: live,
        stagingDirectory: Directory('${directory.path}/data/backup-staging'),
        destination: const UnsupportedBackupDestination(),
        clock: () => DateTime.utc(2026, 10, 22, 12),
      );
      final creation = await service.createBackup(
        password: password,
        token: BackupCancellationToken(),
      );
      final staged = await service.validateArchive(
        archive: creation.archive,
        password: password,
        token: BackupCancellationToken(),
      );
      expect(staged.schemaVersion, currentRecordSchemaVersion);
      final prepared = await live.prepareRestoredDatabase(
        stagedPath: staged.databasePath,
        rekeyTo: staged.rekey,
      );
      final activation = RestoreActivation(databasePath: live.databasePath);
      await activation.activate(
        preparedPath: prepared.path,
        previousGeneration: prepared.previousGeneration,
        newGeneration: prepared.generation,
        previousNamespace: prepared.previousNamespace ?? '',
        reminderNamespace: prepared.reminderNamespace,
        key: restoreTestKey,
        closeLive: live.close,
      );

      live = await RecordStore.open(
        path: livePath,
        key: restoreTestKey,
        isNew: false,
      );
      final restored = (await live.stockContainerById(
        personId: meId,
        containerId: container.id,
      ))!;
      expect(restored.strength.preparation!.addedVolumeMl, '11.8');
      expect(
        (await live.itemDetail(item.id))!.profile!.halfLife!.source,
        'Entered label',
      );
      expect(restored.lot, 'LOT-RESTORE-2');
      expect(restored.expiryDate, CivilDate(2027, 5, 7));
      expect(restored.capacity, ExactAmount(BigInt.from(12)));
      expect(restored.balance.value, ExactAmount(BigInt.from(5)));
      final history = await live.stockMetadataHistory(
        personId: meId,
        containerId: container.id,
      );
      expect(history.map((row) => row.lot), ['LOT-RESTORE-2', 'LOT-RESTORE']);
      final movement = await live.stockUseForRecord(
        personId: meId,
        recordId: recorded.id,
      );
      expect(movement!.strength.label, '10 mg/ml');
      expect(movement.strength.preparation!.finalVolumeMl, '12');

      final selection = ExportSelection(
        personId: meId,
        fromDay: CivilDate(2026, 10, 22),
        beforeDay: CivilDate(2026, 10, 23),
        zoneId: 'UTC',
        contents: const [ExportContent.doses],
        format: ExportFormat.json,
      );
      final document = await live.captureExport(selection);
      expect(document.doses.single.stockSource!.lot, 'LOT-RESTORE-2');
      expect(
        document.doses.single.stockSource!.capacity,
        ExactAmount(BigInt.from(12)),
      );
      final text = utf8.decode(ExportArtifact.build(document).bytes);
      expect(text, contains('LOT-RESTORE-2'));
      expect(text, contains('finalVolumeMl'));
      expect(text, contains('11.8'));
    },
  );
}
