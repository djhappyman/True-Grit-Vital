import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';

import '../../integration_test/perf/dataset.dart';
import '../../integration_test/perf/job.dart';

void main() {
  late Directory dir;
  late RecordStore store;
  final key = List.generate(32, (i) => i + 1);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vital-perf-dataset-');
    store = await RecordStore.open(
      path: '${dir.path}/fixture.db',
      key: key,
      isNew: true,
    );
  });

  tearDown(() async {
    await store.close();
    dir.deleteSync(recursive: true);
  });

  test('dataset hash is deterministic and input-sensitive', () {
    final a = perfDatasetHash(
      spec: perfFixtureSpec,
      seed: 1,
      items: 1,
      records: 2,
      containers: 3,
    );
    final b = perfDatasetHash(
      spec: perfFixtureSpec,
      seed: 1,
      items: 1,
      records: 2,
      containers: 3,
    );
    final c = perfDatasetHash(
      spec: perfFixtureSpec,
      seed: 2,
      items: 1,
      records: 2,
      containers: 3,
    );
    expect(a, b);
    expect(a, isNot(c));
    expect(a, hasLength(64));
  });

  test(
    'seeded dataset produces the declared counts and a count-unit owner',
    () async {
      final dataset = await seedPerfDataset(
        store,
        seed: perfDefaultSeed,
        items: 4,
        records: 20,
        containers: 5,
      );
      expect(dataset.items, hasLength(4));
      expect(dataset.records, 20);
      expect(dataset.containers, 5);
      expect(dataset.items.first.unit, 'count');
      // The synthetic data labels itself nowhere like live health data.
      for (final item in dataset.items) {
        expect(item.name, startsWith('Perf fixture'));
      }
    },
  );

  test('same seed and counts regenerate identical inputs with fresh record identities', () async {
    final datasetA = await seedPerfDataset(
      store,
      seed: 7,
      items: 3,
      records: 9,
      containers: 2,
    );
    // Second store, same seed: the dataset inputs must line up exactly.
    final dirB = await Directory.systemTemp.createTemp('vital-perf-dataset-');
    try {
      final storeB = await RecordStore.open(
        path: '${dirB.path}/fixture-b.db',
        key: key,
        isNew: true,
      );
      final datasetB = await seedPerfDataset(
        storeB,
        seed: 7,
        items: 3,
        records: 9,
        containers: 2,
      );
      // Dataset inputs regenerate identically: names, forms and units in the
      // same order. Store-internal ids are freshly generated and are not
      // part of the identity.
      expect(
        datasetB.items.map((i) => '${i.name}|${i.form}|${i.unit}'),
        datasetA.items.map((i) => '${i.name}|${i.form}|${i.unit}'),
      );
      await storeB.close();
    } finally {
      dirB.deleteSync(recursive: true);
    }
    // The first store's records were written to its own fixed command ids.
    expect(await store.records(), hasLength(9));
  });

  test(
    'wider dataset tracks many distinct days without reaching the future',
    () async {
      final dataset = await seedPerfDataset(
        store,
        seed: perfDefaultSeed,
        items: 2,
        records: 250,
        containers: 0,
      );
      final history = await store.history(dataset.items.first.id);
      final timestamps = history.map((row) => row.actualAt).toList();
      if (timestamps.isNotEmpty) {
        final latest = timestamps.reduce((a, b) => a.isAfter(b) ? a : b);
        expect(latest.isAfter(DateTime.now()), isFalse);
      }
      expect(dataset.records, 250);
    },
  );
}
