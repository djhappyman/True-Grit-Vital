part of 'record_store.dart';

const phaseSchemaV13 = [
  'CREATE TABLE phase_plan(plan TEXT PRIMARY KEY,person TEXT NOT NULL,snapshot TEXT NOT NULL,FOREIGN KEY(plan,person) REFERENCES daily_plan(id,person) ON DELETE CASCADE) STRICT',
  'CREATE TABLE phase_change(id TEXT PRIMARY KEY,plan TEXT NOT NULL,person TEXT NOT NULL,revision INTEGER NOT NULL,snapshot TEXT NOT NULL,recorded_at INTEGER NOT NULL,UNIQUE(plan,revision),FOREIGN KEY(plan,person) REFERENCES daily_plan(id,person) ON DELETE CASCADE) STRICT',
  "CREATE TRIGGER phase_change_immutable BEFORE UPDATE ON phase_change BEGIN SELECT RAISE(ABORT,'phase_history_immutable'); END",
  'CREATE TABLE phase_override(plan TEXT NOT NULL,person TEXT NOT NULL,identity TEXT NOT NULL,origin_date TEXT NOT NULL,target_date TEXT NOT NULL,snapshot TEXT NOT NULL,PRIMARY KEY(plan,identity),FOREIGN KEY(plan,person) REFERENCES daily_plan(id,person) ON DELETE CASCADE) STRICT',
  'CREATE INDEX phase_override_target ON phase_override(plan,target_date,origin_date)',
  'CREATE INDEX phase_override_origin ON phase_override(plan,origin_date,target_date)',
  'ALTER TABLE ordinary_draft RENAME TO ordinary_draft_v12',
  "CREATE TABLE ordinary_draft(id TEXT PRIMARY KEY,generation TEXT NOT NULL,operation TEXT NOT NULL UNIQUE,kind TEXT NOT NULL CHECK(kind IN ('item','dose','correction','profile','dailyPlan','pausePlan','phasePlan','itemType','stockContainer','stockAdjustment','productLabel')),person TEXT REFERENCES person(id),person_revision INTEGER,target TEXT,target_revision INTEGER,snapshot TEXT NOT NULL) STRICT",
  'INSERT INTO ordinary_draft SELECT * FROM ordinary_draft_v12',
  'DROP TABLE ordinary_draft_v12',
];

extension PhaseRecordStore on RecordStore {
  void _phaseTimingBound(DailyPlanVersion p) {
    final timing = p.timing;
    final ids = switch (timing) {
      DailySlots(:final slots) => slots.map((s) => s.id),
      MixedDailyCount(:final slots) => slots.map((s) => s.id),
      DailyWindows(:final windows) => windows.map((w) => w.id),
      _ => const <String>[],
    };
    if (ids.length > 100 || ids.any((id) => id.length > 256)) {
      throw const CommandConflict('daily_slot_bound');
    }
    if (timing is MixedDailyCount && timing.count > 100000) {
      throw const CommandConflict('daily_count_bound');
    }
  }

  Future<List<DailyPlanVersion>> _phaseVersions(
    String planId,
    String personId,
  ) async {
    final rows = await _rows(
      "SELECT v.snapshot FROM daily_version v JOIN daily_plan p ON p.id=v.plan WHERE p.id=? AND p.person=? ORDER BY v.start,COALESCE(json_extract(v.snapshot,'\$.effectiveFrom'),-9223372036854775808),v.rowid LIMIT 1001",
      [planId, personId],
    );
    if (rows.length > 1000) throw const CommandConflict('phase_bound');
    return rows
        .map((r) => decodeDailyPlan(dailyObject(r['snapshot'] as String)))
        .toList();
  }

