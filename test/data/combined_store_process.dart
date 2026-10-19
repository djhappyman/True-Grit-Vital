// Synthetic encrypted interruption fixture. The runner owns its directory.
import 'dart:convert';
import 'dart:io';

import 'package:true_grit_vital/data/record_store.dart';

Future<void> main(List<String> args) async {
  final mode = args[1];
  final input = File('${args[0]}/input.json');
  final store = await RecordStore.open(
    path: '${args[0]}/combined.db',
    key: List.generate(32, (i) => i + 1),
    isNew: mode == 'init',
  );
  if (mode == 'init') {
    final item = await store.createItem(
      commandId: 'item',
      name: 'Synthetic combined process source',
      form: 'liquid',
      unit: 'ml',
      type: 'medicine',
    );
    final c = await store.createStockContainer(
      commandId: 'source',
      personId: meId,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      itemId: item.id,
      label: 'Physical source',
      unit: 'ml',
      strength: LabelledStrength(ingredientId: item.id, label: 'Volume'),
      opening: ExactAmount(BigInt.from(2)),
    );
    final cmd = CombinedUseCommand(
      commandId: 'combined',
      expectedGeneration: store.generation,
      personId: meId,
      expectedPersonRevision: 1,
      actualAt: DateTime.utc(2026, 10, 19),
      components: [
        for (var i = 0; i < 2; i++)
          CombinedUseComponent(
            itemId: item.id,
            expectedItemRevision: item.revision,
            enteredAmount: '0.5',
            siteLabel: i == 0 ? 'Synthetic private site' : null,
            stockUse: StockUseInput(
              expectedGeneration: store.generation,
              entered: EnteredStockAmount('0.5', 'ml'),
              containerId: c.id,
              expectedContainerRevision: c.revision,
            ),
          ),
      ],
    );
    input.writeAsStringSync(jsonEncode(encodeCombinedUse(cmd)));
  } else {
    final cmd = decodeCombinedUse(
      jsonDecode(input.readAsStringSync()) as Map<String, dynamic>,
    );
    if (mode.startsWith('correction-')) {
      final group = await store.recordCombined(cmd);
      final correction = CombinedCorrectionCommand(
        commandId: 'correction',
        actionId: group.actionId,
        personId: meId,
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
        components: [
          for (final r in group.records)
            CombinedCorrectionComponent(
              recordId: r.id,
              expectedRevision: 1,
              enteredAmount: '0.25',
              physicalCorrection: PhysicalCorrection.reverseRecordedEffect,
              siteLabel: r.siteLabel,
            ),
        ],
      );
      if (mode == 'correction-verify-empty') {
        if ((await store.combinedById(
              actionId: group.actionId,
              personId: meId,
            ))!.records.any((r) => r.revision != 1) ||
            (await store.stockMovements(
                  personId: meId,
                  containerId: cmd.components.first.containerId!,
                )).length !=
                3) {
          throw StateError('partial_correction');
        }
      } else {
        final corrected = await store.correctCombined(
          correction,
          beforeCommit: mode == 'correction-before'
              ? () async {
                  exit(73);
                }
              : null,
        );
        if (mode == 'correction-after') exit(74);
        if (!corrected.alreadyCommitted ||
            corrected.records.any((r) => r.revision != 2) ||
            (await store.stockMovements(
                  personId: meId,
                  containerId: cmd.components.first.containerId!,
                )).length !=
                5) {
          throw StateError('correction_not_atomic');
        }
      }
    } else if (mode == 'before' || mode == 'after' || mode == 'verify-retry') {
      final r = await store.recordCombined(
        cmd,
        beforeCommit: mode == 'before'
            ? () async {
                exit(71);
              }
            : null,
      );
      if (mode == 'after') exit(72);
      if (!r.alreadyCommitted ||
          (await store.records()).length != 2 ||
          (await store.stockMovements(
                personId: meId,
                containerId: cmd.components.first.containerId!,
              )).length !=
              3 ||
          (await store.combinedHistory(
                actionId: r.actionId,
                personId: meId,
              )).length !=
              1) {
        throw StateError('combined_not_atomic');
      }
    } else if (mode == 'verify-empty') {
      if ((await store.records()).isNotEmpty ||
          (await store.stockMovements(
                personId: meId,
                containerId: cmd.components.first.containerId!,
              )).length !=
              1 ||
          (await store.siteHistory(personId: meId)).isNotEmpty) {
        throw StateError('partial_combined');
      }
    } else {
      throw ArgumentError('mode');
    }
  }
  await store.close();
  stdout.writeln('PASS combined $mode');
}
