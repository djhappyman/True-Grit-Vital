part of 'record_store.dart';

const pauseSchemaV12 = [
  'DROP TRIGGER daily_version_overlap',
  'ALTER TABLE daily_version RENAME TO daily_version_v11',
  'CREATE TABLE daily_version(id TEXT PRIMARY KEY,plan TEXT NOT NULL,person TEXT NOT NULL,start TEXT NOT NULL,end TEXT,snapshot TEXT NOT NULL,FOREIGN KEY(plan,person) REFERENCES daily_plan(id,person) ON DELETE CASCADE,CHECK(end IS NULL OR end>start)) STRICT',
  'INSERT INTO daily_version SELECT * FROM daily_version_v11',
  'DROP TABLE daily_version_v11',
  'CREATE INDEX daily_version_bounds ON daily_version(plan,start,end)',
  "CREATE TRIGGER daily_version_overlap BEFORE INSERT ON daily_version WHEN EXISTS(SELECT 1 FROM daily_version v WHERE v.plan=NEW.plan AND (NEW.end IS NULL OR v.start<NEW.end) AND (v.end IS NULL OR NEW.start<v.end) AND NOT ((json_extract(v.snapshot,'\$.effectiveUntil') IS NOT NULL AND json_extract(NEW.snapshot,'\$.effectiveFrom') IS NOT NULL AND json_extract(v.snapshot,'\$.effectiveUntil')<=json_extract(NEW.snapshot,'\$.effectiveFrom')) OR (json_extract(NEW.snapshot,'\$.effectiveUntil') IS NOT NULL AND json_extract(v.snapshot,'\$.effectiveFrom') IS NOT NULL AND json_extract(NEW.snapshot,'\$.effectiveUntil')<=json_extract(v.snapshot,'\$.effectiveFrom')))) BEGIN SELECT RAISE(ABORT,'daily_version_overlap'); END",
  'ALTER TABLE ordinary_draft RENAME TO ordinary_draft_v11',
  "CREATE TABLE ordinary_draft(id TEXT PRIMARY KEY,generation TEXT NOT NULL,operation TEXT NOT NULL UNIQUE,kind TEXT NOT NULL CHECK(kind IN ('item','dose','correction','profile','dailyPlan','pausePlan','itemType','stockContainer','stockAdjustment','productLabel')),person TEXT REFERENCES person(id),person_revision INTEGER,target TEXT,target_revision INTEGER,snapshot TEXT NOT NULL) STRICT",
  'INSERT INTO ordinary_draft SELECT * FROM ordinary_draft_v11',
  'DROP TABLE ordinary_draft_v11',
  '''CREATE TABLE pause_change(id TEXT PRIMARY KEY,plan TEXT NOT NULL,person TEXT NOT NULL,revision INTEGER NOT NULL,before_snapshot TEXT NOT NULL,after_snapshot TEXT NOT NULL,recorded_at INTEGER NOT NULL,UNIQUE(plan,revision),FOREIGN KEY(plan,person) REFERENCES daily_plan(id,person) ON DELETE CASCADE) STRICT''',
  '''CREATE TRIGGER pause_change_immutable BEFORE UPDATE ON pause_change BEGIN SELECT RAISE(ABORT,'pause_history_immutable'); END''',
];

