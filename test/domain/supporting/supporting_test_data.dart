import 'package:true_grit_vital/domain/supporting/supporting.dart';
export 'package:true_grit_vital/domain/supporting/supporting.dart';

SupportingProvenance provenance({
  String? lab = 'lab',
  String? method = 'method',
  String? specimen = 'specimen',
}) => SupportingProvenance(
  mode: SupportingProvenanceMode.manualTranscription,
  laboratoryId: lab,
  laboratoryName: 'Saved laboratory',
  methodId: method,
  methodText: 'Saved method',
  specimenId: specimen,
  specimenText: 'Saved specimen',
);
LabResultSnapshot result({
  String id = 'row',
  String metric = 'metric',
  String text = '1',
  String? unit = 'mg/dL',
  SupportingValue? value,
  SupportingProvenance? source,
  SourceReferenceRange? range,
}) => LabResultSnapshot(
  id: id,
  metricId: metric,
  markerName: 'Saved marker',
  originalMarkerText: 'Original marker name',
  value: value ?? SupportingValue.numeric(text),
  unit: unit,
  referenceRange: range,
  provenance: source,
);
SupportingRevision record({
  String id = 'record',
  String person = 'me',
  SupportingDate? collection,
  SupportingDate? report,
  List<LabResultSnapshot>? results,
  SupportingProvenance? source,
  bool voided = false,
  int revision = 1,
  DateTime? entered,
  DateTime? corrected,
}) => SupportingRevision(
  snapshot: LabPanelSnapshot(
    id: SupportingRecordId(id: id, personId: person),
    title: 'Saved panel',
    collectionDate: collection ?? SupportingDate.day(CivilDate(2026, 10, 1)),
    reportDate: report ?? SupportingDate.day(CivilDate(2026, 10, 4)),
    provenance: source ?? provenance(),
    results: results ?? [result()],
  ),
  revision: revision,
  operationId: 'operation_$id',
  enteredAt: entered ?? DateTime.utc(2026, 10, 19),
  revisionEnteredAt: corrected ?? entered ?? DateTime.utc(2026, 10, 19),
  isVoided: voided,
);
SupportingTrendQuery query({
  String person = 'me',
  String metric = 'metric',
  SupportingDateBasis basis = SupportingDateBasis.collection,
  String zone = 'UTC',
  String? group,
}) => SupportingTrendQuery(
  personId: person,
  metricId: metric,
  fromDate: CivilDate(2026, 10, 1),
  beforeDate: CivilDate(2026, 11, 1),
  dateBasis: basis,
  displayZone: zone,
  comparisonGroup: group,
);
SupportingTrendPage trend(
  Iterable<SupportingRevision> records, {
  SupportingTrendQuery? request,
}) => SupportingTrendPage.build(
  query: request ?? query(),
  records: records,
  schemaVersion: 19,
  datasetGeneration: 'dataset',
  requestGeneration: 1,
);
