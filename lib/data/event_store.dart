part of 'record_store.dart';

const eventSchemaV15 = [
  'CREATE TABLE event_record(id TEXT PRIMARY KEY,person TEXT NOT NULL REFERENCES person(id),revision INTEGER NOT NULL CHECK(revision>0),snapshot TEXT NOT NULL CHECK(json_valid(snapshot)),UNIQUE(id,person)) STRICT',
  'CREATE INDEX event_person ON event_record(person,id)',
  'CREATE TABLE event_audit(event TEXT NOT NULL,person TEXT NOT NULL,revision INTEGER NOT NULL,snapshot TEXT NOT NULL CHECK(json_valid(snapshot)),operation TEXT NOT NULL UNIQUE,PRIMARY KEY(event,revision),FOREIGN KEY(event,person) REFERENCES event_record(id,person) ON DELETE CASCADE) STRICT',
  "CREATE TRIGGER event_audit_immutable BEFORE UPDATE ON event_audit BEGIN SELECT RAISE(ABORT,'immutable_event_history'); END",
  'CREATE TABLE event_membership(event TEXT NOT NULL,person TEXT NOT NULL,id TEXT NOT NULL,item TEXT NOT NULL,start INTEGER NOT NULL,end INTEGER,revision INTEGER NOT NULL CHECK(revision>0),PRIMARY KEY(event,id),FOREIGN KEY(event,person) REFERENCES event_record(id,person) ON DELETE CASCADE,FOREIGN KEY(item,person) REFERENCES item(id,person),CHECK(end IS NULL OR end>start)) STRICT',
  'CREATE INDEX event_membership_history ON event_membership(person,item,start,end,event)',
  'CREATE TABLE use_period(id TEXT PRIMARY KEY,person TEXT NOT NULL,item TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),first_ever INTEGER NOT NULL CHECK(first_ever IN (0,1)),snapshot TEXT NOT NULL CHECK(json_valid(snapshot)),UNIQUE(id,person),FOREIGN KEY(item,person) REFERENCES item(id,person)) STRICT',
  'CREATE UNIQUE INDEX use_period_first ON use_period(person,item) WHERE first_ever=1',
  'CREATE TABLE use_period_audit(period TEXT NOT NULL,person TEXT NOT NULL,revision INTEGER NOT NULL,snapshot TEXT NOT NULL CHECK(json_valid(snapshot)),operation TEXT NOT NULL UNIQUE,PRIMARY KEY(period,revision),FOREIGN KEY(period,person) REFERENCES use_period(id,person) ON DELETE CASCADE) STRICT',
  "CREATE TRIGGER use_period_audit_immutable BEFORE UPDATE ON use_period_audit BEGIN SELECT RAISE(ABORT,'immutable_use_period_history'); END",
  'CREATE TABLE event_item_decision(event TEXT NOT NULL,person TEXT NOT NULL,item TEXT NOT NULL,event_revision INTEGER NOT NULL,sequence INTEGER NOT NULL,decision TEXT NOT NULL CHECK(decision IN (\'continuePlan\',\'stopPlan\')),plan TEXT,plan_revision INTEGER,operation TEXT NOT NULL UNIQUE,PRIMARY KEY(event,item,sequence),FOREIGN KEY(event,person) REFERENCES event_record(id,person) ON DELETE CASCADE,FOREIGN KEY(item,person) REFERENCES item(id,person)) STRICT',
  "CREATE TRIGGER event_item_decision_immutable BEFORE UPDATE ON event_item_decision BEGIN SELECT RAISE(ABORT,'immutable_event_decision'); END",
  'CREATE TABLE event_end_request(token TEXT PRIMARY KEY,event TEXT,person TEXT,snapshot TEXT,state TEXT NOT NULL,active INTEGER NOT NULL DEFAULT 1,cancel_ack INTEGER NOT NULL DEFAULT 0,fingerprint TEXT,reason TEXT,intent_revision INTEGER NOT NULL) STRICT',
  'CREATE INDEX event_end_work ON event_end_request(active,state,token)',
  'CREATE TABLE event_pending(envelope TEXT PRIMARY KEY,request TEXT NOT NULL,person TEXT,event TEXT,event_revision INTEGER NOT NULL,person_revision INTEGER NOT NULL,generation TEXT NOT NULL,consumed INTEGER NOT NULL DEFAULT 0) STRICT',
  'ALTER TABLE ordinary_draft RENAME TO ordinary_draft_v14',
  "CREATE TABLE ordinary_draft(id TEXT PRIMARY KEY,generation TEXT NOT NULL,operation TEXT NOT NULL UNIQUE,kind TEXT NOT NULL CHECK(kind IN ('item','dose','correction','profile','dailyPlan','pausePlan','phasePlan','itemType','stockContainer','stockAdjustment','productLabel','combinedDose','combinedCorrection','siteEdit','event','usePeriod','eventReview')),person TEXT REFERENCES person(id),person_revision INTEGER,target TEXT,target_revision INTEGER,snapshot TEXT NOT NULL) STRICT",
  'INSERT INTO ordinary_draft SELECT * FROM ordinary_draft_v14',
  'DROP TABLE ordinary_draft_v14',
];

