part of 'record_store.dart';

const reminderSchemaV9 = [
  'CREATE TABLE reminder_meta(id INTEGER PRIMARY KEY CHECK(id=1),namespace TEXT NOT NULL,sequence INTEGER NOT NULL DEFAULT 0,fingerprint TEXT NOT NULL DEFAULT \'\') STRICT',
  'CREATE TABLE reminder_config(plan TEXT PRIMARY KEY,person TEXT NOT NULL,enabled INTEGER NOT NULL CHECK(enabled IN (0,1)),revision INTEGER NOT NULL CHECK(revision>0),FOREIGN KEY(plan,person) REFERENCES daily_plan(id,person) ON DELETE CASCADE) STRICT',
  'CREATE TABLE reminder_state(bucket TEXT PRIMARY KEY,plan TEXT NOT NULL,person TEXT NOT NULL,revision INTEGER NOT NULL DEFAULT 0,snooze_revision INTEGER NOT NULL DEFAULT 0,ordinary_terminal INTEGER NOT NULL DEFAULT 0 CHECK(ordinary_terminal IN (0,1)),FOREIGN KEY(plan,person) REFERENCES daily_plan(id,person) ON DELETE CASCADE) STRICT',
  'CREATE TABLE reminder_request(token TEXT PRIMARY KEY,bucket TEXT,plan TEXT,person TEXT,snapshot TEXT,intent_revision INTEGER NOT NULL,active INTEGER NOT NULL CHECK(active IN (0,1)),state TEXT NOT NULL,reason TEXT,fingerprint TEXT,cancel_ack INTEGER NOT NULL DEFAULT 0 CHECK(cancel_ack IN (0,1))) STRICT',
  'CREATE INDEX reminder_request_current ON reminder_request(active,plan,bucket)',
  "CREATE INDEX reminder_request_work ON reminder_request(token) WHERE active=1 AND snapshot IS NOT NULL AND state IN ('pending','prepared','failed','unknown','capacity')",
  "CREATE INDEX reminder_request_attention ON reminder_request(state,token) WHERE active=1 AND snapshot IS NOT NULL",
  "CREATE INDEX reminder_request_due ON reminder_request(json_extract(snapshot,'\$.deadline')) WHERE active=1 AND json_extract(snapshot,'\$.kind')='ordinary' AND state IN ('pending','prepared','failed','unknown','capacity')",
  'CREATE TABLE reminder_pending(envelope TEXT PRIMARY KEY,person TEXT,request TEXT,action_token TEXT,action TEXT NOT NULL,command TEXT NOT NULL UNIQUE,draft TEXT NOT NULL UNIQUE,snapshot TEXT,delay INTEGER,delay_text TEXT,observed_zone TEXT,sample TEXT,actual INTEGER,submitted INTEGER NOT NULL DEFAULT 0 CHECK(submitted IN (0,1)),consumed INTEGER NOT NULL DEFAULT 0 CHECK(consumed IN (0,1))) STRICT',
  'CREATE UNIQUE INDEX reminder_pending_token ON reminder_pending(action_token) WHERE action_token IS NOT NULL',
];

Map<String, Object?> _sampleJson(ReminderClockSample s) => {
  'utc': s.utcMilliseconds,
  'elapsed': s.elapsedMilliseconds,
  'boot': s.bootId,
};
ReminderClockSample _sampleRead(dynamic m) => ReminderClockSample(
  utcMilliseconds: m['utc'] as int,
  elapsedMilliseconds: m['elapsed'] as int,
  bootId: m['boot'] as String,
);
Map<String, Object?> _targetJson(ReminderTarget t) => {
  'generation': t.row.generation,
  'person_revision': t.row.personRevision,
  'plan_revision': t.row.planRevision,
  'revision': t.row.revision,
  'reminder_revision': t.reminderRevision,
  'snooze_revision': t.snoozeRevision,
  'config_revision': t.configRevision,
  'expectation': encodeDailyExpectation(t.row.expectation),
  'person_name': t.row.personName,
  'item_name': t.row.itemName,
  if (t.row.productLabel != null) 'product_label': t.row.productLabel!.toJson(),
  if (t.row.productLabel != null) 'item_revision': t.row.itemRevision,
  'taken': t.row.takenCount,
  'skipped': t.row.skippedCount,
};
ReminderTarget _targetRead(dynamic m) => ReminderTarget(
  snoozeRevision: m['snooze_revision'] as int,
  configRevision: m['config_revision'] as int,
  row: DailyRow(
    generation: m['generation'] as String,
    personRevision: m['person_revision'] as int,
    planRevision: m['plan_revision'] as int,
    revision: m['revision'] as int,
    reminderRevision: m['reminder_revision'] as int,
    expectation: decodeDailyExpectation(
      m['expectation'] as Map<String, dynamic>,
    ),
    personName: m['person_name'] as String,
    itemName: m['item_name'] as String,
    itemRevision: m['item_revision'] as int? ?? 1,
    productLabel: m['product_label'] == null
        ? null
        : ProductLabelSnapshot.fromJson(
            Map<String, dynamic>.from(m['product_label'] as Map),
          ),
    takenCount: m['taken'] as int,
    skippedCount: m['skipped'] as int,
    actions: const [],
  ),
);
Map<String, Object?> _desiredJson(DesiredReminder r) => {
  'token': r.requestToken,
  'taken': r.takenToken,
  'snooze': r.snoozeToken,
  'skip': r.skipToken,
  'generation': r.generation,
  'namespace': r.namespace,
  'target': _targetJson(r.target),
  'kind': r.kind.name,
  'trigger': r.trigger.name,
  'deadline': r.deadlineMilliseconds,
  'revision': r.intentRevision,
  'boot': r.bootId,
  'sample': r.sample == null ? null : _sampleJson(r.sample!),
  'delay': r.delayMinutes,
};
DesiredReminder _desiredRead(Map<String, Object?> row) {
  final m = jsonDecode(row['snapshot'] as String) as Map<String, dynamic>;
  return DesiredReminder(
    requestToken: m['token'] as String,
    takenToken: m['taken'] as String,
    snoozeToken: m['snooze'] as String,
    skipToken: m['skip'] as String,
    generation: m['generation'] as String,
    namespace: m['namespace'] as String,
    target: _targetRead(m['target']),
    kind: ReminderKind.values.byName(m['kind'] as String),
    trigger: ReminderTrigger.values.byName(m['trigger'] as String),
    deadlineMilliseconds: m['deadline'] as int,
    intentRevision: m['revision'] as int,
    bootId: m['boot'] as String?,
    sample: m['sample'] == null ? null : _sampleRead(m['sample']),
    delayMinutes: m['delay'] as int?,
    repairState: ReminderRepairState.values.byName(row['state'] as String),
    reason: row['reason'] as String?,
    adapterFingerprint: row['fingerprint'] as String?,
  );
}

