part of 'record_store.dart';

const dailySchemaV6 = [
  '''CREATE TABLE daily_plan(id TEXT PRIMARY KEY,person TEXT NOT NULL,item TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),UNIQUE(id,person),UNIQUE(item,person),FOREIGN KEY(item,person) REFERENCES item(id,person)) STRICT''',
  '''CREATE TABLE daily_version(id TEXT PRIMARY KEY,plan TEXT NOT NULL,person TEXT NOT NULL,start TEXT NOT NULL,end TEXT,snapshot TEXT NOT NULL,UNIQUE(plan,start),FOREIGN KEY(plan,person) REFERENCES daily_plan(id,person) ON DELETE CASCADE,CHECK(end IS NULL OR end>start)) STRICT''',
  '''CREATE TABLE daily_version_audit(id TEXT PRIMARY KEY,plan TEXT NOT NULL,person TEXT NOT NULL,revision INTEGER NOT NULL,snapshot TEXT NOT NULL,FOREIGN KEY(plan,person) REFERENCES daily_plan(id,person) ON DELETE CASCADE) STRICT''',
  '''CREATE INDEX daily_version_bounds ON daily_version(plan,start,end)''',
  '''CREATE TRIGGER daily_version_overlap BEFORE INSERT ON daily_version WHEN EXISTS(SELECT 1 FROM daily_version v WHERE v.plan=NEW.plan AND (NEW.end IS NULL OR v.start<NEW.end) AND (v.end IS NULL OR NEW.start<v.end)) BEGIN SELECT RAISE(ABORT,'daily_version_overlap'); END''',
  '''CREATE TABLE daily_expectation(id TEXT PRIMARY KEY,plan TEXT NOT NULL,person TEXT NOT NULL,date TEXT NOT NULL,snapshot TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),UNIQUE(id,person),FOREIGN KEY(plan,person) REFERENCES daily_plan(id,person) ON DELETE CASCADE) STRICT''',
  '''CREATE INDEX daily_expectation_range ON daily_expectation(plan,date)''',
  '''CREATE TABLE daily_action(id TEXT PRIMARY KEY,bucket TEXT NOT NULL,person TEXT NOT NULL,kind TEXT NOT NULL CHECK(kind IN ('taken','skip')),record TEXT UNIQUE,revision INTEGER NOT NULL CHECK(revision>0),undone INTEGER NOT NULL CHECK(undone IN (0,1)),sequence INTEGER NOT NULL,recorded_at INTEGER NOT NULL,UNIQUE(bucket,sequence),CHECK((kind='taken')=(record IS NOT NULL)),FOREIGN KEY(bucket,person) REFERENCES daily_expectation(id,person) ON DELETE CASCADE,FOREIGN KEY(record,person) REFERENCES administration(id,person)) STRICT''',
  '''CREATE INDEX daily_action_bucket ON daily_action(bucket,id)''',
  '''CREATE TABLE daily_clock(id TEXT PRIMARY KEY,plan TEXT NOT NULL,person TEXT NOT NULL,date TEXT NOT NULL,snapshot TEXT NOT NULL,FOREIGN KEY(plan,person) REFERENCES daily_plan(id,person) ON DELETE CASCADE) STRICT''',
  '''CREATE TABLE daily_reminder_intent(plan TEXT PRIMARY KEY,person TEXT NOT NULL,revision INTEGER NOT NULL,stopped INTEGER NOT NULL CHECK(stopped IN (0,1)),FOREIGN KEY(plan,person) REFERENCES daily_plan(id,person) ON DELETE CASCADE) STRICT''',
];

extension DailyRecordStore on RecordStore {
  void _dailyGeneration(String expected) {
    if (generation != expected) throw const CommandConflict('generation');
  }

  SavedDailyPlan _savedPlan(Map<String, Object?> r) => SavedDailyPlan(
    plan: decodeDailyPlan(dailyObject(r['snapshot'] as String)),
    revision: r['revision'] as int,
    alreadyCommitted: r['replay'] == true,
  );

  Future<SavedDailyPlan> saveDailyPlan({
    required String commandId,
    required DailyPlanVersion plan,
    required int expectedPersonRevision,
    required String expectedGeneration,
    int? expectedPlanRevision,
    ReminderClockSample? intervalClockSample,
  }) async {
    _dailyGeneration(expectedGeneration);
    if ([
      plan.personId,
      plan.planId,
      plan.itemId,
      plan.versionId,
    ].any((id) => id.length > 256)) {
      throw ArgumentError('plan_identity_bound');
    }
    if (plan.timing case DailySlots(:final slots)) {
      if (slots.any((s) => s.id.length > 256)) {
        throw ArgumentError('slot_identity_bound');
      }
    }

    _phaseTimingBound(plan);
    final encoded = jsonEncode(encodeDailyPlan(plan));
    final result = await _command(
      commandId,
      [
        'daily_plan',
        plan.personId,
        encoded,
        expectedPersonRevision,
        expectedPlanRevision,
        if (intervalClockSample != null) _sampleJson(intervalClockSample),
      ],
      () async {
        await _activeOwner(plan.personId, expectedPersonRevision);
        final item = await itemById(plan.itemId, personId: plan.personId);
        if (item == null) throw const CommandConflict('ownership');
        final amounts = switch (plan.timing) {
          AsNeeded() => const <PlannedAmount>[],
          DailyCount(:final amount) => [amount],
          MixedDailyCount(:final amount, :final slots) => [
            amount,
            ...slots.map((s) => s.amount),
          ],
          DailyWindows(:final windows) => windows.map((w) => w.amount).toList(),
          ElapsedInterval(:final amount) => [amount],
          DailySlots(:final slots) => slots.map((s) => s.amount).toList(),
        };
        if (amounts.any((a) => a.unit != item.unit)) {
          throw const CommandConflict('plan_unit');
        }
        if (plan.timing case DailySlots(:final slots)) {
          if (slots.length > 100) throw ArgumentError('daily_slot_bound');
        }
        if (plan.timing case DailyCount(:final count)) {
          if (count > 100000) throw ArgumentError('daily_count_bound');
        }
        if (plan.timing case ElapsedInterval(:final segmentId)) {
          if (segmentId.length > 256 || plan.calendar is! EveryDay) {
            throw const CommandConflict('interval_composition');
          }
        }
        DailyResolver().clock.validateZone(plan.zoneBasis.zoneFor('Etc/UTC'));
        if (plan.timing case ElapsedInterval(
          :final segmentId,
          :final duration,
          :final mode,
          :final plannedAnchor,
        )) {
          final previous = await _rows(
            'SELECT snapshot FROM daily_version_audit WHERE plan=?',
            [plan.planId],
          );
          for (final row in previous) {
            final t = decodeDailyPlan(dailyObject(row['snapshot'] as String))
                .timing;
            if (t is ElapsedInterval &&
                t.segmentId == segmentId &&
                (t.duration.microseconds != duration.microseconds ||
                    t.mode != mode ||
                    t.plannedAnchor != plannedAnchor)) {
              throw const CommandConflict('interval_segment_identity');
            }
          }
        }
        final heads = await _rows('SELECT * FROM daily_plan WHERE id=?', [
          plan.planId,
        ]);
        var revision = 1;
        if (heads.isEmpty) {
          if (expectedPlanRevision != null) {
            throw const CommandConflict('plan_revision');
          }
          // One routine per item; replacement is a version edit, never a second active routine.
          if ((await _rows(
            'SELECT id FROM daily_plan WHERE item=? AND person=?',
            [plan.itemId, plan.personId],
          )).isNotEmpty) {
            throw const CommandConflict('item_plan');
          }
          await _db.customStatement('INSERT INTO daily_plan VALUES (?,?,?,1)', [
            plan.planId,
            plan.personId,
            plan.itemId,
          ]);
        } else {
          final h = heads.single;
          if (h['person'] != plan.personId ||
              h['item'] != plan.itemId ||
              h['revision'] != expectedPlanRevision) {
            throw const CommandConflict('plan_revision');
          }
          if ((await _rows(
            'SELECT id FROM daily_expectation WHERE plan=? AND date>=? LIMIT 1',
            [plan.planId, plan.start.toString()],
          )).isNotEmpty) {
            throw const CommandConflict('captured_history');
          }
          if ((await _rows('SELECT id FROM daily_version_audit WHERE id=?', [
            plan.versionId,
          ])).isNotEmpty) {
            throw const CommandConflict('version_identity');
          }
          final earlier = await _rows(
            'SELECT * FROM daily_version WHERE plan=? AND start<? AND (end IS NULL OR end>?)',
            [plan.planId, plan.start.toString(), plan.start.toString()],
          );
          for (final old in earlier) {
            final v = decodeDailyPlan(dailyObject(old['snapshot'] as String));
            if (plan.effectiveFrom != null &&
                v.effectiveUntil != null &&
                !v.effectiveUntil!.isAfter(plan.effectiveFrom!)) {
              continue;
            }
            final closed = DailyPlanVersion(
              personId: v.personId,
              planId: v.planId,
              itemId: v.itemId,
              versionId: v.versionId,
              start: v.start,
              endExclusive: plan.start,
              timing: v.timing,
              calendar: v.calendar,
              pauses: v.pauses,
              onOff: v.onOff,
              effectiveFrom: v.effectiveFrom,
              effectiveUntil: v.effectiveUntil,
              zoneBasis: v.zoneBasis,
            );
            await _db.customStatement(
              'UPDATE daily_version SET end=?,snapshot=? WHERE id=?',
              [
                plan.start.toString(),
                jsonEncode(encodeDailyPlan(closed)),
                v.versionId,
              ],
            );
          }
          await _db.customStatement(
            "DELETE FROM daily_version WHERE plan=? AND start>=? AND NOT (? IS NOT NULL AND json_extract(snapshot,'\$.effectiveUntil') IS NOT NULL AND json_extract(snapshot,'\$.effectiveUntil')<=?)",
            [
              plan.planId,
              plan.start.toString(),
              plan.effectiveFrom?.microsecondsSinceEpoch,
              plan.effectiveFrom?.microsecondsSinceEpoch,
            ],
          );
          await _db.customStatement(
            'DELETE FROM daily_clock WHERE plan=? AND date>=?',
            [plan.planId, plan.start.toString()],
          );
          revision = (h['revision'] as int) + 1;
          await _db.customStatement(
            'UPDATE daily_plan SET revision=? WHERE id=?',
            [revision, plan.planId],
          );
        }
        await _db.customStatement(
          'INSERT INTO daily_version VALUES (?,?,?,?,?,?)',
          [
            plan.versionId,
            plan.planId,
            plan.personId,
            plan.start.toString(),
            plan.endExclusive?.toString(),
            encoded,
          ],
        );
        await _db.customStatement(
          'INSERT INTO daily_version_audit VALUES (?,?,?,?,?)',
          [plan.versionId, plan.planId, plan.personId, revision, encoded],
        );
        if (plan.timing is ElapsedInterval) {
          await _captureIntervalClock(
            plan,
            intervalClockSample,
            replace: false,
          );
        }
        // Reject an ordinary edit that would orphan an explicit original identity.
        await phasePlan(planId: plan.planId, personId: plan.personId);
        await _dailyIntent(plan.planId, plan.personId, revision, false);
        return {
          'snapshot': encoded,
          'revision': revision,
          'person': plan.personId,
        };
      },
    );
    return _savedPlan(result);
  }

