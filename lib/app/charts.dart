import 'dart:async';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/record_store.dart';
import '../domain/charts/charts.dart';
import 'app_lock.dart';
import 'storage.dart';

typedef ChartWatcher = Stream<ChartObservationBatch> Function(
  ChartSourceRequest,
);
final chartWatcherProvider = Provider<ChartWatcher>(
  (ref) => (request) async* {
    yield* (await ref.read(recordStoreProvider.future))
        .watchChartObservations(request);
  },
);

typedef ChartBuildJob = ({
  ChartQuery query,
  ChartObservationBatch batch,
  int generation,
});
ChartModel _buildChart(ChartBuildJob job) => ChartModel.build(
  query: job.query,
  batch: job.batch,
  generation: job.generation,
);
typedef ChartBuilder = Future<ChartModel> Function(ChartBuildJob job);
final chartBuilderProvider = Provider<ChartBuilder>(
  (_) =>
      (job) => compute(_buildChart, job),
);

class ChartViewState {
  const ChartViewState({
    this.query,
    this.model,
    this.batch,
    this.loading = false,
    this.locked = false,
    this.error,
  });
  final ChartQuery? query;
  final ChartModel? model;
  final ChartObservationBatch? batch;
  final bool loading, locked;
  final Object? error;
}

final chartControllerProvider = NotifierProvider.autoDispose
    .family<ChartController, ChartViewState, String>(ChartController.new);

/// Query epochs, individual build generations and dataset metadata all have to
/// match before a background fold can publish. Lock never retains chart data.
class ChartController extends Notifier<ChartViewState> {
  ChartController(this.route);
  final String route;
  StreamSubscription<ChartObservationBatch>? _subscription;
  ChartRequestState _requests = ChartRequestState.initial();
  int _epoch = 0;
  bool _visible = true;
  @override
  ChartViewState build() {
    ref.watch(recordStoreProvider.select((value) => value.value?.generation));
    ref.onDispose(() {
      _epoch++;
      unawaited(_subscription?.cancel());
    });
    ref.listen(appLockProvider, (_, next) {
      if (next.locked) {
        _epoch++;
        unawaited(_subscription?.cancel());
        _subscription = null;
        state = ChartViewState(query: state.query, locked: true);
      } else if (next.ready && state.query != null && _visible) {
        configure(state.query!, force: true);
      }
    });
    return const ChartViewState();
  }

  Future<void> configure(ChartQuery query, {bool force = false}) async {
    if (!force && state.query?.identity == query.identity) return;
    final epoch = ++_epoch;
    await _subscription?.cancel();
    _subscription = null;
    if (!ref.mounted || epoch != _epoch) return;
    final locked = ref.read(appLockProvider).locked;
    final previous = state;
    final sameQuery = !locked && previous.query?.identity == query.identity;
    state = ChartViewState(
      query: query,
      model: sameQuery ? previous.model : null,
      batch: sameQuery ? previous.batch : null,
      loading: !locked,
      locked: locked,
    );
    if (locked || !_visible) return;
    _subscription = ref
        .read(chartWatcherProvider)(query.sourceRequest)
        .listen(
          (batch) async {
            if (!_current(epoch)) return;
            _requests = _requests.restart(
              query,
              schemaVersion: batch.schemaVersion,
              datasetGeneration: batch.datasetGeneration,
            );
            final generation = _requests.generation;
            try {
              final model = await ref.read(chartBuilderProvider)((
                query: query,
                batch: batch,
                generation: generation,
              ));
              if (!_current(epoch) || !_requests.accepts(model.token)) return;
              state = ChartViewState(query: query, model: model, batch: batch);
            } catch (error) {
              if (!_current(epoch) || generation != _requests.generation) {
                return;
              }
              state = ChartViewState(query: query, error: error);
            }
          },
          onError: (Object error) {
            if (_current(epoch)) {
              state = ChartViewState(query: query, error: error);
            }
          },
        );
  }

  bool _current(int epoch) =>
      ref.mounted &&
      epoch == _epoch &&
      !ref.read(appLockProvider).locked &&
      _visible;
  Future<void> refresh() async {
    if (state.query case final query?) await configure(query, force: true);
  }

  Future<void> visible(bool visible) async {
    if (_visible == visible) return;
    _visible = visible;
    if (!visible) {
      _epoch++;
      await _subscription?.cancel();
      _subscription = null;
    } else if (state.query case final query?) {
      await configure(query, force: true);
    }
  }
}

class ChartContextRequest {
  ChartContextRequest(this.query, this.revision);
  final ChartQuery query;
  final int revision;
  @override
  bool operator ==(Object other) =>
      other is ChartContextRequest &&
      other.query.identity == query.identity &&
      other.revision == revision;
  @override
  int get hashCode => Object.hash(query.identity, revision);
}

final chartContextProvider = FutureProvider.autoDispose
    .family<ChartContextBatch?, ChartContextRequest>((ref, request) async {
      if (ref.watch(appLockProvider.select((value) => value.locked))) {
        return null;
      }
      return (await ref.watch(recordStoreProvider.future))
          .chartContext(request.query);
    });

class ChartPageRequest {
  ChartPageRequest(this.request, this.cursor, {this.revision = 0});
  final ChartDrilldownRequest request;
  final ChartDrilldownCursor? cursor;
  final int revision;
  @override
  bool operator ==(Object other) =>
      other is ChartPageRequest &&
      other.request.identity == request.identity &&
      other.cursor?.encode() == cursor?.encode() &&
      other.revision == revision;
  @override
  int get hashCode => Object.hash(request.identity, cursor?.encode(), revision);
}

final chartSourcePageProvider = FutureProvider.autoDispose
    .family<ChartDrilldownPage?, ChartPageRequest>((ref, request) async {
      if (ref.watch(appLockProvider.select((value) => value.locked))) {
        return null;
      }
      return (await ref.watch(recordStoreProvider.future))
          .chartDrilldown(request.request, cursor: request.cursor);
    });

/// Exact display: finite decimals are retained; non-terminating values use an
/// exact fraction, never an approximate total presented without qualification.
String chartExactAmount(ExactAmount amount) {
  final decimal = amount.roundedDecimal(places: 12);
  final pieces = decimal.split('.');
  final represented = ExactAmount(
    BigInt.parse(pieces.join()),
    BigInt.from(10).pow(12),
  );
  if (represented != amount) return '${amount.numerator}/${amount.denominator}';
  return decimal
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

Map<int, int> chartUnknownCounts(
  ChartObservationBatch batch,
  ChartSeriesKey key,
  ChartViewport viewport,
) {
  final counts = <int, int>{};
  if (key.subject.kind != ChartSubjectKind.ingredient) return counts;
  for (final observation in batch.observations) {
    if (observation.isVoided) continue;
    final unknown =
        observation.product?.label.components.any(
          (component) =>
              component.ingredientId == key.subject.id &&
              component.massUnit == key.unit &&
              (component.concentrationText == null ||
                  component.massUnit != 'mg' ||
                  component.volumeUnit != 'ml'),
        ) ??
        false;
    if (!unknown) continue;
    final index = viewport.indexOf(observation.occurredAt);
    if (index >= 0) {
      counts.update(index, (count) => count + 1, ifAbsent: () => 1);
    }
  }
  return counts;
}