/// A historical inclusion preview is tied to both event and actual revisions.
final class EventMembershipReview {
  EventMembershipReview({
    required this.command,
    required this.personRevision,
    required this.sourceGuard,
    required Iterable<UseRecord> entering,
    required Iterable<UseRecord> leaving,
  }) : entering = List.unmodifiable(entering),
       leaving = List.unmodifiable(leaving);
  final SaveEventCommand command;
  final int personRevision;
  final String sourceGuard;
  final List<UseRecord> entering, leaving;
}

final class EventEndReview {
  EventEndReview({
    required this.event,
    required this.personRevision,
    required this.generation,
    required Iterable<EventEndItem> items,
  }) : items = List.unmodifiable(items);
  final EventRecord event;
  final int personRevision;
  final String generation;
  final List<EventEndItem> items;
}

final class EventEndItem {
  EventEndItem({
    required this.item,
    required Iterable<SavedDailyPlan> plans,
    required this.decision,
    this.decisionSequence = 0,
  }) : plans = List.unmodifiable(plans);
  final SubstanceItem item;
  final List<SavedDailyPlan> plans;
  final String? decision;
  final int decisionSequence;
}

final class PendingEventEndReview {
  const PendingEventEndReview({
    required this.envelopeId,
    required this.eventId,
    required this.personId,
    required this.eventRevision,
    required this.personRevision,
    required this.generation,
  });
  final String envelopeId, eventId, personId, generation;
  final int eventRevision, personRevision;
}

extension EventRecordStore on RecordStore {
  Map<String, Object?> _eventObject(String text) =>
      Map<String, Object?>.from(jsonDecode(text) as Map);
  Future<List<EventRecord>> events({
    String? personId,
    int limit = 100,
    int offset = 0,
  }) async {
    _pageBounds(limit, offset);
    return (await _rows(
          'SELECT snapshot FROM event_record ${personId == null ? '' : 'WHERE person=?'} ORDER BY id LIMIT ? OFFSET ?',
          [?personId, limit, offset],
        ))
        .map((r) => EventRecord.fromJson(_eventObject(r['snapshot'] as String)))
        .toList();
  }

  Stream<List<EventRecord>> watchEvents({
    String? personId,
    int limit = 100,
    int offset = 0,
  }) => _watch(() => events(personId: personId, limit: limit, offset: offset));
  Stream<EventRecord?> watchEventById(String id) => _watch(() => eventById(id));
  Stream<List<RecordedUsePeriod>> watchUsePeriods({
    required String personId,
    required String itemId,
  }) => _watch(() => usePeriods(personId: personId, itemId: itemId));
  Future<EventRecord?> eventById(String id) async {
    final rows = await _rows('SELECT snapshot FROM event_record WHERE id=?', [
      id,
    ]);
    return rows.isEmpty
        ? null
        : EventRecord.fromJson(_eventObject(rows.single['snapshot'] as String));
  }

  Future<List<EventRecord>> eventHistory(String id) async =>
      (await _rows(
            'SELECT snapshot FROM event_audit WHERE event=? ORDER BY revision',
            [id],
          ))
          .map(
            (r) => EventRecord.fromJson(_eventObject(r['snapshot'] as String)),
          )
          .toList();
  Future<String> _eventActualGuard(String person) async {
    final rows = await _rows(
      'SELECT id,revision,actual FROM administration WHERE person=? ORDER BY id LIMIT 100001',
      [person],
    );
    if (rows.length > 100000) {
      throw const CommandConflict('event_history_guard_bound');
    }
    return jsonEncode(rows);
  }

  Future<List<UseRecord>> _actualsForEvents(
    List<EventRecord> selected, {
    int limit = 500,
    int offset = 0,
  }) async {
    _pageBounds(limit, offset);
    if (selected.isEmpty) return [];
    if (selected.length > 100) {
      throw const CommandConflict('event_selection_bound');
    }
    final clauses = <String>[];
    final args = <Object?>[];
    final clock = IanaClock();
    for (final event in selected) {
      final start = (event.actualStart ?? event.plannedStart)?.resolve(
        clock,
        event.zoneId,
      );
      final end = (event.actualEnd ?? event.plannedEnd)?.resolve(
        clock,
        event.zoneId,
        inclusiveEnd: true,
      );
      for (final m in event.memberships) {
        clauses.add(
          '(a.person=? AND a.item=? AND a.actual>=? AND (? IS NULL OR a.actual<?) AND (? IS NULL OR a.actual>=?) AND (? IS NULL OR a.actual<?))',
        );
        args.addAll([
          event.personId,
          m.itemId,
          m.effectiveFrom.microsecondsSinceEpoch,
          m.effectiveUntil?.microsecondsSinceEpoch,
          m.effectiveUntil?.microsecondsSinceEpoch,
          start?.microsecondsSinceEpoch,
          start?.microsecondsSinceEpoch,
          end?.microsecondsSinceEpoch,
          end?.microsecondsSinceEpoch,
        ]);
      }
    }
    if (clauses.isEmpty) return [];
    if (clauses.length > 1000) {
      throw const CommandConflict('event_membership_bound');
    }
    // OR selection and one current administration row deduplicate overlap before pagination.
    return (await _rows(
      '${RecordStore._current} WHERE r.voided=0 AND (${clauses.join(' OR ')}) ORDER BY a.actual DESC,a.id LIMIT ? OFFSET ?',
      [...args, limit, offset],
    )).map(_record).toList();
  }