extension PauseRecordStore on RecordStore {
  /// Previews a change without writing history, sources or reminder intents.
  Future<PauseChangeReview> previewPauseChange({
    required SavedDailyPlan plan,
    required DailyPlanVersion proposed,
    required DateTime now,
    required String observedZone,
    DateTime? restartAt,
  }) => _db.transaction(() async {
    final owner = await profileById(plan.plan.personId);
    if (owner == null || owner.isArchived) {
      throw const CommandConflict('ownership');
    }
    proposed = _pauseProposed(plan.plan, proposed, restartAt, observedZone);
    _validatePauseProposal(plan.plan, proposed, restartAt: restartAt);
    final sources = await intervalSources(
      planId: plan.plan.planId,
      personId: plan.plan.personId,
    );
    if (sources.length > 100000) {
      throw const CommandConflict('interval_source_bound');
    }
    DailyNext next(DailyPlanVersion p) {
      final resolver = DailyResolver();
      if (p.timing is ElapsedInterval &&
          (p.timing as ElapsedInterval).mode == IntervalMode.qualifyingActual) {
        final current = IntervalResolver().current(
          p,
          now: now,
          observedZone: observedZone,
          sources: sources,
        );
        if (!current.complete) throw const CommandConflict('pause_calculation');
        return DailyNext(next: current.next, complete: true, datesExamined: 0);
      }
      final result = p.timing is DailyCount
          ? resolver.nextDate(
              p,
              from: resolver.clock.dateAt(
                now,
                p.zoneBasis.zoneFor(observedZone),
              ),
              observedZone: observedZone,
              intervalSources: sources,
              now: now,
            )
          : resolver.nextInstant(
              p,
              after: now,
              observedZone: observedZone,
              intervalSources: sources,
              maxDates: 366,
              now: now,
            );
      if (!result.complete) throw const CommandConflict('pause_calculation');
      return result;
    }

    final aggregate = await phasePlan(
      planId: plan.plan.planId,
      personId: plan.plan.personId,
    );
    DailyNext phaseNext(PhasePlan candidate) {
      final resolver = PhaseResolver();
      if (candidate.phases.any(
        (p) =>
            p.timing is DailyCount ||
            p.timing is MixedDailyCount ||
            p.timing is DailyWindows &&
                (p.timing as DailyWindows).windows.any(
                  (w) => w.reminderAnchor == null,
                ),
      )) {
        return resolver.nextDate(
          candidate,
          from: resolver.clock.dateAt(
            now,
            candidate.phases.first.zoneBasis.zoneFor(observedZone),
          ),
          observedZone: observedZone,
          intervalSources: sources,
          now: now,
        );
      }
      return resolver.nextInstant(
        candidate,
        after: now,
        maxDates: 366,
        observedZone: observedZone,
        intervalSources: sources,
        now: now,
      );
    }

    PhasePlan revised(PhasePlan current) {
      final phases = <DailyPlanVersion>[];
      for (final p in current.phases) {
        if (p.versionId != plan.plan.versionId) {
          phases.add(p);
          continue;
        }
        if (restartAt != null) {
          phases.add(
            DailyPlanVersion(
              personId: p.personId,
              planId: p.planId,
              itemId: p.itemId,
              versionId: p.versionId,
              start: p.start,
              endExclusive: p.endExclusive,
              timing: p.timing,
              zoneBasis: p.zoneBasis,
              calendar: p.calendar,
              pauses: proposed.pauses,
              onOff: p.onOff,
              instructions: p.instructions,
              timingPolicy: p.timingPolicy,
              requirements: p.requirements,
              doseDisplay: p.doseDisplay,
              stopCondition: p.stopCondition,
              effectiveFrom: p.effectiveFrom,
              effectiveUntil: restartAt,
            ),
          );
        }
        phases.add(proposed);
      }
      final origins = [...current.originPhases];
      if (!phases.any((p) => p.versionId == plan.plan.versionId) &&
          current.overrides.any((o) => o.versionId == plan.plan.versionId) &&
          !origins.any((p) => p.versionId == plan.plan.versionId)) {
        origins.add(plan.plan);
      }
      return PhasePlan(
        phases: phases,
        originPhases: origins,
        end: current.end,
        overrides: current.overrides,
      );
    }

    final before = aggregate == null ? next(plan.plan) : phaseNext(aggregate);
    final after = aggregate == null
        ? next(proposed)
        : phaseNext(revised(aggregate));
    return PauseChangeReview(
      plan: plan,
      proposed: proposed,
      restartAt: restartAt,
      personRevision: owner.revision,
      generation: generation,
      sourceGuard: await _intervalGuard(plan.plan.planId, plan.plan.personId),
      now: now,
      observedZone: observedZone,
      before: before.next,
      after: after.next,
      beforeDate: before.next?.identity.originalDate ?? before.calendarDate,
      afterDate: after.next?.identity.originalDate ?? after.calendarDate,
    );
  });

  DailyPlanVersion _pauseProposed(
    DailyPlanVersion old,
    DailyPlanVersion proposed,
    DateTime? restartAt,
    String observedZone,
  ) {
    if (restartAt == null) return proposed;
    if (!restartAt.isUtc) throw const CommandConflict('restart_boundary');
    final date = DailyResolver().clock.dateAt(
      restartAt,
      proposed.zoneBasis.zoneFor(observedZone),
    );
    if (date.compareTo(old.start) < 0) {
      throw const CommandConflict('restart_boundary');
    }
    return DailyPlanVersion(
      personId: proposed.personId,
      planId: proposed.planId,
      itemId: proposed.itemId,
      versionId: proposed.versionId,
      start: date,
      endExclusive: proposed.endExclusive,
      timing: proposed.timing,
      zoneBasis: proposed.zoneBasis,
      calendar: proposed.calendar,
      pauses: proposed.pauses,
      onOff: proposed.onOff,
      instructions: proposed.instructions,
      timingPolicy: proposed.timingPolicy,
      requirements: proposed.requirements,
      doseDisplay: proposed.doseDisplay,
      stopCondition: proposed.stopCondition,
      effectiveFrom: restartAt,
      effectiveUntil: proposed.effectiveUntil,
    );
  }

