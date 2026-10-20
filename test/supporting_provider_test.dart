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
  void unlockNow() => state = const AppLockState(ready: true, locked: false);
}

typedef TrendRequest = ({
  SupportingTrendQuery query,
  int requestGeneration,
  StreamController<SupportingTrendPage> controller,
});

void main() {
  late Directory dir;
  late RecordStore store;
  late ProviderContainer container;
  final requests = <TrendRequest>[];
  SupportingTrendQuery query(String person) => SupportingTrendQuery(
    personId: person,
    metricId: 'metric',
    fromDate: CivilDate(2026, 10, 1),
    beforeDate: CivilDate(2026, 11, 1),
  );

  /// Emits one page on the current controlled subscription. The late page can
  /// deliberately carry another query or a retired dataset generation so the
  /// tests prove the provider fences it rather than only trusting Riverpod's
  /// element rebuild.
  void emit(
    int index, {
    SupportingTrendQuery? onQuery,
    String? datasetGeneration,
  }) {
    final request = requests[index];
    request.controller.add(
      SupportingTrendPage.build(
        query: onQuery ?? request.query,
        records: const [],
        schemaVersion: 21,
        datasetGeneration: datasetGeneration ?? store.generation,
        requestGeneration: request.requestGeneration,
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
        supportingTrendWatcherProvider.overrideWithValue((
          query, {
          requestGeneration = 0,
        }) {
          final controller = StreamController<SupportingTrendPage>();
          requests.add((
            query: query,
            requestGeneration: requestGeneration,
            controller: controller,
          ));
          return controller.stream;
        }),
      ],
    );
    await container.read(recordStoreProvider.future);
  });
  tearDown(() async {
    container.dispose();
    for (final request in requests) {
      await request.controller.close();
    }
    await store.close();
    await dir.delete(recursive: true);
  });
  test('late person emission cannot replace another person model', () async {
    final a = supportingTrendProvider(jsonEncode(query(meId).toJson())),
        b = supportingTrendProvider(jsonEncode(query('other').toJson()));
    final first = container.listen(a, (_, _) {}),
        second = container.listen(b, (_, _) {});
    await turns();
    final other = requests.indexWhere(
          (request) => request.query.personId == 'other',
        ),
        me = requests.indexWhere((request) => request.query.personId == meId);
    expect(other, isNot(me));
    emit(other);
    expect((await container.read(b.future))!.query.personId, 'other');
    emit(me);
    await turns();
    expect(container.read(b).value!.query.personId, 'other');
    expect(container.read(a).value!.query.personId, meId);
    first.close();
    second.close();
  });
  test('same query invalidation rejects an earlier stream value', () async {
    final p = supportingTrendProvider(jsonEncode(query(meId).toJson()));
    final sub = container.listen(p, (_, _) {});
    await turns();
    expect(requests.length, 1);
    container.invalidate(p);
    container.read(p);
    await turns();
    expect(requests.length, 2);
    expect(
      requests[1].requestGeneration,
      greaterThan(requests[0].requestGeneration),
    );
    emit(1);
    await container.read(p.future);
    expect(
      container.read(p).value!.requestGeneration,
      requests[1].requestGeneration,
    );
    // The retired subscription is detached, so its completion cannot win.
    emit(0);
    await turns();
    expect(
      container.read(p).value!.requestGeneration,
      requests[1].requestGeneration,
    );
    sub.close();
  });
  test('lock clears the model, detaches and rejects a delayed result', () async {
    final p = supportingTrendProvider(jsonEncode(query(meId).toJson()));
    final sub = container.listen(p, (_, _) {});
    await turns();
    expect(requests.length, 1);
    expect(requests.single.controller.hasListener, isTrue);
    (container.read(appLockProvider.notifier) as SupportingTestLock).lockNow();
    expect(await container.read(p.future), isNull);
    expect(requests.single.controller.hasListener, isFalse);
    emit(0);
    await turns();
    expect(container.read(p).value, isNull);
    // Unlocking reattaches once to the current query and adopts its fresh read.
    (container.read(appLockProvider.notifier) as SupportingTestLock)
        .unlockNow();
    await turns();
    expect(requests.length, 2);
    emit(1);
    expect(
      (await container.read(p.future))!.query.identity,
      requests[1].query.identity,
    );
    sub.close();
  });
  test(
    'retired generation and mismatched query emissions cannot publish',
    () async {
      final p = supportingTrendProvider(jsonEncode(query(meId).toJson()));
      final sub = container.listen(p, (_, _) {});
      await turns();
      emit(0, datasetGeneration: 'retired');
      await turns();
      expect(container.read(p).hasValue, isFalse);
      emit(0, onQuery: query('other'));
      await turns();
      expect(container.read(p).hasValue, isFalse);
      emit(0);
      await turns();
      expect(container.read(p).value!.datasetGeneration, store.generation);
      expect(container.read(p).value!.query.personId, meId);
      sub.close();
    },
  );
  test(
    'a loading replacement store never gets a watcher subscription',
    () async {
      final loader = Completer<RecordStore>();
      final replacement = ProviderContainer(
        overrides: [
          storeLoaderProvider.overrideWithValue(() => loader.future),
          appLockProvider.overrideWith(SupportingTestLock.new),
          supportingTrendWatcherProvider.overrideWithValue((
            query, {
            requestGeneration = 0,
          }) {
            final controller = StreamController<SupportingTrendPage>();
            requests.add((
              query: query,
              requestGeneration: requestGeneration,
              controller: controller,
            ));
            return controller.stream;
          }),
        ],
      );
      addTearDown(replacement.dispose);
      final p = supportingTrendProvider(jsonEncode(query(meId).toJson()));
      final sub = replacement.listen(p, (_, _) {});
      await turns();
      expect(requests, isEmpty);
      loader.complete(store);
      await turns();
      expect(requests.length, 1);
      emit(0);
      expect((await replacement.read(p.future))!.query.personId, meId);
      sub.close();
    },
  );
}