  Future<void> _dailyIntent(
    String plan,
    String person,
    int revision,
    bool stopped, {
    bool invalidateRequests = true,
  }) async {
    if (invalidateRequests) await _invalidateReminderPlan(plan);
    final owner = await profileById(person);
    await _db.customStatement(
      'INSERT INTO daily_reminder_intent VALUES (?,?,?,?) ON CONFLICT(plan) DO UPDATE SET revision=daily_reminder_intent.revision+1,stopped=excluded.stopped',
      [
        plan,
        person,
        revision,
        stopped || owner?.remindersStopped == true ? 1 : 0,
      ],
    );
  }

  Future<List<Map<String, Object?>>> dailyReminderIntents() =>
      _rows('SELECT * FROM daily_reminder_intent ORDER BY plan');

  Future<List<SavedDailyPlan>> dailyPlans({
    FeedScope scope = const FeedScope.everyone(),
    String? itemId,
    int limit = 100,
    int offset = 0,
  }) async {
    _pageBounds(limit, offset);
    return (await _rows(
      "SELECT v.snapshot,p.revision FROM daily_plan p JOIN daily_version v ON v.plan=p.id JOIN person o ON o.id=p.person WHERE ${scope.isEveryone ? 'o.archived=0' : 'p.person=?'} ${itemId == null ? '' : 'AND p.item=?'} AND v.id=(SELECT v2.id FROM daily_version v2 WHERE v2.plan=p.id ORDER BY v2.start DESC,COALESCE(json_extract(v2.snapshot,'\$.effectiveFrom'),-9223372036854775808) DESC,v2.rowid DESC LIMIT 1) ORDER BY p.id LIMIT ? OFFSET ?",
      [if (!scope.isEveryone) scope.personId, ?itemId, limit, offset],
    )).map(_savedPlan).toList();
  }

  Stream<List<SavedDailyPlan>> watchDailyPlans({
    FeedScope scope = const FeedScope.everyone(),
    String? itemId,
    int limit = 100,
    int offset = 0,
  }) => _watch(
    () =>
        dailyPlans(scope: scope, itemId: itemId, limit: limit, offset: offset),
  );
  Future<List<SavedDailyPlan>> dailyPlanVersions(
    String planId, {
    required String personId,
    int limit = 100,
    int offset = 0,
  }) async {
    _pageBounds(limit, offset);
    return (await _rows(
      'SELECT v.snapshot,p.revision FROM daily_version v JOIN daily_plan p ON p.id=v.plan WHERE p.id=? AND p.person=? ORDER BY v.start LIMIT ? OFFSET ?',
      [planId, personId, limit, offset],
    )).map(_savedPlan).toList();
  }

  Future<List<SavedDailyPlan>> dailyPlanAudit(
    String planId, {
    required String personId,
    int limit = 100,
    int offset = 0,
  }) async {
    _pageBounds(limit, offset);
    return (await _rows(
      'SELECT snapshot,revision FROM daily_version_audit WHERE plan=? AND person=? ORDER BY rowid LIMIT ? OFFSET ?',
      [planId, personId, limit, offset],
    )).map(_savedPlan).toList();
  }

  Future<List<DailyAction>> dailyActions(
    DailyIdentity identity, {
    int limit = 100,
    int offset = 0,
  }) async {
    _pageBounds(limit, offset);
    return _dailyActions(
      dailyIdentityKey(identity),
      limit: limit,
      offset: offset,
    );
  }

  Future<List<DailyAction>> _dailyActions(
    String id, {
    int limit = 100,
    int offset = 0,
  }) async => (await _rows(
    'SELECT d.*,a.revision AS actual_revision FROM daily_action d LEFT JOIN administration a ON a.id=d.record WHERE d.bucket=? ORDER BY d.sequence DESC LIMIT ? OFFSET ?',
    [id, limit, offset],
  )).map(_dailyAction).toList();
  Future<(int, int, int)> _dailyProgress(String id) async {
    final count = (await _rows(
      "SELECT COALESCE(SUM(kind='taken' AND undone=0),0) AS taken,COALESCE(SUM(kind='skip' AND undone=0),0) AS skipped,COUNT(*) AS total FROM daily_action WHERE bucket=?",
      [id],
    )).single;
    return (
      count['taken'] as int,
      count['skipped'] as int,
      count['total'] as int,
    );
  }

  DailyAction _dailyAction(Map<String, Object?> r) => DailyAction(
    id: r['id'] as String,
    kind: DailyActionKind.values.byName(r['kind'] as String),
    revision: r['revision'] as int,
    sequence: r['sequence'] as int,
    recordedAt: DateTime.fromMicrosecondsSinceEpoch(
      r['recorded_at'] as int,
      isUtc: true,
    ),
    isUndone: r['undone'] == 1,
    recordId: r['record'] as String?,
    recordRevision: r['actual_revision'] as int?,
    alreadyCommitted: r['replay'] == true,
  );

  Future<int> _reminderStateForIdentity(DailyIdentity identity) async {
    final found = await _rows(
      'SELECT revision FROM reminder_state WHERE bucket=?',
      [dailyIdentityKey(identity)],
    );
    return found.isEmpty ? 0 : found.single['revision'] as int;
  }

