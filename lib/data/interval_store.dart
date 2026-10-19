part of 'record_store.dart';

const intervalSchemaV11 = [
  "CREATE TABLE interval_recovery(plan TEXT PRIMARY KEY,person TEXT NOT NULL,cutoff TEXT NOT NULL,FOREIGN KEY(plan,person) REFERENCES daily_plan(id,person) ON DELETE CASCADE) STRICT",
  '''CREATE TABLE interval_clock(plan TEXT NOT NULL,person TEXT NOT NULL,segment TEXT NOT NULL,boot TEXT NOT NULL,utc INTEGER NOT NULL,elapsed INTEGER NOT NULL CHECK(elapsed>=0),PRIMARY KEY(plan,segment),FOREIGN KEY(plan,person) REFERENCES daily_plan(id,person) ON DELETE CASCADE) STRICT''',
  '''CREATE TABLE interval_qualification(plan TEXT NOT NULL,person TEXT NOT NULL,segment TEXT NOT NULL,record TEXT NOT NULL,qualifies INTEGER NOT NULL CHECK(qualifies IN (0,1)),revision INTEGER NOT NULL CHECK(revision>0),PRIMARY KEY(plan,segment,record),FOREIGN KEY(plan,person) REFERENCES daily_plan(id,person) ON DELETE CASCADE,FOREIGN KEY(record,person) REFERENCES administration(id,person)) STRICT''',
];

extension IntervalRecordStore on RecordStore {
  /// Current actual revisions explicitly selected for one routine segment.
  Future<List<IntervalSource>> intervalSources({
    required String planId,
    required String personId,
  }) async =>
      (await _rows(
            '''SELECT q.*,a.item,a.actual,a.revision AS actual_revision,r.voided
       FROM interval_qualification q JOIN administration a ON a.id=q.record AND a.person=q.person
       JOIN revision r ON r.record=a.id AND r.revision=a.revision
       WHERE q.plan=? AND q.person=? ORDER BY q.segment,q.record LIMIT 100001''',
            [planId, personId],
          ))
          .map(
            (r) => IntervalSource(
              actualId: r['record'] as String,
              revision: r['actual_revision'] as int,
              personId: r['person'] as String,
              itemId: r['item'] as String,
              planId: r['plan'] as String,
              segmentId: r['segment'] as String,
              instant: DateTime.fromMicrosecondsSinceEpoch(
                r['actual'] as int,
                isUtc: true,
              ),
              qualifies: r['qualifies'] == 1,
              isVoid: r['voided'] == 1,
            ),
          )
          .toList();

  Future<String> _intervalGuard(String plan, String person) async => jsonEncode(
    await _rows(
      '''SELECT q.segment,q.record,q.qualifies,q.revision,a.revision AS actual_revision,a.actual,r.voided
      FROM interval_qualification q JOIN administration a ON a.id=q.record
      JOIN revision r ON r.record=a.id AND r.revision=a.revision
      WHERE q.plan=? AND q.person=? ORDER BY q.segment,q.record LIMIT 100001''',
      [plan, person],
    ),
  );

