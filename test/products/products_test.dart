import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/products/products.dart';
import 'package:true_grit_vital/domain/stock/exact_amount.dart';

ExactAmount pair(String s) {
  final p = s.split('/');
  return ExactAmount(
    BigInt.parse(p[0]),
    p.length == 1 ? BigInt.one : BigInt.parse(p[1]),
  );
}

void main() {
  final oracle = jsonDecode(
    File('test/fixtures/products/exact_oracle.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  for (final raw in oracle['cases'] as List) {
    final c = raw as Map<String, dynamic>;
    test('independent Fraction vector ${c['id']}', () {
      final label = ProductLabelSnapshot(
        personId: 'me',
        itemId: 'product',
        revision: 1,
        components: [
          for (
            var i = 0;
            i < (c['labelled_concentrations'] as List).length;
            i++
          )
            ProductComponent(
              ingredientId: 'c$i',
              name: 'Same display name',
              concentrationText: c['labelled_concentrations'][i] as String?,
            ),
        ],
      );
      final actual = ProductAdministrationSnapshot(
        label: label,
        defaultLabel: label,
        volume: pair(c['volume'] as String),
      );
      expect(
        actual.components.map((x) => x.amount?.toString()).toList(),
        c['component_masses'],
      );
      final total = aggregateProducts(List.filled(c['repeats'] as int, actual));
      expect(total.volume.toString(), c['total_physical_volume']);
      expect(
        total.ingredients.map((x) => x.total?.toString()).toList(),
        c['total_component_masses'],
      );
      expect(
        ProductAdministrationSnapshot.fromJson(
          jsonDecode(jsonEncode(actual.toJson())) as Map<String, dynamic>,
        ).toJson(),
        actual.toJson(),
      );
    });
  }
  test(
    'unknown contributes incomplete subtotal; units names owners never merge',
    () {
      ProductAdministrationSnapshot row(
        String who,
        String name,
        String? strength, {
        String mass = 'mg',
      }) {
        final label = ProductLabelSnapshot(
          personId: who,
          itemId: 'i',
          revision: 1,
          components: [
            ProductComponent(
              ingredientId: 'a',
              name: name,
              concentrationText: strength,
              massUnit: mass,
            ),
            ProductComponent(
              ingredientId: 'b',
              name: 'B',
              concentrationText: '2',
            ),
          ],
        );
        return ProductAdministrationSnapshot(
          label: label,
          defaultLabel: label,
          volume: pair('1'),
        );
      }

      final total = aggregateProducts([
        row('me', 'Salt A', '3'),
        row('me', 'Salt A', null),
        row('other', 'Salt A', '3'),
        row('me', 'Salt B', '3'),
        row('me', 'Salt A', '3', mass: 'IU'),
      ]);
      final a = total.ingredients.first;
      expect(a.total, isNull);
      expect(a.knownSubtotal, pair('3'));
      expect(a.complete, false);
      expect(total.ingredients, hasLength(6));
    },
  );
  test(
    'explicit budgets make totals unavailable without losing raw snapshot',
    () {
      final label = ProductLabelSnapshot(
        personId: 'me',
        itemId: 'i',
        revision: 1,
        components: [
          ProductComponent(
            ingredientId: 'a',
            name: 'A',
            concentrationText: '9000000000',
          ),
          ProductComponent(ingredientId: 'b', name: 'B'),
        ],
      );
      final r = ProductAdministrationSnapshot(
        label: label,
        defaultLabel: label,
        volume: pair('9000000000'),
      );
      expect(
        aggregateProducts([r], maxBits: 64).ingredients.first.limitReached,
        true,
      );
      expect(aggregateProducts([r, r], maxRecords: 1).volume, isNull);
      expect(r.components.first.amount, pair('81000000000000000000'));
    },
  );
  test('invalid duplicate identities and entered fractions refused', () {
    final c = ProductComponent(ingredientId: 'a', name: 'A');
    expect(
      () => ProductLabelSnapshot(
        personId: 'me',
        itemId: 'i',
        revision: 1,
        components: [c, c],
      ),
      throwsFormatException,
    );
    expect(
      () => ProductComponent(
        ingredientId: 'a',
        name: 'A',
        concentrationText: '1/3',
      ),
      throwsFormatException,
    );
  });
  test('independent correction oracle selects current vector while physical volume is retained', () {
    final c = oracle['correction'] as Map<String, dynamic>;
    final label = ProductLabelSnapshot(
      personId: 'me',
      itemId: 'i',
      revision: 1,
      components: [
        ProductComponent(ingredientId: 'a', name: 'A', concentrationText: '3'),
        ProductComponent(ingredientId: 'b', name: 'B', concentrationText: '7'),
      ],
    );
    ProductAdministrationSnapshot row(String volume) =>
        ProductAdministrationSnapshot(
          label: label,
          defaultLabel: label,
          volume: pair(volume),
        );
    final original = aggregateProducts([row('1/3'), row('1/3'), row('1/3')]);
    final corrected = aggregateProducts([row('2/3'), row('1/3'), row('1/3')]);
    final voided = aggregateProducts([row('2/3'), row('1/3')]);
    expect(original.volume.toString(), c['original_total_volume']);
    expect(corrected.volume.toString(), c['corrected_report_volume']);
    expect(
      corrected.ingredients.map((x) => x.total.toString()).toList(),
      c['corrected_component_totals'],
    );
    expect(voided.volume.toString(), c['after_void_third_report_volume']);
    expect(original.volume.toString(), c['retained_physical_use']);
  });
}
