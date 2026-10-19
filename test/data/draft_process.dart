// Separate-process fixture. Synthetic key and data only.
import 'dart:io';

import 'package:true_grit_vital/data/record_store.dart';

Future<void> main(List<String> args) async {
  final mode = args[1];
  final store = await RecordStore.open(
    path: '${args[0]}/records.db',
    key: List.generate(32, (i) => i + 1),
    isNew: mode == 'init',
  );
  final at = DateTime.utc(2026, 10, 19, 12);
  if (mode == 'init') {
    final item = await store.createItem(
      commandId: 'item',
      name: 'Synthetic process draft',
      form: 'tablet',
      unit: 'mg',
      type: 'medicine',
    );
    await store.saveDraft(
      OrdinaryDraft(
        id: 'dose',
        generation: store.generation,
        operationId: 'dose-operation',
        kind: DraftKind.dose,
        personId: meId,
        personRevision: 1,
        targetId: item.id,
        targetRevision: null,
        submitted: true,
        fields: {
          'amount': '0.125000',
          'date': '2026-10-19',
          'time': '12:00',
          'instant': at.microsecondsSinceEpoch.toString(),
        },
      ),
    );
  } else if (mode == 'before' || mode == 'after') {
    final draft = (await store.drafts()).single;
    await store.record(
      commandId: draft.operationId,
      itemId: draft.targetId!,
      amount: draft.fields['amount']!,
      actualAt: at,
      beforeCommit: mode == 'before' ? () async => exit(71) : null,
    );
    exit(72);
  } else if (mode == 'verify-pending') {
    if ((await store.drafts()).single.operationId != 'dose-operation' ||
        (await store.records()).isNotEmpty) {
      throw StateError('draft_lost');
    }
  } else if (mode == 'verify-committed') {
    if ((await store.drafts()).isNotEmpty ||
        !await store.operationCommitted('dose-operation')) {
      throw StateError('draft_commit_not_atomic');
    }
    final result = await store.record(
      commandId: 'dose-operation',
      itemId: (await store.items()).single.id,
      amount: '0.125000',
      actualAt: at,
    );
    if (!result.alreadyCommitted || (await store.records()).length != 1) {
      throw StateError('duplicate');
    }
  } else {
    throw ArgumentError('mode');
  }
  await store.close();
  stdout.writeln('PASS $mode');
}
