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
  const password = 'synthetic correct horse';

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
    'encrypted restore keeps dose context, revisions and skip reasons',
    () async {
      // Real production container path: create, validate, prepare and activate.
      final item = await live.createItem(
        commandId: 'item',
        expectedPersonRevision: 2,
        name: 'Synthetic restore item',
        form: 'tablet',
        unit: 'mg',
        type: 'medicine',
      );
      final recorded = await live.record(
        commandId: 'record',
        itemId: item.id,
        amount: '1',
        actualAt: DateTime.utc(2026, 10, 20, 8),
        expectedPersonRevision: 2,
        context: const DoseContext(
          notes: 'Saved dose note.',
          contextTags: ['Morning', 'With food'],
        ),
      );
      final corrected = await live.correct(
        commandId: 'correct',
        recordId: recorded.id,
        expectedRevision: recorded.revision,
        amount: '1.5',
        actualAt: recorded.actualAt,
        expectedPersonRevision: 2,
      );
      final date = CivilDate(2026, 10, 20);
      await live.saveDailyPlan(
        commandId: 'plan',
        plan: DailyPlanVersion(
          personId: meId,
          planId: 'plan',
          itemId: item.id,
          versionId: 'v1',
          start: date,
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
        expectedPersonRevision: 2,
        expectedGeneration: live.generation,
      );
      final planRow = (await live.dailyRows(
        from: date,
        toExclusive: date.addDays(1),
        observedZone: 'UTC',
      )).rows.single;
      final skipped = await live.actDaily(
        commandId: 'skip',
        row: planRow,
        kind: DailyActionKind.skip,
        skipReason: 'Felt unwell',
      );
      final event = EventRecord(
        id: 'context-event',
        personId: meId,
        name: 'Context event',
        eventType: 'cycle',
        zoneId: 'UTC',
        revision: 1,
        plannedStart: EventDate.day(date),
        plannedEnd: EventDate.day(date),
        notes: 'Private event wording: 0.125 mg.',
        memberships: [
          EventMembership(
            id: 'context-member',
            itemId: item.id,
            personId: meId,
            effectiveFrom: DateTime.utc(2026, 10, 20),
            revision: 1,
          ),
        ],
      );
      final eventCommand = SaveEventCommand(
        commandId: 'event-save',
        generation: live.generation,
        expectedRevision: null,
        expectedPersonRevision: 2,
        event: event,
      );
      await live.saveEvent(
        eventCommand,
        membershipReview: await live.previewEventMembership(eventCommand),
      );

      final service = BackupService(
        recordStore: live,
        stagingDirectory: Directory('${directory.path}/data/backup-staging'),
        destination: const UnsupportedBackupDestination(),
        clock: () => DateTime.utc(2026, 10, 20, 12),
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
      final restored = (await live.recordById(corrected.id))!;
      expect((await live.eventById(event.id))!.notes, event.notes);
      expect((await live.eventHistory(event.id)).single.notes, event.notes);
      final eventSummary = (await live.eventUseSummary(event.id))!;
      expect(eventSummary.recorded, 1);
      expect(eventSummary.skipped, 1);
      expect(restored.notes, 'Saved dose note.');
      expect(restored.contextTags, ['Morning', 'With food']);
      final history = await live.history(corrected.id);
      expect(history.map((revision) => revision.revision), [1, 2]);
      expect(history.map((revision) => revision.notes), [
        'Saved dose note.',
        'Saved dose note.',
      ]);
      expect(history.map((revision) => revision.contextTags), [
        ['Morning', 'With food'],
        ['Morning', 'With food'],
      ]);
      final restoredRow = (await live.dailyRows(
        from: date,
        toExclusive: date.addDays(1),
        observedZone: 'UTC',
      )).rows.single;
      expect(restoredRow.actions.single.id, skipped.id);
      expect(restoredRow.actions.single.reason, 'Felt unwell');

      ExportSelection export({required bool includeNotes}) => ExportSelection(
        personId: meId,
        fromDay: date,
        beforeDay: date.addDays(1),
        zoneId: 'UTC',
        contents: const [ExportContent.doses],
        format: ExportFormat.json,
        includeNotes: includeNotes,
      );
      final private = await live.captureExport(export(includeNotes: false));
      expect(private.skipped.single.actionId, skipped.id);
      expect(private.skipped.single.reason, isNull);
      expect(private.doses, hasLength(2));
      expect(private.doses.map((r) => r.revision), [1, 2]);
      expect(
        private.doses.map((r) => r.contextTags),
        everyElement(orderedEquals(['Morning', 'With food'])),
      );
      expect(private.doses.map((r) => r.notes), everyElement(isNull));
      final privateText = utf8.decode(ExportArtifact.build(private).bytes);
      expect(privateText, isNot(contains('Saved dose note.')));
      expect(privateText, isNot(contains('Felt unwell')));
      expect(privateText, isNot(contains(event.notes)));
      expect(privateText, contains('Morning'));

      final shared = await live.captureExport(export(includeNotes: true));
      expect(shared.skipped.single.reason, 'Felt unwell');
      expect(
        shared.doses.map((r) => r.notes),
        everyElement('Saved dose note.'),
      );
    },
  );
}
