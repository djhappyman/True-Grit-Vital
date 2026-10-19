// Synthetic process boundaries for complete-group history correction.
import 'dart:convert';
import 'dart:io';

import 'package:true_grit_vital/data/record_store.dart';

Future<void> main(List<String> args) async {
  final dir = args[0], mode = args[1];
  final store = await RecordStore.open(
    path: '$dir/history.db',
    key: List.generate(32, (i) => i + 1),
    isNew: mode == 'init',
  );
  final input = File('$dir/command.json');
  if (mode == 'init') {
    final item = await store.createItem(
      commandId: 'item',
      name: 'Synthetic history source',
      form: 'tablet',
      unit: 'mg',
      type: 'medicine',
    );
    final group = await store.recordCombined(
      CombinedUseCommand(
        commandId: 'group',
        expectedGeneration: store.generation,
        personId: meId,
        expectedPersonRevision: 1,
        actualAt: DateTime.utc(2026, 10, 19),
        components: [
          for (var i = 0; i < 2; i++)
            CombinedUseComponent(
              itemId: item.id,
              expectedItemRevision: 1,
              enteredAmount: '1',
            ),
        ],
      ),
    );
    input.writeAsStringSync(
      jsonEncode({
        'group': group.actionId,
        'generation': store.generation,
        'ids': group.records.map((r) => r.id).toList(),
      }),
    );
  } else {
    final j = jsonDecode(input.readAsStringSync()) as Map;
    final command = CombinedCorrectionCommand(
      commandId: 'move',
      actionId: j['group'] as String,
      personId: meId,
      expectedPersonRevision: 1,
      expectedGeneration: j['generation'] as String,
      actualAt: DateTime.utc(2026, 10, 20),
      components: [
        for (final id in j['ids'] as List)
          CombinedCorrectionComponent(
            recordId: id as String,
            expectedRevision: 1,
            physicalCorrection: null,
          ),
      ],
    );
    if (mode == 'before' || mode == 'after' || mode == 'verify-retry') {
      await store.correctCombined(
        command,
        beforeCommit: mode == 'before'
            ? () async {
                exit(91);
              }
            : null,
      );
      if (mode == 'after') exit(92);
    }
    final page = await store.timeline(
      TimelineQuery(filter: TimelineFilter(), displayZone: 'Europe/London'),
    );
    final entry = page.entries.single as CombinedTimelineEntry;
    final day = mode == 'verify-old' ? 19 : 20;
    if (entry.occurredAt != DateTime.utc(2026, 10, day) ||
        entry.records.length != 2 ||
        await store.recordCount() != 2) {
      throw StateError('history_process_parent');
    }
    for (final r in entry.records) {
      if (r.revision != (day == 19 ? 1 : 2)) {
        throw StateError('history_process_revision');
      }
    }
    final calendar = await store.calendar(
      TimelineQuery(filter: TimelineFilter(), displayZone: 'Europe/London'),
      dates: [CivilDate(2026, 10, 19), CivilDate(2026, 10, 20)],
    );
    if (calendar.cells[day == 19 ? 0 : 1].recorded != 1 ||
        calendar.cells[day == 19 ? 1 : 0].recorded != 0) {
      throw StateError('history_process_calendar');
    }
  }
  await store.close();
  stdout.writeln('PASS history $mode');
}