  Future<List<UseRecord>> eventActuals(
    List<String> eventIds, {
    int limit = 100,
    int offset = 0,
  }) => _db.transaction(() async {
    final selected = <EventRecord>[];
    for (final id in eventIds.toSet()) {
      final event = await eventById(id);
      if (event == null) throw const CommandConflict('event_context');
      selected.add(event);
    }
    return _actualsForEvents(selected, limit: limit, offset: offset);
  });
  Future<void> _validateEvent(SaveEventCommand c) async {
    _dailyGeneration(c.generation);
    await _activeOwner(c.event.personId, c.expectedPersonRevision);
    final event = c.event;
    if ([
          event.id,
          event.personId,
          event.name,
          event.eventType,
          event.zoneId,
        ].any((s) => s.length > 500) ||
        event.memberships.length > 100) {
      throw const CommandConflict('event_bound');
    }
    try {
      event.validateBounds(IanaClock());
    } on EventBoundaryReview catch (error) {
      throw CommandConflict(error.code);
    }
    final old = await eventById(event.id);
    if ((old?.revision) != c.expectedRevision ||
        event.revision != (c.expectedRevision ?? 0) + 1 ||
        old != null && old.personId != event.personId) {
      throw const CommandConflict('event_revision');
    }
    for (final m in event.memberships) {
      final item = await itemById(m.itemId, personId: event.personId);
      if (item == null || m.personId != event.personId) {
        throw const CommandConflict('ownership');
      }
      final previous = old?.memberships.where((p) => p.id == m.id).firstOrNull;
      if (previous != null) {
        if (previous.itemId != m.itemId || previous.personId != m.personId) {
          throw const CommandConflict('membership_identity');
        }
        final same = jsonEncode(previous.toJson()) == jsonEncode(m.toJson());
        if (!same && m.revision != previous.revision + 1) {
          throw const CommandConflict('membership_revision');
        }
      } else if (m.revision != 1) {
        throw const CommandConflict('membership_revision');
      }
    }
    // Retain old associations. Closing their effective interval preserves history.
    if (old != null &&
        old.memberships.any(
          (m) => !event.memberships.any((p) => p.id == m.id),
        )) {
      throw const CommandConflict('membership_close_required');
    }
  }