  void _validatePauseProposal(
    DailyPlanVersion old,
    DailyPlanVersion proposed, {
    DateTime? restartAt,
  }) {
    if (old.personId != proposed.personId ||
        old.planId != proposed.planId ||
        old.itemId != proposed.itemId ||
        (restartAt == null
            ? old.start != proposed.start
            : proposed.start.compareTo(old.start) < 0) ||
        old.endExclusive != proposed.endExclusive ||
        old.versionId == proposed.versionId) {
      throw const CommandConflict('pause_plan_identity');
    }
    if ((restartAt == null &&
            (old.effectiveFrom != proposed.effectiveFrom ||
                old.effectiveUntil != proposed.effectiveUntil)) ||
        (restartAt != null &&
            (proposed.effectiveFrom != restartAt ||
                proposed.effectiveUntil != old.effectiveUntil ||
                old.effectiveFrom != null &&
                    !restartAt.isAfter(old.effectiveFrom!)))) {
      throw const CommandConflict('restart_boundary');
    }
    if (old.zoneBasis.zoneFor('Etc/UTC') !=
        proposed.zoneBasis.zoneFor('Etc/UTC')) {
      throw const CommandConflict('pause_zone');
    }
    if (proposed.versionId.length > 256 ||
        (proposed.timing is ElapsedInterval &&
            (proposed.timing as ElapsedInterval).segmentId.length > 256)) {
      throw const CommandConflict('plan_identity_bound');
    }
    if (proposed.pauses.length > 10000) {
      throw const CommandConflict('pause_history_bound');
    }
    if (old.timing case ElapsedInterval(:final segmentId)) {
      final next = proposed.timing;
      if (next is! ElapsedInterval) throw const CommandConflict('pause_timing');
      if (next.segmentId == segmentId &&
          jsonEncode(encodeDailyPlan(old)['timing']) !=
              jsonEncode(encodeDailyPlan(proposed)['timing'])) {
        throw const CommandConflict('interval_segment_identity');
      }
      if (next.segmentId != segmentId &&
          next.mode != IntervalMode.fixedPlanned) {
        throw const CommandConflict('restart_planned_anchor');
      }
    } else if (jsonEncode(encodeDailyPlan(old)['timing']) !=
        jsonEncode(encodeDailyPlan(proposed)['timing'])) {
      throw const CommandConflict('pause_timing');
    }
  }