  /// Preview is read-only. Revisions and the complete selected source set are
  /// compared again under the command write lock before changing an anchor.
  Future<IntervalChangeReview> previewIntervalChange({
    required SavedDailyPlan plan,
    required String recordId,
    required int expectedRecordRevision,
    DateTime? actualAt,
    bool? qualifies,
    bool voided = false,
    required DateTime now,
    required String observedZone,
    ReminderClockSample? intervalClockSample,
  }) => _db.transaction(() async {
    final p = plan.plan;
    final timing = p.timing;
    if (timing is! ElapsedInterval ||
        timing.mode != IntervalMode.qualifyingActual) {
      throw const CommandConflict('interval_plan');
    }
    final owner = await profileById(p.personId);
    if (owner == null || owner.isArchived) {
      throw const CommandConflict('ownership');
    }
    final records = await _rows(
      '${RecordStore._current} WHERE a.id=? AND a.person=?',
      [recordId, p.personId],
    );
    if (records.isEmpty ||
        records.single['item'] != p.itemId ||
        records.single['revision'] != expectedRecordRevision ||
        records.single['voided'] == 1) {
      throw const CommandConflict('revision');
    }
    final sources = await intervalSources(
      planId: p.planId,
      personId: p.personId,
    );
    if (sources.length > 100000) {
      throw const CommandConflict('interval_source_bound');
    }
    final old = sources
        .where((s) => s.segmentId == timing.segmentId && s.actualId == recordId)
        .firstOrNull;
    if (old == null && sources.length >= 100000) {
      throw const CommandConflict('interval_source_bound');
    }
    final changed = IntervalSource(
      actualId: recordId,
      revision: expectedRecordRevision + (actualAt != null || voided ? 1 : 0),
      personId: p.personId,
      itemId: p.itemId,
      planId: p.planId,
      segmentId: timing.segmentId,
      instant:
          actualAt?.toUtc() ??
          DateTime.fromMicrosecondsSinceEpoch(
            records.single['actual'] as int,
            isUtc: true,
          ),
      qualifies: qualifies ?? old?.qualifies ?? false,
      isVoid: voided,
    );
    changed.validateQualificationAt(now.toUtc());
    final nextSources = [
      for (final s in sources)
        if (s.actualId != recordId || s.segmentId != timing.segmentId) s,
      changed,
    ];
    final resolver = IntervalResolver();
    final before = resolver
        .current(
          p,
          now: _intervalReferenceNow(sources, now),
          observedZone: observedZone,
          sources: sources,
        )
        .next;
    final after = resolver
        .current(
          p,
          now: _intervalReferenceNow(nextSources, now),
          observedZone: observedZone,
          sources: nextSources,
        )
        .next;
    return IntervalChangeReview(
      plan: plan,
      recordId: recordId,
      expectedRecordRevision: expectedRecordRevision,
      sourceGuard: await _intervalGuard(p.planId, p.personId),
      generation: generation,
      personRevision: owner.revision,
      now: now.toUtc(),
      observedZone: observedZone,
      before: before,
      after: after,
      actualAt: actualAt?.toUtc(),
      qualifies: qualifies,
      voided: voided,
      intervalClockSample: intervalClockSample,
    );
  });

  Future<List<IntervalChangeReview>> previewIntervalChanges({
    required String recordId,
    String personId = meId,
    required int expectedRevision,
    DateTime? actualAt,
    bool voided = false,
    required DateTime now,
    required String observedZone,
    ReminderClockSample? intervalClockSample,
  }) => _db.transaction(() async {
    final matches = await _rows(
      '''SELECT DISTINCT v.snapshot,p.revision FROM interval_qualification q
      JOIN daily_version v ON v.plan=q.plan JOIN daily_plan p ON p.id=q.plan
      WHERE q.record=? AND q.person=? AND q.qualifies=1 ORDER BY v.start DESC''',
      [recordId, personId],
    );
    final result = <IntervalChangeReview>[];
    final seen = <String>{};
    for (final r in matches) {
      final saved = _savedPlan(r);
      final t = saved.plan.timing;
      if (t is! ElapsedInterval ||
          t.mode != IntervalMode.qualifyingActual ||
          !seen.add('${saved.plan.planId}:${t.segmentId}')) {
        continue;
      }
      final qualified = await _rows(
        'SELECT record FROM interval_qualification WHERE plan=? AND segment=? AND record=? AND qualifies=1',
        [saved.plan.planId, t.segmentId, recordId],
      );
      if (qualified.isEmpty) continue;
      result.add(
        await previewIntervalChange(
          plan: saved,
          recordId: recordId,
          expectedRecordRevision: expectedRevision,
          actualAt: actualAt,
          voided: voided,
          now: now,
          observedZone: observedZone,
          intervalClockSample: intervalClockSample,
        ),
      );
    }
    return result;
  });

  Map<String, Object?> _intervalReviewPayload(IntervalChangeReview r) => {
    'plan': encodeDailyPlan(r.plan.plan),
    'revision': r.plan.revision,
    'record': r.recordId,
    'recordRevision': r.expectedRecordRevision,
    'guard': r.sourceGuard,
    'personRevision': r.personRevision,
    if (r.intervalClockSample != null)
      'clock': _sampleJson(r.intervalClockSample!),
    'actual': r.actualAt?.microsecondsSinceEpoch,
    'qualifies': r.qualifies,
    'voided': r.voided,
    'before': r.before == null ? null : encodeDailyExpectation(r.before!),
    'after': r.after == null ? null : encodeDailyExpectation(r.after!),
  };

