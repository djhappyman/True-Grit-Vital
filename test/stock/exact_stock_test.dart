import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/stock/exact_amount.dart';
import 'package:true_grit_vital/domain/stock/stock_ledger.dart';

ExactAmount entry(String text) => ExactAmount.parseEntry(text);
void main() {
  test(
    'Python Fraction oracle, repeating fractions, large values, round trips',
    () {
      final cases = jsonDecode(
        File('test/stock/exact_oracle.json').readAsStringSync(),
      ) as List<dynamic>;
      for (final row in cases.cast<Map<String, dynamic>>()) {
        final original = EnteredStockAmount(row['entered'] as String, 'mg');
        final strength = LabelledStrength(
          ingredientId: 'a',
          label: 'source label',
          mgPerMl: entry(row['strength'] as String),
        );
        final ml = strength.equivalent(original.value, from: 'mg', to: 'ml')!;
        expect(original.originalText, row['entered']);
        expect(original.value.toString(), row['mass']);
        expect(ml.toString(), row['volume']);
        expect(strength.equivalent(ml, from: 'ml', to: 'mg'), original.value);
        var total = ExactAmount.zero;
        for (var i = 0; i < 999; i++) {
          total = total + ml;
        }
        expect(total.toString(), row['repeated']);
        expect(
          ExactAmount.fromStorage(
            ml.numerator.toString(),
            ml.denominator.toString(),
          ),
          ml,
        );
      }
    },
  );
  test('entry boundary and unsupported units reject without truncation', () {
    for (final value in [
      '0',
      '-1',
      '1,2',
      '1e2',
      'NaN',
      '1.0000001',
      '9000000000.000001',
    ]) {
      expect(() => entry(value), throwsA(anything));
    }
    expect(() => EnteredStockAmount('1', 'IU'), throwsArgumentError);
    expect(() => ExactAmount.fromStorage('2', '6'), throwsFormatException);
    expect(() => ExactAmount(BigInt.one, BigInt.zero), throwsArgumentError);
    expect(entry('9000000000').toString(), '9000000000/1');
  });
  test('rounding is output only and half away from zero', () {
    final third = ExactAmount(BigInt.one, BigInt.from(3));
    expect(third.roundedDecimal(), '0.333333');
    expect(third.toString(), '1/3');
    expect(
      (-ExactAmount(BigInt.one, BigInt.two)).roundedDecimal(places: 0),
      '-1',
    );
  });
  test('unknown strength never supplies guessed conversion', () {
    final unknown = LabelledStrength(ingredientId: 'a', label: 'unknown');
    expect(unknown.equivalent(entry('1'), from: 'mg', to: 'ml'), isNull);
    expect(unknown.equivalent(entry('1'), from: 'count', to: 'mg'), isNull);
    expect(
      () => LabelledStrength(
        ingredientId: 'a',
        label: 'invalid',
        mgPerMl: ExactAmount.zero,
      ),
      throwsArgumentError,
    );
  });
  test('replacement choice keeps mg or ml explicitly and requires ingredient match', () {
    final old = LabelledStrength(
      ingredientId: 'a',
      label: '3 mg/ml',
      mgPerMl: entry('3'),
    );
    final next = LabelledStrength(
      ingredientId: 'a',
      label: '6 mg/ml',
      mgPerMl: entry('6'),
    );
    final dose = EnteredStockAmount('1', 'mg');
    final massFixed = ReplacementAmounts.calculate(
      entered: dose,
      oldStrength: old,
      newStrength: next,
      keep: FixedReplacementAmount.milligrams,
    )!;
    final volumeFixed = ReplacementAmounts.calculate(
      entered: dose,
      oldStrength: old,
      newStrength: next,
      keep: FixedReplacementAmount.millilitres,
    )!;
    expect(massFixed.milligrams, entry('1'));
    expect(massFixed.millilitres.toString(), '1/6');
    expect(volumeFixed.milligrams, entry('2'));
    expect(volumeFixed.millilitres.toString(), '1/3');
    expect(
      ReplacementAmounts.calculate(
        entered: dose,
        oldStrength: old,
        newStrength: LabelledStrength(ingredientId: 'b', label: 'different'),
        keep: FixedReplacementAmount.milligrams,
      ),
      isNull,
    );
  });
  final owner = StockOwner(personId: 'me', containerId: 'vial1', unit: 'ml');
  test(
    'truthful actual outflow creates signed deficit without refill or clamp',
    () {
      final movements = [
        StockMovement.restock('in', owner, entry('1')),
        StockMovement.use('dose', owner, entry('2')),
      ];
      final result = foldStock(owner, movements, opening: ExactAmount.zero);
      expect(result.value.toString(), '-1/1');
      expect(result.isDeficit, isTrue);
      expect(movements.length, 2);
      expect(foldStock(owner, movements).value, isNull);
    },
  );
  test('correction explicitly reverses duplicate or retains physically consumed stock', () {
    final dose = StockMovement.use('dose', owner, entry('2'));
    final restock = StockMovement.restock('in', owner, entry('1'));
    final reverse = StockMovement.correct(
      'fix',
      dose,
      PhysicalCorrection.reverseRecordedEffect,
    );
    expect(
      foldStock(owner, [
        restock,
        dose,
        reverse,
      ], opening: ExactAmount.zero).value,
      entry('1'),
    );
    expect(
      foldStock(owner, [
        restock,
        dose,
        StockMovement.correct(
          'fix',
          dose,
          PhysicalCorrection.retainPhysicalEffect,
        ),
      ], opening: ExactAmount.zero).value.toString(),
      '-1/1',
    );
    expect(
      () => foldStock(owner, [
        dose,
        reverse,
        StockMovement.correct(
          'again',
          dose,
          PhysicalCorrection.reverseRecordedEffect,
        ),
      ]),
      throwsArgumentError,
    );
    expect(() => foldStock(owner, [reverse]), throwsArgumentError);
    final forged = StockMovement.use('dose', owner, entry('3'));
    expect(
      () => foldStock(owner, [
        dose,
        StockMovement.correct(
          'forged',
          forged,
          PhysicalCorrection.reverseRecordedEffect,
        ),
      ]),
      throwsArgumentError,
    );
  });
  test(
    'ready-mixed components derive independently with one physical outflow',
    () {
      final volume = entry('0.5');
      final first = LabelledStrength(
        ingredientId: 'a',
        label: '3 mg/ml',
        mgPerMl: entry('3'),
      );
      final second = LabelledStrength(ingredientId: 'b', label: 'unknown');
      expect(first.equivalent(volume, from: 'ml', to: 'mg'), entry('1.5'));
      expect(second.equivalent(volume, from: 'ml', to: 'mg'), isNull);
      expect(
        foldStock(owner, [
          StockMovement.use('one', owner, volume),
        ], opening: entry('1')).value,
        volume,
      );
    },
  );
  test('unknown outflow remains unknown through restock until explicit measurement', () {
    final unknown = StockMovement.use('u', owner, null);
    expect(
      foldStock(owner, [
        unknown,
        StockMovement.restock('r', owner, entry('5')),
      ], opening: entry('4')).value,
      isNull,
    );
    expect(
      foldStock(owner, [
        unknown,
        StockMovement.reconcile('measure', owner, entry('3')),
      ], opening: entry('4')).value,
      entry('3'),
    );
    expect(
      foldStock(owner, [
        StockMovement.reconcile('unknown', owner, null),
      ], opening: entry('4')).value,
      isNull,
    );
  });
  test('corrections cannot change a later measured physical balance', () {
    for (final amount in [entry('3'), null]) {
      final old = StockMovement.use('old', owner, amount);
      final correction = StockMovement.correct(
        'fix',
        old,
        PhysicalCorrection.reverseRecordedEffect,
      );
      expect(
        foldStock(owner, [
          old,
          StockMovement.reconcile('m', owner, entry('5')),
          correction,
        ], opening: entry('10')).value,
        entry('5'),
      );
      expect(
        foldStock(owner, [
          old,
          StockMovement.reconcile('m', owner, null),
          correction,
        ], opening: entry('10')).value,
        isNull,
      );
    }
    final recent = StockMovement.use('recent', owner, entry('3'));
    expect(
      foldStock(owner, [
        StockMovement.reconcile('m', owner, entry('5')),
        recent,
        StockMovement.correct(
          'fix',
          recent,
          PhysicalCorrection.reverseRecordedEffect,
        ),
      ]).value,
      entry('5'),
    );
  });
  test('opening and unknown-balance inputs obey the rational bit budget', () {
    final huge = ExactAmount(BigInt.one << 100);
    expect(
      foldStock(owner, const [], opening: huge, maxBits: 64).limitReached,
      isTrue,
    );
    expect(
      foldStock(owner, [
        StockMovement.use('huge', owner, huge),
      ], maxBits: 64).limitReached,
      isTrue,
    );
    final tiny = ExactAmount(BigInt.one, BigInt.one << 100);
    expect(
      foldStock(owner, [
        StockMovement.use('tiny', owner, tiny),
      ], maxBits: 64).limitReached,
      isTrue,
    );
  });
  test('ownership, duplicates and aggregate limits remain explicit', () {
    final dose = StockMovement.use('d', owner, entry('1'));
    expect(
      () => foldStock(
        StockOwner(personId: 'other', containerId: 'vial1', unit: 'ml'),
        [dose],
      ),
      throwsArgumentError,
    );
    expect(() => foldStock(owner, [dose, dose]), throwsArgumentError);
    expect(
      foldStock(owner, [
        dose,
        StockMovement.use('d2', owner, entry('1')),
      ], maxMovements: 1).limitReached,
      isTrue,
    );
    expect(
      foldStock(
        owner,
        [StockMovement.restock('large', owner, ExactAmount(BigInt.one << 100))],
        opening: ExactAmount.zero,
        maxBits: 64,
      ).limitReached,
      isTrue,
    );
    // Larger than SQLite int64 SUM, exactly retained as text-backed BigInt.
    final huge = ExactAmount(BigInt.parse('9223372036854775808'));
    expect(
      foldStock(owner, [
        StockMovement.restock('h', owner, huge),
      ], opening: ExactAmount.zero).value,
      huge,
    );
  });
}