extension ReminderRecordStore on RecordStore {
  Stream<void> watchReminderChanges() => _changes.stream;

  /// Narrow non-clinical repair transaction. It grants no clinical write access.
  Future<T> _reminderTransaction<T>(Future<T> Function() body) async {
    if (_closed) throw StateError('closed_store');
    final work = _db.transaction(() async {
      await _db.customStatement('UPDATE dataset SET generation=generation');
      if ((await _rows('SELECT generation FROM dataset'))
              .single['generation'] !=
          generation) {
        throw const CommandConflict('generation');
      }
      return body();
    });
    final tracked = work.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _reminderWork.add(tracked);
    tracked.whenComplete(() => _reminderWork.remove(tracked));
    return work;
  }

  Future<Map<String, Object?>> _reminderMeta() async {
    await _db.customStatement(
      'INSERT INTO reminder_meta(id,namespace) VALUES (1,?) ON CONFLICT(id) DO NOTHING',
      [newCommandId()],
    );
    return (await _rows('SELECT * FROM reminder_meta WHERE id=1')).single;
  }

  Future<Map<String, Object?>> _reminderState(DailyRow row) async {
    final e = row.expectation;
    final found = await _rows('SELECT * FROM reminder_state WHERE bucket=?', [
      dailyIdentityKey(e.identity),
    ]);
    return found.isEmpty
        ? {'revision': 0, 'snooze_revision': 0, 'ordinary_terminal': 0}
        : found.single;
  }

  Future<void> _ensureReminderState(DailyRow row) async {
    await _db.customStatement(
      'INSERT INTO reminder_state(bucket,plan,person) VALUES (?,?,?) ON CONFLICT(bucket) DO NOTHING',
      [
        dailyIdentityKey(row.expectation.identity),
        row.expectation.identity.planId,
        row.expectation.identity.personId,
      ],
    );
  }

  Future<void> _cancelReminderBucket(String bucket) async {
    await _db.customStatement(
      "UPDATE reminder_request SET active=0,state='pending',reason='cancelled' WHERE bucket=? AND active=1",
      [bucket],
    );
    await _db.customStatement(
      'UPDATE reminder_state SET revision=revision+1 WHERE bucket=?',
      [bucket],
    );
  }

  Future<void> _invalidateReminderPlan(String plan) async {
    await _db.customStatement(
      "UPDATE reminder_request SET active=0,state='pending',reason='cancelled' WHERE plan=? AND active=1",
      [plan],
    );
  }

  Future<void> _stopPersonReminderRequests(String person) async {
    await _db.customStatement(
      "UPDATE event_end_request SET active=0,state='pending',reason='cancelled' WHERE person=? AND active=1",
      [person],
    );
    await _db.customStatement(
      'UPDATE event_pending SET consumed=1 WHERE person=?',
      [person],
    );
    await _db.customStatement(
      'UPDATE reminder_config SET enabled=0,revision=revision+1 WHERE person=?',
      [person],
    );
    await _db.customStatement(
      "UPDATE reminder_request SET active=0,state='pending',reason='cancelled' WHERE person=? AND active=1",
      [person],
    );
  }

  Future<void> _forgetReminderPerson(String person) async {
    await _stopPersonReminderRequests(person);
    await _db.customStatement(
      "UPDATE reminder_request SET snapshot=NULL,person=NULL,plan=NULL,bucket=NULL WHERE person=?",
      [person],
    );
    await _db.customStatement('DELETE FROM reminder_pending WHERE person=?', [
      person,
    ]);
  }

  Future<bool> planRemindersEnabled(String planId) async {
    final rows = await _rows(
      'SELECT c.enabled,o.archived,o.reminders_stopped FROM reminder_config c JOIN person o ON o.id=c.person WHERE c.plan=?',
      [planId],
    );
    if (rows.isEmpty ||
        rows.single['enabled'] != 1 ||
        rows.single['archived'] != 0 ||
        rows.single['reminders_stopped'] != 0) {
      return false;
    }
    final versions = await _rows(
      'SELECT snapshot FROM daily_version WHERE plan=? ORDER BY start DESC,rowid DESC LIMIT 1',
      [planId],
    );
    if (versions.isEmpty) return false;
    final timing = decodeDailyPlan(
      dailyObject(versions.single['snapshot'] as String),
    ).timing;
    return timing is DailySlots || timing is ElapsedInterval;
  }

  Future<void> setPlanReminders({
    required String commandId,
    required String planId,
    required String personId,
    required int expectedPlanRevision,
    required int expectedPersonRevision,
    required bool enabled,
  }) async {
    await _command(
      commandId,
      [
        'reminder_preference',
        personId,
        planId,
        expectedPlanRevision,
        expectedPersonRevision,
        enabled,
      ],
      () async {
        await _activeOwner(personId, expectedPersonRevision);
        final head = await _rows(
          'SELECT revision FROM daily_plan WHERE id=? AND person=?',
          [planId, personId],
        );
        if (head.isEmpty || head.single['revision'] != expectedPlanRevision) {
          throw const CommandConflict('plan_revision');
        }
        final versions = await _rows(
          'SELECT snapshot FROM daily_version WHERE plan=? ORDER BY start DESC,rowid DESC LIMIT 1',
          [planId],
        );
        final timing = versions.isEmpty
            ? null
            : decodeDailyPlan(
                dailyObject(versions.single['snapshot'] as String),
              ).timing;
        bool timed(DailyTiming? value) =>
            value is DailySlots ||
            value is ElapsedInterval ||
            value is MixedDailyCount ||
            value is DailyWindows &&
                value.windows.any(
                  (w) => w.reminderEnabled && w.reminderAnchor != null,
                );
        final aggregate = await phasePlan(planId: planId, personId: personId);
        if (enabled &&
            !(aggregate == null
                ? timed(timing)
                : aggregate.phases.any((p) => timed(p.timing)))) {
          throw const CommandConflict('reminder_untimed');
        }
        await _db.customStatement(
          'INSERT INTO reminder_config VALUES (?,?,?,1) ON CONFLICT(plan) DO UPDATE SET enabled=excluded.enabled,revision=revision+1',
          [planId, personId, enabled ? 1 : 0],
        );
        if (enabled) {
          await _db.customStatement(
            'UPDATE person SET reminders_stopped=0 WHERE id=?',
            [personId],
          );
        }
        await _invalidateReminderPlan(planId);
        return {'person': personId, 'plan': planId, 'enabled': enabled};
      },
    );
  }