  Future<void> _validateIntervalReview(IntervalChangeReview r) async {
    _dailyGeneration(r.generation);
    final p = r.plan.plan;
    await _activeOwner(p.personId, r.personRevision);
    final head = await _rows(
      'SELECT revision,item,person FROM daily_plan WHERE id=?',
      [p.planId],
    );
    if (head.isEmpty ||
        head.single['revision'] != r.plan.revision ||
        head.single['item'] != p.itemId ||
        head.single['person'] != p.personId ||
        await _intervalGuard(p.planId, p.personId) != r.sourceGuard) {
      throw const CommandConflict('interval_source_revision');
    }
    final version = await _rows(
      'SELECT snapshot FROM daily_version WHERE id=? AND plan=?',
      [p.versionId, p.planId],
    );
    if (version.isEmpty ||
        version.single['snapshot'] != jsonEncode(encodeDailyPlan(p))) {
      throw const CommandConflict('plan_version');
    }
    if (!r.voided) {
      final selected = await _rows(
        'SELECT qualifies FROM interval_qualification WHERE plan=? AND segment=? AND record=?',
        [p.planId, (p.timing as ElapsedInterval).segmentId, r.recordId],
      );
      if (r.qualifies == true ||
          r.qualifies != false &&
              selected.isNotEmpty &&
              selected.single['qualifies'] == 1) {
        final actual = await _rows(
          'SELECT actual FROM administration WHERE id=? AND person=?',
          [r.recordId, p.personId],
        );
        final at =
            r.actualAt ??
            DateTime.fromMicrosecondsSinceEpoch(
              actual.single['actual'] as int,
              isUtc: true,
            );
        if (at.isAfter(DateTime.now().toUtc())) {
          throw const CommandConflict('future_interval_qualification');
        }
      }
    }
    final fresh = await previewIntervalChange(
      plan: r.plan,
      recordId: r.recordId,
      expectedRecordRevision: r.expectedRecordRevision,
      actualAt: r.actualAt,
      qualifies: r.qualifies,
      voided: r.voided,
      now: r.now,
      observedZone: r.observedZone,
      intervalClockSample: r.intervalClockSample,
    );
    if (jsonEncode(_intervalReviewPayload(fresh)) !=
        jsonEncode(_intervalReviewPayload(r))) {
      throw const CommandConflict('interval_review');
    }
  }

  Future<void> qualifyInterval({
    required String commandId,
    required IntervalChangeReview review,
  }) async {
    if (review.qualifies == null || review.actualAt != null || review.voided) {
      throw ArgumentError('interval_qualification_review');
    }
    await _command(
      commandId,
      [
        'interval_qualify',
        review.plan.plan.personId,
        _intervalReviewPayload(review),
      ],
      () async {
        await _validateIntervalReview(review);
        final p = review.plan.plan;
        final t = p.timing as ElapsedInterval;
        await _writeIntervalQualification(
          p.planId,
          p.personId,
          t.segmentId,
          review.recordId,
          review.qualifies!,
        );
        await _captureIntervalClock(p, review.intervalClockSample);
        await _dailyIntent(p.planId, p.personId, review.plan.revision, false);
        return {'person': p.personId, 'record': review.recordId};
      },
    );
  }

  Future<void> _writeIntervalQualification(
    String plan,
    String person,
    String segment,
    String actual,
    bool qualifies,
  ) => _db.customStatement(
    '''INSERT INTO interval_qualification VALUES (?,?,?,?,?,1) ON CONFLICT(plan,segment,record) DO UPDATE SET qualifies=excluded.qualifies,revision=interval_qualification.revision+1''',
    [plan, person, segment, actual, qualifies ? 1 : 0],
  );

  Future<void> _validateIntervalRevisionReviews(
    String record,
    String person,
    int revision,
    DateTime? actual,
    bool voided,
    List<IntervalChangeReview>? reviews,
  ) async {
    final expected = await _rows(
      'SELECT plan,segment FROM interval_qualification WHERE record=? AND person=? AND qualifies=1 ORDER BY plan,segment',
      [record, person],
    );
    final supplied = reviews ?? const <IntervalChangeReview>[];
    if (expected.length != supplied.length) {
      throw const CommandConflict('interval_review_required');
    }
    final keys = <String>{};
    for (final r in supplied) {
      final t = r.plan.plan.timing;
      if (t is! ElapsedInterval ||
          r.recordId != record ||
          r.plan.plan.personId != person ||
          r.expectedRecordRevision != revision ||
          r.actualAt != actual?.toUtc() ||
          r.voided != voided ||
          r.qualifies != null ||
          !keys.add('${r.plan.plan.planId}:${t.segmentId}')) {
        throw const CommandConflict('interval_review');
      }
      await _validateIntervalReview(r);
    }
    if (expected.any((e) => !keys.contains('${e['plan']}:${e['segment']}'))) {
      throw const CommandConflict('interval_review_required');
    }
  }

