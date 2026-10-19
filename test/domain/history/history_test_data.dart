import 'package:true_grit_vital/domain/records.dart';
import 'package:true_grit_vital/domain/scheduling/daily_plan.dart';
import 'package:true_grit_vital/domain/scheduling/iana_clock.dart';
import 'package:true_grit_vital/domain/scheduling/stored_daily.dart';

UseRecord testRecord({
  String id = 'record-1',
  String person = 'me',
  String item = 'item-1',
  String name = 'Test item',
  String type = 'medication',
  String unit = 'mg',
  String amount = '1',
  DateTime? actualAt,
  DateTime? enteredAt,
  bool voided = false,
  String? combinedActionId,
}) => UseRecord(
  id: id,
  personId: person,
  itemId: item,
  name: name,
  form: 'tablet',
  unit: unit,
  type: type,
  enteredAmount: amount,
  actualAt: actualAt ?? DateTime.utc(2026, 10, 19, 8),
  enteredAt: enteredAt ?? DateTime.utc(2026, 10, 19, 8, 1),
  revision: 1,
  isVoided: voided,
  combinedActionId: combinedActionId,
);

DailyExpectation exactExpectation({
  String person = 'me',
  String item = 'item-1',
  String plan = 'plan-1',
  CivilDate? originalDate,
  CivilDate? effectiveDate,
  DateTime? instant,
  String zone = 'Europe/London',
}) {
  final date = originalDate ?? CivilDate(2026, 10, 19);
  final at = instant ?? DateTime.utc(2026, 10, 19, 8);
  return DailyExpectation(
    identity: DailyIdentity(
      personId: person,
      planId: plan,
      originalDate: date,
      slotId: 'slot-1',
    ),
    itemId: item,
    versionId: 'version-1',
    zoneId: zone,
    amount: PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
    resolution: DailyResolution.exact,
    calculatorVersion: 'calculator-1',
    timezoneDataVersion: IanaClock.dataVersion,
    originalTime: WallTime(9, 0),
    effectiveTime: WallTime(9, 0),
    instant: at,
    effectiveDate: effectiveDate,
    clockCandidates: [at],
  );
}

DailyExpectation untimedExpectation({
  String person = 'me',
  String item = 'item-1',
  String plan = 'plan-1',
  CivilDate? originalDate,
  CivilDate? effectiveDate,
  String zone = 'UTC',
}) => DailyExpectation(
  identity: DailyIdentity(
    personId: person,
    planId: plan,
    originalDate: originalDate ?? CivilDate(2026, 10, 19),
  ),
  itemId: item,
  versionId: 'version-1',
  zoneId: zone,
  amount: PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
  resolution: DailyResolution.untimed,
  calculatorVersion: 'calculator-1',
  timezoneDataVersion: IanaClock.dataVersion,
  plannedCount: 1,
  effectiveDate: effectiveDate,
);

DailyExpectation missingClockExpectation({
  String person = 'me',
  String item = 'item-1',
  String plan = 'plan-1',
  CivilDate? originalDate,
  CivilDate? effectiveDate,
  String zone = 'Europe/London',
}) => DailyExpectation(
  identity: DailyIdentity(
    personId: person,
    planId: plan,
    originalDate: originalDate ?? CivilDate(2026, 10, 25),
    slotId: 'slot-1',
  ),
  itemId: item,
  versionId: 'version-1',
  zoneId: zone,
  amount: PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
  resolution: DailyResolution.missingClock,
  calculatorVersion: 'calculator-1',
  timezoneDataVersion: IanaClock.dataVersion,
  originalTime: WallTime(1, 30),
  effectiveTime: WallTime(1, 30),
  effectiveDate: effectiveDate,
);

DailyExpectation repeatedClockExpectation({
  String person = 'me',
  String item = 'item-1',
  String plan = 'plan-1',
  CivilDate? originalDate,
  CivilDate? effectiveDate,
  String zone = 'Europe/London',
}) {
  final date = originalDate ?? CivilDate(2026, 10, 25);
  return DailyExpectation(
    identity: DailyIdentity(
      personId: person,
      planId: plan,
      originalDate: date,
      slotId: 'slot-1',
    ),
    itemId: item,
    versionId: 'version-1',
    zoneId: zone,
    amount: PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
    resolution: DailyResolution.repeatedClock,
    calculatorVersion: 'calculator-1',
    timezoneDataVersion: IanaClock.dataVersion,
    originalTime: WallTime(1, 30),
    effectiveTime: WallTime(1, 30),
    clockCandidates: [
      DateTime.utc(2026, 10, 25, 0, 30),
      DateTime.utc(2026, 10, 25, 1, 30),
    ],
    effectiveDate: effectiveDate,
  );
}

DailyExpectation noAlertExpectation({
  String person = 'me',
  String item = 'item-1',
  String plan = 'plan-1',
  CivilDate? originalDate,
  CivilDate? effectiveDate,
  String zone = 'Europe/London',
}) => DailyExpectation(
  identity: DailyIdentity(
    personId: person,
    planId: plan,
    originalDate: originalDate ?? CivilDate(2026, 10, 19),
    slotId: 'slot-1',
  ),
  itemId: item,
  versionId: 'version-1',
  zoneId: zone,
  amount: PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
  resolution: DailyResolution.noAlert,
  calculatorVersion: 'calculator-1',
  timezoneDataVersion: IanaClock.dataVersion,
  originalTime: WallTime(9, 0),
  effectiveTime: WallTime(9, 0),
  effectiveDate: effectiveDate,
);

DailyAction skipAction({
  String id = 'skip-1',
  bool undone = false,
  String? recordId,
  DateTime? recordedAt,
}) => DailyAction(
  id: id,
  kind: DailyActionKind.skip,
  revision: 1,
  isUndone: undone,
  sequence: 1,
  recordedAt: recordedAt ?? DateTime.utc(2026, 10, 19, 9),
  recordId: recordId,
);

DailyAction takenAction({
  String id = 'taken-1',
  String recordId = 'record-1',
}) => DailyAction(
  id: id,
  kind: DailyActionKind.taken,
  revision: 1,
  isUndone: false,
  sequence: 1,
  recordedAt: DateTime.utc(2026, 10, 19, 9),
  recordId: recordId,
);
