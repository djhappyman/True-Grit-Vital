import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/events/events.dart';
import 'package:true_grit_vital/domain/scheduling/daily_plan.dart';
import 'package:true_grit_vital/domain/scheduling/iana_clock.dart';
import 'package:true_grit_vital/domain/reminders/reminders.dart';

void main() {
  test('review uses actual end, durable completion, then planned end', () {
    final clock = IanaClock();
    final planned = EventRecord(
      id: 'e',
      personId: 'p',
      name: 'Event',
      eventType: 'Course',
      zoneId: 'Europe/London',
      revision: 1,
      plannedEnd: EventDate.day(CivilDate(2026, 11, 1)),
    );
    expect(planned.endReviewAt(clock), DateTime.utc(2026, 11, 2));
    final completed = planned.copyWith(
      completed: true,
      completedAt: DateTime.utc(2026, 10, 19),
    );
    expect(completed.endReviewAt(clock), DateTime.utc(2026, 10, 19));
    expect(
      completed
          .copyWith(actualEnd: EventDate.exact(DateTime.utc(2026, 10, 18)))
          .endReviewAt(clock),
      DateTime.utc(2026, 10, 18),
    );
    expect(
      EventRecord.fromJson(completed.toJson()).completedAt,
      DateTime.utc(2026, 10, 19),
    );
    expect(
      completed
          .copyWith(completed: false, clearCompletedAt: true)
          .endReviewAt(clock),
      DateTime.utc(2026, 11, 2),
    );
  });
  test('event validates its zone without relying on a civil bound', () {
    final event = EventRecord(
      id: 'e',
      personId: 'p',
      name: 'Event',
      eventType: 'Course',
      zoneId: 'Europe/Lundon',
      revision: 1,
    );
    expect(
      () => event.validateBounds(IanaClock()),
      throwsA(
        isA<EventBoundaryReview>().having(
          (v) => v.code,
          'code',
          'event_zone_review',
        ),
      ),
    );
    final folded = event.copyWith(
      zoneId: 'America/Havana',
      plannedStart: EventDate.day(CivilDate(2026, 11, 1)),
    );
    expect(
      () => folded.validateBounds(IanaClock()),
      throwsA(
        isA<EventBoundaryReview>().having(
          (v) => v.code,
          'code',
          'event_boundary_review',
        ),
      ),
    );
  });
  test('exact dates reject normalized civil time and offset overflow', () {
    for (final raw in [
      '2026-02-30T12:00:00Z',
      '2026-10-19T24:00:00Z',
      '2026-10-19T12:60:00Z',
      '2026-10-19T12:00:99Z',
      '2026-10-19T12:00:00+24:00',
      '2026-10-19T12:00:00+01:60',
    ]) {
      expect(
        () => EventDate.fromJson({'precision': 'exact', 'value': raw}),
        throwsA(anything),
        reason: raw,
      );
    }
    final raw = '2026-10-19T12:00:59.123456+01:00';
    final valid = EventDate(precision: EventDatePrecision.exact, value: raw);
    expect(
      valid.resolve(IanaClock(), 'Europe/London'),
      DateTime.utc(2026, 10, 19, 11, 0, 59, 123, 456),
    );
    expect(
      EventDate.exact(DateTime.utc(2026, 10, 19)).value,
      '2026-10-19T00:00:00.000Z',
    );
  });

  final clock = IanaClock();
  EventRecord event({
    List<EventMembership>? memberships,
    String person = 'p',
  }) => EventRecord(
    id: 'a',
    personId: person,
    name: 'Course',
    eventType: 'Prescription',
    zoneId: 'Europe/London',
    revision: 1,
    plannedStart: EventDate.day(CivilDate(2026, 10, 1)),
    plannedEnd: EventDate.day(CivilDate(2026, 10, 25)),
    memberships:
        memberships ??
        [
          EventMembership(
            id: 'm',
            itemId: 'i',
            personId: 'p',
            effectiveFrom: DateTime.utc(2026, 10, 10),
            effectiveUntil: DateTime.utc(2026, 10, 20),
            revision: 1,
          ),
        ],
  );
  test('saved London inclusive final day includes its 25-hour civil day', () {
    final start = EventDate.day(CivilDate(2026, 10, 25))
        .resolve(clock, 'Europe/London')!;
    final end = event().endReviewAt(clock)!;
    expect(end, DateTime.utc(2026, 10, 26));
    expect(end.difference(start), const Duration(hours: 25));
  });
  test('membership retains removed history and actual corrections change inclusion', () {
    final e = event();
    bool includes(int day) => e.includes(
      ownerId: 'p',
      itemId: 'i',
      actualAt: DateTime.utc(2026, 10, day),
      clock: clock,
    );
    expect(includes(9), false);
    expect(includes(11), true);
    expect(includes(15), true);
    expect(includes(20), false);
    expect(
      e.includes(
        ownerId: 'other',
        itemId: 'i',
        actualAt: DateTime.utc(2026, 10, 15),
        clock: clock,
      ),
      false,
    );
    expect(() => event(person: 'other'), throwsArgumentError);
  });
  test('event codec retains planned and actual boundaries separately', () {
    final original = EventRecord(
      id: 'a',
      personId: 'p',
      name: 'Course',
      eventType: 'Cycle',
      zoneId: 'Europe/London',
      revision: 2,
      completed: true,
      plannedEnd: EventDate.day(CivilDate(2026, 10, 25)),
      actualEnd: EventDate.exact(DateTime.utc(2026, 10, 20)),
    );
    final reopened = EventRecord.fromJson(original.toJson());
    expect(reopened.toJson(), original.toJson());
    expect(reopened.plannedEnd!.precision, EventDatePrecision.day);
    expect(reopened.actualEnd!.precision, EventDatePrecision.exact);
  });
  test('unknown, partial and open use periods have no fabricated duration', () {
    final p = RecordedUsePeriod(
      id: 'u',
      personId: 'p',
      itemId: 'i',
      revision: 1,
      start: EventDate.unknown(),
      firstEver: true,
    );
    expect(p.duration(clock, 'Europe/London'), null);
    expect(
      RecordedUsePeriod.fromJson(p.toJson()).start.precision,
      EventDatePrecision.unknown,
    );
    expect(
      EventDate(
        precision: EventDatePrecision.month,
        value: '2026-10',
      ).resolve(clock, 'Europe/London'),
      null,
    );
    expect(
      () => EventDate(precision: EventDatePrecision.month, value: '2026-13'),
      throwsArgumentError,
    );
  });
  test(
    'review pool is bounded and globally ordered independently of dose pools',
    () {
      final requests = List.generate(
        10,
        (i) => EventEndReminder(
          requestToken: 'r$i',
          takenToken: 't$i',
          snoozeToken: 's$i',
          skipToken: 'k$i',
          generation: 'g',
          namespace: 'n',
          eventId: 'e$i',
          personId: 'p',
          eventRevision: 1,
          personRevision: 1,
          deadlineMilliseconds: 10000 - i,
          repairState: ReminderRepairState.pending,
        ),
      );
      final result = allocateEventEndReminders(requests);
      expect(result.selected.length, 8);
      expect(result.excluded.length, 2);
      expect(result.selected.first.requestToken, 'r9');
    },
  );
  test(
    'folded civil midnight requires review instead of selecting an instant',
    () {
      expect(
        () =>
            EventDate.day(CivilDate(2026, 11, 1))
                .resolve(clock, 'America/Havana'),
        throwsStateError,
      );
    },
  );
  test('protected command codec retains owner and revision fences', () {
    final command = SaveEventCommand(
      commandId: 'c',
      generation: 'g',
      expectedRevision: 1,
      expectedPersonRevision: 4,
      event: event().copyWith(revision: 2, endReviewDismissed: true),
    );
    final reopened = SaveEventCommand.fromJson(command.toJson());
    expect(reopened.toJson(), command.toJson());
    expect(reopened.expectedPersonRevision, 4);
    expect(
      reopened.event.memberships.single.effectiveUntil,
      DateTime.utc(2026, 10, 20),
    );
  });
  test('a recorded stop cannot precede its equally precise start', () {
    expect(
      () => RecordedUsePeriod(
        id: 'u',
        personId: 'p',
        itemId: 'i',
        revision: 1,
        start: EventDate.day(CivilDate(2026, 10, 20)),
        end: EventDate.day(CivilDate(2026, 10, 19)),
      ),
      throwsArgumentError,
    );
  });
  test('overlapping membership rejects accidental ambiguous association', () {
    expect(
      () => event(
        memberships: [
          EventMembership(
            id: 'm1',
            itemId: 'i',
            personId: 'p',
            effectiveFrom: DateTime.utc(2026),
            revision: 1,
          ),
          EventMembership(
            id: 'm2',
            itemId: 'i',
            personId: 'p',
            effectiveFrom: DateTime.utc(2026, 10),
            revision: 1,
          ),
        ],
      ),
      throwsArgumentError,
    );
  });
}