  DateTime _intervalReferenceNow(
    Iterable<IntervalSource> sources,
    DateTime now,
  ) {
    var reference = now.toUtc();
    for (final s in sources) {
      if (s.qualifies && !s.isVoid && s.instant.isAfter(reference)) {
        reference = s.instant;
      }
    }
    return reference;
  }

  Future<IntervalClockReview> previewIntervalClockRecovery({
    required SavedDailyPlan plan,
    required ReminderClockSample sample,
    required CivilDate reviewedFrom,
    required String observedZone,
  }) => _db.transaction(() async {
    final p = plan.plan;
    if (p.timing is! ElapsedInterval ||
        sample.bootId.isEmpty ||
        sample.elapsedMilliseconds < 0) {
      throw const CommandConflict('elapsed_clock_sample');
    }
    final owner = await profileById(p.personId);
    if (owner == null || owner.isArchived) {
      throw const CommandConflict('ownership');
    }
    final now = DateTime.fromMillisecondsSinceEpoch(
      sample.utcMilliseconds,
      isUtc: true,
    );
    final zone = p.zoneBasis.zoneFor(observedZone);
    final date = DailyResolver().currentDate(p, now: now, observedZone: zone);
    final minimum = date.compareTo(p.start) < 0 ? p.start : date;
    if (reviewedFrom != minimum || !p.includes(reviewedFrom)) {
      throw const CommandConflict('interval_recovery_cutoff');
    }
    final sources = await intervalSources(
      planId: p.planId,
      personId: p.personId,
    );
    final next = IntervalResolver().next(
      p,
      after: now,
      now: _intervalReferenceNow(sources, now),
      observedZone: zone,
      sources: sources,
    );
    if (!next.complete) throw const CommandConflict('interval_calculation');
    return IntervalClockReview(
      plan: plan,
      personRevision: owner.revision,
      generation: generation,
      sample: sample,
      reviewedFrom: reviewedFrom,
      sourceGuard: await _intervalGuard(p.planId, p.personId),
      observedZone: observedZone,
      next: next.next,
    );
  });

  Map<String, Object?> _intervalClockPayload(IntervalClockReview r) => {
    'plan': encodeDailyPlan(r.plan.plan),
    'revision': r.plan.revision,
    'personRevision': r.personRevision,
    'sample': _sampleJson(r.sample),
    'zone': r.observedZone,
    'from': r.reviewedFrom.toString(),
    'guard': r.sourceGuard,
    'next': r.next == null ? null : encodeDailyExpectation(r.next!),
  };

  Future<void> resetIntervalClock({
    required String commandId,
    required IntervalClockReview review,
  }) async {
    await _command(
      commandId,
      [
        'interval_clock',
        review.plan.plan.personId,
        _intervalClockPayload(review),
      ],
      () async {
        _dailyGeneration(review.generation);
        final p = review.plan.plan;
        await _activeOwner(p.personId, review.personRevision);
        final head = await _rows(
          'SELECT revision,item FROM daily_plan WHERE id=? AND person=?',
          [p.planId, p.personId],
        );
        final version = await _rows(
          'SELECT snapshot FROM daily_version WHERE id=? AND plan=?',
          [p.versionId, p.planId],
        );
        if (head.isEmpty ||
            head.single['revision'] != review.plan.revision ||
            head.single['item'] != p.itemId ||
            version.isEmpty ||
            version.single['snapshot'] != jsonEncode(encodeDailyPlan(p))) {
          throw const CommandConflict('plan_revision');
        }
        final fresh = await previewIntervalClockRecovery(
          plan: review.plan,
          sample: review.sample,
          reviewedFrom: review.reviewedFrom,
          observedZone: review.observedZone,
        );
        if (jsonEncode(_intervalClockPayload(fresh)) !=
            jsonEncode(_intervalClockPayload(review))) {
          throw const CommandConflict('interval_source_revision');
        }
        await _captureIntervalClock(p, review.sample);
        await _db.customStatement(
          'INSERT INTO interval_recovery VALUES (?,?,?) ON CONFLICT(plan) DO UPDATE SET cutoff=excluded.cutoff',
          [p.planId, p.personId, review.reviewedFrom.toString()],
        );
        await _dailyIntent(p.planId, p.personId, review.plan.revision, false);
        return {'person': p.personId, 'plan': p.planId};
      },
    );
  }