  Future<EventMembershipReview> previewEventMembership(
    SaveEventCommand command,
  ) => _db.transaction(() async {
    await _validateEvent(command);
    final old = await eventById(command.event.id);
    final before = old == null
        ? <UseRecord>[]
        : await _actualsForEvents([old], limit: 500);
    final after = await _actualsForEvents([command.event], limit: 500);
    // A preview must never silently truncate its historical impact.
    if (before.length == 500 || after.length == 500) {
      throw const CommandConflict('event_history_preview_bound');
    }
    return EventMembershipReview(
      command: command,
      personRevision: command.expectedPersonRevision,
      sourceGuard: await _eventActualGuard(command.event.personId),
      entering: after.where((r) => !before.any((p) => p.id == r.id)),
      leaving: before.where((r) => !after.any((p) => p.id == r.id)),
    );
  });
  Future<EventRecord> saveEvent(
    SaveEventCommand command, {
    EventMembershipReview? membershipReview,
    bool failBeforeCommit = false,
    Future<void> Function()? beforeCommit,
  }) async {
    _dailyGeneration(command.generation);
    final encoded = jsonEncode(command.event.toJson());
    final result = await _command(
      command.commandId,
      [
        'event',
        command.event.personId,
        encoded,
        command.expectedRevision,
        command.expectedPersonRevision,
      ],
      () async {
        await _validateEvent(command);
        final fresh = await previewEventMembership(command);
        if (fresh.entering.isNotEmpty || fresh.leaving.isNotEmpty) {
          if (membershipReview == null ||
              jsonEncode(membershipReview.command.event.toJson()) != encoded ||
              membershipReview.command.expectedRevision !=
                  command.expectedRevision ||
              membershipReview.personRevision !=
                  command.expectedPersonRevision ||
              membershipReview.sourceGuard != fresh.sourceGuard) {
            throw const CommandConflict('membership_review');
          }
        } else if (membershipReview != null &&
            membershipReview.sourceGuard != fresh.sourceGuard) {
          throw const CommandConflict('membership_review');
        }
        final oldEvent = await eventById(command.event.id);
        var savedEvent = command.event.copyWith(
          completedAt: command.event.completed
              ? (oldEvent?.completed == true
                    ? oldEvent?.completedAt ?? DateTime.now().toUtc()
                    : DateTime.now().toUtc())
              : null,
          clearCompletedAt: !command.event.completed,
        );
        String occurrence(EventRecord event) => jsonEncode([
          event.zoneId,
          event.actualEnd?.toJson(),
          if (event.actualEnd == null) event.completed,
          if (event.actualEnd == null && event.completed)
            event.completedAt?.toIso8601String(),
          if (event.actualEnd == null && !event.completed)
            event.plannedEnd?.toJson(),
        ]);
        if (oldEvent != null &&
            (occurrence(oldEvent) != occurrence(savedEvent) ||
                oldEvent.completed && !savedEvent.completed)) {
          savedEvent = savedEvent.copyWith(endReviewDismissed: false);
        }
        final storedSnapshot = jsonEncode(savedEvent.toJson());
        await _db.customStatement(
          'INSERT INTO event_record VALUES (?,?,?,?) ON CONFLICT(id) DO UPDATE SET revision=excluded.revision,snapshot=excluded.snapshot',
          [
            command.event.id,
            command.event.personId,
            command.event.revision,
            storedSnapshot,
          ],
        );
        await _writeEventHistoryBounds(savedEvent);
        await _db.customStatement(
          'INSERT INTO event_audit VALUES (?,?,?,?,?)',
          [
            command.event.id,
            command.event.personId,
            command.event.revision,
            storedSnapshot,
            command.commandId,
          ],
        );
        await _db.customStatement(
          'DELETE FROM event_membership WHERE event=?',
          [command.event.id],
        );
        for (final m in command.event.memberships) {
          await _db.customStatement(
            'INSERT INTO event_membership VALUES (?,?,?,?,?,?,?)',
            [
              command.event.id,
              command.event.personId,
              m.id,
              m.itemId,
              m.effectiveFrom.microsecondsSinceEpoch,
              m.effectiveUntil?.microsecondsSinceEpoch,
              m.revision,
            ],
          );
        }
        await _invalidateEventRequests(command.event.id);
        return {'person': command.event.personId, 'event': savedEvent.toJson()};
      },
      failBeforeCommit: failBeforeCommit,
      beforeCommit: beforeCommit,
    );
    return EventRecord.fromJson(
      Map<String, Object?>.from(result['event'] as Map),
    );
  }

  Future<List<RecordedUsePeriod>> usePeriods({
    required String personId,
    required String itemId,
  }) async {
    final rows = await _rows(
      'SELECT snapshot FROM use_period WHERE person=? AND item=? ORDER BY id LIMIT 10001',
      [personId, itemId],
    );
    if (rows.length > 10000) throw const CommandConflict('use_period_bound');
    return rows
        .map(
          (r) =>
              RecordedUsePeriod.fromJson(_eventObject(r['snapshot'] as String)),
        )
        .toList();
  }

  Future<List<RecordedUsePeriod>> usePeriodHistory(String id) async =>
      (await _rows(
            'SELECT snapshot FROM use_period_audit WHERE period=? ORDER BY revision',
            [id],
          ))
          .map(
            (r) => RecordedUsePeriod.fromJson(
              _eventObject(r['snapshot'] as String),
            ),
          )
          .toList();
  Future<RecordedUsePeriod> saveUsePeriod(
    SaveUsePeriodCommand command, {
    bool failBeforeCommit = false,
    Future<void> Function()? beforeCommit,
  }) async {
    _dailyGeneration(command.generation);
    final p = command.period, encoded = jsonEncode(command.period.toJson());
    final result = await _command(
      command.commandId,
      [
        'use_period',
        p.personId,
        encoded,
        command.expectedRevision,
        command.expectedPersonRevision,
      ],
      () async {
        await _activeOwner(p.personId, command.expectedPersonRevision);
        if (await itemById(p.itemId, personId: p.personId) == null) {
          throw const CommandConflict('ownership');
        }
        p.duration(IanaClock(), 'UTC');
        final prior = await _rows(
          'SELECT person,item,revision FROM use_period WHERE id=?',
          [p.id],
        );
        if ((prior.firstOrNull?['revision']) != command.expectedRevision ||
            p.revision != (command.expectedRevision ?? 0) + 1 ||
            prior.isNotEmpty &&
                (prior.single['person'] != p.personId ||
                    prior.single['item'] != p.itemId)) {
          throw const CommandConflict('use_period_revision');
        }
        if (p.firstEver &&
            (await _rows(
              'SELECT id FROM use_period WHERE person=? AND item=? AND first_ever=1 AND id<>?',
              [p.personId, p.itemId, p.id],
            )).isNotEmpty) {
          throw const CommandConflict('first_ever_exists');
        }
        await _db.customStatement(
          'INSERT INTO use_period VALUES (?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET revision=excluded.revision,first_ever=excluded.first_ever,snapshot=excluded.snapshot',
          [
            p.id,
            p.personId,
            p.itemId,
            p.revision,
            p.firstEver ? 1 : 0,
            encoded,
          ],
        );
        await _db.customStatement(
          'INSERT INTO use_period_audit VALUES (?,?,?,?,?)',
          [p.id, p.personId, p.revision, encoded, command.commandId],
        );
        return {'person': p.personId, 'period': p.toJson()};
      },
      failBeforeCommit: failBeforeCommit,
      beforeCommit: beforeCommit,
    );
    return RecordedUsePeriod.fromJson(
      Map<String, Object?>.from(result['period'] as Map),
    );
  }