  Future<DailyRow> _dailyRow(DailyExpectation e, int planRevision) async {
    final owner = await profileById(e.identity.personId);
    final item = await itemById(e.itemId, personId: e.identity.personId);
    if (owner == null || item == null) throw const CommandConflict('ownership');
    final saved = await _rows(
      'SELECT revision FROM daily_expectation WHERE id=?',
      [dailyIdentityKey(e.identity)],
    );
    final progress = await _dailyProgress(dailyIdentityKey(e.identity));
    return DailyRow(
      takenCount: progress.$1,
      skippedCount: progress.$2,
      actionsComplete: progress.$3 <= 100,
      generation: generation,
      reminderRevision: (await _reminderStateForIdentity(e.identity)),
      personRevision: owner.revision,
      planRevision: planRevision,
      expectation: e,
      personName: owner.name,
      itemName: item.name,
      itemRevision: item.revision,
      productLabel: await productLabel(
        personId: e.identity.personId,
        itemId: e.itemId,
      ),
      revision: saved.isEmpty ? 0 : saved.single['revision'] as int,
      actions: await _dailyActions(dailyIdentityKey(e.identity)),
    );
  }

  Future<DailyRows> capturedDailyRows({
    FeedScope scope = const FeedScope.everyone(),
    int limit = 100,
    int offset = 0,
  }) async {
    _pageBounds(limit, offset);
    return _db.transaction(() async {
      final captures = await _rows(
        'SELECT e.snapshot,p.revision FROM daily_expectation e JOIN daily_plan p ON p.id=e.plan JOIN person o ON o.id=e.person WHERE ${scope.isEveryone ? 'o.archived=0' : 'e.person=?'} ORDER BY e.date DESC,e.id LIMIT ? OFFSET ?',
        [if (!scope.isEveryone) scope.personId, limit + 1, offset],
      );
      final rows = <DailyRow>[];
      for (final r in captures.take(limit)) {
        rows.add(
          await _dailyRow(
            decodeDailyExpectation(dailyObject(r['snapshot'] as String)),
            r['revision'] as int,
          ),
        );
      }
      return DailyRows(rows: rows, complete: captures.length <= limit);
    });
  }

  Stream<DailyRows> watchCapturedDailyRows({
    FeedScope scope = const FeedScope.everyone(),
    int limit = 100,
    int offset = 0,
  }) => _watch(
    () => capturedDailyRows(scope: scope, limit: limit, offset: offset),
  );

  Future<DailyPlanNextRows> nextDailyPlans({
    FeedScope scope = const FeedScope.everyone(),
    required DateTime now,
    required String? observedZone,
    int maxPlans = 100,
    int maxVersions = 100,
    int maxDates = 366,
  }) async {
    if (maxPlans < 1 ||
        maxPlans > 1000 ||
        maxVersions < 1 ||
        maxVersions > 1000 ||
        maxDates < 1 ||
        maxDates > 366) {
      throw ArgumentError('daily_next_bound');
    }
    return _db.transaction(() async {
      final resolver = DailyResolver();
      final envelope = resolver.clock.dateEnvelopeAt(now);
      final heads = await _rows(
        'SELECT p.id FROM daily_plan p JOIN person o ON o.id=p.person WHERE ${scope.isEveryone ? 'o.archived=0' : 'p.person=?'} ORDER BY p.id LIMIT ?',
        [if (!scope.isEveryone) scope.personId, maxPlans + 1],
      );
      var complete = heads.length <= maxPlans;
      final rows = <DailyPlanNextRow>[];
      for (final h in heads.take(maxPlans)) {
        final phaseOwner = await _rows(
          'SELECT person FROM daily_plan WHERE id=?',
          [h['id']],
        );
        final phased = await phasePlan(
          planId: h['id'] as String,
          personId: phaseOwner.single['person'] as String,
        );
        if (phased != null) {
          if (observedZone == null &&
              phased.phases.any((p) => p.zoneBasis is FollowingLocal)) {
            complete = false;
            rows.add(
              DailyPlanNextRow(
                plan: phased.phases.last,
                result: DailyNext(
                  complete: false,
                  datesExamined: 0,
                  issue: DailyCalculationIssue.observedZoneUnavailable,
                ),
              ),
            );
            continue;
          }
          final sources = await intervalSources(
            planId: phased.planId,
            personId: phased.personId,
          );
          final captures = await _rows(
            'SELECT snapshot FROM daily_expectation WHERE plan=? LIMIT 100001',
            [phased.planId],
          );
          if (captures.length > 100000) {
            complete = false;
            continue;
          }
          final historical = {
            for (final r in captures)
              decodeDailyExpectation(dailyObject(r['snapshot'] as String))
                  .identity: decodeDailyExpectation(
                dailyObject(r['snapshot'] as String),
              ),
          };
          final choices = await _rows(
            'SELECT snapshot FROM daily_clock WHERE plan=? LIMIT 100001',
            [phased.planId],
          );
          if (choices.length > 100000) {
            complete = false;
            continue;
          }
          final decisions = {
            for (final r in choices)
              decodeDailyChoice(dailyObject(r['snapshot'] as String))
                  .identity: decodeDailyChoice(
                dailyObject(r['snapshot'] as String),
              ),
          };
          final result = await _nextPhase(
            phased,
            now: _intervalReferenceNow(sources, now),
            observedZone:
                observedZone ??
                phased.phases.first.zoneBasis.zoneFor('Etc/UTC'),
            maxDates: maxDates,
            historical: historical,
            decisions: decisions,
            sources: sources,
          );
          complete = complete && result.complete;
          rows.add(DailyPlanNextRow(plan: phased.phases.last, result: result));
          continue;
        }
        // Seek directly past expired versions; never paginate through old history.
        final versions = await _rows(
          "SELECT snapshot FROM daily_version WHERE plan=? AND (end IS NULL OR end>?) AND (json_extract(snapshot,'\$.effectiveUntil') IS NULL OR json_extract(snapshot,'\$.effectiveUntil')>?) ORDER BY start,COALESCE(json_extract(snapshot,'\$.effectiveFrom'),-9223372036854775808),rowid LIMIT ?",
          [
            h['id'],
            envelope.$1.toString(),
            now.toUtc().microsecondsSinceEpoch,
            maxVersions + 1,
          ],
        );
        var planComplete = true;
        var provedBeforeLaterVersions = false;
        DailyExpectation? next;
        CivilDate? calendarDate;
        DailyPlanVersion? chosen;
        final review = <DailyIdentity, DailyExpectation>{};
        DailyCalculationIssue? issue;
        var examined = 0;
        for (final v in versions.take(maxVersions)) {
          final p = decodeDailyPlan(dailyObject(v['snapshot'] as String));
          if (next != null && _dailyVersionAfterCandidate(p, next, resolver)) {
            provedBeforeLaterVersions = true;
            break;
          }
          chosen ??= p;
          final result = await _nextDailyVersion(
            p,
            now: now,
            observedZone: observedZone,
            maxDates: maxDates,
            resolver: resolver,
          );
          planComplete = planComplete && result.complete;
          issue ??= result.issue;
          if (result.calendarDate case final candidateDate?) {
            if (calendarDate == null ||
                candidateDate.compareTo(calendarDate) < 0) {
              calendarDate = candidateDate;
              if (next == null) chosen = p;
            }
          }
          examined += result.datesExamined;
          for (final r in result.needsReview) {
            review[r.identity] = r;
          }
          if (result.next case final candidate?) {
            if (next == null || _dailyNextOrder(candidate, next) < 0) {
              next = candidate;
              chosen = p;
            }
          }
        }
        if (versions.length > maxVersions && !provedBeforeLaterVersions) {
          final firstUnread = decodeDailyPlan(
            dailyObject(versions[maxVersions]['snapshot'] as String),
          );
          if (next == null ||
              !_dailyVersionAfterCandidate(firstUnread, next, resolver)) {
            planComplete = false;
          }
        }
        if (chosen == null) {
          final latest = await _rows(
            'SELECT snapshot FROM daily_version WHERE plan=? ORDER BY start DESC,rowid DESC LIMIT 1',
            [h['id']],
          );
          if (latest.isEmpty) {
            throw const CommandConflict('missing_plan_version');
          }
          chosen = decodeDailyPlan(
            dailyObject(latest.single['snapshot'] as String),
          );
        }
        complete = complete && planComplete;
        rows.add(
          DailyPlanNextRow(
            plan: chosen,
            result: DailyNext(
              next: next,
              calendarDate: next?.identity.originalDate ?? calendarDate,
              complete: planComplete,
              datesExamined: examined,
              issue: issue,
              needsReview: review.values,
            ),
          ),
        );
      }
      return DailyPlanNextRows(rows: rows, complete: complete);
    });
  }

