import '../substance_profile.dart';

import 'dart:convert';

import '../stock/exact_amount.dart';

/// Original ingredient label, without salt, name or unit equivalence guesses.
final class ProductComponent {
  ProductComponent({
    required this.ingredientId,
    required this.name,
    this.concentrationText,
    this.massUnit = 'mg',
    this.volumeUnit = 'ml',
    this.halfLife,
  }) {
    if (ingredientId.isEmpty ||
        ingredientId.length > 256 ||
        name.trim().isEmpty ||
        name.length > 500 ||
        massUnit.trim().isEmpty ||
        massUnit.length > 50 ||
        volumeUnit.trim().isEmpty ||
        volumeUnit.length > 50) {
      throw const FormatException('product_component');
    }
    if (concentrationText != null) ExactAmount.parseEntry(concentrationText!);
  }
  final String ingredientId, name, massUnit, volumeUnit;
  final String? concentrationText;
  final HalfLife? halfLife;
  ExactAmount? get mgPerMl =>
      concentrationText == null || massUnit != 'mg' || volumeUnit != 'ml'
      ? null
      : ExactAmount.parseEntry(concentrationText!);
  Map<String, Object?> toJson() => {
    'ingredientId': ingredientId,
    'name': name,
    'concentrationText': concentrationText,
    'massUnit': massUnit,
    'volumeUnit': volumeUnit,
    if (halfLife != null) 'halfLife': halfLife!.toJson(),
  };
  factory ProductComponent.fromJson(Map<String, dynamic> m) => ProductComponent(
    ingredientId: m['ingredientId'] as String,
    name: m['name'] as String,
    concentrationText: m['concentrationText'] as String?,
    massUnit: m['massUnit'] as String,
    volumeUnit: m['volumeUnit'] as String,
    halfLife: m['halfLife'] == null
        ? null
        : HalfLife.fromJson(Map<String, dynamic>.from(m['halfLife'] as Map)),
  );
}

final class ProductLabelSnapshot {
  ProductLabelSnapshot({
    required this.personId,
    required this.itemId,
    required this.revision,
    required Iterable<ProductComponent> components,
  }) : components = List.unmodifiable(components) {
    if (personId.isEmpty ||
        itemId.isEmpty ||
        revision < 1 ||
        this.components.length < 2 ||
        this.components.length > 32 ||
        this.components.map((c) => c.ingredientId).toSet().length !=
            this.components.length ||
        jsonEncode(toJson()).length > 32000) {
      throw const FormatException('product_label');
    }
  }
  final String personId, itemId;
  final int revision;
  final List<ProductComponent> components;
  Map<String, Object?> toJson() => {
    'personId': personId,
    'itemId': itemId,
    'revision': revision,
    'components': components.map((c) => c.toJson()).toList(),
  };
  factory ProductLabelSnapshot.fromJson(Map<String, dynamic> m) =>
      ProductLabelSnapshot(
        personId: m['personId'] as String,
        itemId: m['itemId'] as String,
        revision: m['revision'] as int,
        components: (m['components'] as List).map(
          (c) => ProductComponent.fromJson(Map<String, dynamic>.from(c as Map)),
        ),
      );
}

/// Frozen command input. A selected container can supply a different label;
/// the volume remains the fixed entry and the routine label is unchanged.
final class ProductUseInput {
  const ProductUseInput({
    required this.expectedGeneration,
    required this.label,
    required this.enteredVolume,
    this.containerId,
    this.expectedItemRevision,
    this.expectedContainerRevision,
    this.sourceLabel,
  });
  final String expectedGeneration;
  final ProductLabelSnapshot label;
  final EnteredStockAmount enteredVolume;
  final String? containerId;
  final int? expectedItemRevision, expectedContainerRevision;
  final ProductLabelSnapshot? sourceLabel;
  Map<String, Object?> toJson() => {
    'generation': expectedGeneration,
    'label': label.toJson(),
    'volume': enteredVolume.originalText,
    'unit': enteredVolume.unit,
    'container': containerId,
    'containerRevision': expectedContainerRevision,
    if (expectedItemRevision != null) 'itemRevision': expectedItemRevision,
    'sourceLabel': sourceLabel?.toJson(),
  };
  factory ProductUseInput.fromJson(Map<String, dynamic> m) => ProductUseInput(
    expectedGeneration: m['generation'] as String,
    label: ProductLabelSnapshot.fromJson(
      Map<String, dynamic>.from(m['label'] as Map),
    ),
    enteredVolume: EnteredStockAmount(
      m['volume'] as String,
      m['unit'] as String,
    ),
    containerId: m['container'] as String?,
    expectedContainerRevision: m['containerRevision'] as int?,
    expectedItemRevision: m['itemRevision'] as int?,
    sourceLabel: m['sourceLabel'] == null
        ? null
        : ProductLabelSnapshot.fromJson(
            Map<String, dynamic>.from(m['sourceLabel'] as Map),
          ),
  );
}

final class ProductComponentAmount {
  const ProductComponentAmount(this.component, this.amount);
  final ProductComponent component;
  final ExactAmount? amount;
  String get unit => 'mg';
}

