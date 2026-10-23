import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:true_grit_vital/data/record_store.dart';

/// Deterministic synthetic dataset for the Vital performance fixture.
///
/// The dataset is generated from one seed with a simple linear congruential
/// generator and fixed command identifiers, so the same job always produces
/// the same dataset inputs (names, forms, units, amounts and dates) and can
/// never reopen a previous fixture store by accident. Store-internal record
/// identifiers come from the store's own id generation and are not part of
/// the dataset identity; the artifact carries the deterministic
/// `datasetHash` over spec, seed and counts instead. It contains no live
/// health data, no real names and no catalogue matches: everything is
/// labelled `Perf fixture`. Amounts use small integer values so arithmetic
/// stays trivial.

final class SeededDataset {
  SeededDataset({
    required this.items,
    required this.records,
    required this.containers,
  });

  final List<SubstanceItem> items;
  final int records;
  final int containers;
}

/// Seeds a fresh, already-single-user store with the fixture dataset.
///
/// [counts] must match the declared dataset block in the artifact identity:
/// the identical numbers the job carries. Records are spread over the last
/// [counts.recordDays] civil days so the long History page tracks many
/// distinct months without touching the future.
Future<SeededDataset> seedPerfDataset(
  RecordStore store, {
  required int seed,
  required int items,
  required int records,
  required int containers,
  DateTime? now,
}) {
  final clock = now ?? DateTime.utc(2026, 10, 1, 12);
  var state = _RandomState(seed);
  return _Seed(
    state: state,
    clock: clock,
    items: items,
    records: records,
    containers: containers,
  ).run(store);
}

final class _RandomState {
  _RandomState(this.seed) : _current = (seed | 1) & 0x7fffffff;
  final int seed;
  int _current;

  int next() {
    _current = (_current * 1103515245 + 12345) & 0x7fffffff;
    return _current >> 8;
  }

  int upTo(int bound) => bound <= 1 ? 0 : next() % bound;
}

final class _Seed {
  _Seed({
    required this.state,
    required this.clock,
    required this.items,
    required this.records,
    required this.containers,
  });

  static const itemNames = [
    'Perf fixture tablet',
    'Perf fixture liquid',
    'Perf fixture patch',
    'Perf fixture capsule',
    'Perf fixture inhaler',
    'Perf fixture drops',
  ];

  static const forms = ['Tablet', 'Liquid', 'Patch', 'Capsule'];
  static const units = ['mg', 'ml', 'count'];

  final _RandomState state;
  final DateTime clock;
  final int items;
  final int records;
  final int containers;

  Future<SeededDataset> run(RecordStore store) async {
    await store.enableSingleUser();
    final seededMe = await store.profileById(meId);
    if (seededMe == null) {
      throw const PerfDatasetError('own_profile_absent');
    }
    final profile = await store.editProfile(
      commandId: 'perf-profile',
      personId: meId,
      expectedRevision: seededMe.revision,
      name: 'Perf fixture adult',
      adultConfirmed: true,
    );

    final fixedItems = <SubstanceItem>[];
    for (var i = 0; i < items; i++) {
      final name = i < itemNames.length ? itemNames[i] : 'Perf fixture item $i';
      // Item 0 is always a count-unit tablet so every container has one
      // stable, valid owner; other items vary deterministically.
      final unit = i == 0 ? 'count' : units[state.upTo(units.length)];
      fixedItems.add(
        await store.createItem(
          commandId: 'perf-item-${i.toString().padLeft(6, '0')}',
          personId: profile.id,
          expectedPersonRevision: profile.revision,
          name: name,
          form: i == 0 ? 'Tablet' : forms[state.upTo(forms.length)],
          unit: unit,
          type: 'Perf fixture type ${i.toString().padLeft(4, '0')} item',
        ),
      );
    }

    // Commit history over the last recordDays days for the long History feed,
    // in chronological order so ids and stock movements stay monotonic.
    final created = <UseRecord>[];
    final recordDays = records < 200 ? 30 : 120;
    var recordIndex = 0;
    while (recordIndex < records) {
      final daysAgo = state.upTo(recordDays);
      final within = state.upTo(10);
      final at = clock.subtract(Duration(days: daysAgo, minutes: within * 61));
      final item = fixedItems[state.upTo(fixedItems.length)];
      created.add(
        await store.record(
          commandId: 'perf-record-${recordIndex.toString().padLeft(8, '0')}',
          itemId: item.id,
          amount: '${state.upTo(2) + 1}',
          actualAt: DateTime.utc(at.year, at.month, at.day, 8, 30),
          personId: profile.id,
          expectedPersonRevision: profile.revision,
        ),
      );
      recordIndex++;
    }

    // Containers all attach to the fixed count-unit item so the strength and
    // unit stay valid without conditional arithmetic.
    var containerIndex = 0;
    while (containerIndex < containers) {
      await store.createStockContainer(
        commandId:
            'perf-container-${containerIndex.toString().padLeft(8, '0')}',
        personId: profile.id,
        expectedPersonRevision: profile.revision,
        expectedGeneration: store.generation,
        itemId: fixedItems.first.id,
        label: 'Perf fixture container $containerIndex',
        unit: 'count',
        strength: LabelledStrength(
          ingredientId: 'perf-ingredient-item-0',
          label: '5 mg each',
          mgPerCount: ExactAmount(BigInt.from(5), BigInt.one),
        ),
        opening: ExactAmount(BigInt.from(400), BigInt.one),
      );
      containerIndex++;
    }
    return SeededDataset(
      items: fixedItems,
      records: created.length,
      containers: containerIndex,
    );
  }
}

/// Deterministic dataset identity hash over the fixed fixture spec, seed and
/// dataset counts. The fixture also uses fixed command identifiers so the
/// same inputs always regenerate the same dataset contents.
String perfDatasetHash({
  required String spec,
  required int seed,
  required int items,
  required int records,
  required int containers,
}) => sha256
    .convert(utf8.encode('$spec|$seed|$items|$records|$containers'))
    .toString();

final class PerfDatasetError implements Exception {
  const PerfDatasetError(this.code);
  final String code;
  @override
  String toString() => 'PerfDatasetError($code)';
}
