import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';

EventRecord cycle({
  EventDate? start,
  EventDate? end,
  bool completed = false,
  EventDate? actualEnd,
  String zone = 'Europe/London',
}) => EventRecord(
  id: 'cycle',
  personId: meId,
  name: 'Fixture',
  eventType: 'cycle',
  zoneId: zone,
  revision: 1,
  plannedStart: start,
  plannedEnd: end,
  completed: completed,
  actualEnd: actualEnd,
);
EventDate day(String value) => EventDate.day(CivilDate.parse(value));

void main() {
  test('date-only timing includes the final day across DST', () {
    final event = cycle(start: day('2026-03-28'), end: day('2026-03-29'));
    expect(cycleTiming(event, DateTime.utc(2026, 3, 29, 12)), (
      elapsed: 1,
      remaining: 1,
      startsIn: null,
    ));
    expect(cycleTiming(event, DateTime.utc(2026, 3, 29, 23)), (
      elapsed: 2,
      remaining: 0,
      startsIn: null,
    ));
  });
  test('open and future periods avoid invented remaining lengths', () {
    expect(
      cycleTiming(
        cycle(start: day('2026-10-01')),
        DateTime.utc(2026, 10, 19, 12),
      ),
      (elapsed: 18, remaining: null, startsIn: null),
    );
    expect(
      cycleTiming(
        cycle(start: day('2026-10-21')),
        DateTime.utc(2026, 10, 19, 12),
      ),
      (elapsed: null, remaining: null, startsIn: 2),
    );
  });
  test('exact timing counts full elapsed and started remaining days', () {
    final event = cycle(
      start: EventDate.exact(DateTime.utc(2026, 10, 1, 12)),
      end: EventDate.exact(DateTime.utc(2026, 10, 3, 12)),
    );
    expect(cycleTiming(event, DateTime.utc(2026, 10, 2, 13)), (
      elapsed: 1,
      remaining: 1,
      startsIn: null,
    ));
    expect(cycleTiming(event, DateTime.utc(2026, 10, 5)), (
      elapsed: 2,
      remaining: 0,
      startsIn: null,
    ));
  });
  test('partial and completed periods do not invent an ending', () {
    final partial = EventDate(
      precision: EventDatePrecision.month,
      value: '2026-10',
    );
    for (final event in [
      cycle(start: partial),
      cycle(start: day('2026-10-01'), end: partial),
      cycle(start: day('2026-10-01'), completed: true),
    ]) {
      expect(cycleTiming(event, DateTime.utc(2026, 10, 19)), (
        elapsed: null,
        remaining: null,
        startsIn: null,
      ));
    }
  });
}