/// Every revision retains its own complete original label and exact volume.
final class ProductAdministrationSnapshot {
  ProductAdministrationSnapshot({
    required this.label,
    required this.defaultLabel,
    required this.volume,
  }) {
    if (volume <= ExactAmount.zero ||
        label.personId != defaultLabel.personId ||
        label.itemId != defaultLabel.itemId) {
      throw const FormatException('product_actual');
    }
  }
  final ProductLabelSnapshot label, defaultLabel;
  final ExactAmount volume;
  List<ProductComponentAmount> get components => List.unmodifiable(
    label.components.map(
      (c) => ProductComponentAmount(
        c,
        c.mgPerMl == null ? null : volume * c.mgPerMl!,
      ),
    ),
  );
  Map<String, Object?> toJson() => {
    'label': label.toJson(),
    'defaultLabel': defaultLabel.toJson(),
    'volume': [volume.numerator.toString(), volume.denominator.toString()],
    'amounts': components
        .map(
          (c) => c.amount == null
              ? null
              : [
                  c.amount!.numerator.toString(),
                  c.amount!.denominator.toString(),
                ],
        )
        .toList(),
  };
  factory ProductAdministrationSnapshot.fromJson(Map<String, dynamic> m) {
    final pair = m['volume'] as List;
    final value = ProductAdministrationSnapshot(
      label: ProductLabelSnapshot.fromJson(
        Map<String, dynamic>.from(m['label'] as Map),
      ),
      defaultLabel: ProductLabelSnapshot.fromJson(
        Map<String, dynamic>.from(m['defaultLabel'] as Map),
      ),
      volume: ExactAmount.fromStorage(pair[0] as String, pair[1] as String),
    );
    if (jsonEncode(m['amounts']) != jsonEncode(value.toJson()['amounts'])) {
      throw const FormatException('product_vector');
    }
    return value;
  }
}

final class ProductIngredientTotal {
  const ProductIngredientTotal({
    required this.personId,
    required this.ingredientId,
    required this.name,
    required this.unit,
    required this.knownSubtotal,
    required this.complete,
    required this.contributions,
    required this.limitReached,
  });
  final String personId, ingredientId, name, unit;
  final ExactAmount? knownSubtotal;
  final bool complete, limitReached;
  final int contributions;
  ExactAmount? get total => complete ? knownSubtotal : null;
}

final class ProductTotals {
  ProductTotals({
    required Iterable<ProductIngredientTotal> ingredients,
    required this.volume,
    required this.administrations,
    required this.complete,
    required this.limitReached,
  }) : ingredients = List.unmodifiable(ingredients);
  final List<ProductIngredientTotal> ingredients;
  final ExactAmount? volume;
  final int administrations;
  final bool complete, limitReached;
}

/// Only compatible exact identity, original name and units share a total.
/// Unknown contributions retain a separately labelled known subtotal.
ProductTotals aggregateProducts(
  Iterable<ProductAdministrationSnapshot> records, {
  int maxRecords = 100000,
  int maxBits = 65536,
}) {
  if (maxRecords < 1 || maxBits < 64) throw ArgumentError('product_budget');
  final sums = <String, ExactAmount?>{};
  final labels = <String, ProductComponent>{};
  final people = <String, String>{};
  final unknown = <String>{}, limits = <String>{};
  final counts = <String, int>{};
  var volume = ExactAmount.zero, count = 0, limited = false;
  bool exceeds(ExactAmount a) =>
      a.numerator.bitLength > maxBits || a.denominator.bitLength > maxBits;
  for (final r in records) {
    if (++count > maxRecords) {
      limited = true;
      count--;
      break;
    }
    volume = volume + r.volume;
    if (exceeds(volume)) limited = true;
    for (final c in r.components) {
      final id = jsonEncode([
        r.label.personId,
        c.component.ingredientId,
        c.component.name,
        c.component.massUnit,
        c.component.volumeUnit,
      ]);
      labels[id] = c.component;
      people[id] = r.label.personId;
      counts[id] = (counts[id] ?? 0) + 1;
      if (c.amount == null) unknown.add(id);
      final sum =
          (sums[id] ?? ExactAmount.zero) + (c.amount ?? ExactAmount.zero);
      if (exceeds(sum) || limits.contains(id)) {
        limits.add(id);
        sums[id] = null;
      } else {
        sums[id] = sum;
      }
    }
  }
  return ProductTotals(
    ingredients: [
      for (final id in labels.keys)
        ProductIngredientTotal(
          personId: people[id]!,
          ingredientId: labels[id]!.ingredientId,
          name: labels[id]!.name,
          unit: labels[id]!.mgPerMl == null ? labels[id]!.massUnit : 'mg',
          knownSubtotal: sums[id],
          complete: !limited && !unknown.contains(id) && !limits.contains(id),
          contributions: counts[id]!,
          limitReached: limited || limits.contains(id),
        ),
    ],
    volume: limited ? null : volume,
    administrations: count,
    complete: !limited,
    limitReached: limited || limits.isNotEmpty,
  );
}
