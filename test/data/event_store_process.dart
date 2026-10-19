// Synthetic process-death fixture. Its caller owns the temporary directory.
import 'dart:convert';
import 'dart:io';

import 'package:true_grit_vital/data/record_store.dart';

Future<void> main(List<String> args) async {
  final dir = args[0], mode = args[1];
  final store = await RecordStore.open(
    path: '$dir/event.db',
    key: List.generate(32, (i) => i + 1),
    isNew: mode == 'init',
  );
  final input = File('$dir/input.json');
  if (mode == 'init') {
    final item = await store.createItem(
      commandId: 'item',
      name: 'Synthetic process item',
      form: 'tablet',
      unit: 'count',
      type: 'medicine',
    );
    final event = EventRecord(
      id: 'event',
      personId: meId,
      name: 'Synthetic event',
      eventType: 'course',
      zoneId: 'Europe/London',
      revision: 1,
      memberships: [
        EventMembership(
          id: 'member',
          itemId: item.id,
          personId: meId,
          effectiveFrom: DateTime.utc(2026, 10, 19),
          revision: 1,
        ),
      ],
    );
    input.writeAsStringSync(
      jsonEncode(
        SaveEventCommand(
          commandId: 'save',
          generation: store.generation,
          expectedRevision: null,
          event: event,
        ).toJson(),
      ),
    );
  } else {
    final command = SaveEventCommand.fromJson(
      Map<String, Object?>.from(jsonDecode(input.readAsStringSync()) as Map),
    );
    if (mode == 'before' || mode == 'after' || mode == 'verify-retry') {
      await store.saveEvent(
        command,
        beforeCommit: mode == 'before'
            ? () async {
                exit(73);
              }
            : null,
      );
      if (mode == 'after') exit(74);
      if ((await store.eventHistory('event')).length != 1 ||
          (await store.events()).length != 1 ||
          (await store.records()).isNotEmpty) {
        throw StateError('event_not_atomic');
      }
    } else if (mode == 'verify-empty') {
      if ((await store.events()).isNotEmpty ||
          (await store.eventHistory('event')).isNotEmpty) {
        throw StateError('partial_event');
      }
    } else {
      throw ArgumentError('mode');
    }
  }
  await store.close();
  stdout.writeln('PASS event $mode');
}