  Stream<DailyPlanNextRows> watchNextDailyPlans({
    FeedScope scope = const FeedScope.everyone(),
    required DateTime now,
    required String? observedZone,
    int maxPlans = 100,
    int maxVersions = 100,
    int maxDates = 366,
  }) => _watch(
    () => nextDailyPlans(
      scope: scope,
      now: now,
      observedZone: observedZone,
      maxPlans: maxPlans,
      maxVersions: maxVersions,
      maxDates: maxDates,
    ),
  );

  bool _dailyVersionAfterCandidate(
    DailyPlanVersion plan,
    DailyExpectation candidate,
    DailyResolver resolver,
  ) {
    final bound = candidate.instant == null
        ? candidate.identity.originalDate.addDays(1)
        : resolver.clock.dateEnvelopeAt(candidate.instant!).$2;
    return plan.start.compareTo(bound) >= 0;
  }

  int _dailyNextOrder(DailyExpectation a, DailyExpectation b) {
    if (a.instant != null && b.instant != null) {
      return a.instant!.compareTo(b.instant!);
    }
    final date = a.identity.originalDate.compareTo(b.identity.originalDate);
    if (date != 0) {
      return date;
    }
    return (a.identity.slotId ?? '').compareTo(b.identity.slotId ?? '');
  }

  Future<DailyNext> _nextDailyVersion(
    DailyPlanVersion p, {
    required DateTime now,
    required String? observedZone,
    required int maxDates,
    required DailyResolver resolver,
  }) async {
    if (p.timing is AsNeeded) {
      return DailyNext(complete: true, datesExamined: 0);
    }
    final zone =
        observedZone ??
        (p.zoneBasis is FixedHome ? (p.zoneBasis as FixedHome).zoneId : null);
    if (zone == null) {
      return DailyNext(
        complete: false,
        datesExamined: 0,
        issue: DailyCalculationIssue.observedZoneUnavailable,
      );
    }
    if (p.timing is ElapsedInterval &&
        (p.timing as ElapsedInterval).mode == IntervalMode.qualifyingActual) {
      final sources = await intervalSources(
        planId: p.planId,
        personId: p.personId,
      );
      final result = IntervalResolver().current(
        p,
        now: _intervalReferenceNow(sources, now),
        observedZone: zone,
        sources: sources,
      );
      if (result.next == null) {
        return DailyNext(
          complete: result.complete,
          datesExamined: 0,
          issue: DailyResolver.intervalIssue(result.issue),
        );
      }
      final progress = await _dailyProgress(
        dailyIdentityKey(result.next!.identity),
      );
      if (progress.$1 + progress.$2 > 0) {
        return DailyNext(complete: true, datesExamined: 0);
      }
      return DailyNext(
        next: result.next,
        calendarDate: result.next?.identity.originalDate,
        complete: result.complete,
        datesExamined: 0,
        issue: DailyResolver.intervalIssue(result.issue),
      );
    }
    CivilDate date;
    try {
      date = resolver.currentDate(p, now: now, observedZone: zone);
    } on UnsupportedClockRange {
      return DailyNext(
        complete: false,
        datesExamined: 0,
        issue: DailyCalculationIssue.unsupportedTimezoneRange,
      );
    }
    if (date.compareTo(p.start) < 0) {
      date = p.start;
    }
    if (!p.includes(date)) {
      return DailyNext(complete: true, datesExamined: 0);
    }
    // Load only bounded future context. Resolver snapshots still win over changed
    // clocks, and one clock choice can never be applied to another semantic zone.
    final captures = await _rows(
      'SELECT snapshot FROM daily_expectation WHERE plan=? AND date>=? AND date<=? LIMIT 100001',
      [p.planId, date.toString(), '9999-12-31'],
    );
    final choices = await _rows(
      'SELECT snapshot FROM daily_clock WHERE plan=? AND date>=? AND date<=? LIMIT 100001',
      [p.planId, date.toString(), '9999-12-31'],
    );
    if (captures.length > 100000 || choices.length > 100000) {
      return DailyNext(complete: false, datesExamined: 0);
    }
    final historical = <DailyIdentity, DailyExpectation>{};
    for (final r in captures) {
      final e = decodeDailyExpectation(dailyObject(r['snapshot'] as String));
      historical[e.identity] = e;
    }
    final decisions = <DailyIdentity, DailyClockChoice>{};
    for (final r in choices) {
      final c = decodeDailyChoice(dailyObject(r['snapshot'] as String));
      if (_dailyChoiceApplies(c, p, zone)) {
        decisions[c.identity] = c;
      }
    }
    final progress = await _rows(
      "SELECT e.id,SUM(d.undone=0) AS resolved FROM daily_expectation e JOIN daily_action d ON d.bucket=e.id WHERE e.plan=? AND e.date>=? AND e.date<=? GROUP BY e.id LIMIT 100001",
      [p.planId, date.toString(), '9999-12-31'],
    );
    if (progress.length > 100000) {
      return DailyNext(complete: false, datesExamined: 0);
    }
    final resolved = {
      for (final r in progress) r['id'] as String: r['resolved'] as int,
    };
    bool isResolved(DailyExpectation e) =>
        (resolved[dailyIdentityKey(e.identity)] ?? 0) >= (e.plannedCount ?? 1);
    final review = <DailyIdentity, DailyExpectation>{};
    var examined = 0;
    if (p.timing is DailyCount) {
      for (var i = 0; i < maxDates; i++) {
        final result = resolver.nextDate(
          p,
          from: date,
          observedZone: zone,
          decisions: decisions,
          historical: historical,
        );
        examined += result.datesExamined;
        if (result.next == null || !result.complete) {
          return DailyNext(
            next: result.next,
            calendarDate: result.calendarDate,
            complete: result.complete,
            datesExamined: examined,
            issue: result.issue,
            needsReview: result.needsReview,
          );
        }
        if (!isResolved(result.next!)) {
          return DailyNext(
            next: result.next,
            calendarDate: result.calendarDate,
            complete: true,
            datesExamined: examined,
          );
        }
        if (result.next!.identity.originalDate == CivilDate(9999, 12, 31)) {
          return DailyNext(complete: true, datesExamined: examined);
        }
        date = result.next!.identity.originalDate.addDays(1);
      }
      return DailyNext(
        complete:
            p.endExclusive != null && date.compareTo(p.endExclusive!) >= 0,
        datesExamined: examined,
      );
    }
    var cursor = now.toUtc();
    // Each successful seek advances strictly after one exact slot. The bounded
    // loop also handles already-recorded future slots without inventing a next.
    for (var attempt = 0; attempt < maxDates * 100; attempt++) {
      final remainingDates = maxDates - examined;
      if (remainingDates <= 0) {
        return DailyNext(
          complete: false,
          datesExamined: examined,
          needsReview: review.values,
        );
      }
      final result = resolver.nextInstant(
        p,
        after: cursor,
        observedZone: zone,
        maxDates: remainingDates,
        decisions: decisions,
        historical: historical,
      );
      examined += result.datesExamined;
      for (final r in result.needsReview) {
        if (!isResolved(r)) {
          review[r.identity] = r;
        }
      }
      final candidate = result.next;
      if (candidate == null || !result.complete || !isResolved(candidate)) {
        return DailyNext(
          next: candidate,
          calendarDate: result.calendarDate,
          complete: result.complete,
          datesExamined: examined,
          issue: result.issue,
          needsReview: review.values,
        );
      }
      // Distinct stable slots may share one instant. Do not advance past a
      // pending sibling merely because the resolver's first tie was resolved.
      final simultaneous =
          resolver
              .resolveDate(
                p,
                candidate.identity.originalDate,
                observedZone: zone,
                decisions: decisions,
                historical: historical,
              )
              .where((e) => e.instant == candidate.instant && !isResolved(e))
              .toList()
            ..sort(
              (a, b) =>
                  (a.identity.slotId ?? '').compareTo(b.identity.slotId ?? ''),
            );
      if (simultaneous.isNotEmpty) {
        return DailyNext(
          next: simultaneous.first,
          complete: true,
          datesExamined: examined,
          needsReview: review.values,
        );
      }
      cursor = candidate.instant!;
    }
    return DailyNext(
      complete: false,
      datesExamined: examined,
      needsReview: review.values,
    );
  }