  Future<void> _validatePauseDeadline(
    ReminderTarget target,
    DateTime instant,
  ) async {
    final e = target.row.expectation;
    if (e.windowEnd != null && !instant.isBefore(e.windowEnd!)) {
      throw const CommandConflict('plan_window');
    }
    final aggregate = await phasePlan(
      planId: e.identity.planId,
      personId: e.identity.personId,
    );
    if (aggregate != null) {
      if (aggregate.end != null &&
          !instant.isBefore(aggregate.end!.exclusiveInstant)) {
        throw const CommandConflict('plan_ended');
      }
      for (final phase in aggregate.phases) {
        if (phase.pauses.any((p) => p.contains(instant))) {
          throw const CommandConflict('plan_paused');
        }
        final date = DailyResolver().clock.dateAt(
          instant,
          phase.zoneBasis.zoneFor(e.zoneId),
        );
        if (phase.onOff != null && !phase.onOff!.includes(date)) {
          throw const CommandConflict('plan_break');
        }
      }
      return;
    }
    final versions = await _rows(
      'SELECT snapshot FROM daily_version WHERE id=?',
      [e.versionId],
    );
    if (versions.isEmpty) throw const CommandConflict('plan_version');
    final plan = decodeDailyPlan(
      dailyObject(versions.single['snapshot'] as String),
    );
    if (plan.pauses.any((p) => p.contains(instant))) {
      throw const CommandConflict('plan_paused');
    }
    final date = DailyResolver().clock.dateAt(
      instant,
      plan.zoneBasis.zoneFor(e.zoneId),
    );
    if (!plan.includes(date) ||
        !plan.includesInstant(instant) ||
        (plan.onOff != null && !plan.onOff!.includes(date))) {
      throw const CommandConflict('plan_break');
    }
  }

  Future<void> _validateReminderTarget(
    ReminderTarget target,
    String? observedZone,
  ) async {
    await _validateDailyRow(target.row);
    final row = target.row, e = row.expectation;
    if (row.isResolved ||
        (await _dailyProgress(dailyIdentityKey(e.identity))).$1 +
                (await _dailyProgress(dailyIdentityKey(e.identity))).$2 >=
            row.plannedCount) {
      throw const CommandConflict('already_resolved');
    }
    final state = await _reminderState(row);
    if (state['revision'] != target.reminderRevision ||
        state['snooze_revision'] != target.snoozeRevision) {
      throw const CommandConflict('reminder_revision');
    }
    final config = await _rows(
      'SELECT c.enabled,c.revision,o.reminders_stopped FROM reminder_config c JOIN person o ON o.id=c.person WHERE c.plan=?',
      [e.identity.planId],
    );
    if (config.isEmpty ||
        config.single['enabled'] != 1 ||
        config.single['revision'] != target.configRevision ||
        config.single['reminders_stopped'] != 0 ||
        e.instant == null) {
      throw const CommandConflict('reminder_disabled');
    }
    final versions = await _rows(
      'SELECT snapshot FROM daily_version WHERE id=?',
      [e.versionId],
    );
    if (versions.isEmpty) throw const CommandConflict('plan_version');
    final plan = decodeDailyPlan(
      dailyObject(versions.single['snapshot'] as String),
    );
    if (plan.zoneBasis is FollowingLocal &&
        (observedZone == null || e.zoneId != observedZone)) {
      throw const CommandConflict('reminder_zone');
    }
  }

  Future<void> validateReminderTarget(
    ReminderTarget target, {
    required String? observedZone,
  }) async {
    _requireWritable();
    await _db.transaction(() => _validateReminderTarget(target, observedZone));
  }

  Future<ReminderTarget> reminderTarget(
    DailyRow row, {
    required String? observedZone,
  }) async {
    _requireWritable();
    return _db.transaction(() async {
      final state = await _reminderState(row);
      final config = await _rows(
        'SELECT revision FROM reminder_config WHERE plan=?',
        [row.expectation.identity.planId],
      );
      final target = ReminderTarget(
        row: row,
        configRevision: config.isEmpty ? 0 : config.single['revision'] as int,
        snoozeRevision: state['snooze_revision'] as int,
      );
      await _validateReminderTarget(target, observedZone);
      return target;
    });
  }

  Future<DesiredReminder> _insertReminder(
    ReminderTarget target, {
    required ReminderKind kind,
    required int deadline,
    ReminderClockSample? sample,
    int? delay,
  }) async {
    final meta = await _reminderMeta();
    final r = DesiredReminder(
      requestToken: newCommandId(),
      takenToken: newCommandId(),
      snoozeToken: newCommandId(),
      skipToken: newCommandId(),
      generation: generation,
      namespace: meta['namespace'] as String,
      target: target,
      kind: kind,
      trigger:
          kind == ReminderKind.snooze ||
              target.row.expectation.identity.intervalSegmentId != null
          ? ReminderTrigger.elapsed
          : ReminderTrigger.wall,
      deadlineMilliseconds: deadline,
      intentRevision: target.reminderRevision,
      repairState: ReminderRepairState.pending,
      bootId: sample?.bootId,
      sample: sample,
      delayMinutes: delay,
    );
    await _db.customStatement(
      "INSERT INTO reminder_request VALUES (?,?,?,?,?,?,1,'pending',NULL,NULL,0)",
      [
        r.requestToken,
        dailyIdentityKey(target.row.expectation.identity),
        target.row.expectation.identity.planId,
        target.row.expectation.identity.personId,
        jsonEncode(_desiredJson(r)),
        r.intentRevision,
      ],
    );
    return r;
  }

