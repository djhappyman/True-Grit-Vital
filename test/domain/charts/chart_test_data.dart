import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/charts/charts.dart';
import 'package:true_grit_vital/domain/products/products.dart';
import 'package:true_grit_vital/domain/stock/exact_amount.dart';

Matcher chartModelError(String code) => throwsA(
  isA<ChartModelException>().having((error) => error.code, 'code', code),
);

Matcher chartRangeError(String code) => throwsA(
  isA<ChartRangeException>().having((error) => error.code, 'code', code),
);

ChartObservation chartObservation({
  String record = 'record-1',
  int revision = 1,
  String person = 'me',
  String item = 'item-1',
  String itemName = 'Test item',
  String amount = '1',
  String unit = 'mg',
  DateTime? at,
  String? enteredAmount,
  String? enteredUnit,
  String? typeId,
  String? typeName,
  ProductAdministrationSnapshot? product,
  bool voided = false,
  String? combinedActionId,
}) => ChartObservation(
  source: ChartSourceRef(
    recordId: record,
    revision: revision,
    combinedActionId: combinedActionId,
  ),
  personId: person,
  itemId: item,
  itemName: itemName,
  amount: ExactAmount.parseEntry(amount),
  unit: unit,
  occurredAt: at ?? DateTime.utc(2026, 10, 19, 8),
  enteredAmountText: enteredAmount,
  enteredUnit: enteredUnit,
  typeId: typeId,
  typeName: typeName,
  product: product,
  isVoided: voided,
);

ProductComponent productComponent(
  String id,
  String name, {
  String? mgPerMl,
  String massUnit = 'mg',
  String volumeUnit = 'ml',
}) => ProductComponent(
  ingredientId: id,
  name: name,
  concentrationText: mgPerMl,
  massUnit: massUnit,
  volumeUnit: volumeUnit,
);

ProductAdministrationSnapshot productSnapshot({
  required String volume,
  required Iterable<ProductComponent> components,
  String person = 'me',
  String item = 'item-1',
}) {
  final label = ProductLabelSnapshot(
    personId: person,
    itemId: item,
    revision: 1,
    components: components,
  );
  return ProductAdministrationSnapshot(
    label: label,
    defaultLabel: label,
    volume: ExactAmount.parseEntry(volume),
  );
}

ChartObservationBatch chartBatch({
  DateTime? from,
  DateTime? before,
  Iterable<ChartObservation> observations = const [],
  String person = 'me',
  int schemaVersion = 17,
  String datasetGeneration = 'generation-1',
  bool truncated = false,
}) => ChartObservationBatch(
  personId: person,
  fromInstant: from ?? DateTime.utc(2026, 10, 19),
  beforeInstant: before ?? DateTime.utc(2026, 10, 22),
  schemaVersion: schemaVersion,
  datasetGeneration: datasetGeneration,
  observations: observations,
  truncated: truncated,
);

ChartViewport chartViewport({
  DateTime? from,
  DateTime? before,
  String zone = 'UTC',
  ChartBucketSize size = ChartBucketSize.day,
}) => ChartViewport(
  fromInstant: from ?? DateTime.utc(2026, 10, 19),
  beforeInstant: before ?? DateTime.utc(2026, 10, 22),
  displayZone: zone,
  bucketSize: size,
);

ChartQuery chartQuery({
  String person = 'me',
  ChartViewport? viewport,
  ChartSeriesKey? focus,
}) => ChartQuery(
  personId: person,
  viewport: viewport ?? chartViewport(),
  focus: focus,
);

ChartModel chartModel({
  ChartQuery? query,
  ChartObservationBatch? batch,
  Iterable<ChartAnnotation> annotations = const [],
  int generation = 1,
}) {
  final resolvedQuery = query ?? chartQuery();
  return ChartModel.build(
    query: resolvedQuery,
    batch:
        batch ??
        chartBatch(
          from: resolvedQuery.viewport.fromInstant,
          before: resolvedQuery.viewport.beforeInstant,
        ),
    generation: generation,
    annotations: annotations,
  );
}

String describeModel(ChartModel model) => [
  for (final series in model.series)
    '${series.key} label=${series.label} '
        'total=${series.total.exactTotal ?? series.total.knownSubtotal} '
        'known=${series.total.knownContributions} '
        'unknown=${series.total.unknownContributions} '
        'points=${[for (final bucket in series.buckets) '${bucket.bounds.fromInstant.toIso8601String()}:'
              '${bucket.amount}@${bucket.contributionCount}'].join(',')}',
].join('|');