  Future<void> _invalidateEventRequests(String id) async {
    await _db.customStatement(
      "UPDATE event_end_request SET active=0,state='pending',reason='cancelled' WHERE event=? AND active=1",
      [id],
    );
    await _db.customStatement(
      'UPDATE event_pending SET consumed=1 WHERE event=?',
      [id],
    );
  }

  Future<void> _forgetEventPerson(String person) async {
    await _db.customStatement(
      "UPDATE event_end_request SET active=0,state='pending',reason='cancelled',snapshot=NULL,person=NULL,event=NULL WHERE person=?",
      [person],
    );
    await _db.customStatement('DELETE FROM event_pending WHERE person=?', [
      person,
    ]);
    await _db.customStatement('DELETE FROM event_record WHERE person=?', [
      person,
    ]);
    await _db.customStatement('DELETE FROM use_period WHERE person=?', [
      person,
    ]);
  }

  Future<EventEndReview> eventEndReview(String eventId) =>
      _db.transaction(() async {
        final event = await eventById(eventId);
        if (event == null) throw const CommandConflict('event_context');
        final owner = await profileById(event.personId);
        if (owner == null || owner.isArchived) {
          throw const CommandConflict('ownership');
        }
        final items = <EventEndItem>[];
        for (final id in event.memberships.map((m) => m.itemId).toSet()) {
          final item = await itemById(id, personId: event.personId);
          if (item == null) throw const CommandConflict('ownership');
          final plans = await dailyPlans(
            scope: FeedScope.person(event.personId),
            itemId: id,
            limit: 500,
          );
          if (plans.length == 500) {
            throw const CommandConflict('event_plan_bound');
          }
          final decision = await _rows(
            'SELECT decision,sequence FROM event_item_decision WHERE event=? AND item=? AND event_revision=? ORDER BY sequence DESC LIMIT 1',
            [event.id, id, event.revision],
          );
          items.add(
            EventEndItem(
              item: item,
              plans: plans,
              decision: decision.firstOrNull?['decision'] as String?,
              decisionSequence: decision.firstOrNull?['sequence'] as int? ?? 0,
            ),
          );
        }
        return EventEndReview(
          event: event,
          personRevision: owner.revision,
          generation: generation,
          items: items,
        );
      });
  Future<void> _validateEndReview(EventEndReview review) async {
    _dailyGeneration(review.generation);
    await _activeOwner(review.event.personId, review.personRevision);
    final event = await eventById(review.event.id);
    if (event == null ||
        event.personId != review.event.personId ||
        event.revision != review.event.revision ||
        event.endReviewDismissed) {
      throw const CommandConflict('event_revision');
    }
  }

