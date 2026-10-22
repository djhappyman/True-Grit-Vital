import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/l10n/app_localizations.dart';
import 'package:true_grit_vital/domain/stock/stored_stock.dart';
import 'package:true_grit_vital/features/stock/stock_widgets.dart';
import 'package:true_grit_vital/features/stock/stock_providers.dart'
    show sameStockStrength;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/substance_profile.dart';
import 'package:true_grit_vital/domain/products/products.dart';

void main() {
  ExactAmount n(String v) => ExactAmount.parseEntry(v);
  test(
    'prepared vial retains originals and calculates exact volume equivalents',
    () {
      final p = VialPreparation(
        powderAmount: '24',
        massUnit: 'mg',
        finalVolumeMl: '12',
        liquid: 'Labelled mixing liquid',
        addedVolumeMl: '11.8',
        preparedOn: '2026-10-22',
      );
      final strength = LabelledStrength(
        ingredientId: 'i',
        label: 'Vial A',
        mgPerMl: p.mgPerMl,
        preparation: p,
      );
      expect(p.mgPerMl, n('2'));
      expect(strength.equivalent(n('0.25'), from: 'ml', to: 'mg'), n('0.5'));
      expect(strength.equivalent(n('0.5'), from: 'mg', to: 'ml'), n('0.25'));
      expect(
        LabelledStrength.fromJson(
          jsonDecode(jsonEncode(strength.toJson())) as Map<String, dynamic>,
        ).preparation!.toJson(),
        p.toJson(),
      );
      expect(p.addedVolumeMl, '11.8');
    },
  );
  test('repeating concentration never rounds before a conversion', () {
    final p = VialPreparation(
      powderAmount: '1',
      massUnit: 'mg',
      finalVolumeMl: '3',
    );
    expect(p.mgPerMl, ExactAmount(BigInt.one, BigInt.from(3)));
    expect(p.mgPerMl * n('3'), n('1'));
  });
  test(
    'micrograms convert explicitly and count strength is independent of volume',
    () {
      final p = SubstanceProfile(
        route: SubstanceRoute.oral,
        form: SubstanceForm.tablet,
        strengthText: '250',
        massUnit: 'mcg',
      );
      final s = p.labelledStrength('i', 'Tablet')!;
      expect(s.equivalent(n('2'), from: 'count', to: 'mg'), n('0.5'));
      expect(s.equivalent(n('0.5'), from: 'mg', to: 'count'), n('2'));
      expect(s.equivalent(n('2'), from: 'count', to: 'ml'), isNull);
      expect(
        VialPreparation(
          powderAmount: '250',
          massUnit: 'mcg',
          finalVolumeMl: '2',
        ).mgPerMl,
        n('0.125'),
      );
    },
  );
  test(
    'rejects incompatible choices, missing totals and contradictory strengths',
    () {
      expect(
        () => SubstanceProfile(
          route: SubstanceRoute.oral,
          form: SubstanceForm.oil,
        ),
        throwsFormatException,
      );
      for (final v in ['0', '-1', '', 'NaN', '1e6']) {
        expect(
          () => VialPreparation(
            powderAmount: v,
            massUnit: 'mg',
            finalVolumeMl: '12',
          ),
          throwsA(anything),
        );
        expect(
          () => VialPreparation(
            powderAmount: '24',
            massUnit: 'mg',
            finalVolumeMl: v,
          ),
          throwsA(anything),
        );
        expect(() => HalfLife(value: v, unit: 'days'), throwsA(anything));
      }
      expect(
        () => VialPreparation(
          powderAmount: '1',
          massUnit: 'mg',
          finalVolumeMl: '3',
          preparedOn: '2026-02-30',
        ),
        throwsFormatException,
      );
      final p = VialPreparation(
        powderAmount: '1',
        massUnit: 'mg',
        finalVolumeMl: '3',
      );
      expect(
        () => LabelledStrength(
          ingredientId: 'i',
          label: 'i',
          mgPerMl: n('0.333333'),
          preparation: p,
        ),
        throwsArgumentError,
      );
    },
  );
  test('half-life stays optional and preserves each blend ingredient independently', () {
    final a = ProductComponent(
      ingredientId: 'a',
      name: 'Ingredient A',
      halfLife: HalfLife(
        value: '8',
        unit: 'days',
        context: 'Labelled ester A, IM',
        source: 'Entered source A',
      ),
    );
    final b = ProductComponent(
      ingredientId: 'b',
      name: 'Ingredient B',
      halfLife: HalfLife(value: '12', unit: 'hours'),
    );
    final p = ProductLabelSnapshot(
      personId: 'me',
      itemId: 'i',
      revision: 1,
      components: [a, b],
    );
    final read = ProductLabelSnapshot.fromJson(
      jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>,
    );
    expect(read.components.first.halfLife!.unit, 'days');
    expect(read.components.last.halfLife!.unit, 'hours');
    expect(
      SubstanceProfile(
        route: SubstanceRoute.injectable,
        form: SubstanceForm.oil,
      ).halfLife,
      isNull,
    );
  });
  test('equal known count strengths do not become replacements because pack labels differ', () {
    expect(
      sameStockStrength(
        LabelledStrength(
          ingredientId: 'i',
          label: 'Pack A',
          mgPerCount: n('0.25'),
        ),
        LabelledStrength(
          ingredientId: 'i',
          label: 'Pack B',
          mgPerCount: n('0.25'),
        ),
      ),
      isTrue,
    );
    expect(
      sameStockStrength(
        LabelledStrength(
          ingredientId: 'i',
          label: 'Pack A',
          mgPerCount: n('0.25'),
        ),
        LabelledStrength(
          ingredientId: 'i',
          label: 'Pack B',
          mgPerCount: n('0.5'),
        ),
      ),
      isFalse,
    );
  });
  testWidgets(
    'an unsupported volume against tablet stock stays unknown without crashing',
    (tester) async {
      final container = StoredStockContainer(
        id: 'c',
        personId: 'me',
        itemId: 'i',
        label: 'Tablets',
        unit: 'count',
        strength: LabelledStrength(
          ingredientId: 'i',
          label: '250 micrograms each',
          mgPerCount: n('0.25'),
        ),
        revision: 1,
        balance: StockBalance(n('10')),
        sequence: 0,
        refillEnabled: false,
      );
      await tester.pumpWidget(
        ShadcnApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            child: StockDosePreview(
              enteredText: '1',
              enteredUnit: 'ml',
              selected: container,
              base: null,
              keep: null,
              onKeep: (_) {},
              onActual: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(StockDosePreview));
      expect(
        find.text(AppLocalizations.of(context).stockNoEquivalent),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
