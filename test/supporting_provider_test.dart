import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/supporting.dart';
import 'package:true_grit_vital/data/record_store.dart';

class SupportingTestLock extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: false);
  void lockNow() => state = const AppLockState(ready: true, locked: true);
}

void main() {
  late Directory dir;
  late RecordStore store;
  late ProviderContainer container;
  final requests =
      <({SupportingTrendQuery query, Completer<SupportingTrendPage> result})>[];
  SupportingTrendQuery query(String person) => SupportingTrendQuery(
    personId: person,
    metricId: 'metric',
    fromDate: CivilDate(2026, 10, 1),
    beforeDate: CivilDate(2026, 11, 1),
  );
  void finish(int index) {
    final r = requests[index];
    r.result.complete(
      SupportingTrendPage.build(
        query: r.query,
        records: [],
        schemaVersion: 19,
        datasetGeneration: store.generation,
      ),
    );
  }

  Future<void> turns() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  setUp(() async {
    requests.clear();
    dir = await Directory.systemTemp.createTemp('vital-supporting-provider-');
    store = await RecordStore.open(
      path: '${dir.path}/records.db',
      key: List.generate(32, (i) => i + 1),
      isNew: true,
    );
    container = ProviderContainer(
      overrides: [
        storeLoaderProvider.overrideWithValue(() async => store),
        appLockProvider.overrideWith(SupportingTestLock.new),
        supportingTrendReaderProvider.overrideWithValue((query) {
          final result = Completer<SupportingTrendPage>();
          requests.add((query: query, result: result));
          return result.future;
        }),
      ],
    );
    await container.read(recordStoreProvider.future);
  });
  tearDown(() async {
    container.dispose();
    await store.close();
    await dir.delete(recursive: true);
  });
  test('late person query cannot replace another person model', () async {
    final a = supportingTrendProvider(jsonEncode(query(meId).toJson())),
        b = supportingTrendProvider(jsonEncode(query('other').toJson()));
    final first = container.listen(a, (_, _) {}),
        second = container.listen(b, (_, _) {});
    await turns();
    finish(1);
    expect((await container.read(b.future))!.query.personId, 'other');
    finish(0);
    await turns();
    expect(container.read(b).value!.query.personId, 'other');
    first.close();
    second.close();
  });
  test('same query invalidation rejects earlier completion', () async {
    final p = supportingTrendProvider(jsonEncode(query(meId).toJson()));
    final sub = container.listen(p, (_, _) {});
    await turns();
    container.invalidate(p);
    container.read(p);
    await turns();
    finish(1);
    await container.read(p.future);
    finish(0);
    await turns();
    expect(container.read(p).hasValue, isTrue);
    expect(requests.length, 2);
    sub.close();
  });
  test(
    'lock clears current results and rejects a pending completion',
    () async {
      final p = supportingTrendProvider(jsonEncode(query(meId).toJson()));
      final sub = container.listen(p, (_, _) {});
      await turns();
      (container.read(appLockProvider.notifier) as SupportingTestLock)
          .lockNow();
      expect(await container.read(p.future), isNull);
      finish(0);
      await turns();
      expect(container.read(p).value, isNull);
      sub.close();
    },
  );
}