  Future<void> applyEventItemDecision({
    required String commandId,
    required EventEndReview review,
    required String itemId,
    required bool continuePlan,
    PhaseChangeReview? stopReview,
    List<PhaseChangeReview> stopReviews = const [],
    ReminderClockSample? intervalClockSample,
    bool failBeforeCommit = false,
    Future<void> Function()? beforeCommit,
  }) async {
    _dailyGeneration(review.generation);
    final stops = [?stopReview, ...stopReviews];
    final encoded = [
      for (final r in stops)
        [
          encodePhasePlan(r.proposed),
          r.plan.revision,
          r.personRevision,
          r.generation,
          r.sourceGuard,
          r.now.microsecondsSinceEpoch,
          r.observedZone,
        ],
    ];
    await _command(
      commandId,
      [
        'event_item',
        review.event.personId,
        review.event.id,
        review.event.revision,
        review.personRevision,
        itemId,
        continuePlan,
        encoded,
        [
          for (final item in review.items)
            [
              item.item.id,
              item.item.revision,
              item.decisionSequence,
              for (final p in item.plans) [p.plan.planId, p.revision],
            ],
        ],
        if (intervalClockSample != null) _sampleJson(intervalClockSample),
      ],
      () async {
        await _validateEndReview(review);
        final item = review.items
            .where((i) => i.item.id == itemId)
            .singleOrNull;
        if (item == null ||
            !review.event.memberships.any((m) => m.itemId == itemId)) {
          throw const CommandConflict('membership_revision');
        }
        final priorDecision = await _rows(
          'SELECT sequence FROM event_item_decision WHERE event=? AND item=? AND event_revision=? ORDER BY sequence DESC LIMIT 1',
          [review.event.id, itemId, review.event.revision],
        );
        if ((priorDecision.firstOrNull?['sequence'] as int? ?? 0) !=
            item.decisionSequence) {
          throw const CommandConflict('event_decision_revision');
        }
        final currentItem = await itemById(
          itemId,
          personId: review.event.personId,
        );
        if (currentItem == null || currentItem.revision != item.item.revision) {
          throw const CommandConflict('item_revision');
        }
        final current = await dailyPlans(
          scope: FeedScope.person(review.event.personId),
          itemId: itemId,
          limit: 500,
        );
        if (jsonEncode([
              for (final p in current) [p.plan.planId, p.revision],
            ]) !=
            jsonEncode([
              for (final p in item.plans) [p.plan.planId, p.revision],
            ])) {
          throw const CommandConflict('plan_revision');
        }
        if (continuePlan && stops.isNotEmpty ||
            !continuePlan &&
                (stops.length != current.length ||
                    stops.map((r) => r.plan.plan.planId).toSet().length !=
                        stops.length)) {
          throw const CommandConflict('event_plan_review');
        }
        if (!continuePlan) {
          for (final r in stops) {
            if (r.plan.plan.personId != review.event.personId ||
                r.plan.plan.itemId != itemId ||
                r.generation != review.generation ||
                r.personRevision != review.personRevision ||
                !current.any(
                  (p) =>
                      p.plan.planId == r.plan.plan.planId &&
                      p.revision == r.plan.revision,
                ) ||
                r.proposed.end == null) {
              throw const CommandConflict('event_plan_review');
            }
            final before =
                await phasePlan(
                  planId: r.plan.plan.planId,
                  personId: review.event.personId,
                ) ??
                PhasePlan(
                  phases: await _phaseVersions(
                    r.plan.plan.planId,
                    review.event.personId,
                  ),
                );
            final oldShape = encodePhasePlan(before)..remove('end');
            final newShape = encodePhasePlan(r.proposed)..remove('end');
            if (jsonEncode(oldShape) != jsonEncode(newShape)) {
              throw const CommandConflict('event_stop_only');
            }
            await savePhasePlan(
              commandId: '$commandId:${r.plan.plan.planId}',
              review: r,
              intervalClockSample: intervalClockSample,
            );
          }
        }
        final sequence = (await _rows(
          'SELECT COALESCE(MAX(sequence),0)+1 AS n FROM event_item_decision WHERE event=? AND item=?',
          [review.event.id, itemId],
        )).single['n'];
        await _db.customStatement(
          'INSERT INTO event_item_decision VALUES (?,?,?,?,?,?,?,?,?)',
          [
            review.event.id,
            review.event.personId,
            itemId,
            review.event.revision,
            sequence,
            continuePlan ? 'continuePlan' : 'stopPlan',
            null,
            null,
            commandId,
          ],
        );
        return {
          'person': review.event.personId,
          'eventId': review.event.id,
          'item': itemId,
          'decision': continuePlan ? 'continuePlan' : 'stopPlan',
        };
      },
      failBeforeCommit: failBeforeCommit,
      beforeCommit: beforeCommit,
    );
  }

  Future<EventRecord> dismissEventEndReview({
    required String commandId,
    required EventEndReview review,
  }) async {
    return saveEvent(
      SaveEventCommand(
        commandId: commandId,
        generation: review.generation,
        expectedPersonRevision: review.personRevision,
        expectedRevision: review.event.revision,
        event: review.event.copyWith(
          revision: review.event.revision + 1,
          endReviewDismissed: true,
        ),
      ),
    );
  }

  Future<List<PendingEventEndReview>> pendingEventEndReviews() async {
    _requireWritable();
    return (await _rows(
          'SELECT * FROM event_pending WHERE consumed=0 ORDER BY envelope LIMIT 64',
        ))
        .map(
          (r) => PendingEventEndReview(
            envelopeId: r['envelope'] as String,
            eventId: r['event'] as String,
            personId: r['person'] as String,
            eventRevision: r['event_revision'] as int,
            personRevision: r['person_revision'] as int,
            generation: r['generation'] as String,
          ),
        )
        .toList();
  }

  Future<void> consumePendingEventEndReview(String envelopeId) async {
    _requireWritable();
    await _reminderTransaction(() async {
      await _db.customStatement(
        'UPDATE event_pending SET consumed=1 WHERE envelope=?',
        [envelopeId],
      );
    });
  }