  Future<DailyRows> dailyRows({
    FeedScope scope = const FeedScope.everyone(),
    required CivilDate from,
    required CivilDate toExclusive,
    required String? observedZone,
    int maxPlans = 100,
    int maxRows = 1000,
  }) => _readDaily(
    scope: scope,
    from: from,
    toExclusive: toExclusive,
    observedZone: observedZone,
    maxPlans: maxPlans,
    maxRows: maxRows,
  );
  Future<DailyRows> todayDailyRows({
    FeedScope scope = const FeedScope.everyone(),
    required DateTime now,
    required String? observedZone,
    int maxPlans = 100,
    int maxRows = 1000,
  }) => _readDaily(
    scope: scope,
    now: now,
    observedZone: observedZone,
    maxPlans: maxPlans,
    maxRows: maxRows,
  );
  Stream<DailyRows> watchDailyRows({
    FeedScope scope = const FeedScope.everyone(),
    required CivilDate from,
    required CivilDate toExclusive,
    required String? observedZone,
    int maxPlans = 100,
    int maxRows = 1000,
  }) => _watch(
    () => dailyRows(
      scope: scope,
      from: from,
      toExclusive: toExclusive,
      observedZone: observedZone,
      maxPlans: maxPlans,
      maxRows: maxRows,
    ),
  );
  Stream<DailyRows> watchTodayDailyRows({
    FeedScope scope = const FeedScope.everyone(),
    required DateTime now,
    required String? observedZone,
    int maxPlans = 100,
    int maxRows = 1000,
  }) => _watch(
    () => todayDailyRows(
      scope: scope,
      now: now,
      observedZone: observedZone,
      maxPlans: maxPlans,
      maxRows: maxRows,
    ),
  );

  Future<DailyRows> _readDaily({
    required FeedScope scope,
    CivilDate? from,
    CivilDate? toExclusive,
    DateTime? now,
    required String? observedZone,
    required int maxPlans,
    required int maxRows,
    String? reminderPlanId,
    String? reminderVersionId,
    DateTime? calculationNow,
  }) async {
    if (maxPlans < 1 || maxPlans > 1000 || maxRows < 1 || maxRows > 100000) {
      throw ArgumentError('daily_read_bound');
    }
    if (from != null &&
        (toExclusive!.compareTo(from) < 0 ||
            toExclusive.calendarValue.difference(from.calendarValue).inDays >
                366)) {
      throw ArgumentError('daily_date_bound');
    }
    return _db.transaction(() async {
      final heads = await _rows(
        'SELECT p.id FROM daily_plan p JOIN person o ON o.id=p.person WHERE ${scope.isEveryone ? 'o.archived=0' : 'p.person=?'} ${reminderPlanId == null ? '' : 'AND p.id=?'} ORDER BY p.id LIMIT ?',
        [if (!scope.isEveryone) scope.personId, ?reminderPlanId, maxPlans + 1],
      );
      final rows = <DailyRow>[];
      final seen = <DailyIdentity>{};
      var complete = heads.length <= maxPlans;
      DailyCalculationIssue? issue;
      final resolver = DailyResolver();
      final envelope = now == null ? null : resolver.clock.dateEnvelopeAt(now);
      for (final head in heads.take(maxPlans)) {
        final versions = await _rows(
          "SELECT v.snapshot,p.revision FROM daily_version v JOIN daily_plan p ON p.id=v.plan WHERE v.plan=? AND v.start<? AND (v.end IS NULL OR v.end>?) AND (json_extract(v.snapshot,'\$.effectiveUntil') IS NULL OR json_extract(v.snapshot,'\$.effectiveUntil')>?) AND (json_extract(v.snapshot,'\$.effectiveFrom') IS NULL OR json_extract(v.snapshot,'\$.effectiveFrom')<?) ORDER BY v.start,COALESCE(json_extract(v.snapshot,'\$.effectiveFrom'),-9223372036854775808),v.rowid LIMIT 1001",
          [
            head['id'],
            (toExclusive ?? envelope!.$2).toString(),
            (from ?? envelope!.$1).toString(),
            (from ?? envelope!.$1).calendarValue
                .subtract(const Duration(days: 2))
                .microsecondsSinceEpoch,
            (toExclusive ?? envelope!.$2).calendarValue
                .add(const Duration(days: 2))
                .microsecondsSinceEpoch,
          ],
        );
        if (versions.length > 1000) complete = false;
        final phaseHead = await _rows(
          'SELECT person,revision FROM daily_plan WHERE id=?',
          [head['id']],
        );
        final phased = await phasePlan(
          planId: head['id'] as String,
          personId: phaseHead.single['person'] as String,
        );
        if (phased != null) {
          final saved = SavedDailyPlan(
            plan: phased.phases.first,
            revision: phaseHead.single['revision'] as int,
          );
          final zone =
              observedZone ??
              (saved.plan.zoneBasis is FixedHome
                  ? (saved.plan.zoneBasis as FixedHome).zoneId
                  : null);
          if (zone == null) {
            complete = false;
            issue ??= DailyCalculationIssue.observedZoneUnavailable;
            continue;
          }
          final start =
              from ??
              resolver.currentDate(saved.plan, now: now!, observedZone: zone);
          final end = toExclusive ?? start.addDays(1);
          final captures = await _rows(
            'SELECT snapshot FROM daily_expectation WHERE plan=? LIMIT 100001',
            [head['id']],
          );
          if (captures.length > 100000) {
            complete = false;
            continue;
          }
          final historical = {
            for (final r in captures)
              decodeDailyExpectation(dailyObject(r['snapshot'] as String))
                  .identity: decodeDailyExpectation(
                dailyObject(r['snapshot'] as String),
              ),
          };
          final choices = await _rows(
            'SELECT snapshot FROM daily_clock WHERE plan=? LIMIT 100001',
            [head['id']],
          );
          if (choices.length > 100000) {
            complete = false;
            continue;
          }
          final decisions = {
            for (final r in choices)
              decodeDailyChoice(dailyObject(r['snapshot'] as String))
                  .identity: decodeDailyChoice(
                dailyObject(r['snapshot'] as String),
              ),
          };
          final sources = await intervalSources(
            planId: saved.plan.planId,
            personId: saved.plan.personId,
          );
          if (rows.length >= maxRows) {
            complete = false;
            break;
          }
          final ranged = await phasePlan(
            planId: phased.planId,
            personId: phased.personId,
            from: start,
            toExclusive: end,
          );
          final expanded = PhaseResolver().expand(
            ranged!,
            from: start,
            toExclusive: end,
            observedZone: zone,
            maxDates: 366,
            maxRows: maxRows - rows.length,
            historical: historical,
            decisions: decisions,
            intervalSources: sources,
            now: _intervalReferenceNow(
              sources,
              calculationNow ?? now ?? DateTime.now().toUtc(),
            ),
          );
          complete = complete && expanded.complete;
          issue ??= expanded.issue;
          for (final e in expanded.rows) {
            if ((reminderVersionId == null ||
                    e.versionId == reminderVersionId) &&
                seen.add(e.identity)) {
              rows.add(await _dailyRow(e, saved.revision));
            }
          }
          continue;
        }
        for (final v in versions.take(1000)) {
          final saved = _savedPlan(v);
          final p = saved.plan;
          if (reminderVersionId != null && p.versionId != reminderVersionId) {
            continue;
          }
          final zone =
              observedZone ??
              (p.zoneBasis is FixedHome
                  ? (p.zoneBasis as FixedHome).zoneId
                  : null);
          if (zone == null) {
            if (p.timing is! AsNeeded) {
              complete = false;
              issue ??= DailyCalculationIssue.observedZoneUnavailable;
            }
            continue;
          }
          CivilDate start, end;
          try {
            start =
                from ?? resolver.currentDate(p, now: now!, observedZone: zone);
            end = toExclusive ?? start.addDays(1);
          } on UnsupportedClockRange {
            complete = false;
            issue = DailyCalculationIssue.unsupportedTimezoneRange;
            continue;
          }
          if (!p.includes(start) && now != null) continue;
          final captures = await _rows(
            'SELECT snapshot FROM daily_expectation WHERE plan=? AND date>=? AND date<?',
            [p.planId, start.toString(), end.toString()],
          );
          final historical = {
            for (final r in captures)
              decodeDailyExpectation(dailyObject(r['snapshot'] as String))
                  .identity: decodeDailyExpectation(
                dailyObject(r['snapshot'] as String),
              ),
          };
          final choices = await _rows(
            'SELECT snapshot FROM daily_clock WHERE plan=? AND date>=? AND date<?',
            [
              p.planId,
              start.toString(),
              (p.timing is DailyWindows ? end.addDays(1) : end).toString(),
            ],
          );
          final decisions = <DailyIdentity, DailyClockChoice>{};
          for (final r in choices) {
            final choice = decodeDailyChoice(
              dailyObject(r['snapshot'] as String),
            );
            if (_dailyChoiceApplies(choice, p, zone)) {
              decisions[choice.identity] = choice;
            }
          }
          if (rows.length >= maxRows) {
            complete = false;
            break;
          }
          final sources = await intervalSources(
            planId: p.planId,
            personId: p.personId,
          );
          final expanded = resolver.expand(
            p,
            intervalSources: sources,
            now: _intervalReferenceNow(
              sources,
              calculationNow ?? now ?? DateTime.now().toUtc(),
            ),
            from: start,
            toExclusive: end,
            observedZone: zone,
            maxDates: 366,
            maxRows: maxRows - rows.length,
            historical: historical,
            decisions: decisions,
          );
          complete = complete && expanded.complete;
          issue ??= expanded.issue;
          for (final e in expanded.rows) {
            if (seen.add(e.identity)) {
              rows.add(await _dailyRow(e, saved.revision));
            }
          }
          if (now != null &&
              p.timing is ElapsedInterval &&
              (p.timing as ElapsedInterval).mode ==
                  IntervalMode.qualifyingActual &&
              expanded.rows.isEmpty) {
            final overdue = IntervalResolver()
                .current(
                  p,
                  now: _intervalReferenceNow(sources, now),
                  observedZone: zone,
                  sources: sources,
                )
                .next;
            if (overdue != null &&
                overdue.identity.originalDate.compareTo(start) < 0 &&
                rows.length < maxRows) {
              final row = await _dailyRow(overdue, saved.revision);
              if (!row.isResolved && seen.add(row.expectation.identity)) {
                rows.add(row);
              }
            }
          }
        }
      }
      return DailyRows(rows: rows, complete: complete, issue: issue);
    });
  }