  Future<PhasePlan?> phasePlan({
    required String planId,
    required String personId,
    CivilDate? from,
    CivilDate? toExclusive,
  }) async {
    final rows = await _rows(
      'SELECT snapshot FROM phase_plan WHERE plan=? AND person=?',
      [planId, personId],
    );
    // Versions are authoritative after ordinary edits or pause/restart commands.
    final versions = await _phaseVersions(planId, personId);
    if (versions.isEmpty) return null;
    if (rows.isEmpty && versions.every((p) => p.stopCondition == null)) {
      return null;
    }
    final stored = rows.isEmpty
        ? PhasePlan(phases: versions)
        : decodePhasePlan(dailyObject(rows.single['snapshot'] as String));
    final versionEnds = <String, PlanEnd>{};
    for (final version in versions) {
      final bound = await _scheduleStop(version);
      if (bound != null) versionEnds[version.versionId] = bound;
    }
    final origins = <DailyPlanVersion>[];
    for (final id
        in stored.overrides
            .map((o) => o.versionId)
            .toSet()
            .where((id) => !versions.any((p) => p.versionId == id))) {
      final rows = await _rows(
        'SELECT snapshot FROM daily_version_audit WHERE id=? AND plan=? AND person=?',
        [id, planId, personId],
      );
      if (rows.length != 1) {
        throw const CommandConflict('override_origin_unavailable');
      }
      origins.add(
        decodeDailyPlan(dailyObject(rows.single['snapshot'] as String)),
      );
    }
    var overrides = stored.overrides;
    if (from != null && toExclusive != null) {
      final selected = await _rows(
        'SELECT snapshot FROM phase_override WHERE plan=? AND target_date>=? AND target_date<? UNION SELECT snapshot FROM phase_override WHERE plan=? AND origin_date>=? AND origin_date<? LIMIT 1001',
        [
          planId,
          from.toString(),
          toExclusive.toString(),
          planId,
          from.toString(),
          toExclusive.toString(),
        ],
      );
      if (selected.length > 1000) throw const CommandConflict('phase_bound');
      overrides = [
        for (final row in selected)
          ...decodePhasePlan({
            'phases': [for (final p in versions) encodeDailyPlan(p)],
            'originPhases': [for (final p in origins) encodeDailyPlan(p)],
            'overrides': jsonDecode(row['snapshot'] as String),
          }).overrides,
      ];
    }
    return PhasePlan(
      phases: versions,
      originPhases: origins,
      end: stored.end,
      versionEnds: versionEnds,
      overrides: overrides,
    );
  }

