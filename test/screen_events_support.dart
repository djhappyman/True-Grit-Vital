import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';

import 'vital_app_test.dart' show runIo;

const screenEventsZone = 'Europe/London';

DateTime screenEventsNow() => DateTime.utc(2026, 10, 24, 11, 55);

Future<SubstanceItem> screenEventItem(
  WidgetTester tester,
  RecordStore store,
  String name, {
  String unit = 'mg',
  String type = 'Prescription',
}) async => (await runIo(
  tester,
  () => store.createItem(
    commandId: newCommandId(),
    expectedPersonRevision: 2,
    name: name,
    form: 'Tablet',
    unit: unit,
    type: type,
  ),
))!;

Future<EventRecord> screenEvent(
  WidgetTester tester,
  RecordStore store, {
  required String id,
  required String name,
  required String type,
  required EventDate? start,
  EventDate? end,
  bool completed = false,
  List<SubstanceItem> items = const [],
  DateTime? memberFrom,
}) async {
  final event = EventRecord(
    id: id,
    personId: meId,
    name: name,
    eventType: type,
    zoneId: screenEventsZone,
    revision: 1,
    plannedStart: start,
    plannedEnd: end,
    completed: completed,
    memberships: [
      for (final (index, item) in items.indexed)
        EventMembership(
          id: 'member-$id-$index',
          itemId: item.id,
          personId: meId,
          effectiveFrom: memberFrom ?? DateTime.utc(2026, 1, 1),
          revision: 1,
        ),
    ],
  );
  final command = SaveEventCommand(
    commandId: newCommandId(),
    generation: store.generation,
    expectedRevision: null,
    expectedPersonRevision: (await runIo(
      tester,
      () => store.profileById(meId),
    ))!.revision,
    event: event,
  );
  return (await runIo(
    tester,
    () async => store.saveEvent(
      command,
      membershipReview: await store.previewEventMembership(command),
    ),
  ))!;
}

EventDate screenEventDay(int year, int month, int day) =>
    EventDate.day(CivilDate(year, month, day));

/// Four recorded events spanning active, upcoming and completed states.
/// Names, units and ranges are synthetic; no clinical meaning is implied.
Future<void> seedScreenEvents(WidgetTester tester, RecordStore store) async {
  final telmisartan = await screenEventItem(tester, store, 'Telmisartan');
  final vitaminD = await screenEventItem(
    tester,
    store,
    'Vitamin D3 + K2',
    type: 'Supplement',
  );
  final omega = await screenEventItem(
    tester,
    store,
    'Omega-3 EPA/DHA',
    type: 'Supplement',
  );
  final zinc = await screenEventItem(
    tester,
    store,
    'Zinc Picolinate',
    type: 'Supplement',
  );
  final curcumin = await screenEventItem(
    tester,
    store,
    'Curcumin',
    type: 'Supplement',
  );
  final collagen = await screenEventItem(
    tester,
    store,
    'Collagen Peptides',
    type: 'Supplement',
  );
  await screenEvent(
    tester,
    store,
    id: 'a-hypertension',
    name: 'Hypertension Management 2026',
    type: 'prescription',
    start: screenEventDay(2025, 1, 15),
    items: [telmisartan],
    memberFrom: DateTime.utc(2025, 1, 15),
  );
  await screenEvent(
    tester,
    store,
    id: 'b-autumn',
    name: 'Autumn Immunity & Recovery Cycle',
    type: 'cycle',
    start: screenEventDay(2026, 10, 1),
    end: screenEventDay(2026, 11, 30),
    items: [vitaminD, omega, zinc],
    memberFrom: DateTime.utc(2026, 10, 1),
  );
  await screenEvent(
    tester,
    store,
    id: 'c-winter',
    name: 'Winter Joint Protocol',
    type: 'cycle',
    start: screenEventDay(2026, 12, 1),
    end: screenEventDay(2027, 2, 28),
    items: [curcumin, collagen],
    memberFrom: DateTime.utc(2026, 12, 1),
  );
  await screenEvent(
    tester,
    store,
    id: 'd-summer',
    name: 'Summer Endurance Prep',
    type: 'cycle',
    start: screenEventDay(2026, 6, 1),
    end: screenEventDay(2026, 8, 31),
    completed: true,
    items: [vitaminD],
    memberFrom: DateTime.utc(2026, 6, 1),
  );
}

/// One event whose planned end has passed without a completion mark. Its end
/// review stays due until the record changes or the review is dismissed.
Future<void> seedEndedScreenEvent(
  WidgetTester tester,
  RecordStore store,
) async {
  final item = await screenEventItem(tester, store, 'Telmisartan');
  await screenEvent(
    tester,
    store,
    id: 'ended-review',
    name: 'Ended Review Course',
    type: 'prescription',
    start: screenEventDay(2026, 9, 1),
    end: screenEventDay(2026, 10, 20),
    items: [item],
    memberFrom: DateTime.utc(2026, 9, 1),
  );
}