  bool _dailyChoiceApplies(
    DailyClockChoice c,
    DailyPlanVersion p,
    String observedZone,
  ) {
    if (c.versionId != p.versionId ||
        c.identity.personId != p.personId ||
        c.identity.planId != p.planId ||
        c.zoneId != p.zoneBasis.zoneFor(observedZone)) {
      return false;
    }
    if (p.timing case MixedDailyCount(:final slots)) {
      return slots.any(
        (s) => s.id == c.identity.slotId && s.time == c.originalTime,
      );
    }
    if (p.timing case DailyWindows(:final windows)) {
      return windows.any(
        (w) =>
            (c.identity.slotId == '${w.id}:start' &&
                c.originalTime == w.start) ||
            (c.identity.slotId == '${w.id}:end' && c.originalTime == w.end) ||
            (c.identity.slotId == w.id && c.originalTime == w.reminderAnchor),
      );
    }
    if (p.timing case DailySlots(:final slots)) {
      return slots.any(
        (s) => s.id == c.identity.slotId && s.time == c.originalTime,
      );
    }
    return false;
  }

  Future<void> _validateDailyRow(
    DailyRow row, {
    bool requireCurrentVersion = true,
  }) async {
    _dailyGeneration(row.generation);
    final e = row.expectation;
    await _activeOwner(e.identity.personId, row.personRevision);
    final heads = await _rows(
      'SELECT * FROM daily_plan WHERE id=? AND person=?',
      [e.identity.planId, e.identity.personId],
    );
    if (heads.isEmpty ||
        heads.single['revision'] != row.planRevision ||
        heads.single['item'] != e.itemId) {
      throw const CommandConflict('plan_revision');
    }
    final saved = await _rows('SELECT * FROM daily_expectation WHERE id=?', [
      dailyIdentityKey(e.identity),
    ]);
    if ((saved.isEmpty ? 0 : saved.single['revision']) != row.revision) {
      throw const CommandConflict('occurrence_revision');
    }
    final phased = await phasePlan(
      planId: e.identity.planId,
      personId: e.identity.personId,
    );
    if (requireCurrentVersion && phased != null) {
      final sources = await intervalSources(
        planId: e.identity.planId,
        personId: e.identity.personId,
      );
      final expected = PhaseResolver().resolveDate(
        phased,
        e.effectiveDate ?? e.identity.originalDate,
        observedZone: e.zoneId,
        historical: saved.isEmpty
            ? const {}
            : {
                e.identity: decodeDailyExpectation(
                  dailyObject(saved.single['snapshot'] as String),
                ),
              },
        intervalSources: sources,
        now: _intervalReferenceNow(sources, DateTime.now().toUtc()),
      );
      if (!expected.any(
        (x) =>
            jsonEncode(encodeDailyExpectation(x)) ==
            jsonEncode(encodeDailyExpectation(e)),
      )) {
        throw const CommandConflict('expectation_snapshot');
      }
      if (saved.isNotEmpty &&
          saved.single['snapshot'] != jsonEncode(encodeDailyExpectation(e))) {
        throw const CommandConflict('expectation_snapshot');
      }
      return;
    }
    if (requireCurrentVersion && e.identity.intervalSegmentId != null) {
      await _validateIntervalExpectation(e);
    }
    if (requireCurrentVersion) {
      final current = await _rows(
        "SELECT snapshot FROM daily_version WHERE plan=? AND start<=? AND (end IS NULL OR end>?) AND (json_extract(snapshot,'\$.effectiveFrom') IS NULL OR json_extract(snapshot,'\$.effectiveFrom')<=?) AND (json_extract(snapshot,'\$.effectiveUntil') IS NULL OR json_extract(snapshot,'\$.effectiveUntil')>?) ORDER BY start DESC,rowid DESC LIMIT 1",
        [
          e.identity.planId,
          e.identity.originalDate.toString(),
          e.identity.originalDate.toString(),
          (e.originalInstant ?? e.instant ?? DateTime.now().toUtc())
              .microsecondsSinceEpoch,
          (e.originalInstant ?? e.instant ?? DateTime.now().toUtc())
              .microsecondsSinceEpoch,
        ],
      );
      if (current.isEmpty) throw const CommandConflict('plan_version');
      final plan = decodeDailyPlan(
        dailyObject(current.single['snapshot'] as String),
      );
      final target = e.instant ?? DateTime.now().toUtc();
      if (plan.pauses.any(
        (p) =>
            !target.isBefore(p.start) &&
            (p.resume == null || target.isBefore(p.resume!)),
      )) {
        throw const CommandConflict('plan_paused');
      }
      if (plan.onOff != null &&
          !plan.onOff!.includes(e.identity.originalDate)) {
        throw const CommandConflict('plan_break');
      }
    }
    if (saved.isNotEmpty) {
      if (saved.single['snapshot'] != jsonEncode(encodeDailyExpectation(e))) {
        throw const CommandConflict('expectation_snapshot');
      }
      return;
    }
    if (!requireCurrentVersion) return;
    final versions = await _rows(
      'SELECT snapshot FROM daily_version WHERE id=? AND plan=? AND start<=? AND (end IS NULL OR end>?)',
      [
        e.versionId,
        e.identity.planId,
        e.identity.originalDate.toString(),
        e.identity.originalDate.toString(),
      ],
    );
    if (versions.isEmpty) throw const CommandConflict('plan_version');
    final choices = await _rows(
      'SELECT snapshot FROM daily_clock WHERE plan=? AND date>=? AND date<=?',
      [
        e.identity.planId,
        e.identity.originalDate.toString(),
        e.identity.originalDate.addDays(1).toString(),
      ],
    );
    final plan = decodeDailyPlan(
      dailyObject(versions.single['snapshot'] as String),
    );
    final decisions = <DailyIdentity, DailyClockChoice>{};
    for (final c in choices) {
      final choice = decodeDailyChoice(dailyObject(c['snapshot'] as String));
      if (_dailyChoiceApplies(choice, plan, e.zoneId)) {
        decisions[choice.identity] = choice;
      }
    }
    final sources = await intervalSources(
      planId: plan.planId,
      personId: plan.personId,
    );
    final expected = DailyResolver().resolveDate(
      plan,
      e.identity.originalDate,
      intervalSources: sources,
      now: _intervalReferenceNow(sources, DateTime.now().toUtc()),
      observedZone: e.zoneId,
      decisions: decisions,
    );
    if (!expected.any(
      (x) =>
          jsonEncode(encodeDailyExpectation(x)) ==
          jsonEncode(encodeDailyExpectation(e)),
    )) {
      throw const CommandConflict('expectation_snapshot');
    }
  }