  Future<PhaseChangeReview> previewPhasePlan({
    required SavedDailyPlan plan,
    required PhasePlan proposed,
    required DateTime now,
    required String observedZone,
  }) => _db.transaction(() async {
    final p = plan.plan;
    if (proposed.planId != p.planId ||
        proposed.personId != p.personId ||
        proposed.itemId != p.itemId) {
      throw const CommandConflict('phase_identity');
    }
    final owner = await profileById(p.personId);
    if (owner == null || owner.isArchived) {
      throw const CommandConflict('ownership');
    }
    final sources = await intervalSources(
      planId: p.planId,
      personId: p.personId,
    );
    final existing =
        await phasePlan(planId: p.planId, personId: p.personId) ??
        PhasePlan(phases: await _phaseVersions(p.planId, p.personId));
    final resolver = PhaseResolver();
    DailyNext next(PhasePlan candidate) {
      final hasUntimed = candidate.phases.any(
        (p) =>
            p.timing is DailyCount ||
            p.timing is MixedDailyCount ||
            p.timing is DailyWindows &&
                (p.timing as DailyWindows).windows.any(
                  (w) => w.reminderAnchor == null,
                ),
      );
      if (hasUntimed) {
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

    final before = next(existing), after = next(proposed);
    if (!before.complete || !after.complete) {
      throw const CommandConflict('phase_calculation');
    }
    await _validatePhaseProposal(existing, proposed, now, observedZone);
    return PhaseChangeReview(
      plan: plan,
      proposed: proposed,
      personRevision: owner.revision,
      generation: generation,
      sourceGuard: await _intervalGuard(p.planId, p.personId),
      now: now,
      observedZone: observedZone,
      before: before.next,
      after: after.next,
      beforeIssue: before.issue,
      afterIssue: after.issue,
    );
  });

  Future<DailyNext> _nextPhase(
    PhasePlan plan, {
    required DateTime now,
    required String observedZone,
    required int maxDates,
    required Map<DailyIdentity, DailyExpectation> historical,
    required Map<DailyIdentity, DailyClockChoice> decisions,
    required List<IntervalSource> sources,
  }) async {
    final resolver = PhaseResolver();
    final hasUntimed = plan.phases.any(
      (p) =>
          p.timing is DailyCount ||
          p.timing is MixedDailyCount ||
          p.timing is DailyWindows &&
              (p.timing as DailyWindows).windows.any(
                (w) => w.reminderAnchor == null,
              ),
    );
    var date = resolver.clock.dateAt(
      now,
      plan.phases.first.zoneBasis.zoneFor(observedZone),
    );
    var cursor = now;
    for (var attempt = 0; attempt < maxDates * 100; attempt++) {
      final result = hasUntimed
          ? resolver.nextDate(
              plan,
              from: date,
              observedZone: observedZone,
              historical: historical,
              decisions: decisions,
              intervalSources: sources,
              now: now,
            )
          : resolver.nextInstant(
              plan,
              after: cursor,
              observedZone: observedZone,
              maxDates: maxDates,
              historical: historical,
              decisions: decisions,
              intervalSources: sources,
              now: now,
            );
      if (!result.complete || result.next == null) return result;
      final candidate = result.next!;
      final candidateDate =
          candidate.effectiveDate ?? candidate.identity.originalDate;
      final siblings = resolver.resolveDate(
        plan,
        candidateDate,
        observedZone: observedZone,
        historical: historical,
        decisions: decisions,
        intervalSources: sources,
        now: now,
      );
      for (final row in siblings) {
        if (!hasUntimed && row.instant != candidate.instant) continue;
        final progress = await _dailyProgress(dailyIdentityKey(row.identity));
        if (progress.$1 + progress.$2 < (row.plannedCount ?? 1)) {
          return DailyNext(
            next: row,
            calendarDate: candidateDate,
            complete: true,
            datesExamined: result.datesExamined,
            needsReview: result.needsReview,
            issue: result.issue,
          );
        }
      }
      if (hasUntimed) {
        if (candidateDate == CivilDate(9999, 12, 31)) {
          return DailyNext(complete: true, datesExamined: result.datesExamined);
        }
        date = candidateDate.addDays(1);
        if (attempt >= maxDates) {
          return DailyNext(complete: false, datesExamined: maxDates);
        }
      } else {
        cursor = candidate.instant!;
      }
    }
    return DailyNext(complete: false, datesExamined: maxDates);
  }

  /// Saves an explicit gap/fold decision for one entered window endpoint.
  Future<void> chooseWindowClock({
    required String commandId,
    required DailyRow row,
    required DailyExpectation endpoint,
    required ClockDecision decision,
  }) async {
    _dailyGeneration(row.generation);
    final choice = DailyClockChoice.capture(endpoint, decision);
    final encoded = jsonEncode(encodeDailyChoice(choice));
    await _command(
      commandId,
      [
        'window_clock',
        row.expectation.identity.personId,
        encoded,
        row.planRevision,
        row.personRevision,
        row.revision,
      ],
      () async {
        await _validateDailyRow(row);
        if (row.revision != 0) throw const CommandConflict('captured_history');
        if (!row.expectation.windowEndpoints.any(
          (e) =>
              jsonEncode(encodeDailyExpectation(e)) ==
              jsonEncode(encodeDailyExpectation(endpoint)),
        )) {
          throw const CommandConflict('window_endpoint');
        }
        final versions = await _rows(
          'SELECT snapshot FROM daily_version WHERE id=? AND person=?',
          [endpoint.versionId, endpoint.identity.personId],
        );
        if (versions.length != 1 ||
            !_dailyChoiceApplies(
              choice,
              decodeDailyPlan(
                dailyObject(versions.single['snapshot'] as String),
              ),
              endpoint.zoneId,
            )) {
          throw const CommandConflict('window_endpoint');
        }
        final currentPlan = decodeDailyPlan(
          dailyObject(versions.single['snapshot'] as String),
        );
        final savedChoices = await _rows(
          'SELECT snapshot FROM daily_clock WHERE plan=? AND date>=? AND date<=?',
          [
            choice.identity.planId,
            row.expectation.identity.originalDate.toString(),
            row.expectation.identity.originalDate.addDays(1).toString(),
          ],
        );
        final decisions = <DailyIdentity, DailyClockChoice>{};
        for (final saved in savedChoices) {
          final previous = decodeDailyChoice(
            dailyObject(saved['snapshot'] as String),
          );
          if (_dailyChoiceApplies(previous, currentPlan, endpoint.zoneId)) {
            decisions[previous.identity] = previous;
          }
        }
        decisions[choice.identity] = choice;
        final resolved = DailyResolver().resolveDate(
          currentPlan,
          row.expectation.identity.originalDate,
          observedZone: endpoint.zoneId,
          decisions: decisions,
        );
        if (resolved.any(
          (e) =>
              e.identity == row.expectation.identity &&
              e.eligibilityConflict != null,
        )) {
          throw const CommandConflict('window_boundary');
        }
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

  bool _phaseRetainsPrefix(
    DailyPlanVersion old,
    DailyPlanVersion next,
    DateTime now,
    String zone,
  ) {
    if (jsonEncode(encodeDailyPlan(old)) == jsonEncode(encodeDailyPlan(next))) {
      return true;
    }
    final before = Map<String, Object?>.from(encodeDailyPlan(old))
      ..remove('end')
      ..remove('effectiveUntil');
    final after = Map<String, Object?>.from(encodeDailyPlan(next))
      ..remove('end')
      ..remove('effectiveUntil');
    if (jsonEncode(before) != jsonEncode(after)) return false;
    if (old.endExclusive != null &&
        (next.endExclusive == null ||
            next.endExclusive!.compareTo(old.endExclusive!) > 0)) {
      return false;
    }
    if (old.effectiveUntil != null &&
        (next.effectiveUntil == null ||
            next.effectiveUntil!.isAfter(old.effectiveUntil!))) {
      return false;
    }
    if (next.effectiveUntil != old.effectiveUntil &&
        (next.effectiveUntil == null || next.effectiveUntil!.isBefore(now))) {
      return false;
    }
    if (next.endExclusive != old.endExclusive &&
        (next.endExclusive == null ||
            next.endExclusive!.compareTo(
                  DailyResolver().clock.dateAt(
                    now,
                    old.zoneBasis.zoneFor(zone),
                  ),
                ) <=
                0)) {
      return false;
    }
    return true;
  }

  Future<void> _validatePhaseProposal(
    PhasePlan existing,
    PhasePlan proposed,
    DateTime now,
    String zone,
  ) async {
    if (proposed.phases.length > 100 ||
        proposed.originPhases.length > 1000 ||
        proposed.overrides.length > 1000) {
      throw const CommandConflict('phase_bound');
    }
    for (final origin in proposed.originPhases) {
      final audit = await _rows(
        'SELECT snapshot FROM daily_version_audit WHERE id=? AND plan=? AND person=?',
        [origin.versionId, proposed.planId, proposed.personId],
      );
      if (audit.length != 1 ||
          audit.single['snapshot'] != jsonEncode(encodeDailyPlan(origin))) {
        throw const CommandConflict('override_origin_revision');
      }
    }
    final item = await itemById(proposed.itemId, personId: proposed.personId);
    if (item == null) throw const CommandConflict('ownership');
    for (final p in proposed.phases) {
      _phaseTimingBound(p);
      if (p.versionId.length > 256) {
        throw const CommandConflict('plan_identity_bound');
      }
      final amounts = switch (p.timing) {
        AsNeeded() => const <PlannedAmount>[],
        DailyCount(:final amount) => [amount],
        ElapsedInterval(:final amount) => [amount],
        DailySlots(:final slots) => slots.map((s) => s.amount),
        DailyWindows(:final windows) => windows.map((w) => w.amount),
        MixedDailyCount(:final amount, :final slots) => [
          amount,
          ...slots.map((s) => s.amount),
        ],
      };
      if (amounts.any((a) => a.unit != item.unit)) {
        throw const CommandConflict('plan_unit');
      }
      DailyResolver().clock.validateZone(p.zoneBasis.zoneFor(zone));
    }
    for (final old in existing.phases) {
      final replacement = proposed.phases.where(
        (p) => p.versionId == old.versionId,
      );
      final date = DailyResolver().clock.dateAt(
        now,
        old.zoneBasis.zoneFor(zone),
      );
      if (old.start.compareTo(date) <= 0 &&
          (replacement.length != 1 ||
              !_phaseRetainsPrefix(old, replacement.single, now, zone))) {
        throw const CommandConflict('phase_history');
      }
    }
    // Verify explicitly entered window boundaries without expanding unbounded future dates.
    for (final phase in proposed.phases.where(
      (p) => p.timing is DailyWindows,
    )) {
      final clock = DailyResolver().clock;
      final phaseZone = phase.zoneBasis.zoneFor(zone);
      final dates = <CivilDate>{
        phase.start,
        if (phase.endExclusive != null) phase.endExclusive!,
      };
      final instants = <DateTime>[
        ?phase.effectiveFrom,
        ?phase.effectiveUntil,
        ?proposed.end?.exclusiveInstant,
        for (final pause in phase.pauses) ...[pause.start, ?pause.resume],
      ];
      for (final instant in instants) {
        dates.add(clock.dateAt(instant, phaseZone));
      }
      final checks = <CivilDate>{
        ...dates,
        for (final date in dates)
          if (date != CivilDate(1, 1, 1)) date.addDays(-1),
      };
      if (checks.length > 2000 || phase.pauses.length > 10000) {
        throw const CommandConflict('phase_boundary_bound');
      }
      final savedChoices = await _rows(
        'SELECT snapshot FROM daily_clock WHERE plan=? LIMIT 100001',
        [proposed.planId],
      );
      if (savedChoices.length > 100000) {
        throw const CommandConflict('phase_boundary_bound');
      }
      final decisions = <DailyIdentity, DailyClockChoice>{};
      for (final saved in savedChoices) {
        final choice = decodeDailyChoice(
          dailyObject(saved['snapshot'] as String),
        );
        if (_dailyChoiceApplies(choice, phase, zone)) {
          decisions[choice.identity] = choice;
        }
      }
      for (final date in checks) {
        if (date == CivilDate(9999, 12, 31)) {
          continue;
        }
        PhaseResolver(strictOverrides: true).expand(
          PhasePlan(phases: [phase], end: proposed.end),
          from: date,
          toExclusive: date.addDays(1),
          observedZone: zone,
          maxDates: 2,
          maxRows: 1000,
          decisions: decisions,
          now: now,
        );
      }
    }
    final captures = await _rows(
      'SELECT snapshot FROM daily_expectation WHERE plan=? LIMIT 100001',
      [proposed.planId],
    );
    if (captures.length > 100000) {
      throw const CommandConflict('captured_history');
    }
    for (final row in captures) {
      final e = decodeDailyExpectation(dailyObject(row['snapshot'] as String));
      final retained = [
        ...proposed.phases,
        ...proposed.originPhases,
      ].where((p) => p.versionId == e.versionId);
      if (retained.length != 1 ||
          !retained.single.includes(e.identity.originalDate) ||
          (e.originalInstant ?? e.instant) != null &&
              !retained.single.includesInstant(
                (e.originalInstant ?? e.instant)!,
              )) {
        throw const CommandConflict('captured_history');
      }
      final nextOverride = proposed.overrides.where(
        (o) => o.identity == e.identity,
      );
      final oldOverride = existing.overrides.where(
        (o) => o.identity == e.identity,
      );
      String encodedOverride(Iterable<OccurrenceOverride> overrides) =>
          jsonEncode(
            encodePhasePlan(
              PhasePlan(
                phases: existing.phases,
                originPhases: existing.originPhases,
                overrides: overrides,
              ),
            )['overrides'],
          );
      if (encodedOverride(nextOverride) != encodedOverride(oldOverride)) {
        throw const CommandConflict('captured_history');
      }
    }
    final sources = await intervalSources(
      planId: proposed.planId,
      personId: proposed.personId,
    );
    for (final o in proposed.overrides) {
      final origin = [
        ...proposed.phases,
        ...proposed.originPhases,
      ].singleWhere((p) => p.versionId == o.versionId);
      final count = switch (origin.timing) {
        DailyCount(:final count) => count,
        MixedDailyCount(:final count, :final slots) => count - slots.length,
        _ => 0,
      };
      if (o.identity.slotId == null && count > 1) {
        throw const CommandConflict('one_off_requires_single_opportunity');
      }
      if (o.amount != null && o.amount!.unit != item.unit) {
        throw const CommandConflict('plan_unit');
      }
      final result = PhaseResolver(strictOverrides: true).resolveDate(
        proposed,
        o.windowTarget != null
            ? DailyResolver().clock.dateAt(
                o.windowTarget!.start,
                o.windowTarget!.zoneId,
              )
            : o.targetInstant == null
            ? o.identity.originalDate
            : DailyResolver().clock.dateAt(o.targetInstant!, o.targetZoneId!),
        observedZone: zone,
        intervalSources: sources,
        now: now,
      );
      if (!result.any((e) => e.identity == o.identity)) {
        throw const CommandConflict('occurrence_override');
      }
    }
  }

  Future<SavedDailyPlan> savePhasePlan({
    required String commandId,
    required PhaseChangeReview review,
    ReminderClockSample? intervalClockSample,
    bool failBeforeCommit = false,
    Future<void> Function()? beforeCommit,
  }) async {
    _dailyGeneration(review.generation);
    final p = review.plan.plan, proposed = review.proposed;
    if (proposed.personId != p.personId ||
        proposed.planId != p.planId ||
        proposed.itemId != p.itemId) {
      throw const CommandConflict('phase_identity');
    }
    final encoded = jsonEncode(encodePhasePlan(proposed));
    final result = await _command(
      commandId,
      [
        'phase_plan',
        p.personId,
        encoded,
        review.plan.revision,
        review.personRevision,
        review.sourceGuard,
        review.now.microsecondsSinceEpoch,
        review.observedZone,
        if (intervalClockSample != null) _sampleJson(intervalClockSample),
      ],
      () async {
        await _activeOwner(p.personId, review.personRevision);
        final head = await _rows(
          'SELECT revision FROM daily_plan WHERE id=? AND person=? AND item=?',
          [p.planId, p.personId, p.itemId],
        );
        if (head.length != 1 ||
            head.single['revision'] != review.plan.revision) {
          throw const CommandConflict('plan_revision');
        }
        if (await _intervalGuard(p.planId, p.personId) != review.sourceGuard) {
          throw const CommandConflict('interval_source_revision');
        }
        final existing =
            await phasePlan(planId: p.planId, personId: p.personId) ??
            PhasePlan(phases: await _phaseVersions(p.planId, p.personId));
        await _validatePhaseProposal(
          existing,
          proposed,
          review.now,
          review.observedZone,
        );
        final priorVersions = await _rows(
          'SELECT snapshot FROM daily_version_audit WHERE plan=? LIMIT 10001',
          [p.planId],
        );
        if (priorVersions.length > 10000) {
          throw const CommandConflict('phase_history_bound');
        }
        for (final phase in proposed.phases) {
          if (phase.timing case ElapsedInterval(
            :final segmentId,
            :final duration,
            :final mode,
            :final plannedAnchor,
          )) {
            if (phase.calendar is! EveryDay || segmentId.length > 256) {
              throw const CommandConflict('interval_composition');
            }
            for (final row in priorVersions) {
              final timing = decodeDailyPlan(
                dailyObject(row['snapshot'] as String),
              ).timing;
              if (timing is ElapsedInterval &&
                  timing.segmentId == segmentId &&
                  (timing.duration.microseconds != duration.microseconds ||
                      timing.mode != mode ||
                      timing.plannedAnchor != plannedAnchor)) {
                throw const CommandConflict('interval_segment_identity');
              }
            }
          }
        }
        final revision = review.plan.revision + 1;
        for (final next in proposed.phases) {
          final prior = await _rows(
            'SELECT snapshot FROM daily_version_audit WHERE id=?',
            [next.versionId],
          );
          if (prior.isNotEmpty &&
              !existing.phases.any(
                (v) =>
                    v.versionId == next.versionId &&
                    _phaseRetainsPrefix(
                      v,
                      next,
                      review.now,
                      review.observedZone,
                    ),
              )) {
            throw const CommandConflict('version_identity');
          }
        }
        await _db.customStatement('DELETE FROM daily_version WHERE plan=?', [
          p.planId,
        ]);
        for (final next in proposed.phases) {
          final snapshot = jsonEncode(encodeDailyPlan(next));
          await _db.customStatement(
            'INSERT INTO daily_version VALUES (?,?,?,?,?,?)',
            [
              next.versionId,
              p.planId,
              p.personId,
              next.start.toString(),
              next.endExclusive?.toString(),
              snapshot,
            ],
          );
          await _db.customStatement(
            'INSERT INTO daily_version_audit VALUES (?,?,?,?,?) ON CONFLICT(id) DO NOTHING',
            [next.versionId, p.planId, p.personId, revision, snapshot],
          );
          if (next.timing is ElapsedInterval &&
              !existing.phases.any(
                (v) =>
                    v.timing is ElapsedInterval &&
                    (v.timing as ElapsedInterval).segmentId ==
                        (next.timing as ElapsedInterval).segmentId,
              )) {
            await _captureIntervalClock(
              next,
              intervalClockSample,
              replace: false,
            );
          }
        }
        await _db.customStatement('DELETE FROM phase_override WHERE plan=?', [
          p.planId,
        ]);
        for (final o in proposed.overrides) {
          final target = o.windowTarget?.start ?? o.targetInstant;
          final targetZone = o.windowTarget?.zoneId ?? o.targetZoneId;
          final targetDate = target == null
              ? o.identity.originalDate
              : DailyResolver().clock.dateAt(target, targetZone!);
          final snapshot = jsonEncode(
            encodePhasePlan(
              PhasePlan(
                phases: proposed.phases,
                originPhases: proposed.originPhases,
                overrides: [o],
              ),
            )['overrides'],
          );
          await _db.customStatement(
            'INSERT INTO phase_override VALUES (?,?,?,?,?,?)',
            [
              p.planId,
              p.personId,
              dailyIdentityKey(o.identity),
              o.identity.originalDate.toString(),
              targetDate.toString(),
              snapshot,
            ],
          );
        }
        await _db.customStatement(
          'INSERT INTO phase_plan VALUES (?,?,?) ON CONFLICT(plan) DO UPDATE SET snapshot=excluded.snapshot',
          [p.planId, p.personId, encoded],
        );
        await _db.customStatement(
          'INSERT INTO phase_change VALUES (?,?,?,?,?,?)',
          [
            commandId,
            p.planId,
            p.personId,
            revision,
            encoded,
            DateTime.now().microsecondsSinceEpoch,
          ],
        );
        await _db.customStatement(
          'UPDATE daily_plan SET revision=? WHERE id=?',
          [revision, p.planId],
        );
        await _db.customStatement(
          'UPDATE reminder_state SET revision=revision+1,snooze_revision=snooze_revision+1 WHERE plan=?',
          [p.planId],
        );
        await _dailyIntent(p.planId, p.personId, revision, false);
        return {
          'person': p.personId,
          'snapshot': jsonEncode(encodeDailyPlan(proposed.phases.last)),
          'revision': revision,
        };
      },
      failBeforeCommit: failBeforeCommit,
      beforeCommit: beforeCommit,
    );
    return _savedPlan(result);
  }

  /// Bounded immutable phase and exception command history.
  Future<List<Map<String, Object?>>> phaseHistory({
    required String planId,
    required String personId,
    int limit = 100,
    int offset = 0,
  }) {
    _pageBounds(limit, offset);
    return _rows(
      'SELECT * FROM phase_change WHERE plan=? AND person=? ORDER BY revision LIMIT ? OFFSET ?',
      [planId, personId, limit, offset],
    );
  }
}
