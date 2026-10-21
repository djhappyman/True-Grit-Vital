import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/exports/exports.dart';

void main() {
  group('dose context normalisation', () {
    test('trims, drops blanks and dedupes tags without inferring values', () {
      final context = normaliseDoseContext(
        const DoseContext(
          notes: '  Taken with breakfast.  ',
          contextTags: ['Morning', ' morning ', '', 'With food'],
        ),
      );
      expect(context.notes, 'Taken with breakfast.');
      expect(context.contextTags, ['Morning', 'With food']);
      expect(normaliseDoseNote('   '), isNull);
      expect(normaliseDoseContextTags(['with food', 'WITH FOOD']), [
        'with food',
      ]);
    });

    test('bounds notes, tag count and tag length', () {
      expect(
        () => normaliseDoseNote('x' * (maxDoseNoteLength + 1)),
        throwsArgumentError,
      );
      expect(
        () => normaliseDoseContextTags([
          for (var i = 0; i <= maxDoseContextTags; i++) 'tag$i',
        ]),
        throwsArgumentError,
      );
      expect(
        () => normaliseDoseContextTags(['x' * (maxDoseContextTagLength + 1)]),
        throwsArgumentError,
      );
      expect(
        () => normaliseSkipReason('x' * (maxSkipReasonLength + 1)),
        throwsArgumentError,
      );
    });
  });

  group('dose context persistence', () {
    late Directory directory;
    late RecordStore store;
    late SubstanceItem item;
    final key = List.generate(32, (i) => i + 3);

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('vital-context-');
      store = await RecordStore.open(
        path: '${directory.path}/records.db',
        key: key,
        isNew: true,
      );
      item = await store.createItem(
        commandId: 'item',
        name: 'Synthetic context item',
        form: 'tablet',
        unit: 'mg',
        type: 'medicine',
      );
    });

    tearDown(() async {
      await store.close();
      await directory.delete(recursive: true);
    });

    Future<UseRecord> record(
      String command, {
      DoseContext context = DoseContext.empty,
    }) => store.record(
      commandId: command,
      itemId: item.id,
      amount: '1',
      actualAt: DateTime.utc(2026, 10, 20, 8),
      context: context,
    );

    test(
      'record, default correction and clear are separate revisions',
      () async {
        final first = await record(
          'take',
          context: const DoseContext(
            notes: '  Taken with breakfast.  ',
            contextTags: ['Morning', 'morning', 'With food'],
          ),
        );
        expect(first.notes, 'Taken with breakfast.');
        expect(first.contextTags, ['Morning', 'With food']);

        final retained = await store.correct(
          commandId: 'correct-amount',
          recordId: first.id,
          expectedRevision: first.revision,
          amount: '2',
          actualAt: first.actualAt,
        );
        expect(retained.notes, 'Taken with breakfast.');
        expect(retained.contextTags, ['Morning', 'With food']);

        final cleared = await store.correct(
          commandId: 'clear-context',
          recordId: first.id,
          expectedRevision: retained.revision,
          amount: null,
          actualAt: first.actualAt,
          context: const DoseContext(),
        );
        expect(cleared.notes, isNull);
        expect(cleared.contextTags, isEmpty);
        expect((await store.recordById(first.id))!.notes, isNull);

        final history = await store.history(first.id);
        expect(history.map((r) => r.notes), [
          'Taken with breakfast.',
          'Taken with breakfast.',
          null,
        ]);
        expect(history.first.contextTags, ['Morning', 'With food']);
      },
    );

    test('empty context stays valid and survives encrypted restart', () async {
      final first = await record('take');
      expect(first.notes, isNull);
      expect(first.contextTags, isEmpty);
      await store.close();
      store = await RecordStore.open(
        path: '${directory.path}/records.db',
        key: key,
        isNew: false,
      );
      final reopened = await store.recordById(first.id);
      expect(reopened!.notes, isNull);
      expect(reopened.contextTags, isEmpty);
      expect(await store.history(first.id), hasLength(1));
    });

    test('retry keeps context and a changed retry conflicts', () async {
      const context = DoseContext(
        notes: 'Only what the person chose.',
        contextTags: ['Evening'],
      );
      final first = await record('same-command', context: context);
      final retry = await record('same-command', context: context);
      expect(retry.alreadyCommitted, isTrue);
      expect(retry.id, first.id);
      expect(retry.notes, context.notes);
      expect(retry.contextTags, ['Evening']);
      await expectLater(
        record(
          'same-command',
          context: const DoseContext(contextTags: ['Morning']),
        ),
        throwsA(isA<CommandConflict>()),
      );
    });

    test('dose drafts accept only the reviewed context fields', () {
      final draft = OrdinaryDraft(
        id: 'draft',
        generation: 'generation',
        operationId: 'operation',
        kind: DraftKind.dose,
        personId: meId,
        personRevision: 1,
        targetId: item.id,
        targetRevision: item.revision,
        fields: const {
          'amount': '1',
          'notes': 'Draft note',
          'contextTags': 'Morning, With food',
        },
      );
      expect(draft.fields['notes'], 'Draft note');
      expect(
        () => OrdinaryDraft(
          id: 'bad',
          generation: 'generation',
          operationId: 'operation',
          kind: DraftKind.dose,
          personId: meId,
          personRevision: 1,
          targetId: item.id,
          targetRevision: item.revision,
          fields: const {'notes': 'note', 'unknown': 'field'},
        ),
        throwsFormatException,
      );
    });

    test(
      'notes are gated in export and report, tags stay structured',
      () async {
        final saved = await record(
          'take',
          context: const DoseContext(
            notes: 'Private dose note.',
            contextTags: ['With food', 'Evening'],
          ),
        );
        ExportSelection selection({required bool includeNotes}) =>
            ExportSelection(
              personId: meId,
              fromDay: CivilDate(2026, 10, 20),
              beforeDay: CivilDate(2026, 10, 21),
              zoneId: 'UTC',
              contents: const [ExportContent.doses],
              format: ExportFormat.json,
              includeNotes: includeNotes,
            );

        final private = await store.captureExport(
          selection(includeNotes: false),
        );
        final privateContext =
            private.doses.single.toJson()['context'] as Map<String, Object?>;
        expect(privateContext['tags'], ['With food', 'Evening']);
        expect(privateContext['note'], isNull);

        final shared = await store.captureExport(selection(includeNotes: true));
        final sharedContext =
            shared.doses.single.toJson()['context'] as Map<String, Object?>;
        expect(sharedContext['note'], 'Private dose note.');

        final csv = utf8.decode(
          ExportArtifact.build(
            await store.captureExport(
              ExportSelection(
                personId: meId,
                fromDay: CivilDate(2026, 10, 20),
                beforeDay: CivilDate(2026, 10, 21),
                zoneId: 'UTC',
                contents: const [ExportContent.doses],
                format: ExportFormat.csv,
                includeNotes: false,
              ),
            ),
          ).bytes,
        );
        final lines = csv.split('\r\n');
        expect(lines.first, contains('context_tags'));
        expect(lines.first, contains('dose_notes'));
        expect(lines[1], contains('With food; Evening'));
        expect(lines[1], isNot(contains('Private dose note.')));

        final reportPrivate = ReportRecord.fromUseRecord(saved);
        expect(reportPrivate.contextTags, ['With food', 'Evening']);
        expect(reportPrivate.notes, isNull);
        final reportShared = ReportRecord.fromUseRecord(
          saved,
          includeNotes: true,
        );
        expect(reportShared.notes, 'Private dose note.');
      },
    );
  });

  group('skip reason persistence', () {
    late Directory directory;
    late RecordStore store;
    late SubstanceItem item;
    final key = List.generate(32, (i) => i + 4);
    final date = CivilDate(2026, 10, 20);

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('vital-skip-');
      store = await RecordStore.open(
        path: '${directory.path}/records.db',
        key: key,
        isNew: true,
      );
      item = await store.createItem(
        commandId: 'item',
        name: 'Synthetic skip item',
        form: 'tablet',
        unit: 'mg',
        type: 'medicine',
      );
      await store.saveDailyPlan(
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
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
      );
    });

    tearDown(() async {
      await store.close();
      await directory.delete(recursive: true);
    });

    Future<DailyRow> row() async => (await store.dailyRows(
      from: date,
      toExclusive: date.addDays(1),
      observedZone: 'Europe/London',
    )).rows.single;

    test(
      'skip reason is optional, trimmed and kept in action history',
      () async {
        final firstRow = await row();
        final skipped = await store.actDaily(
          commandId: 'skip-one',
          row: firstRow,
          kind: DailyActionKind.skip,
          skipReason: '  Felt unwell  ',
        );
        expect(skipped.reason, 'Felt unwell');
        expect((await row()).actions.single.reason, 'Felt unwell');

        final replay = await store.actDaily(
          commandId: 'skip-one',
          row: firstRow,
          kind: DailyActionKind.skip,
          skipReason: '  Felt unwell  ',
        );
        expect(replay.alreadyCommitted, isTrue);
        expect(replay.reason, 'Felt unwell');
        await expectLater(
          store.actDaily(
            commandId: 'skip-one',
            row: firstRow,
            kind: DailyActionKind.skip,
            skipReason: 'Changed reason',
          ),
          throwsA(isA<CommandConflict>()),
        );

        await store.undoDaily(
          commandId: 'undo-one',
          row: await row(),
          action: (await row()).actions.single,
        );
        await store.actDaily(
          commandId: 'skip-two',
          row: await row(),
          kind: DailyActionKind.skip,
          skipReason: 'Travelling',
        );
        final actions = (await row()).actions;
        expect(actions.first.reason, 'Travelling');
        expect(actions.last.reason, 'Felt unwell');

        await store.close();
        store = await RecordStore.open(
          path: '${directory.path}/records.db',
          key: key,
          isNew: false,
        );
        expect((await row()).actions.first.reason, 'Travelling');
      },
    );

    test('export keeps skip identity and gates the free-text reason', () async {
      final skipped = await store.actDaily(
        commandId: 'skip-export',
        row: await row(),
        kind: DailyActionKind.skip,
        skipReason: 'Felt unwell',
      );
      ExportSelection export({
        required bool includeNotes,
        ExportFormat format = ExportFormat.json,
      }) => ExportSelection(
        personId: meId,
        fromDay: date,
        beforeDay: date.addDays(1),
        zoneId: 'Europe/London',
        contents: const [ExportContent.doses],
        format: format,
        includeNotes: includeNotes,
      );

      final private = await store.captureExport(export(includeNotes: false));
      expect(private.skipped.single.actionId, skipped.id);
      expect(private.skipped.single.itemId, item.id);
      expect(private.skipped.single.reason, isNull);
      final privateJson = private.toJson();
      final privateRow =
          (privateJson['skipped'] as List<Object?>).single
              as Map<String, Object?>;
      expect(privateRow['actionId'], skipped.id);
      expect(privateRow['reason'], isNull);

      final shared = await store.captureExport(export(includeNotes: true));
      expect(shared.skipped.single.reason, 'Felt unwell');

      final csv = utf8.decode(
        ExportArtifact.build(
          await store.captureExport(
            export(includeNotes: false, format: ExportFormat.csv),
          ),
        ).bytes,
      );
      final skipLine = csv
          .split('\r\n')
          .firstWhere((line) => line.startsWith('skip,'));
      expect(skipLine, contains(skipped.id));
      expect(skipLine, isNot(contains('Felt unwell')));
    });

    test('skip accepts no reason and taken never accepts one', () async {
      await store.actDaily(
        commandId: 'skip-empty',
        row: await row(),
        kind: DailyActionKind.skip,
      );
      expect((await row()).actions.single.reason, isNull);

      await expectLater(
        store.actDaily(
          commandId: 'taken-reason',
          row: await row(),
          kind: DailyActionKind.taken,
          actualAt: DateTime.utc(2026, 10, 20, 9),
          skipReason: 'Not allowed',
        ),
        throwsArgumentError,
      );
      await expectLater(
        store.actDaily(
          commandId: 'skip-too-long',
          row: await row(),
          kind: DailyActionKind.skip,
          skipReason: 'x' * (maxSkipReasonLength + 1),
        ),
        throwsArgumentError,
      );
    });
  });

  group('legacy record command identity', () {
    test('a pre-D10 empty-context record command still replays', () async {
      final directory = await Directory.systemTemp.createTemp('vital-legacy-');
      final path = '${directory.path}/records.db';
      final key = List.generate(32, (i) => i + 9);
      final db = sqlite3.open(path);
      final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
      db.execute("PRAGMA cipher='chacha20'");
      db.execute("PRAGMA key=\"x'$hex'\"");
      db.execute(
        await File('test/data/fixtures/record_store_v1.sql').readAsString(),
      );
      db.close();
      final store = await RecordStore.open(path: path, key: key, isNew: false);
      addTearDown(() async {
        await store.close();
        await directory.delete(recursive: true);
      });

      final replay = await store.record(
        commandId: 'fixture-operation',
        itemId: 'item',
        amount: '0.125000',
        actualAt: DateTime.fromMicrosecondsSinceEpoch(
          1792368000000000,
          isUtc: true,
        ),
      );
      expect(replay.alreadyCommitted, isTrue);
      expect(replay.id, 'record');
      expect(replay.notes, isNull);
      expect(replay.contextTags, isEmpty);
    });
  });
}