  Future<void> _captureIntervalClock(
    DailyPlanVersion p,
    ReminderClockSample? sample, {
    bool replace = true,
  }) async {
    final t = p.timing as ElapsedInterval;
    if (sample == null) {
      if (replace) {
        await _db.customStatement(
          'DELETE FROM interval_clock WHERE plan=? AND segment=?',
          [p.planId, t.segmentId],
        );
      }
      return;
    }
    if (sample.bootId.isEmpty || sample.elapsedMilliseconds < 0) {
      throw const CommandConflict('elapsed_clock_sample');
    }
    await _db.customStatement(
      "INSERT INTO interval_clock VALUES (?,?,?,?,?,?) ON CONFLICT(plan,segment) DO ${replace ? 'UPDATE SET boot=excluded.boot,utc=excluded.utc,elapsed=excluded.elapsed' : 'NOTHING'}",
      [
        p.planId,
        p.personId,
        t.segmentId,
        sample.bootId,
        sample.utcMilliseconds,
        sample.elapsedMilliseconds,
      ],
    );
  }

  /// A segment's native ordinal projection retains one monotonic mapping.
  /// Reboot cannot manufacture elapsed continuity from a changed wall clock.
  Future<(DateTime, ReminderClockSample)?> _intervalProjectionClock(
    DailyPlanVersion p,
    ReminderClockSample? current,
  ) async {
    if (current == null ||
        current.elapsedMilliseconds < 0 ||
        current.bootId.isEmpty) {
      return null;
    }
    final t = p.timing as ElapsedInterval;
    final found = await _rows(
      'SELECT * FROM interval_clock WHERE plan=? AND segment=?',
      [p.planId, t.segmentId],
    );
    if (found.isEmpty) return null;
    final r = found.single;
    final elapsed = r['elapsed'] as int;
    if (r['boot'] != current.bootId || current.elapsedMilliseconds < elapsed) {
      return null;
    }
    final micros =
        (BigInt.from(r['utc'] as int) +
            BigInt.from(current.elapsedMilliseconds) -
            BigInt.from(elapsed)) *
        BigInt.from(1000);
    if (micros < BigInt.from(DateTime.utc(1).microsecondsSinceEpoch) ||
        micros >
            BigInt.from(DateTime.utc(9999, 12, 31).microsecondsSinceEpoch)) {
      return null;
    }
    return (
      DateTime.fromMicrosecondsSinceEpoch(micros.toInt(), isUtc: true),
      ReminderClockSample(
        bootId: r['boot'] as String,
        utcMilliseconds: r['utc'] as int,
        elapsedMilliseconds: elapsed,
      ),
    );
  }

  Future<void> _validateIntervalExpectation(DailyExpectation e) async {
    final versions = await _rows(
      'SELECT snapshot FROM daily_version WHERE id=? AND plan=? AND person=?',
      [e.versionId, e.identity.planId, e.identity.personId],
    );
    if (versions.isEmpty) throw const CommandConflict('plan_version');
    final p = decodeDailyPlan(
      dailyObject(versions.single['snapshot'] as String),
    );
    final t = p.timing;
    if (t is! ElapsedInterval || t.segmentId != e.identity.intervalSegmentId) {
      throw const CommandConflict('interval_source_revision');
    }
    if (t.mode == IntervalMode.qualifyingActual) {
      final sources = await intervalSources(
        planId: p.planId,
        personId: p.personId,
      );
      if (sources.length > 100000) {
        throw const CommandConflict('interval_source_bound');
      }
      var admittedNow = DateTime.now().toUtc();
      for (final s in sources) {
        if (s.qualifies &&
            !s.isVoid &&
            s.segmentId == t.segmentId &&
            s.instant.isAfter(admittedNow)) {
          admittedNow = s.instant;
        }
      }
      final current = IntervalResolver().current(
        p,
        now: admittedNow,
        observedZone: e.zoneId,
        sources: sources,
      );
      if (current.next?.identity != e.identity ||
          current.next?.instant != e.instant) {
        throw const CommandConflict('interval_source_revision');
      }
    }
  }

  Future<void> _intervalActualChanged(
    String record,
    String person, {
    List<IntervalChangeReview>? reviews,
  }) async {
    final plans = await _rows(
      'SELECT DISTINCT q.plan,p.revision FROM interval_qualification q JOIN daily_plan p ON p.id=q.plan WHERE q.record=? AND q.person=?',
      [record, person],
    );
    for (final review in reviews ?? const <IntervalChangeReview>[]) {
      await _captureIntervalClock(review.plan.plan, review.intervalClockSample);
    }
    for (final p in plans) {
      await _dailyIntent(
        p['plan'] as String,
        person,
        p['revision'] as int,
        false,
      );
    }
  }
}
