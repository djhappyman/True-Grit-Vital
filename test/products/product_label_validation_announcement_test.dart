import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/products/product_widgets.dart';

import '../product_ui_test.dart' show editIngredient, product;
import '../vital_app_test.dart' show appTest, launch, runIo, settle, tap;

const invalidIngredients =
    'Enter 2–32 ingredients with names and units. Known concentrations must be positive decimals with up to six decimal places.';

void main() {
  appTest('invalid product ingredients are announced once beside the fields', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () => product(f.store)))!;
    f.container.read(routerProvider).go('/products/$meId/label/${item.id}');
    await settle(tester);

    await editIngredient(tester, 'Concentration', 0, 'not a number');
    await settle(tester);
    await tap(tester, 'Save');

    // The editor owns this validation message; a second copy above Save is a
    // duplicate visible error and a second live-region announcement.
    expect(find.text(invalidIngredients), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ProductComponentEditor),
        matching: find.text(invalidIngredients),
      ),
      findsOneWidget,
    );
    expect(
      (await runIo(
        tester,
        () => f.store.productLabel(personId: meId, itemId: item.id),
      ))!.revision,
      1,
    );
    expect(tester.takeException(), isNull);
  });
}