  Future<SnoozeResult> snoozeReminder(
    SnoozeCommand command, {
    required String? currentObservedZone,
  }) async {
    final target = command.target;
    final deadline = snoozeDeadline(command.sample, command.delayMinutes);
    final result = await _command(
      command.commandId,
      [
        'reminder_snooze',
        target.row.expectation.identity.personId,
        _targetJson(target),
        command.delayMinutes,
        _sampleJson(command.sample),
        command.observedZone,
      ],
      () async {
        await _validateReminderTarget(target, currentObservedZone);
        await _validatePauseDeadline(
          target,
          DateTime.fromMillisecondsSinceEpoch(
            command.sample.utcMilliseconds,
            isUtc: true,
          ).add(Duration(minutes: command.delayMinutes)),
        );
        await _ensureReminderState(target.row);
        await _cancelReminderBucket(
          dailyIdentityKey(target.row.expectation.identity),
        );
        await _db.customStatement(
          'UPDATE reminder_state SET snooze_revision=snooze_revision+1 WHERE bucket=?',
          [dailyIdentityKey(target.row.expectation.identity)],
        );
        final fresh = await _dailyRow(
          target.row.expectation,
          target.row.planRevision,
        );
        final next = ReminderTarget(
          row: fresh,
          snoozeRevision: target.snoozeRevision + 1,
          configRevision: target.configRevision,
        );
        final desired = await _insertReminder(
          next,
          kind: ReminderKind.snooze,
          deadline: deadline.elapsedMilliseconds,
          sample: command.sample,
          delay: command.delayMinutes,
        );
        return {
          'person': target.row.expectation.identity.personId,
          'desired': _desiredJson(desired),
        };
      },
    );
    final desired = _desiredRead({
      'snapshot': jsonEncode(result['desired']),
      'state': 'pending',
    });
    return SnoozeResult(
      desired: desired,
      alreadyCommitted: result['replay'] == true,
    );
  }

  PendingReminderAction _pendingRead(Map<String, Object?> r) =>
      PendingReminderAction(
        envelopeId: r['envelope'] as String,
        commandId: r['command'] as String,
        draftId: r['draft'] as String,
        target: _targetRead(jsonDecode(r['snapshot'] as String)),
        action: ReminderActionKind.values.byName(r['action'] as String),
        submitted: r['submitted'] == 1,
        delayMinutes: r['delay'] as int?,
        delayText: r['delay_text'] as String?,
        observedZone: r['observed_zone'] as String?,
        sample: r['sample'] == null
            ? null
            : _sampleRead(jsonDecode(r['sample'] as String)),
        actualAt: r['actual'] == null
            ? null
            : DateTime.fromMicrosecondsSinceEpoch(
                r['actual'] as int,
                isUtc: true,
              ),
      );
  Future<PendingReminderAction> _insertPending(
    String envelope,
    ReminderTarget target,
    ReminderActionKind action, {
    String? request,
    String? actionToken,
  }) async {
    final command = newCommandId(), draft = newCommandId();
    await _db.customStatement(
      'INSERT INTO reminder_pending(envelope,person,request,action_token,action,command,draft,snapshot) VALUES (?,?,?,?,?,?,?,?)',
      [
        envelope,
        target.row.expectation.identity.personId,
        request,
        actionToken,
        action.name,
        command,
        draft,
        jsonEncode(_targetJson(target)),
      ],
    );
    return _pendingRead(
      (await _rows('SELECT * FROM reminder_pending WHERE envelope=?', [
        envelope,
      ])).single,
    );
  }

  Future<PendingReminderAction> createReminderAction({
    required ReminderTarget target,
    required ReminderActionKind action,
    required String? observedZone,
  }) async {
    _requireWritable();
    return _reminderTransaction(() async {
      _requireWritable();
      await _validateReminderTarget(target, observedZone);
      return _insertPending(newCommandId(), target, action);
    });
  }

  Future<PendingReminderAction?> captureReminderAction({
    required String envelopeId,
    required String namespace,
    required String requestToken,
    required String actionToken,
    required ReminderActionKind action,
  }) async {
    _requireWritable();
    if ([
      envelopeId,
      namespace,
      requestToken,
      actionToken,
    ].any((s) => s.isEmpty || s.length > 128)) {
      throw const CommandConflict('reminder_envelope');
    }
    return _reminderTransaction(() async {
      _requireWritable();
      final prior = await _rows(
        'SELECT * FROM reminder_pending WHERE envelope=? OR action_token=?',
        [envelopeId, actionToken],
      );
      if (prior.isNotEmpty) {
        final p = prior.single;
        if (p['request'] != requestToken ||
            p['action_token'] != actionToken ||
            p['action'] != action.name) {
          throw const CommandConflict('reminder_envelope');
        }
        return p['consumed'] == 1 || p['snapshot'] == null
            ? null
            : _pendingRead(p);
      }
      final requests = await _rows(
        'SELECT * FROM reminder_request WHERE token=? AND active=1 AND snapshot IS NOT NULL',
        [requestToken],
      );
      if (requests.isEmpty) return null;
      final r = _desiredRead(requests.single);
      final expected = switch (action) {
        ReminderActionKind.open => r.requestToken,
        ReminderActionKind.taken => r.takenToken,
        ReminderActionKind.snooze => r.snoozeToken,
        ReminderActionKind.skip => r.skipToken,
      };
      if (r.namespace != namespace || actionToken != expected) return null;
      // Capture the original immutable target even when it now needs review.
      return _insertPending(
        envelopeId,
        r.target,
        action,
        request: requestToken,
        actionToken: actionToken,
      );
    });
  }

  Future<List<PendingReminderAction>> pendingReminderActions() async {
    _requireWritable();
    return (await _rows(
      'SELECT * FROM reminder_pending WHERE consumed=0 AND snapshot IS NOT NULL ORDER BY envelope LIMIT 64',
    )).map(_pendingRead).toList();
  }