  Future<DailyAction> actDaily({
    required String commandId,
    required DailyRow row,
    required DailyActionKind kind,
    DateTime? actualAt,
    StockUseInput? stockUse,
    ProductUseInput? productUse,
    ReminderTarget? reminderTarget,
    String? reminderObservedZone,
    bool failBeforeCommit = false,
    Future<void> Function()? beforeCommit,
    ReminderClockSample? intervalClockSample,
  }) async {
    if ((kind == DailyActionKind.taken) != (actualAt != null)) {
      throw ArgumentError('daily_actual');
    }
    if (kind == DailyActionKind.skip &&
        (stockUse != null || productUse != null)) {
      throw ArgumentError('skip_stock');
    }
    _dailyGeneration(row.generation);
    final e = row.expectation;
    final capturedProductUse =
        productUse ??
        (kind == DailyActionKind.taken && row.productLabel != null
            ? ProductUseInput(
                expectedGeneration: row.generation,
                label: row.productLabel!,
                expectedItemRevision: row.itemRevision,
                enteredVolume: EnteredStockAmount(
                  e.amount.enteredText,
                  e.amount.unit,
                ),
              )
            : null);
    final bucket = dailyIdentityKey(e.identity);
    final r = await _command(
      commandId,
      [
        'daily_action',
        e.identity.personId,
        bucket,
        row.planRevision,
        row.personRevision,
        row.revision,
        row.reminderRevision,
        jsonEncode(encodeDailyExpectation(e)),
        kind.name,
        actualAt?.microsecondsSinceEpoch,
        if (stockUse != null) _stockUsePayload(stockUse),
        if (capturedProductUse != null) capturedProductUse.toJson(),
        if (reminderTarget != null) _targetJson(reminderTarget),
        if (intervalClockSample != null) _sampleJson(intervalClockSample),
      ],
      () => _actDailyInTransaction(
        commandId: commandId,
        row: row,
        kind: kind,
        actualAt: actualAt,
        stockUse: stockUse,
        capturedProductUse: capturedProductUse,
        reminderTarget: reminderTarget,
        reminderObservedZone: reminderObservedZone,
        intervalClockSample: intervalClockSample,
      ),
      failBeforeCommit: failBeforeCommit,
      beforeCommit: beforeCommit,
    );
    return _dailyAction(r);
  }

  Future<Map<String, Object?>> _actDailyInTransaction({
    required String commandId,
    required DailyRow row,
    required DailyActionKind kind,
    DateTime? actualAt,
    StockUseInput? stockUse,
    ProductUseInput? capturedProductUse,
    ReminderTarget? reminderTarget,
    String? reminderObservedZone,
    ReminderClockSample? intervalClockSample,
  }) async {
    final e = row.expectation;
    final bucket = dailyIdentityKey(e.identity);

    await _validateDailyRow(row);
    final actionInstant = actualAt ?? DateTime.now().toUtc();
    final aggregate = await phasePlan(
      planId: e.identity.planId,
      personId: e.identity.personId,
    );
    if (e.plannedCount != null &&
        aggregate?.end != null &&
        !actionInstant.isBefore(aggregate!.end!.exclusiveInstant)) {
      throw const CommandConflict('plan_ended');
    }
    if (e.eligibilityConflict != null) {
      throw const CommandConflict('plan_boundary');
    }
    final actionDate = DailyResolver().clock.dateAt(actionInstant, e.zoneId);
    final activePlans = await _rows(
      "SELECT snapshot FROM daily_version WHERE plan=? AND start<=? AND (end IS NULL OR end>?) AND (json_extract(snapshot,'\$.effectiveFrom') IS NULL OR json_extract(snapshot,'\$.effectiveFrom')<=?) AND (json_extract(snapshot,'\$.effectiveUntil') IS NULL OR json_extract(snapshot,'\$.effectiveUntil')>?) ORDER BY start DESC,rowid DESC LIMIT 1",
      [
        e.identity.planId,
        actionDate.toString(),
        actionDate.toString(),
        (actualAt ?? DateTime.now().toUtc()).microsecondsSinceEpoch,
        (actualAt ?? DateTime.now().toUtc()).microsecondsSinceEpoch,
      ],
    );
    if (activePlans.isNotEmpty) {
      final activePlan = decodeDailyPlan(
        dailyObject(activePlans.single['snapshot'] as String),
      );
      if (activePlan.pauses.any((pause) => pause.contains(actionInstant))) {
        throw const CommandConflict('plan_paused');
      }
    }
    if (kind == DailyActionKind.taken && e.identity.sourceActualId != null) {
      final sources = await intervalSources(
        planId: e.identity.planId,
        personId: e.identity.personId,
      );
      final anchor = sources
          .where(
            (source) =>
                source.actualId == e.identity.sourceActualId &&
                source.segmentId == e.identity.intervalSegmentId,
          )
          .firstOrNull;
      if (anchor == null || !actualAt!.isAfter(anchor.instant)) {
        throw const CommandConflict('interval_actual_review');
      }
    }
    if (reminderTarget != null) {
      if (jsonEncode(
            _targetJson(
              ReminderTarget(
                row: row,
                snoozeRevision: reminderTarget.snoozeRevision,
                configRevision: reminderTarget.configRevision,
              ),
            ),
          ) !=
          jsonEncode(_targetJson(reminderTarget))) {
        throw const CommandConflict('reminder_target');
      }
      await _validateReminderTarget(reminderTarget, reminderObservedZone);
    }
    if (await _reminderStateForIdentity(e.identity) != row.reminderRevision) {
      throw const CommandConflict('reminder_revision');
    }
    final progress = await _dailyProgress(bucket);
    if (progress.$1 + progress.$2 >= (e.plannedCount ?? 1)) {
      throw const CommandConflict('already_resolved');
    }
    if (row.revision == 0) {
      await _db.customStatement(
        'INSERT INTO daily_expectation(id,plan,person,date,snapshot,revision,occurs_at,effective_date,item_type,item_name,item_id,date_only) VALUES (?,?,?,?,?,1,?,?,?,?,?,?)',
        [
          bucket,
          e.identity.planId,
          e.identity.personId,
          e.identity.originalDate.toString(),
          jsonEncode(encodeDailyExpectation(e)),
          (e.instant ??
                  DisplayTime()
                      .dayBounds(
                        e.effectiveDate ?? e.identity.originalDate,
                        e.zoneId,
                      )
                      .start)
              .microsecondsSinceEpoch,
          (e.effectiveDate ?? e.identity.originalDate).toString(),
          (await _rows('SELECT type FROM item WHERE id=? AND person=?', [
            e.itemId,
            e.identity.personId,
          ])).single['type'],
          (await _rows('SELECT name FROM item WHERE id=? AND person=?', [
            e.itemId,
            e.identity.personId,
          ])).single['name'],
          e.itemId,
          e.instant == null ? 1 : 0,
        ],
      );
    } else {
      await _db.customStatement(
        'UPDATE daily_expectation SET revision=revision+1 WHERE id=?',
        [bucket],
      );
    }
    String? actualId;
    if (kind == DailyActionKind.taken) {
      final item = (await _rows('SELECT * FROM item WHERE id=? AND person=?', [
        e.itemId,
        e.identity.personId,
      ])).single;
      final currentProduct = await productLabel(
        personId: e.identity.personId,
        itemId: e.itemId,
      );
      if ((currentProduct != null) != (capturedProductUse != null) ||
          (capturedProductUse != null &&
              (stockUse != null ||
                  e.amount.unit != 'ml' ||
                  !_sameProductLabel(
                    row.productLabel,
                    capturedProductUse.label,
                  )))) {
        throw const CommandConflict('product_input');
      }
      actualId = newCommandId();
      await _db.customStatement(
        'INSERT INTO administration VALUES (?,?,?,1,?)',
        [
          actualId,
          e.identity.personId,
          e.itemId,
          actualAt!.microsecondsSinceEpoch,
        ],
      );
      final stockFields = capturedProductUse != null
          ? await _consumeProduct(
              commandId,
              e.identity.personId,
              e.itemId,
              actualId,
              capturedProductUse,
              e.amount.enteredText,
            )
          : await _consumeStock(
              commandId,
              e.identity.personId,
              e.itemId,
              actualId,
              stockUse,
              item['unit'] as String,
              e.amount.enteredText,
            );
      await _insertRevision({
        ...item,
        ...stockFields,
        'id': actualId,
        'item': e.itemId,
        'revision': 1,
        'amount': e.amount.quantity.scaled,
        'entered': e.amount.enteredText,
        'actual': actualAt.microsecondsSinceEpoch,
        'entered_at': DateTime.now().microsecondsSinceEpoch,
        'voided': 0,
        'source': e.identity.personId == meId
            ? RecordSource.selfReported.name
            : RecordSource.recordedOnBehalf.name,
      });
    }
    if (kind == DailyActionKind.taken && e.identity.intervalSegmentId != null) {
      final versions = await _rows(
        'SELECT snapshot FROM daily_version WHERE id=?',
        [e.versionId],
      );
      final timing = decodeDailyPlan(
        dailyObject(versions.single['snapshot'] as String),
      ).timing;
      if (timing is ElapsedInterval &&
          timing.mode == IntervalMode.qualifyingActual) {
        if (actualAt!.isAfter(DateTime.now().toUtc())) {
          throw const CommandConflict('future_interval_qualification');
        }
        await _writeIntervalQualification(
          e.identity.planId,
          e.identity.personId,
          timing.segmentId,
          actualId!,
          true,
        );
        await _captureIntervalClock(
          decodeDailyPlan(dailyObject(versions.single['snapshot'] as String)),
          intervalClockSample,
        );
        await _invalidateReminderPlan(e.identity.planId);
      }
    }
    await _cancelReminderBucket(bucket);
    final recordedAt = DateTime.now().microsecondsSinceEpoch;
    await _db.customStatement(
      'INSERT INTO daily_action(id,bucket,person,kind,record,revision,undone,sequence,recorded_at,occurs_at) VALUES (?,?,?,?,?,1,0,?,?,(SELECT occurs_at FROM daily_expectation WHERE id=? AND person=?))',
      [
        commandId,
        bucket,
        e.identity.personId,
        kind.name,
        actualId,
        row.revision + 1,
        recordedAt,
        bucket,
        e.identity.personId,
      ],
    );
    await _dailyIntent(
      e.identity.planId,
      e.identity.personId,
      row.planRevision,
      false,
      invalidateRequests: false,
    );
    return {
      'id': commandId,
      'kind': kind.name,
      'sequence': row.revision + 1,
      'recorded_at': recordedAt,
      'revision': 1,
      'undone': 0,
      'record': actualId,
      'actual_revision': actualId == null ? null : 1,
      'person': e.identity.personId,
    };
  }

