import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/records.dart';
import 'package:true_grit_vital/domain/scheduling/daily_plan.dart';
import 'package:true_grit_vital/domain/scheduling/daily_resolver.dart';
import 'package:true_grit_vital/domain/scheduling/iana_clock.dart';
import 'package:true_grit_vital/domain/scheduling/phase_plan.dart';

PlannedAmount amount([String value = '1']) =>
    PlannedAmount(quantity: ExactQuantity.parse(value), unit: 'tablet');
DailyPlanVersion phase(
  String id,
  CivilDate start, {
  CivilDate? end,
  DailyTiming? timing,
  CalendarPattern calendar = const EveryDay(),
  List<PlanPause> pauses = const [],
  DateTime? effectiveFrom,
  DateTime? effectiveUntil,
}) => DailyPlanVersion(
  personId: 'person',
  planId: 'plan',
  itemId: 'item',
  versionId: id,
  start: start,
  endExclusive: end,
  timing:
      timing ??
      DailySlots([
        DailySlot(
          id: 'slot',
          time: WallTime(23, 30),
          amount: amount(),
          reminderEnabled: true,
        ),
      ]),
  zoneBasis: FixedHome('Europe/London'),
  calendar: calendar,
  pauses: pauses,
  effectiveFrom: effectiveFrom,
  effectiveUntil: effectiveUntil,
);
void main() {
  final resolver = PhaseResolver(strictOverrides: true);
  final october = CivilDate(2026, 10, 31), november = CivilDate(2026, 11, 1);
  DailyExpansion expand(
    PhasePlan plan, {
    CivilDate? from,
    CivilDate? to,
    int maxDates = 20,
    int maxRows = 100,
  }) => resolver.expand(
    plan,
    from: from ?? october,
    toExclusive: to ?? CivilDate(2026, 11, 3),
    observedZone: 'Pacific/Auckland',
    maxDates: maxDates,
    maxRows: maxRows,
  );
  final originalIdentity = DailyIdentity(
    personId: 'person',
    planId: 'plan',
    originalDate: october,
    slotId: 'slot',
  );
  test('phases reject overlap and preserve deliberate gaps', () {
    expect(
      () => PhasePlan(phases: [phase('a', october), phase('b', november)]),
      throwsArgumentError,
    );
    final rows = expand(
      PhasePlan(
        phases: [
          phase('a', october, end: november),
          phase('b', CivilDate(2026, 11, 2)),
        ],
      ),
    ).rows;
    expect(rows.map((r) => r.identity.originalDate), [
      october,
      CivilDate(2026, 11, 2),
    ]);
  });
  test('same-day exact versions preserve two disjoint segments', () {
    final date = CivilDate(2026, 10, 20);
    final rows = expand(
      PhasePlan(
        phases: [
          phase(
            'a',
            date,
            effectiveUntil: DateTime.utc(2026, 10, 20, 12),
            timing: DailySlots([
              DailySlot(
                id: 'morning',
                time: WallTime(9, 0),
                amount: amount(),
                reminderEnabled: false,
              ),
            ]),
          ),
          phase('b', date, effectiveFrom: DateTime.utc(2026, 10, 20, 12)),
        ],
      ),
      from: date,
      to: date.addDays(1),
    ).rows;
    expect(rows.map((r) => r.versionId), ['a', 'b']);
  });
  test('move across phase retains original identity and quantity', () {
    final plan = PhasePlan(
      phases: [
        phase('a', october, end: november),
        phase(
          'b',
          november,
          timing: DailySlots([
            DailySlot(
              id: 'slot',
              time: WallTime(23, 30),
              amount: amount('2'),
              reminderEnabled: true,
            ),
          ]),
        ),
      ],
      overrides: [
        OccurrenceOverride(
          identity: originalIdentity,
          versionId: 'a',
          targetInstant: DateTime.utc(2026, 11, 1, 0, 30),
          targetZoneId: 'Europe/London',
        ),
      ],
    );
    final rows = expand(plan, from: november, to: november.addDays(1)).rows;
    expect(rows.length, 2);
    expect(rows.first.identity, originalIdentity);
    expect(rows.first.amount.quantity.canonical, '1');
    expect(rows.first.originalInstant, DateTime.utc(2026, 10, 31, 23, 30));
    expect(rows.last.amount.quantity.canonical, '2');
  });
  test('explicit amount override changes only selected occurrence', () {
    final rows = expand(
      PhasePlan(
        phases: [phase('a', october)],
        overrides: [
          OccurrenceOverride(
            identity: originalIdentity,
            versionId: 'a',
            amount: amount('3'),
          ),
        ],
      ),
    ).rows;
    expect(rows.first.amount.quantity.canonical, '3');
    expect(rows.first.originalAmount!.quantity.canonical, '1');
    expect(rows.last.amount.quantity.canonical, '1');
  });
  test('collisions stay separate and require explicit acknowledgement', () {
    PhasePlan plan(bool review) => PhasePlan(
      phases: [phase('a', october)],
      overrides: [
        OccurrenceOverride(
          identity: originalIdentity,
          versionId: 'a',
          targetInstant: DateTime.utc(2026, 11, 1, 23, 30),
          targetZoneId: 'Europe/London',
          reviewedCollisions: review
              ? [
                  DailyIdentity(
                    personId: 'person',
                    planId: 'plan',
                    originalDate: november,
                    slotId: 'slot',
                  ),
                ]
              : [],
        ),
      ],
    );
    expect(() => expand(plan(false)), throwsArgumentError);
    final rows = expand(plan(true)).rows
        .where((r) => r.instant == DateTime.utc(2026, 11, 1, 23, 30))
        .toList();
    expect(rows.length, 2);
    expect(rows.first.identity, isNot(rows.last.identity));
  });
  test('saved last date includes the complete 25-hour day', () {
    final clock = IanaClock();
    final last = CivilDate(2026, 10, 25);
    final end = PlanEnd.onDate(
      lastDate: last,
      zoneId: 'Europe/London',
      clock: clock,
    );
    expect(
      end.exclusiveInstant
          .difference(
            clock.candidates(last, WallTime(0, 0), 'Europe/London').single,
          )
          .inHours,
      25,
    );
    final rows = expand(
      PhasePlan(phases: [phase('a', last)], end: end),
      from: last,
      to: last.addDays(2),
    ).rows;
    expect(rows.length, 1);
    expect(rows.single.identity.originalDate, last);
  });
  test('saved last date includes the complete 23-hour day', () {
    final clock = IanaClock();
    final last = CivilDate(2026, 3, 29);
    final end = PlanEnd.onDate(
      lastDate: last,
      zoneId: 'Europe/London',
      clock: clock,
    );
    expect(
      end.exclusiveInstant
          .difference(
            clock.candidates(last, WallTime(0, 0), 'Europe/London').single,
          )
          .inHours,
      23,
    );
  });
  test('exact end is exclusive and move cannot escape it', () {
    final end = PlanEnd(
      zoneId: 'Europe/London',
      exclusiveInstant: DateTime.utc(2026, 10, 31, 23, 30),
    );
    expect(
      expand(PhasePlan(phases: [phase('a', october)], end: end)).rows,
      isEmpty,
    );
    final plan = PhasePlan(
      phases: [phase('a', october)],
      end: PlanEnd(
        zoneId: 'Europe/London',
        exclusiveInstant: DateTime.utc(2026, 11, 1),
      ),
      overrides: [
        OccurrenceOverride(
          identity: originalIdentity,
          versionId: 'a',
          targetInstant: DateTime.utc(2026, 11, 1),
          targetZoneId: 'Europe/London',
        ),
      ],
    );
    expect(() => expand(plan), throwsArgumentError);
  });
  test('paused origin cannot be moved out and target cannot enter pause', () {
    final pause = PlanPause(
      start: DateTime.utc(2026, 10, 31, 23),
      resume: DateTime.utc(2026, 11, 1),
    );
    expect(
      () => expand(
        PhasePlan(
          phases: [
            phase('a', october, pauses: [pause]),
          ],
          overrides: [
            OccurrenceOverride(
              identity: originalIdentity,
              versionId: 'a',
              targetInstant: DateTime.utc(2026, 11, 1, 1),
              targetZoneId: 'Europe/London',
            ),
          ],
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => expand(
        PhasePlan(
          phases: [
            phase(
              'a',
              october,
              pauses: [
                PlanPause(
                  start: DateTime.utc(2026, 11, 1),
                  resume: DateTime.utc(2026, 11, 2),
                ),
              ],
            ),
          ],
          overrides: [
            OccurrenceOverride(
              identity: originalIdentity,
              versionId: 'a',
              targetInstant: DateTime.utc(2026, 11, 1, 1),
              targetZoneId: 'Europe/London',
            ),
          ],
        ),
      ),
      throwsArgumentError,
    );
  });
  test('cross-midnight window keeps original date and explicit anchor', () {
    final rows = expand(
      PhasePlan(
        phases: [
          phase(
            'a',
            october,
            timing: DailyWindows(
              windows: [
                DailyWindow(
                  id: 'window',
                  start: WallTime(23, 0),
                  end: WallTime(1, 0),
                  amount: amount(),
                  reminderAnchor: WallTime(0, 30),
                  reminderEnabled: true,
                ),
              ],
            ),
          ),
        ],
      ),
      to: november,
    ).rows;
    final row = rows.single;
    expect(row.identity.originalDate, october);
    expect(row.windowStart, DateTime.utc(2026, 10, 31, 23));
    expect(row.windowEnd, DateTime.utc(2026, 11, 1, 1));
    expect(row.instant, DateTime.utc(2026, 11, 1, 0, 30));
  });
  test(
    'window without anchor invents no administration or reminder instant',
    () {
      final row = expand(
        PhasePlan(
          phases: [
            phase(
              'a',
              october,
              timing: DailyWindows(
                windows: [
                  DailyWindow(
                    id: 'window',
                    start: WallTime(23, 0),
                    end: WallTime(1, 0),
                    amount: amount(),
                  ),
                ],
              ),
            ),
          ],
        ),
        to: november,
      ).rows.single;
      expect(row.instant, isNull);
      expect(row.reminderAnchor, isNull);
      expect(
        row.reminderStateAt(DateTime.utc(2026)),
        DailyReminderState.noAlert,
      );
    },
  );
  test('window crossing a hard end is a conflict, not a truncated row', () {
    final plan = PhasePlan(
      phases: [
        phase(
          'a',
          october,
          timing: DailyWindows(
            windows: [
              DailyWindow(
                id: 'w',
                start: WallTime(23, 0),
                end: WallTime(1, 0),
                amount: amount(),
              ),
            ],
          ),
        ),
      ],
      end: PlanEnd(
        zoneId: 'Europe/London',
        exclusiveInstant: DateTime.utc(2026, 11, 1),
      ),
    );
    expect(() => expand(plan, to: november), throwsArgumentError);
  });
  test(
    'window touching pause only at end stays eligible; crossing conflicts',
    () {
      DailyPlanVersion window(DateTime pauseStart) => phase(
        'a',
        october,
        timing: DailyWindows(
          windows: [
            DailyWindow(
              id: 'w',
              start: WallTime(23, 0),
              end: WallTime(1, 0),
              amount: amount(),
            ),
          ],
        ),
        pauses: [PlanPause(start: pauseStart)],
      );
      expect(
        expand(
          PhasePlan(phases: [window(DateTime.utc(2026, 11, 1, 1))]),
          to: november,
        ).rows.length,
        1,
      );
      expect(
        () => expand(
          PhasePlan(phases: [window(DateTime.utc(2026, 11, 1, 0, 30))]),
          to: november,
        ),
        throwsArgumentError,
      );
    },
  );
  test('fold endpoint stays unresolved until an explicit clock instance', () {
    final date = CivilDate(2026, 10, 25);
    final plan = phase(
      'a',
      date,
      timing: DailyWindows(
        windows: [
          DailyWindow(
            id: 'w',
            start: WallTime(0, 30),
            end: WallTime(1, 30),
            amount: amount(),
          ),
        ],
      ),
    );
    final row = DailyResolver()
        .resolveDate(plan, date, observedZone: 'Europe/London')
        .single;
    expect(row.resolution, DailyResolution.repeatedClock);
    expect(row.windowEnd, isNull);
    final endpoint = DailyIdentity(
      personId: 'person',
      planId: 'plan',
      originalDate: date,
      slotId: 'w:end',
    );
    final resolved = DailyResolver()
        .resolveDate(
          plan,
          date,
          observedZone: 'Europe/London',
          decisions: {
            endpoint: DailyClockChoice(
              identity: endpoint,
              versionId: 'a',
              zoneId: 'Europe/London',
              originalTime: WallTime(1, 30),
              decision: const ChooseClockInstance(1),
            ),
          },
        )
        .single;
    expect(resolved.windowEnd, DateTime.utc(2026, 10, 25, 1, 30));
    expect(resolved.instant, isNull);
  });
  test('partially timed count preserves every opportunity without spacing', () {
    final timing = MixedDailyCount(
      count: 4,
      amount: amount(),
      slots: [
        DailySlot(
          id: 'chosen',
          time: WallTime(9, 0),
          amount: amount('2'),
          reminderEnabled: true,
        ),
      ],
    );
    final rows = expand(
      PhasePlan(phases: [phase('a', october, timing: timing)]),
      to: november,
    ).rows;
    expect(rows.length, 2);
    expect(rows.singleWhere((r) => r.identity.slotId == null).plannedCount, 3);
    expect(
      rows
          .singleWhere((r) => r.identity.slotId == 'chosen')
          .amount
          .quantity
          .canonical,
      '2',
    );
    expect(
      () => MixedDailyCount(count: 1, amount: amount(), slots: timing.slots),
      throwsArgumentError,
    );
  });
  test('bounded expansion says incomplete and independent seek reaches distant phase', () {
    final plan = PhasePlan(
      phases: [
        phase('a', CivilDate(2026, 1, 1), end: CivilDate(2026, 1, 2)),
        phase('b', CivilDate(2030, 1, 1)),
      ],
    );
    expect(
      expand(
        plan,
        from: CivilDate(2030, 1, 1),
        to: CivilDate(2030, 2, 1),
        maxDates: 1,
      ).complete,
      isFalse,
    );
    final next = resolver.nextDate(
      plan,
      from: october,
      observedZone: 'Europe/London',
    );
    expect(next.next!.identity.originalDate, CivilDate(2030, 1, 1));
  });
  test('captured past expectations retain their original meaning', () {
    final original = DailyResolver()
        .resolveDate(
          phase('a', october),
          october,
          observedZone: 'Europe/London',
        )
        .single;
    final changed = phase(
      'a',
      october,
      timing: DailySlots([
        DailySlot(
          id: 'slot',
          time: WallTime(12, 0),
          amount: amount('9'),
          reminderEnabled: false,
        ),
      ]),
    );
    final rows = resolver.resolveDate(
      PhasePlan(phases: [changed]),
      october,
      observedZone: 'Europe/London',
      historical: {original.identity: original},
    );
    expect(identical(rows.single, original), isTrue);
  });
  test('independent DST window oracle retains elapsed endpoint meaning', () {
    final cases = [
      (
        CivilDate(2026, 3, 28),
        WallTime(3, 0),
        DateTime.utc(2026, 3, 28, 23),
        DateTime.utc(2026, 3, 29, 2),
      ),
      (
        CivilDate(2026, 10, 24),
        WallTime(2, 0),
        DateTime.utc(2026, 10, 24, 22),
        DateTime.utc(2026, 10, 25, 2),
      ),
    ];
    for (final (date, end, startInstant, endInstant) in cases) {
      final plan = PhasePlan(
        phases: [
          phase(
            'a',
            date,
            timing: DailyWindows(
              windows: [
                DailyWindow(
                  id: 'w',
                  start: WallTime(23, 0),
                  end: end,
                  amount: amount(),
                ),
              ],
            ),
          ),
        ],
      );
      final row = expand(plan, from: date, to: date.addDays(1)).rows.single;
      expect(row.windowStart, startInstant);
      expect(row.windowEnd, endInstant);
    }
  });
  test(
    'mixed counts share one same-day remainder bucket across exact versions',
    () {
      final date = CivilDate(2026, 10, 20);
      final timing = MixedDailyCount(
        count: 3,
        amount: amount(),
        slots: [
          DailySlot(
            id: 'slot',
            time: WallTime(9, 0),
            amount: amount(),
            reminderEnabled: false,
          ),
        ],
      );
      final rows = expand(
        PhasePlan(
          phases: [
            phase(
              'a',
              date,
              timing: timing,
              effectiveUntil: DateTime.utc(2026, 10, 20, 12),
            ),
            phase(
              'b',
              date,
              timing: timing,
              effectiveFrom: DateTime.utc(2026, 10, 20, 12),
            ),
          ],
        ),
        from: date,
        to: date.addDays(1),
      ).rows;
      expect(rows.where((r) => r.identity.slotId == null).length, 1);
      expect(rows.fold(0, (sum, r) => sum + (r.plannedCount ?? 1)), 3);
    },
  );
  test('next date seeks past an original moved out of the requested day', () {
    final plan = PhasePlan(
      phases: [phase('a', october)],
      overrides: [
        OccurrenceOverride(
          identity: originalIdentity,
          versionId: 'a',
          targetInstant: DateTime.utc(2026, 11, 2, 1),
          targetZoneId: 'Europe/London',
        ),
      ],
    );
    final next = resolver.nextDate(
      plan,
      from: october,
      observedZone: 'Europe/London',
    );
    expect(next.next!.identity.originalDate, november);
    expect(next.calendarDate, november);
  });
  test('unsupported timezone range remains explicitly incomplete', () {
    final date = CivilDate(2040, 1, 1);
    final result = expand(
      PhasePlan(phases: [phase('a', date)]),
      from: date,
      to: date.addDays(1),
    );
    expect(result.complete, isFalse);
    expect(result.issue, DailyCalculationIssue.unsupportedTimezoneRange);
  });
  test('host seek jumps decades-old phase without daily replay', () {
    final plan = PhasePlan(
      phases: [
        DailyPlanVersion(
          personId: 'person',
          planId: 'plan',
          itemId: 'item',
          versionId: 'old',
          start: CivilDate(1900, 1, 1),
          endExclusive: CivilDate(1900, 1, 2),
          timing: DailyCount(3, amount()),
          zoneBasis: FixedHome('UTC'),
        ),
        DailyPlanVersion(
          personId: 'person',
          planId: 'plan',
          itemId: 'item',
          versionId: 'future',
          start: CivilDate(2030, 1, 1),
          timing: DailyCount(3, amount()),
          zoneBasis: FixedHome('UTC'),
        ),
      ],
    );
    final watch = Stopwatch()..start();
    var examined = 0;
    for (var i = 0; i < 1000; i++) {
      final result = resolver.nextDate(
        plan,
        from: october,
        observedZone: 'UTC',
      );
      expect(result.next!.identity.originalDate, CivilDate(2030, 1, 1));
      examined += result.datesExamined;
    }
    watch.stop();
    // Host timing is intentional reproducible test evidence.
    // ignore: avoid_print
    print(
      'phase_host seeks=1000 elapsed_us=${watch.elapsedMicroseconds} dates_examined=$examined',
    );
    expect(examined, lessThanOrEqualTo(1000));
  });

  test(
    'window move keeps explicit endpoints, original identity and amount',
    () {
      final origin = DailyWindow(
        id: 'w',
        start: WallTime(23, 0),
        end: WallTime(1, 0),
        amount: amount(),
        reminderAnchor: WallTime(23, 30),
        reminderEnabled: true,
      );
      final identity = DailyIdentity(
        personId: 'person',
        planId: 'plan',
        originalDate: october,
        slotId: 'w',
      );
      final plan = PhasePlan(
        phases: [
          phase(
            'a',
            october,
            end: november.addDays(1),
            timing: DailyWindows(windows: [origin]),
            calendar: SelectedWeekdays([6]),
          ),
        ],
        overrides: [
          OccurrenceOverride(
            identity: identity,
            versionId: 'a',
            windowTarget: WindowOverrideTarget(
              start: DateTime.utc(2026, 11, 2, 20),
              end: DateTime.utc(2026, 11, 2, 22),
              zoneId: 'Europe/London',
              reminderAnchor: DateTime.utc(2026, 11, 2, 21),
            ),
          ),
        ],
      );
      final row = expand(
        plan,
        from: CivilDate(2026, 11, 2),
        to: CivilDate(2026, 11, 3),
      ).rows.single;
      expect(row.identity, identity);
      expect(row.amount.quantity.canonical, '1');
      expect(row.windowStart, DateTime.utc(2026, 11, 2, 20));
      expect(row.windowEnd, DateTime.utc(2026, 11, 2, 22));
      expect(row.instant, DateTime.utc(2026, 11, 2, 21));
      expect(row.originalWindowStart, DateTime.utc(2026, 10, 31, 23));
      expect(row.originalWindowEnd, DateTime.utc(2026, 11, 1, 1));
      final next = resolver.nextDate(
        plan,
        from: november,
        observedZone: 'Europe/London',
      );
      expect(next.calendarDate, CivilDate(2026, 11, 2));
    },
  );
  test('window move cannot infer endpoint or escape pause/end', () {
    final identity = DailyIdentity(
      personId: 'person',
      planId: 'plan',
      originalDate: october,
      slotId: 'w',
    );
    final phaseValue = phase(
      'a',
      october,
      end: november.addDays(1),
      timing: DailyWindows(
        windows: [
          DailyWindow(
            id: 'w',
            start: WallTime(23, 0),
            end: WallTime(1, 0),
            amount: amount(),
          ),
        ],
      ),
    );
    expect(
      () => expand(
        PhasePlan(
          phases: [phaseValue],
          overrides: [
            OccurrenceOverride(
              identity: identity,
              versionId: 'a',
              targetInstant: DateTime.utc(2026, 11, 2, 20),
              targetZoneId: 'Europe/London',
            ),
          ],
        ),
      ),
      throwsArgumentError,
    );
    final plan = PhasePlan(
      phases: [phaseValue],
      end: PlanEnd(
        zoneId: 'UTC',
        exclusiveInstant: DateTime.utc(2026, 11, 2, 21),
      ),
      overrides: [
        OccurrenceOverride(
          identity: identity,
          versionId: 'a',
          windowTarget: WindowOverrideTarget(
            start: DateTime.utc(2026, 11, 2, 20),
            end: DateTime.utc(2026, 11, 2, 22),
            zoneId: 'UTC',
          ),
        ),
      ],
    );
    expect(() => expand(plan), throwsArgumentError);
  });
  test('overlapping moved windows require symmetric explicit review', () {
    final first = DailyIdentity(
      personId: 'person',
      planId: 'plan',
      originalDate: october,
      slotId: 'w',
    );
    final second = DailyIdentity(
      personId: 'person',
      planId: 'plan',
      originalDate: november,
      slotId: 'w',
    );
    PhasePlan plan(bool both) => PhasePlan(
      phases: [
        phase(
          'a',
          october,
          timing: DailyWindows(
            windows: [
              DailyWindow(
                id: 'w',
                start: WallTime(23, 0),
                end: WallTime(1, 0),
                amount: amount(),
              ),
            ],
          ),
        ),
      ],
      overrides: [
        OccurrenceOverride(
          identity: first,
          versionId: 'a',
          windowTarget: WindowOverrideTarget(
            start: DateTime.utc(2026, 11, 2, 20),
            end: DateTime.utc(2026, 11, 2, 22),
            zoneId: 'UTC',
          ),
          reviewedCollisions: both ? [second] : [],
        ),
        OccurrenceOverride(
          identity: second,
          versionId: 'a',
          windowTarget: WindowOverrideTarget(
            start: DateTime.utc(2026, 11, 2, 21),
            end: DateTime.utc(2026, 11, 2, 23),
            zoneId: 'UTC',
          ),
          reviewedCollisions: [first],
        ),
      ],
    );
    expect(
      () => expand(
        plan(false),
        from: CivilDate(2026, 11, 2),
        to: CivilDate(2026, 11, 3),
      ),
      throwsArgumentError,
    );
    expect(
      expand(
        plan(true),
        from: CivilDate(2026, 11, 2),
        to: CivilDate(2026, 11, 3),
      ).rows.length,
      3,
    );
  });
  test('aggregate row budget never emits a partial effective date', () {
    final date = november;
    final plan = PhasePlan(
      phases: [phase('a', october)],
      overrides: [
        OccurrenceOverride(
          identity: originalIdentity,
          versionId: 'a',
          targetInstant: DateTime.utc(2026, 11, 1, 1),
          targetZoneId: 'Europe/London',
        ),
      ],
    );
    final result = expand(plan, from: date, to: date.addDays(1), maxRows: 1);
    expect(result.complete, isFalse);
    expect(result.rows, isEmpty);
    expect(result.resumeDate, date);
  });
  test('archived origin version survives a later pause version edit', () {
    final origin = phase('a', october);
    final plan = PhasePlan(
      phases: [phase('b', october)],
      originPhases: [origin],
      overrides: [
        OccurrenceOverride(
          identity: originalIdentity,
          versionId: 'a',
          amount: amount('2'),
        ),
      ],
    );
    final row = expand(plan, to: november).rows.single;
    expect(row.versionId, 'a');
    expect(row.amount.quantity.canonical, '2');
  });
  test('a later pause suppresses saved move without losing origin history', () {
    final old = phase('a', october);
    final changed = phase(
      'b',
      october,
      pauses: [
        PlanPause(
          start: DateTime.utc(2026, 11, 1),
          resume: DateTime.utc(2026, 11, 2),
        ),
      ],
    );
    final plan = PhasePlan(
      phases: [changed],
      originPhases: [old],
      overrides: [
        OccurrenceOverride(
          identity: originalIdentity,
          versionId: 'a',
          targetInstant: DateTime.utc(2026, 11, 1, 1),
          targetZoneId: 'Europe/London',
        ),
      ],
    );
    final result = PhaseResolver().expand(
      plan,
      from: october,
      toExclusive: CivilDate(2026, 11, 3),
      observedZone: 'Europe/London',
      maxDates: 20,
      maxRows: 100,
    );
    expect(result.complete, isTrue);
    expect(result.rows.any((r) => r.identity == originalIdentity), isFalse);
    expect(result.rows.single.identity.originalDate, CivilDate(2026, 11, 2));
    expect(() => expand(plan), throwsArgumentError);
  });
  test('unavailable override origin returns explicit incomplete result', () {
    final plan = PhasePlan(
      phases: [phase('a', november)],
      overrides: [
        OccurrenceOverride(
          identity: originalIdentity,
          versionId: 'a',
          amount: amount('2'),
        ),
      ],
    );
    final result = PhaseResolver().expand(
      plan,
      from: november,
      toExclusive: november.addDays(1),
      observedZone: 'Europe/London',
      maxDates: 10,
      maxRows: 10,
    );
    expect(result.complete, isFalse);
    expect(result.issue, DailyCalculationIssue.phaseOriginUnavailable);
    final next = PhaseResolver().nextDate(
      plan,
      from: november,
      observedZone: 'Europe/London',
    );
    expect(next.complete, isFalse);
    expect(next.issue, DailyCalculationIssue.phaseOriginUnavailable);
  });
  test(
    'an ended partial-day count retains progress meaning but has no next',
    () {
      final cutoff = DateTime.utc(2026, 10, 31, 12);
      final plan = PhasePlan(
        phases: [phase('a', october, timing: DailyCount(3, amount()))],
        end: PlanEnd(zoneId: 'UTC', exclusiveInstant: cutoff),
      );
      final runtime = PhaseResolver();
      final row = runtime
          .resolveDate(
            plan,
            october,
            observedZone: 'Europe/London',
            now: cutoff,
          )
          .single;
      expect(row.plannedCount, 3);
      expect(row.eligibilityConflict, 'plan_ended');
      expect(
        runtime
            .nextDate(
              plan,
              from: october,
              observedZone: 'Europe/London',
              now: cutoff,
            )
            .next,
        isNull,
      );
    },
  );
  test(
    'unresolved window endpoint and resolved anchor retain review metadata',
    () {
      final date = CivilDate(2026, 10, 25);
      final plan = phase(
        'a',
        date,
        timing: DailyWindows(
          windows: [
            DailyWindow(
              id: 'w',
              start: WallTime(0, 30),
              end: WallTime(1, 30),
              amount: amount(),
              reminderAnchor: WallTime(0, 45),
              reminderEnabled: true,
            ),
          ],
        ),
      );
      final row = DailyResolver()
          .resolveDate(plan, date, observedZone: 'Europe/London')
          .single;
      expect(row.resolution, DailyResolution.repeatedClock);
      expect(row.instant, isNull);
      expect(row.reminderAnchor, DateTime.utc(2026, 10, 24, 23, 45));
      expect(row.windowEndpoints.length, 3);
      expect(
        row.reminderStateAt(DateTime.utc(2026)),
        DailyReminderState.reviewClock,
      );
    },
  );
  test(
    'captured moved snapshot checks original pause against original instant',
    () {
      final source = phase('a', october);
      final override = OccurrenceOverride(
        identity: originalIdentity,
        versionId: 'a',
        targetInstant: DateTime.utc(2026, 11, 1, 1),
        targetZoneId: 'Europe/London',
      );
      final captured = PhaseResolver()
          .resolveDate(
            PhasePlan(phases: [source], overrides: [override]),
            november,
            observedZone: 'Europe/London',
          )
          .singleWhere((r) => r.identity == originalIdentity);
      final changed = phase(
        'b',
        october,
        pauses: [
          PlanPause(
            start: DateTime.utc(2026, 10, 31, 23),
            resume: DateTime.utc(2026, 11, 1),
          ),
        ],
      );
      final result = PhaseResolver().expand(
        PhasePlan(
          phases: [changed],
          originPhases: [source],
          overrides: [override],
        ),
        from: november,
        toExclusive: november.addDays(1),
        observedZone: 'Europe/London',
        maxDates: 10,
        maxRows: 10,
        historical: {originalIdentity: captured},
      );
      expect(result.complete, isTrue);
      expect(result.rows.any((r) => r.identity == originalIdentity), isFalse);
    },
  );
  test(
    'runtime partial window conflicts stay visible with reminders disabled',
    () {
      final window = DailyWindow(
        id: 'w',
        start: WallTime(23, 0),
        end: WallTime(1, 0),
        amount: amount(),
        reminderAnchor: WallTime(23, 30),
        reminderEnabled: true,
      );
      final plan = PhasePlan(
        phases: [
          phase(
            'a',
            october,
            timing: DailyWindows(windows: [window]),
            pauses: [PlanPause(start: DateTime.utc(2026, 11, 1, 0, 30))],
          ),
        ],
      );
      final row = PhaseResolver()
          .resolveDate(plan, october, observedZone: 'Europe/London')
          .single;
      expect(row.eligibilityConflict, 'window_crosses_pause');
      expect(row.windowEnd, DateTime.utc(2026, 11, 1, 1));
      expect(
        row.reminderStateAt(DateTime.utc(2026, 10, 1)),
        DailyReminderState.noAlert,
      );
      expect(() => expand(plan, to: november), throwsArgumentError);
    },
  );
  test('multi-opportunity buckets reject one-off shared quantity changes', () {
    final identity = DailyIdentity(
      personId: 'person',
      planId: 'plan',
      originalDate: october,
    );
    PhasePlan plan(int count) => PhasePlan(
      phases: [phase('a', october, timing: DailyCount(count, amount()))],
      overrides: [
        OccurrenceOverride(
          identity: identity,
          versionId: 'a',
          amount: amount('2'),
        ),
      ],
    );
    expect(
      () => expand(plan(3), to: november),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          'one_off_requires_single_opportunity',
        ),
      ),
    );
    final row = expand(plan(1), to: november).rows.single;
    expect(row.plannedCount, 1);
    expect(row.amount.quantity.canonical, '2');
  });
}