  Future<PendingReminderAction> updateReminderAction(
    String envelopeId, {
    int? delayMinutes,
    String? delayText,
    bool clearDelayMinutes = false,
    bool clearDelayText = false,
    String? observedZone,
    ReminderClockSample? sample,
    DateTime? actualAt,
    bool submit = false,
  }) async {
    _requireWritable();
    if (clearDelayMinutes && delayMinutes != null ||
        clearDelayText && delayText != null) {
      throw ArgumentError('reminder_delay_patch');
    }
    return _reminderTransaction(() async {
      _requireWritable();
      final rows = await _rows(
        'SELECT * FROM reminder_pending WHERE envelope=? AND consumed=0',
        [envelopeId],
      );
      if (rows.isEmpty) throw const CommandConflict('reminder_action');
      final p = _pendingRead(rows.single);
      final rawDelay = clearDelayText ? null : delayText ?? p.delayText;
      final savedZone = observedZone ?? p.observedZone;
      if (rawDelay != null && rawDelay.length > 1000) {
        throw const FormatException('snooze_input');
      }
      final delay = clearDelayMinutes ? null : delayMinutes ?? p.delayMinutes,
          clock = sample ?? p.sample,
          actual = actualAt ?? p.actualAt;
      if (delay != null && delay <= 0) {
        throw const FormatException('snooze_input');
      }
      if (p.submitted) {
        if (savedZone != p.observedZone ||
            rawDelay != p.delayText ||
            delay != p.delayMinutes ||
            jsonEncode(clock == null ? null : _sampleJson(clock)) !=
                jsonEncode(p.sample == null ? null : _sampleJson(p.sample!)) ||
            actual != p.actualAt) {
          throw const CommandConflict('reminder_payload');
        }
        return p;
      }
      if (submit && p.action == ReminderActionKind.snooze) {
        if (delay == null || clock == null) {
          throw const FormatException('snooze_input');
        }
        snoozeDeadline(clock, delay);
      }
      if (submit && p.action == ReminderActionKind.taken && actual == null) {
        throw const FormatException('daily_actual');
      }
      await _db.customStatement(
        'UPDATE reminder_pending SET delay=?,delay_text=?,observed_zone=?,sample=?,actual=?,submitted=? WHERE envelope=?',
        [
          delay,
          rawDelay,
          savedZone,
          clock == null ? null : jsonEncode(_sampleJson(clock)),
          actual?.microsecondsSinceEpoch,
          submit ? 1 : 0,
          envelopeId,
        ],
      );
      return _pendingRead(
        (await _rows('SELECT * FROM reminder_pending WHERE envelope=?', [
          envelopeId,
        ])).single,
      );
    });
  }

  Future<void> acknowledgeReminderAction(String envelopeId) async {
    _requireWritable();
    await _reminderTransaction(() async {
      _requireWritable();
      await _db.customStatement(
        'UPDATE reminder_pending SET consumed=1,snapshot=NULL,sample=NULL,actual=NULL,delay=NULL,delay_text=NULL,observed_zone=NULL,person=NULL WHERE envelope=?',
        [envelopeId],
      );
    });
  }