  Map<String, Object?> _eventRequestJson(EventEndReminder r) => {
    'token': r.requestToken,
    'taken': r.takenToken,
    'snooze': r.snoozeToken,
    'skip': r.skipToken,
    'generation': r.generation,
    'namespace': r.namespace,
    'eventId': r.eventId,
    'personId': r.personId,
    'eventRevision': r.eventRevision,
    'personRevision': r.personRevision,
    'deadline': r.deadlineMilliseconds,
  };
  EventEndReminder _eventRequestRead(Map<String, Object?> row) {
    final m = _eventObject(row['snapshot'] as String);
    return EventEndReminder(
      requestToken: m['token'] as String,
      takenToken: m['taken'] as String,
      snoozeToken: m['snooze'] as String,
      skipToken: m['skip'] as String,
      generation: m['generation'] as String,
      namespace: m['namespace'] as String,
      eventId: m['eventId'] as String,
      personId: m['personId'] as String,
      eventRevision: m['eventRevision'] as int,
      personRevision: m['personRevision'] as int,
      deadlineMilliseconds: m['deadline'] as int,
      repairState: ReminderRepairState.values.byName(row['state'] as String),
      reason: row['reason'] as String?,
      adapterFingerprint: row['fingerprint'] as String?,
    );
  }

  Future<
    (
      EventEndAllocation,
      List<String>,
      List<EventEndReminder>,
      bool,
      List<ReminderExclusion>,
    )
  >
  _prepareEventEnds(DateTime now, String namespace) async {
    var complete = true;
    final exclusions = <ReminderExclusion>[];
    await _pruneEventReminderState();
    final heads = await _rows(
      'SELECT e.id,e.snapshot,p.revision AS owner_revision,p.archived,p.reminders_stopped FROM event_record e JOIN person p ON p.id=e.person ORDER BY e.id LIMIT 1001',
    );
    if (heads.length > 1000) complete = false;
    for (final head in heads.take(1000)) {
      EventRecord event;
      DateTime? deadline;
      try {
        event = EventRecord.fromJson(_eventObject(head['snapshot'] as String));
        event.validateBounds(IanaClock());
        deadline = event.endReviewAt(IanaClock());
      } catch (error) {
        complete = false;
        exclusions.add(
          ReminderExclusion(
            scope: 'event:${head['id']}',
            reason: error is EventBoundaryReview
                ? error.code
                : 'event_boundary_review',
            count: 1,
          ),
        );
        await _invalidateEventRequests(head['id'] as String);
        continue;
      }
      if (head['archived'] == 1 ||
          head['reminders_stopped'] == 1 ||
          event.endReviewDismissed) {
        continue;
      }
      if (deadline == null ||
          deadline.isAfter(now.add(const Duration(days: 7)))) {
        continue;
      }
      final requests = await _rows(
        'SELECT * FROM event_end_request WHERE event=? AND active=1',
        [event.id],
      );
      final valid = requests.where((r) {
        final v = _eventRequestRead(r);
        return v.eventRevision == event.revision &&
            v.personRevision == head['owner_revision'] &&
            v.namespace == namespace &&
            v.generation == generation;
      }).toList();
      if (valid.isNotEmpty) continue;
      await _invalidateEventRequests(event.id);
      final request = EventEndReminder(
        requestToken: newCommandId(),
        takenToken: newCommandId(),
        snoozeToken: newCommandId(),
        skipToken: newCommandId(),
        generation: generation,
        namespace: namespace,
        eventId: event.id,
        personId: event.personId,
        eventRevision: event.revision,
        personRevision: head['owner_revision'] as int,
        deadlineMilliseconds: deadline.millisecondsSinceEpoch,
        repairState: deadline.isAfter(now)
            ? ReminderRepairState.pending
            : ReminderRepairState.review,
        reason: deadline.isAfter(now) ? null : 'event_end_due',
      );
      await _db.customStatement(
        'INSERT INTO event_end_request(token,event,person,snapshot,state,intent_revision,reason) VALUES (?,?,?,?,?,?,?)',
        [
          request.requestToken,
          event.id,
          event.personId,
          jsonEncode(_eventRequestJson(request)),
          request.repairState.name,
          event.revision,
          request.reason,
        ],
      );
    }
    final active = await _rows(
      'SELECT * FROM event_end_request WHERE active=1 AND snapshot IS NOT NULL ORDER BY token LIMIT 1001',
    );
    if (active.length > 1000) complete = false;
    for (final raw in active.take(1000)) {
      final r = _eventRequestRead(raw);
      final event = await eventById(r.eventId);
      final owner = await profileById(r.personId);
      if (event == null ||
          owner == null ||
          owner.isArchived ||
          owner.remindersStopped ||
          event.endReviewDismissed ||
          event.revision != r.eventRevision ||
          owner.revision != r.personRevision ||
          r.generation != generation ||
          r.namespace != namespace) {
        await _invalidateEventRequests(r.eventId);
      }
    }
    final all = (await _rows(
      "SELECT * FROM event_end_request WHERE active=1 AND snapshot IS NOT NULL ORDER BY token LIMIT 1001",
    )).take(1000).map(_eventRequestRead).toList();
    final allocation = allocateEventEndReminders(all);
    for (final r in allocation.excluded) {
      await _db.customStatement(
        "UPDATE event_end_request SET state='capacity',reason='capacity' WHERE token=?",
        [r.requestToken],
      );
    }
    final obsolete = (await _rows(
      'SELECT token FROM event_end_request WHERE active=0 AND cancel_ack=0 ORDER BY token LIMIT 257',
    )).map((r) => r['token'] as String).toList();
    if (obsolete.length > 256) complete = false;
    return (allocation, obsolete.take(256).toList(), all, complete, exclusions);
  }