  Future<void> undoDaily({
    required String commandId,
    required DailyRow row,
    required DailyAction action,
    PhysicalCorrection? stockCorrection,
    List<IntervalChangeReview>? intervalReviews,
  }) async {
    _dailyGeneration(row.generation);
    await _command(
      commandId,
      [
        'daily_undo',
        row.expectation.identity.personId,
        dailyIdentityKey(row.expectation.identity),
        row.planRevision,
        row.personRevision,
        row.revision,
        action.id,
        action.revision,
        action.recordRevision,
        if (stockCorrection != null) stockCorrection.name,
        if (intervalReviews?.isNotEmpty == true)
          [for (final r in intervalReviews!) _intervalReviewPayload(r)],
      ],
      () async {
        await _validateDailyRow(row, requireCurrentVersion: false);
        final targets = await _rows(
          'SELECT d.*,a.revision AS actual_revision FROM daily_action d LEFT JOIN administration a ON a.id=d.record WHERE d.id=? AND d.bucket=?',
          [action.id, dailyIdentityKey(row.expectation.identity)],
        );
        final target = targets.isEmpty ? null : _dailyAction(targets.single);
        if (target == null ||
            target.isUndone ||
            target.revision != action.revision ||
            target.recordRevision != action.recordRevision) {
          throw const CommandConflict('action_revision');
        }
        if (target.recordId != null) {
          if ((await _rows(
            'SELECT action FROM combined_member WHERE record=? AND person=?',
            [target.recordId, row.expectation.identity.personId],
          )).isNotEmpty) {
            throw const CommandConflict('combined_action_required');
          }
          final old = (await _rows(
            '${RecordStore._current} WHERE a.id=? AND a.person=?',
            [target.recordId, row.expectation.identity.personId],
          )).single;
          if (old['voided'] == 1) {
            throw const CommandConflict('action_revision');
          }
          await _validateIntervalRevisionReviews(
            target.recordId!,
            row.expectation.identity.personId,
            old['revision'] as int,
            null,
            true,
            intervalReviews,
          );
          final revision = (old['revision'] as int) + 1;
          final data = {
            ...old,
            'revision': revision,
            'entered_at': DateTime.now().microsecondsSinceEpoch,
            'voided': 1,
          };
          await _correctStock(
            commandId,
            row.expectation.identity.personId,
            target.recordId!,
            stockCorrection,
          );
          await _insertRevision(data);
          await _db.customStatement(
            'UPDATE administration SET revision=? WHERE id=?',
            [revision, target.recordId],
          );
        }
        if (target.recordId != null) {
          await _intervalActualChanged(
            target.recordId!,
            row.expectation.identity.personId,
            reviews: intervalReviews,
          );
        }
        await _db.customStatement(
          'UPDATE daily_action SET undone=1,revision=revision+1 WHERE id=?',
          [action.id],
        );
        await _db.customStatement(
          'UPDATE daily_expectation SET revision=revision+1 WHERE id=?',
          [dailyIdentityKey(row.expectation.identity)],
        );
        await _dailyIntent(
          row.expectation.identity.planId,
          row.expectation.identity.personId,
          row.planRevision,
          false,
        );
        return {
          'person': row.expectation.identity.personId,
          'undone': action.id,
        };
      },
    );
  }

  Future<void> chooseDailyClock({
    required String commandId,
    required DailyRow row,
    required ClockDecision decision,
  }) async {
    _dailyGeneration(row.generation);
    final choice = DailyClockChoice.capture(row.expectation, decision);
    final encoded = jsonEncode(encodeDailyChoice(choice));
    await _command(
      commandId,
      [
        'daily_clock',
        choice.identity.personId,
        encoded,
        row.planRevision,
        row.personRevision,
        row.revision,
      ],
      () async {
        await _validateDailyRow(row);
        if (row.revision != 0) throw const CommandConflict('captured_history');
        final versions = await _rows(
          'SELECT snapshot FROM daily_version WHERE id=? AND plan=? AND person=?',
          [choice.versionId, choice.identity.planId, choice.identity.personId],
        );
        final p = decodeDailyPlan(
          dailyObject(versions.single['snapshot'] as String),
        );
        DailyResolver().resolveDate(
          p,
          choice.identity.originalDate,
          observedZone: choice.zoneId,
          decisions: {choice.identity: choice},
        );
        await _db.customStatement(
          'INSERT INTO daily_clock VALUES (?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET snapshot=excluded.snapshot',
          [
            dailyIdentityKey(choice.identity),
            choice.identity.planId,
            choice.identity.personId,
            choice.identity.originalDate.toString(),
            encoded,
          ],
        );
        await _dailyIntent(
          choice.identity.planId,
          choice.identity.personId,
          row.planRevision,
          false,
        );
        return {'person': choice.identity.personId, 'choice': encoded};
      },
    );
  }
}