  /// Commits the reviewed future definition and immutable history atomically.
  Future<SavedDailyPlan> savePauseChange({
    required String commandId,
    required PauseChangeReview review,
    ReminderClockSample? intervalClockSample,
    bool failBeforeCommit = false,
    Future<void> Function()? beforeCommit,
  }) async {
    _dailyGeneration(review.generation);
    final p = review.plan.plan, proposed = review.proposed;
    final before = jsonEncode(encodeDailyPlan(p)),
        after = jsonEncode(encodeDailyPlan(proposed));
    final result = await _command(
      commandId,
      [
        'pause_change',
        p.personId,
        before,
        after,
        review.plan.revision,
        review.personRevision,
        review.sourceGuard,
        review.now.microsecondsSinceEpoch,
        review.observedZone,
        review.restartAt?.microsecondsSinceEpoch,
        if (intervalClockSample != null) _sampleJson(intervalClockSample),
      ],
      () async {
        await _activeOwner(p.personId, review.personRevision);
        _validatePauseProposal(p, proposed, restartAt: review.restartAt);
        if (review.restartAt != null &&
            _pauseProposed(
                  p,
                  proposed,
                  review.restartAt,
                  review.observedZone,
                ).start !=
                proposed.start) {
          throw const CommandConflict('restart_boundary');
        }
        final current = await _rows(
          'SELECT v.snapshot,p.revision FROM daily_version v JOIN daily_plan p ON p.id=v.plan WHERE v.id=? AND p.person=?',
          [p.versionId, p.personId],
        );
        if (current.length != 1 ||
            current.single['revision'] != review.plan.revision ||
            current.single['snapshot'] != before) {
          throw const CommandConflict('plan_revision');
        }
        if (await _intervalGuard(p.planId, p.personId) != review.sourceGuard) {
          throw const CommandConflict('interval_source_revision');
        }
        if ((await _rows('SELECT id FROM daily_version_audit WHERE id=?', [
          proposed.versionId,
        ])).isNotEmpty) {
          throw const CommandConflict('version_identity');
        }
        if (proposed.timing case ElapsedInterval(:final segmentId)) {
          if (p.timing is! ElapsedInterval ||
              segmentId != (p.timing as ElapsedInterval).segmentId) {
            final history = await _rows(
              'SELECT snapshot FROM daily_version_audit WHERE plan=? LIMIT 10001',
              [p.planId],
            );
            if (history.length > 10000) {
              throw const CommandConflict('pause_history_bound');
            }
            for (final row in history) {
              final timing = decodeDailyPlan(
                dailyObject(row['snapshot'] as String),
              ).timing;
              if (timing is ElapsedInterval && timing.segmentId == segmentId) {
                throw const CommandConflict('interval_segment_identity');
              }
            }
          }
        }
        final revision = review.plan.revision + 1;
        await _db.customStatement(
          'INSERT INTO pause_change VALUES (?,?,?,?,?,?,?)',
          [
            commandId,
            p.planId,
            p.personId,
            revision,
            before,
            after,
            DateTime.now().microsecondsSinceEpoch,
          ],
        );
        if (review.restartAt != null) {
          final closed = DailyPlanVersion(
            personId: p.personId,
            planId: p.planId,
            itemId: p.itemId,
            versionId: p.versionId,
            start: p.start,
            endExclusive: p.endExclusive,
            timing: p.timing,
            zoneBasis: p.zoneBasis,
            calendar: p.calendar,
            pauses: proposed.pauses,
            onOff: p.onOff,
            instructions: p.instructions,
            timingPolicy: p.timingPolicy,
            requirements: p.requirements,
            doseDisplay: p.doseDisplay,
            stopCondition: p.stopCondition,
            effectiveFrom: p.effectiveFrom,
            effectiveUntil: review.restartAt,
          );
          await _db.customStatement(
            'UPDATE daily_version SET snapshot=? WHERE id=?',
            [jsonEncode(encodeDailyPlan(closed)), p.versionId],
          );
          await _db.customStatement(
            'INSERT INTO daily_version VALUES (?,?,?,?,?,?)',
            [
              proposed.versionId,
              p.planId,
              p.personId,
              proposed.start.toString(),
              proposed.endExclusive?.toString(),
              after,
            ],
          );
        } else {
          await _db.customStatement(
            'UPDATE daily_version SET id=?,snapshot=? WHERE id=?',
            [proposed.versionId, after, p.versionId],
          );
        }
        await _db.customStatement(
          'INSERT INTO daily_version_audit VALUES (?,?,?,?,?)',
          [proposed.versionId, p.planId, p.personId, revision, after],
        );
        await _db.customStatement(
          'UPDATE daily_plan SET revision=? WHERE id=?',
          [revision, p.planId],
        );
        // Preserve the existing segment clock, sources and reviewed recovery cutoff.
        // A restart receives its own segment and requires separate clock review.
        await _db.customStatement(
          'UPDATE reminder_state SET revision=revision+1,snooze_revision=snooze_revision+1 WHERE plan=?',
          [p.planId],
        );
        if (proposed.timing is ElapsedInterval &&
            (p.timing as ElapsedInterval).segmentId !=
                (proposed.timing as ElapsedInterval).segmentId) {
          await _captureIntervalClock(
            proposed,
            intervalClockSample,
            replace: false,
          );
        }
        await phasePlan(planId: p.planId, personId: p.personId);
        await _dailyIntent(p.planId, p.personId, revision, false);
        return {'person': p.personId, 'snapshot': after, 'revision': revision};
      },
      failBeforeCommit: failBeforeCommit,
      beforeCommit: beforeCommit,
    );
    return _savedPlan(result);
  }

  /// Returns a bounded page of immutable pause and break changes.
  Future<List<Map<String, Object?>>> pauseHistory({
    required String planId,
    required String personId,
    int limit = 100,
    int offset = 0,
  }) {
    _pageBounds(limit, offset);
    return _rows(
      'SELECT * FROM pause_change WHERE plan=? AND person=? ORDER BY revision LIMIT ? OFFSET ?',
      [planId, personId, limit, offset],
    );
  }
}