  Future<ReminderProjection> prepareReminders({
    required DateTime now,
    required String? observedZone,
    required ReminderClockSample? clockSample,
    required String adapterFingerprint,
  }) => _reminderTransaction(() async {
    final meta = await _reminderMeta();
    final configured = await _rows(
      'SELECT c.plan,c.person,c.enabled,o.archived,o.reminders_stopped FROM reminder_config c JOIN person o ON o.id=c.person ORDER BY c.plan LIMIT 1001',
    );
    var complete = configured.length <= 1000;
    final exclusions = <ReminderExclusion>[];
    final expandedRows = <DailyRow>[];
    final intervalClocks = <String, (DateTime, ReminderClockSample)>{};
    var examined = 0;
    for (final config in configured.take(1000)) {
      final scope = 'plan:${config['plan']}';
      if (config['enabled'] != 1 ||
          config['archived'] != 0 ||
          config['reminders_stopped'] != 0) {
        exclusions.add(
          ReminderExclusion(scope: scope, reason: 'disabled', count: 1),
        );
        continue;
      }
      if (examined >= 100 || expandedRows.length >= 5000) {
        complete = false;
        exclusions.add(
          ReminderExclusion(scope: scope, reason: 'work_limit', count: 1),
        );
        continue;
      }
      examined++;
      final versions = await _rows(
        'SELECT snapshot FROM daily_version WHERE plan=? ORDER BY start DESC,rowid DESC LIMIT 1001',
        [config['plan']],
      );
      final recovery = await _rows(
        'SELECT cutoff FROM interval_recovery WHERE plan=?',
        [config['plan']],
      );
      final cutoff = recovery.isEmpty
          ? null
          : CivilDate.parse(recovery.single['cutoff'] as String);
      final planRows = <DailyRow>[];
      var planComplete = versions.length <= 1000;
      DailyCalculationIssue? planIssue;
      for (final version in versions.take(1000)) {
        if (planRows.length + expandedRows.length >= 5000) {
          planComplete = false;
          break;
        }
        final p = decodeDailyPlan(dailyObject(version['snapshot'] as String));
        if (cutoff != null &&
            p.endExclusive != null &&
            p.endExclusive!.compareTo(cutoff) <= 0) {
          continue;
        }
        var projectionNow = now;
        if (p.timing case ElapsedInterval(:final segmentId)) {
          final mapped = await _intervalProjectionClock(p, clockSample);
          if (mapped == null) {
            planComplete = false;
            exclusions.add(
              ReminderExclusion(
                scope: scope,
                reason: 'elapsed_clock_recovery',
                count: 1,
              ),
            );
            continue;
          }
          intervalClocks['${p.planId}:$segmentId'] = mapped;
          projectionNow = mapped.$1;
        }
        final projectionDate = CivilDate(
          projectionNow.year,
          projectionNow.month,
          projectionNow.day,
        );
        final part = await _readDaily(
          scope: const FeedScope.everyone(),
          from: projectionDate.addDays(-1),
          toExclusive: projectionDate.addDays(9),
          observedZone: observedZone,
          maxPlans: 1,
          maxRows: 5000 - expandedRows.length - planRows.length,
          reminderPlanId: config['plan'] as String,
          reminderVersionId: p.versionId,
          calculationNow: projectionNow,
        );
        planRows.addAll(
          part.rows.where(
            (row) =>
                cutoff == null ||
                row.expectation.identity.originalDate.compareTo(cutoff) >= 0,
          ),
        );
        planComplete = planComplete && part.complete;
        planIssue ??= part.issue;
      }
      final expansion = DailyRows(
        rows: planRows,
        complete: planComplete,
        issue: planIssue,
      );
      expandedRows.addAll(expansion.rows);
      if (!expansion.complete) {
        complete = false;
        exclusions.add(
          ReminderExclusion(
            scope: scope,
            reason: expansion.issue?.name ?? 'calculation_incomplete',
            count: 1,
          ),
        );
      }
      final unresolved = expansion.rows
          .where(
            (r) =>
                !r.isResolved &&
                r.expectation.instant == null &&
                r.expectation.windowStart == null &&
                r.expectation.plannedCount == null,
          )
          .length;
      if (unresolved > 0) {
        complete = false;
        exclusions.add(
          ReminderExclusion(
            scope: scope,
            reason: 'clock_review',
            count: unresolved,
          ),
        );
      }
      final untimed = expansion.rows
          .where((r) => r.expectation.plannedCount != null)
          .length;
      if (untimed > 0 || expansion.rows.isEmpty && expansion.complete) {
        exclusions.add(
          ReminderExclusion(
            scope: scope,
            reason: untimed > 0 ? 'untimed' : 'no_occurrences',
            count: untimed > 0 ? untimed : 1,
          ),
        );
      }
    }
    await _db.customStatement(
      "UPDATE reminder_request SET state='expired',reason='deadline_passed' WHERE active=1 AND json_extract(snapshot,'\$.kind')='ordinary' AND json_extract(snapshot,'\$.trigger')='wall' AND state IN ('pending','prepared','failed','unknown','capacity') AND json_extract(snapshot,'\$.deadline')<=?",
      [now.toUtc().millisecondsSinceEpoch],
    );
    final active = await _rows(
      "SELECT * FROM reminder_request WHERE active=1 AND snapshot IS NOT NULL AND state IN ('pending','prepared','failed','unknown','capacity') ORDER BY token LIMIT 5001",
    );
    if (active.length > 5000) complete = false;
    for (final raw in active.take(5000)) {
      final r = _desiredRead(raw);
      try {
        await _validateReminderTarget(r.target, observedZone);
        if (r.kind == ReminderKind.snooze && r.sample != null) {
          await _validatePauseDeadline(
            r.target,
            DateTime.fromMillisecondsSinceEpoch(
              r.sample!.utcMilliseconds +
                  r.deadlineMilliseconds -
                  r.sample!.elapsedMilliseconds,
              isUtc: true,
            ),
          );
        }
      } on CommandConflict {
        if (r.kind == ReminderKind.snooze) {
          await _db.customStatement(
            "UPDATE reminder_request SET state='review',reason='target_changed' WHERE token=?",
            [r.requestToken],
          );
        } else {
          await _db.customStatement(
            "UPDATE reminder_request SET active=0,state='pending',reason='cancelled' WHERE token=?",
            [r.requestToken],
          );
        }
        continue;
      }
      if (r.trigger == ReminderTrigger.elapsed &&
          ![
            ReminderRepairState.consumed,
            ReminderRepairState.postUncertain,
            ReminderRepairState.interrupted,
            ReminderRepairState.expired,
            ReminderRepairState.review,
          ].contains(r.repairState)) {
        final clockState = snoozeClockState(
          saved: r.sample!,
          deadlineMilliseconds: r.deadlineMilliseconds,
          current: clockSample,
        );
        if (clockState != ReminderRepairState.pending) {
          await _db.customStatement(
            'UPDATE reminder_request SET state=?,reason=? WHERE token=?',
            [
              clockState.name,
              '${r.kind.name}_${clockState.name}',
              r.requestToken,
            ],
          );
        }
      }
    }
    for (final row in expandedRows) {
      final e = row.expectation;
      final mappedClock =
          intervalClocks['${e.identity.planId}:${e.identity.intervalSegmentId}'];
      final projectionNow = mappedClock?.$1 ?? now;
      final projectionHorizon = projectionNow.add(const Duration(days: 7));
      if (row.isResolved ||
          e.instant == null ||
          !e.instant!.isAfter(projectionNow) ||
          e.instant!.isAfter(projectionHorizon)) {
        continue;
      }
      final config = await _rows(
        'SELECT c.enabled,c.revision,o.reminders_stopped,o.archived FROM reminder_config c JOIN person o ON o.id=c.person WHERE c.plan=?',
        [e.identity.planId],
      );
      if (config.isEmpty ||
          config.single['enabled'] != 1 ||
          config.single['reminders_stopped'] != 0 ||
          config.single['archived'] != 0) {
        continue;
      }
      final state = await _reminderState(row);
      final bucket = dailyIdentityKey(e.identity);
      final exists = await _rows(
        'SELECT token FROM reminder_request WHERE bucket=? AND active=1 LIMIT 1',
        [bucket],
      );
      if (exists.isNotEmpty || state['ordinary_terminal'] == 1) continue;
      final isInterval = e.identity.intervalSegmentId != null;
      if (isInterval && mappedClock == null) {
        complete = false;
        exclusions.add(
          ReminderExclusion(
            scope: 'plan:${e.identity.planId}',
            reason: 'elapsed_clock_unavailable',
            count: 1,
          ),
        );
        continue;
      }
      final projectedDeadline =
          e.instant!.millisecondsSinceEpoch +
          (e.instant!.microsecondsSinceEpoch % 1000 == 0 ? 0 : 1);
      final origin = mappedClock?.$2;
      final elapsedDeadline = isInterval
          ? origin!.elapsedMilliseconds +
                projectedDeadline -
                origin.utcMilliseconds
          : projectedDeadline;
      if (elapsedDeadline < 0 || elapsedDeadline > 9223372036854775807) {
        complete = false;
        exclusions.add(
          ReminderExclusion(
            scope: 'plan:${e.identity.planId}',
            reason: 'elapsed_clock_range',
            count: 1,
          ),
        );
        continue;
      }
      await _ensureReminderState(row);
      await _insertReminder(
        ReminderTarget(
          row: row,
          snoozeRevision: state['snooze_revision'] as int,
          configRevision: config.single['revision'] as int,
        ),
        kind: ReminderKind.ordinary,
        deadline: elapsedDeadline,
        sample: isInterval ? origin : null,
      );
    }
    final all = (await _rows(
      "SELECT * FROM reminder_request WHERE active=1 AND snapshot IS NOT NULL AND state IN ('pending','prepared','failed','unknown','capacity') ORDER BY token LIMIT 5001",
    )).take(5000).map(_desiredRead).toList();
    final eligible = all
        .where(
          (r) => ![
            ReminderRepairState.review,
            ReminderRepairState.interrupted,
            ReminderRepairState.expired,
            ReminderRepairState.cancelled,
            ReminderRepairState.consumed,
            ReminderRepairState.postUncertain,
          ].contains(r.repairState),
        )
        .where(
          (r) =>
              r.trigger == ReminderTrigger.elapsed ||
              r.projectedUtc.isAfter(now) ||
              [
                ReminderRepairState.consumed,
                ReminderRepairState.postUncertain,
              ].contains(r.repairState),
        )
        .toList();
    final allocation = allocateReminders(eligible);
    final eventProjection = await _prepareEventEnds(
      now,
      meta['namespace'] as String,
    );
    final eventAllocation = eventProjection.$1;
    complete = complete && eventProjection.$4;
    for (final excluded in allocation.excluded) {
      await _db.customStatement(
        "UPDATE reminder_request SET state='capacity',reason='capacity' WHERE token=?",
        [excluded.requestToken],
      );
    }
    final selected = allocation.selected;
    final selectedTokens = selected.map((r) => r.requestToken).toSet();
    final obsoleteRows = await _rows(
      "SELECT token FROM reminder_request WHERE active=0 AND cancel_ack=0 ORDER BY token LIMIT 257",
    );
    if (obsoleteRows.length > 256) complete = false;
    final cancelledActive = {
      for (final r in await _rows(
        "SELECT token FROM reminder_request WHERE active=1 AND cancel_ack=1 AND state IN ('review','expired','interrupted') ORDER BY token LIMIT 5001",
      ))
        r['token'] as String,
    };
    final obsolete = <String>{
      ...eventProjection.$2,
      ...obsoleteRows.take(256).map((r) => r['token'] as String),
      ...[
            ...all,
            ...(await _rows(
              "SELECT * FROM reminder_request WHERE active=1 AND state IN ('review','expired','interrupted') AND cancel_ack=0 AND snapshot IS NOT NULL ORDER BY token LIMIT 256",
            )).map(_desiredRead),
          ]
          .where(
            (r) =>
                !selectedTokens.contains(r.requestToken) &&
                !cancelledActive.contains(r.requestToken) &&
                [
                  ReminderRepairState.interrupted,
                  ReminderRepairState.expired,
                  ReminderRepairState.review,
                ].contains(r.repairState),
          )
          .map((r) => r.requestToken),
    }.toList()..sort();
    // Fingerprint the exact opaque native payload. Receipt changes alone do not
    // manufacture a new native command sequence.
    final ordered = selected.toList()
      ..sort((a, b) => a.requestToken.compareTo(b.requestToken));
    final fingerprint = jsonEncode([
      for (final r in ordered)
        [
          r.requestToken,
          r.takenToken,
          r.snoozeToken,
          r.skipToken,
          r.trigger.name,
          r.deadlineMilliseconds,
          r.bootId,
        ],
      [for (final r in eventAllocation.selected) _eventRequestJson(r)],
      obsolete,
    ]);
    if (meta['fingerprint'] != fingerprint) {
      await _db.customStatement(
        'UPDATE reminder_meta SET sequence=sequence+1,fingerprint=? WHERE id=1',
        [fingerprint],
      );
    }
    final current = (await _rows('SELECT * FROM reminder_meta WHERE id=1'))
        .single;
    final uncertain = (await _rows(
      "SELECT * FROM reminder_request WHERE active=1 AND state IN ('interrupted','expired','review','postUncertain') AND snapshot IS NOT NULL ORDER BY token LIMIT 257",
    )).map(_desiredRead).toList();
    if (uncertain.length > 256) complete = false;
    final healthRequests = [...all, ...uncertain.take(256)];
    final scopes = <String, List<DesiredReminder>>{'everyone': healthRequests};
    for (final config in configured.take(1000)) {
      scopes.putIfAbsent('plan:${config['plan']}', () => []);
      scopes.putIfAbsent('person:${config['person']}', () => []);
    }
    for (final r in healthRequests) {
      (scopes.putIfAbsent(
        'person:${r.target.row.expectation.identity.personId}',
        () => [],
      )).add(r);
      (scopes.putIfAbsent(
        'plan:${r.target.row.expectation.identity.planId}',
        () => [],
      )).add(r);
    }
    final coverage = <ReminderCoverage>[];
    for (final entry in scopes.entries) {
      final sorted = entry.value.toList()
        ..sort((a, b) => a.projectedUtc.compareTo(b.projectedUtc));
      DateTime? through;
      String? reason;
      DateTime? groupTime;
      var groupSuccessful = true;
      for (final r in sorted) {
        if (groupTime != null && groupTime != r.projectedUtc) {
          if (!groupSuccessful) break;
          through = groupTime;
        }
        groupTime = r.projectedUtc;
        final success =
            (selectedTokens.contains(r.requestToken) ||
                r.repairState == ReminderRepairState.consumed) &&
            [
              ReminderRepairState.prepared,
              ReminderRepairState.consumed,
            ].contains(r.repairState) &&
            r.adapterFingerprint == adapterFingerprint;
        if (!success) {
          groupSuccessful = false;
          reason ??= r.reason ?? r.repairState.name;
        }
      }
      if (groupTime != null && groupSuccessful) through = groupTime;
      final scopeExclusions = exclusions
          .where(
            (e) =>
                e.scope == entry.key ||
                entry.key == 'everyone' ||
                entry.key.startsWith('person:') &&
                    configured.any(
                      (c) =>
                          e.scope == 'plan:${c['plan']}' &&
                          entry.key == 'person:${c['person']}',
                    ),
          )
          .toList();
      reason ??= scopeExclusions.isEmpty ? null : scopeExclusions.first.reason;
      final scopeComplete =
          complete && reason == null && allocation.excluded.isEmpty;
      coverage.add(
        ReminderCoverage(
          scope: entry.key,
          generation: generation,
          basis: observedZone ?? 'observed_zone_unavailable',
          adapterFingerprint: adapterFingerprint,
          checkedAt: now.toUtc(),
          complete: scopeComplete,
          preparedThrough: complete ? through : null,
          reason: reason ?? (!complete ? 'calculation_incomplete' : null),
        ),
      );
    }
    // One truthful capacity row per scope, with the exact displaced count.
    final capacityExclusions = <String, int>{};
    for (final r in allocation.excluded) {
      final scope = 'plan:${r.target.row.expectation.identity.planId}';
      capacityExclusions.update(scope, (n) => n + 1, ifAbsent: () => 1);
    }
    for (final r in eventAllocation.excluded) {
      final scope = 'event:${r.eventId}';
      capacityExclusions.update(scope, (n) => n + 1, ifAbsent: () => 1);
    }
    return ReminderProjection(
      generation: generation,
      namespace: current['namespace'] as String,
      sequence: current['sequence'] as int,
      desired: selected,
      eventEnds: eventAllocation.selected,
      eventEndAttention: eventProjection.$3.where(
        (r) =>
            !eventAllocation.selected.any(
              (v) => v.requestToken == r.requestToken,
            ) ||
            r.repairState != ReminderRepairState.prepared ||
            r.adapterFingerprint != adapterFingerprint,
      ),
      obsoleteTokens: obsolete,
      complete:
          complete &&
          allocation.excluded.isEmpty &&
          eventAllocation.excluded.isEmpty,
      coverage: [
        ...coverage,
        for (final r in eventProjection.$3)
          ReminderCoverage(
            scope: 'event:${r.eventId}',
            generation: generation,
            basis: 'saved_event_zone',
            adapterFingerprint: adapterFingerprint,
            checkedAt: now,
            complete:
                eventAllocation.selected.any(
                  (v) => v.requestToken == r.requestToken,
                ) &&
                r.repairState == ReminderRepairState.prepared &&
                r.adapterFingerprint == adapterFingerprint,
            preparedThrough:
                r.repairState == ReminderRepairState.prepared &&
                    r.adapterFingerprint == adapterFingerprint
                ? r.projectedUtc
                : null,
            reason:
                r.repairState == ReminderRepairState.prepared &&
                    r.adapterFingerprint == adapterFingerprint
                ? null
                : r.reason ?? r.repairState.name,
          ),
      ],
      exclusions: [
        ...exclusions,
        ...eventProjection.$5,
        for (final entry in capacityExclusions.entries)
          ReminderExclusion(
            scope: entry.key,
            reason: 'capacity',
            count: entry.value,
          ),
      ],
      attention: healthRequests
          .where(
            (r) => [
              ReminderRepairState.interrupted,
              ReminderRepairState.expired,
              ReminderRepairState.review,
              ReminderRepairState.postUncertain,
              ReminderRepairState.capacity,
              ReminderRepairState.failed,
              ReminderRepairState.unknown,
            ].contains(r.repairState),
          )
          .take(256),
    );
  });

