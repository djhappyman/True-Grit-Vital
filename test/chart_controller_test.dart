import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/charts.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/charts/charts.dart';

class ControlledChartLock extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: false);
  void setLocked(bool value) =>
      state = AppLockState(ready: true, locked: value);
}

Future<void> until(bool Function() condition) async {
  final time = Stopwatch()..start();
  while (!condition()) {
    if (time.elapsed > const Duration(seconds: 5)) {
      throw StateError('chart_test_timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void main() {
  late Directory directory;
  late RecordStore store;
  late ProviderContainer container;
  final streams = <StreamController<ChartObservationBatch>>[];
  final jobs = <({ChartBuildJob job, Completer<ChartModel> completion})>[];
  late ProviderSubscription<ChartViewState> subscription;
  final provider = chartControllerProvider('/charts');
  ChartQuery query(String person) => ChartQuery(
    personId: person,
    viewport: ChartViewport(
      fromInstant: DateTime.utc(2026, 10, 1),
      beforeInstant: DateTime.utc(2026, 11, 1),
      displayZone: 'Europe/London',
      bucketSize: ChartBucketSize.day,
    ),
  );
  ChartObservationBatch batch(ChartQuery q, {bool truncated = false}) =>
      ChartObservationBatch(
        personId: q.personId,
        fromInstant: q.viewport.fromInstant,
        beforeInstant: q.viewport.beforeInstant,
        schemaVersion: 17,
        datasetGeneration: store.generation,
        truncated: truncated,
        observations: [
          if (!truncated)
            ChartObservation(
              source: ChartSourceRef(recordId: q.personId, revision: 1),
              personId: q.personId,
              itemId: 'item',
              itemName: 'Medicine',
              amount: ExactAmount.parseEntry('1'),
              unit: 'mg',
              occurredAt: DateTime.utc(2026, 10, 19),
            ),
        ],
      );
  void finish(int index) {
    final captured = jobs[index];
    captured.completion.complete(
      ChartModel.build(
        query: captured.job.query,
        batch: captured.job.batch,
        generation: captured.job.generation,
      ),
    );
  }

  setUp(() async {
    streams.clear();
    jobs.clear();
    directory = await Directory.systemTemp.createTemp(
      'vital-chart-controller-',
    );
    store = await RecordStore.open(
      path: '${directory.path}/records.db',
      key: List.generate(32, (i) => i + 1),
      isNew: true,
    );
    container = ProviderContainer(
      overrides: [
        storeLoaderProvider.overrideWithValue(() async => store),
        appLockProvider.overrideWith(ControlledChartLock.new),
        chartWatcherProvider.overrideWithValue((request) {
          final stream = StreamController<ChartObservationBatch>();
          streams.add(stream);
          return stream.stream;
        }),
        chartBuilderProvider.overrideWithValue((job) {
          final completion = Completer<ChartModel>();
          jobs.add((job: job, completion: completion));
          return completion.future;
        }),
      ],
    );
    await container.read(recordStoreProvider.future);
    subscription = container.listen(provider, (_, _) {});
  });
  tearDown(() async {
    subscription.close();
    container.dispose();
    for (final stream in streams) {
      await stream.close();
    }
    await store.close();
    await directory.delete(recursive: true);
  });

  test('late person/filter builds cannot overwrite the new query', () async {
    final first = query(meId), second = query('other-adult');
    final controller = container.read(provider.notifier);
    await controller.configure(first);
    streams[0].add(batch(first));
    await until(() => jobs.length == 1);
    await controller.configure(second);
    streams[1].add(batch(second));
    await until(() => jobs.length == 2);
    finish(1);
    await until(() => container.read(provider).model != null);
    expect(container.read(provider).model!.query.personId, 'other-adult');
    finish(0);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(container.read(provider).model!.query.identity, second.identity);
  });
  test(
    'same-query refresh rejects earlier fold and lock clears all values',
    () async {
      final q = query(meId), controller = container.read(provider.notifier);
      await controller.configure(q);
      streams[0].add(batch(q));
      await until(() => jobs.length == 1);
      await controller.refresh();
      streams[1].add(batch(q));
      await until(() => jobs.length == 2);
      finish(1);
      await until(() => container.read(provider).model != null);
      (container.read(appLockProvider.notifier) as ControlledChartLock)
          .setLocked(true);
      expect(container.read(provider).model, isNull);
      expect(container.read(provider).batch, isNull);
      finish(0);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(container.read(provider).locked, isTrue);
      expect(container.read(provider).model, isNull);
    },
  );
  test('hidden charts detach their source and reattach on return', () async {
    final q = query(meId), controller = container.read(provider.notifier);
    await controller.configure(q);
    expect(streams.single.hasListener, isTrue);
    await controller.visible(false);
    expect(streams.single.hasListener, isFalse);
    await controller.visible(true);
    expect(streams.length, 2);
    expect(streams.last.hasListener, isTrue);
  });
  test('exact amount labels never round a claimed total', () {
    expect(chartExactAmount(ExactAmount(BigInt.one, BigInt.two)), '0.5');
    expect(chartExactAmount(ExactAmount(BigInt.one, BigInt.from(3))), '1/3');
    expect(chartExactAmount(ExactAmount(BigInt.from(100))), '100');
    expect(chartExactAmount(ExactAmount.zero), '0');
  });
}
