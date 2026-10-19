// Synthetic encrypted crash fixture. All temporary files belong to its runner.
import 'dart:convert';
import 'dart:io';

import 'package:true_grit_vital/data/record_store.dart';

Future<void> main(List<String> args) async {
  final path = '${args[0]}/product.db', mode = args[1];
  final inputFile = File('${args[0]}/input.json');
  final store = await RecordStore.open(
    path: path,
    key: List.generate(32, (i) => i + 1),
    isNew: mode == 'init',
  );
  if (mode == 'init') {
    final item = await store.createItem(
      commandId: 'item',
      name: 'Synthetic product crash',
      form: 'liquid',
      unit: 'ml',
      type: 'medicine',
      productComponents: [
        ProductComponent(
          ingredientId: 'a',
          name: 'Original A',
          concentrationText: '3',
        ),
        ProductComponent(ingredientId: 'b', name: 'Unknown B'),
      ],
    );
    final label = (await store.productLabel(personId: meId, itemId: item.id))!;
    final c = await store.createStockContainer(
      commandId: 'container',
      personId: meId,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      itemId: item.id,
      label: 'Physical vial',
      unit: 'ml',
      strength: LabelledStrength(ingredientId: item.id, label: 'Volume'),
      productLabel: label,
      opening: ExactAmount(BigInt.one),
    );
    inputFile.writeAsStringSync(
      jsonEncode(
        ProductUseInput(
          expectedGeneration: store.generation,
          label: label,
          enteredVolume: EnteredStockAmount('0.5', 'ml'),
          containerId: c.id,
          expectedContainerRevision: c.revision,
          sourceLabel: label,
        ).toJson(),
      ),
    );
  } else {
    final input = ProductUseInput.fromJson(
      jsonDecode(inputFile.readAsStringSync()) as Map<String, dynamic>,
    );
    if (mode == 'before' || mode == 'after' || mode == 'verify-retry') {
      final r = await store.recordProduct(
        commandId: 'take',
        personId: meId,
        expectedPersonRevision: 1,
        itemId: input.label.itemId,
        actualAt: DateTime.utc(2026, 10, 19),
        use: input,
        beforeCommit: mode == 'before'
            ? () async {
                exit(71);
              }
            : null,
      );
      if (mode == 'after') exit(72);
      if (mode == 'verify-retry' &&
          (!r.alreadyCommitted ||
              (await store.records()).length != 1 ||
              r.product!.components.length != 2 ||
              (await store.stockMovements(
                    personId: meId,
                    containerId: input.containerId!,
                  )).length !=
                  2)) {
        throw StateError('product_retry_not_atomic');
      }
    } else if (mode == 'verify-empty') {
      if ((await store.records()).isNotEmpty ||
          (await store.stockMovements(
                personId: meId,
                containerId: input.containerId!,
              )).length !=
              1) {
        throw StateError('partial_product');
      }
    } else {
      throw ArgumentError('mode');
    }
  }
  await store.close();
  stdout.writeln('PASS product $mode');
}