  Future<bool> acknowledgeReminder({
    required String generation,
    required String requestToken,
    required int intentRevision,
    required int sequence,
    required ReminderReceipt receipt,
    String? reason,
    required String adapterFingerprint,
  }) => _reminderTransaction(() async {
    if (generation != this.generation) return false;
    if ((await _reminderMeta())['sequence'] != sequence) return false;
    final rows = await _rows('SELECT * FROM reminder_request WHERE token=?', [
      requestToken,
    ]);
    if (rows.isEmpty) {
      return _acknowledgeEventEnd(
        requestToken,
        intentRevision,
        receipt,
        adapterFingerprint,
        reason,
      );
    }
    if (rows.single['intent_revision'] != intentRevision) {
      return false;
    }
    final raw = rows.single;
    if (raw['active'] == 0 && receipt != ReminderReceipt.cancelled) {
      return false;
    }
    final currentState = raw['state'] as String;
    if (['consumed', 'postUncertain', 'cancelled'].contains(currentState)) {
      if (currentState == receipt.name) return true;
      if (!(currentState == 'postUncertain' &&
          receipt == ReminderReceipt.consumed)) {
        return false;
      }
    }
    if (['interrupted', 'expired', 'review'].contains(currentState)) {
      return receipt == ReminderReceipt.cancelled;
    }
    final state = switch (receipt) {
      ReminderReceipt.accepted => ReminderRepairState.prepared,
      ReminderReceipt.consumed => ReminderRepairState.consumed,
      ReminderReceipt.cancelled => ReminderRepairState.cancelled,
      ReminderReceipt.postUncertain => ReminderRepairState.postUncertain,
      ReminderReceipt.failed => ReminderRepairState.failed,
      ReminderReceipt.unknown => ReminderRepairState.unknown,
    };
    await _db.customStatement(
      'UPDATE reminder_request SET state=?,reason=?,fingerprint=? WHERE token=?',
      [state.name, reason, adapterFingerprint, requestToken],
    );
    if (raw['snapshot'] != null &&
        [
          ReminderReceipt.consumed,
          ReminderReceipt.postUncertain,
        ].contains(receipt)) {
      final r = _desiredRead(raw);
      if (r.kind == ReminderKind.ordinary) {
        await _db.customStatement(
          'UPDATE reminder_state SET ordinary_terminal=1 WHERE bucket=?',
          [raw['bucket']],
        );
      }
    }
    return true;
  });
  Future<bool> acknowledgeObsoleteReminder({
    required String generation,
    required String requestToken,
    required int sequence,
    required ReminderReceipt receipt,
    required String adapterFingerprint,
    String? reason,
  }) => _reminderTransaction(() async {
    if (generation != this.generation ||
        ![
          ReminderReceipt.cancelled,
          ReminderReceipt.consumed,
          ReminderReceipt.postUncertain,
        ].contains(receipt)) {
      return false;
    }
    final meta = await _reminderMeta();
    if (meta['sequence'] != sequence) return false;
    final payload = jsonDecode(meta['fingerprint'] as String) as List<dynamic>;
    if (payload.isEmpty ||
        !(payload.last as List<dynamic>).contains(requestToken)) {
      return false;
    }
    final rows = await _rows(
      'SELECT active FROM reminder_request WHERE token=?',
      [requestToken],
    );
    if (rows.isEmpty) {
      final events = await _rows(
        'SELECT token FROM event_end_request WHERE token=?',
        [requestToken],
      );
      if (events.isEmpty) return false;
      await _db.customStatement(
        "UPDATE event_end_request SET cancel_ack=1,state=CASE WHEN active=0 THEN 'cancelled' ELSE state END,fingerprint=? WHERE token=?",
        [adapterFingerprint, requestToken],
      );
      return true;
    }
    await _db.customStatement(
      "UPDATE reminder_request SET cancel_ack=1,state=CASE WHEN active=0 THEN 'cancelled' ELSE state END,fingerprint=? WHERE token=?",
      [adapterFingerprint, requestToken],
    );
    return true;
  });
}