  Future<bool> captureEventEndAction({
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
      final rows = await _rows(
        'SELECT * FROM event_end_request WHERE token=? AND active=1 AND snapshot IS NOT NULL',
        [requestToken],
      );
      if (rows.isEmpty) return false;
      if (_eventObject(rows.single['snapshot'] as String)['opened'] == 1) {
        return false;
      }
      final r = _eventRequestRead(rows.single);
      if (action != ReminderActionKind.open ||
          namespace != r.namespace ||
          actionToken != r.requestToken) {
        return false;
      }
      final event = await eventById(r.eventId),
          owner = await profileById(r.personId);
      if (event == null ||
          owner == null ||
          owner.isArchived ||
          owner.remindersStopped ||
          event.revision != r.eventRevision ||
          owner.revision != r.personRevision ||
          event.endReviewDismissed ||
          r.generation != generation) {
        return false;
      }
      final prior = await _rows(
        'SELECT request FROM event_pending WHERE envelope=? OR request=?',
        [envelopeId, requestToken],
      );
      if (prior.isNotEmpty && prior.first['request'] != requestToken) {
        throw const CommandConflict('reminder_envelope');
      }
      if (prior.isNotEmpty) return true;
      await _db.customStatement(
        'INSERT INTO event_pending VALUES (?,?,?,?,?,?,?,0) ON CONFLICT(envelope) DO NOTHING',
        [
          envelopeId,
          requestToken,
          r.personId,
          r.eventId,
          r.eventRevision,
          r.personRevision,
          r.generation,
        ],
      );
      return true;
    });
  }

  Future<void> _pruneEventReminderState() async {
    await _db.customStatement(
      "UPDATE event_end_request SET snapshot=json_set(snapshot,'\$.opened',1) WHERE snapshot IS NOT NULL AND token IN (SELECT request FROM event_pending WHERE consumed=1 ORDER BY envelope LIMIT 256)",
    );
    await _db.customStatement(
      'DELETE FROM event_pending WHERE rowid IN (SELECT rowid FROM event_pending WHERE consumed=1 ORDER BY envelope LIMIT 256)',
    );
    await _db.customStatement(
      'DELETE FROM event_end_request WHERE rowid IN (SELECT r.rowid FROM event_end_request r WHERE r.active=0 AND r.cancel_ack=1 AND NOT EXISTS(SELECT 1 FROM event_pending p WHERE p.request=r.token AND p.consumed=0) ORDER BY r.token LIMIT 256)',
    );
  }

  Future<bool> _acknowledgeEventEnd(
    String token,
    int intentRevision,
    ReminderReceipt receipt,
    String fingerprint,
    String? reason,
  ) async {
    final rows = await _rows('SELECT * FROM event_end_request WHERE token=?', [
      token,
    ]);
    if (rows.isEmpty || rows.single['intent_revision'] != intentRevision) {
      return false;
    }
    final row = rows.single;
    if (row['active'] == 0 && receipt != ReminderReceipt.cancelled) {
      return false;
    }
    final old = row['state'] as String;
    // Terminal monotonicity mirrors the ordinary lane: consumed, postUncertain
    // and cancelled rows never move backwards, and the only advancement is
    // postUncertain to consumed. If the terminal row were released to a mere
    // repair state here, a later accepted receipt would resurrect an ended
    // intent under the same event revision.
    if (['consumed', 'postUncertain', 'cancelled'].contains(old) &&
        !(old == 'postUncertain' && receipt == ReminderReceipt.consumed) &&
        old != receipt.name) {
      return false;
    }
    final state = switch (receipt) {
      ReminderReceipt.accepted => 'prepared',
      ReminderReceipt.consumed => 'consumed',
      ReminderReceipt.cancelled => 'cancelled',
      ReminderReceipt.postUncertain => 'postUncertain',
      ReminderReceipt.failed => 'failed',
      ReminderReceipt.unknown => 'unknown',
    };
    // The adapter evidenced this token's end, so the cancellation is
    // acknowledged monotonically without ever regressing. The row itself
    // remains the terminal fence: preparation only recognises active rows,
    // so releasing this row would immediately mint a replacement token for
    // the same event revision, re-arming a notice the device already ended.
    final settled = receipt == ReminderReceipt.cancelled;
    await _db.customStatement(
      'UPDATE event_end_request SET state=?,fingerprint=?,reason=?,cancel_ack=? WHERE token=?',
      [
        state,
        fingerprint,
        reason,
        settled || (row['cancel_ack'] as int) == 1 ? 1 : 0,
        token,
      ],
    );
    return true;
  }
}
