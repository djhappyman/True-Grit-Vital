// Host-only ticket 17 scale harness.
//
// Builds a deterministic, encrypted, ten-adult History dataset with 100,000
// current administrations, seven archived adults, combined groups, skips,
// event memberships, a saved-type change and voided rows. It asserts bounded
// keyset pages, fixed ownership/current revisions, parent-first combined
// groups and actual SQLite query plans. It measures host query time only; it
// is not Android, G06, UI-frame, memory or release evidence.
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';

const _zone = 'Europe/London';
const _adultCount = 10;
const _totalAdministrations = 100000;
final _recentDay = DateTime.utc(2026, 10, 19);
final _recentDayMicros = _recentDay.microsecondsSinceEpoch;
const _dayMicros = Duration.microsecondsPerDay;

final _key = List<int>.generate(32, (i) => i + 1);

final class _AdultScale {
  _AdultScale({
    required this.profile,
    required this.items,
    required this.recentWeight,
    required this.historyWeight,
  });
  final AdultProfile profile;
  final List<SubstanceItem> items;
  final int recentWeight;
  final int historyWeight;
  SubstanceItem get primary => items.first;
  SubstanceItem get secondary => items.last;
}

final class _ScaleFixture {
  _ScaleFixture({
    required this.directory,
    required this.path,
    required this.store,
    required this.adults,
    required this.active,
    required this.archived,
    required this.groups,
    required this.correctedGroup,
    required this.voidedGroup,
    required this.events,
    required this.typeChangedRecord,
    required this.voidedRecord,
    required this.correctedRecord,
    required this.skips,
    required this.lateSkip,
    required this.repeatSkip,
    required this.savedTypeSkip,
    required this.undoneSkip,
    required this.measurements,
  });

  final Directory directory;
  final String path;
  final RecordStore store;
  final List<_AdultScale> adults;
  final List<AdultProfile> active;
  final List<AdultProfile> archived;
  final List<CombinedUseResult> groups;
  final CombinedUseResult correctedGroup;
  final CombinedUseResult voidedGroup;
  final List<EventRecord> events;
  final UseRecord typeChangedRecord;
  final UseRecord voidedRecord;
  final UseRecord correctedRecord;
  final List<DailyAction> skips;
  final DailyAction lateSkip;
  final DailyAction repeatSkip;
  final DailyAction savedTypeSkip;
  final DailyAction undoneSkip;
  final Map<String, Object?> measurements;

  Future<void> close() async {
    await store.close();
    await directory.delete(recursive: true);
  }
}

Future<_ScaleFixture> _buildFixture() async {
  final directory = await Directory.systemTemp.createTemp(
    'vital-history-scale-',
  );
  final path = '${directory.path}/history.db';
  final timer = Stopwatch()..start();
  var store = await RecordStore.open(path: path, key: _key, isNew: true);
  final measurements = <String, Object?>{
    'platform': Platform.operatingSystem,
    'runtime': Platform.version,
    'scope': 'host-only History scale fixture; not G06, Android, frame or memory evidence',
  };
  measurements['fresh_open_us'] = timer.elapsedMicroseconds;

  final adults = <_AdultScale>[];
  final profiles = <AdultProfile>[];
  final me = await store.profileById(meId);
  if (me == null) throw StateError('scale_me_missing');
  profiles.add(me);
  for (var i = 1; i < _adultCount; i++) {
    profiles.add(
      await store.createProfile(
        commandId: 'scale-profile-$i',
        name: 'Scale adult ${i.toString().padLeft(2, '0')}',
        adultConfirmed: true,
      ),
    );
  }
  // Six archived adults is deliberately archived-heavy. The last archived
  // adult is low-volume so full keyset paging can be compared to a raw oracle.
  final recentWeights = <int>[42, 24, 14, 6, 4, 3, 1, 1, 1, 0];
  final historyWeights = <int>[5, 5, 5, 20, 20, 18, 12, 8, 4, 3];
  for (var i = 0; i < profiles.length; i++) {
    final profile = profiles[i];
    final primary = await store.createItem(
      commandId: 'scale-item-${profile.id}-medicine',
      personId: profile.id,
      name: 'Scale medicine ${i + 1}',
      form: 'tablet',
      unit: 'mg',
      type: 'medicine',
    );
    final secondary = await store.createItem(
      commandId: 'scale-item-${profile.id}-supplement',
      personId: profile.id,
      name: 'Scale supplement ${i + 1}',
      form: 'capsule',
      unit: 'count',
      type: 'supplement',
    );
    adults.add(
      _AdultScale(
        profile: profile,
        items: [primary, secondary],
        recentWeight: recentWeights[i],
        historyWeight: historyWeights[i],
      ),
    );
  }
  final active = profiles.take(3).toList();
  final archived = profiles.skip(3).toList();

  // Create events before the bulk rows exist. The event preview refuses to
  // truncate history at 500 rows, so this also keeps the fixture creation
  // bounded and avoids turning a preview into a full-history scan.
  final events = <EventRecord>[];
  final meScale = adults[0];
  final activeOne = adults[1];
  final archivedOne = adults[3];
  final eventSpecs =
      <(AdultProfile, SubstanceItem, String, DateTime, DateTime)>[
        (
          meScale.profile,
          meScale.primary,
          'Scale course A',
          DateTime.utc(2026, 9, 1),
          DateTime.utc(2026, 10, 1),
        ),
        (
          meScale.profile,
          meScale.primary,
          'Scale course B',
          DateTime.utc(2026, 9, 15),
          DateTime.utc(2026, 10, 5),
        ),
        (
          activeOne.profile,
          activeOne.primary,
          'Scale course C',
          DateTime.utc(2026, 10, 1),
          DateTime.utc(2026, 10, 26),
        ),
        (
          archivedOne.profile,
          archivedOne.primary,
          'Archived course',
          DateTime.utc(2026, 9, 1),
          DateTime.utc(2026, 10, 1),
        ),
      ];
  for (var i = 0; i < eventSpecs.length; i++) {
    final (person, item, name, start, end) = eventSpecs[i];
    final event = EventRecord(
      id: 'scale-event-$i',
      personId: person.id,
      name: name,
      eventType: 'course',
      zoneId: _zone,
      revision: 1,
      plannedStart: EventDate.exact(start),
      plannedEnd: EventDate.exact(end),
      memberships: [
        EventMembership(
          id: 'scale-event-$i-member',
          itemId: item.id,
          personId: person.id,
          effectiveFrom: start,
          revision: 1,
        ),
      ],
    );
    final command = SaveEventCommand(
      commandId: 'scale-save-event-$i',
      generation: store.generation,
      expectedRevision: null,
      event: event,
    );
    events.add(await store.saveEvent(command));
  }
  // A date-only end in a DST zone exercises the saved event-bounds path.
  final dstEvent = EventRecord(
    id: 'scale-event-dst',
    personId: activeOne.profile.id,
    name: 'Scale DST course',
    eventType: 'course',
    zoneId: _zone,
    revision: 1,
    plannedStart: EventDate.day(CivilDate(2026, 10, 20)),
    plannedEnd: EventDate.day(CivilDate(2026, 10, 25)),
    memberships: [
      EventMembership(
        id: 'scale-event-dst-member',
        itemId: activeOne.primary.id,
        personId: activeOne.profile.id,
        effectiveFrom: DateTime.utc(2026, 10, 20),
        revision: 1,
      ),
    ],
  );
  events.add(
    await store.saveEvent(
      SaveEventCommand(
        commandId: 'scale-save-event-dst',
        generation: store.generation,
        expectedRevision: null,
        event: dstEvent,
      ),
    ),
  );

  // Daily plans: a date-only count plan for the first five adults, an explicit
  // late slot for Me, a repeated-clock slot for adult 2 and a plan for the
  // saved-type check on adult 2.
  final skips = <DailyAction>[];
  Future<DailyRow> rowFor(
    _AdultScale adult,
    SubstanceItem item,
    CivilDate date,
  ) async {
    final rows = await store.dailyRows(
      scope: FeedScope.person(adult.profile.id),
      from: date,
      toExclusive: date.addDays(1),
      observedZone: _zone,
    );
    return rows.rows.singleWhere((row) => row.expectation.itemId == item.id);
  }

  Future<void> savePlan(
    _AdultScale adult,
    SubstanceItem item,
    String suffix,
    DailyTiming timing,
    CivilDate start,
  ) async {
    await store.saveDailyPlan(
      commandId: 'scale-plan-${adult.profile.id}-$suffix',
      plan: DailyPlanVersion(
        personId: adult.profile.id,
        planId: 'scale-plan-${adult.profile.id}-$suffix',
        itemId: item.id,
        versionId: 'scale-plan-${adult.profile.id}-$suffix-v1',
        start: start,
        timing: timing,
        zoneBasis: FixedHome(_zone),
      ),
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
    );
  }

  PlannedAmount amountFor(SubstanceItem item) => PlannedAmount(
    quantity: ExactQuantity.parse('1'),
    enteredText: '1',
    unit: item.unit,
  );

  for (final adult in adults.take(5)) {
    await savePlan(
      adult,
      adult.primary,
      'daily',
      DailyCount(1, amountFor(adult.primary)),
      CivilDate(2026, 10, 1),
    );
    final row = await rowFor(adult, adult.primary, CivilDate(2026, 10, 18));
    skips.add(
      await store.actDaily(
        commandId: 'scale-skip-${adult.profile.id}-daily',
        row: row,
        kind: DailyActionKind.skip,
      ),
    );
  }
  await savePlan(
    meScale,
    meScale.secondary,
    'late',
    DailySlots([
      DailySlot(
        id: 'late',
        reminderEnabled: false,
        time: WallTime(23, 58),
        amount: amountFor(meScale.secondary),
      ),
    ]),
    CivilDate(2026, 10, 1),
  );
  final lateSkip = await store.actDaily(
    commandId: 'scale-skip-me-late',
    row: await rowFor(meScale, meScale.secondary, CivilDate(2026, 10, 19)),
    kind: DailyActionKind.skip,
  );
  skips.add(lateSkip);
  await savePlan(
    activeOne,
    activeOne.secondary,
    'repeat',
    DailySlots([
      DailySlot(
        id: 'repeat',
        reminderEnabled: false,
        time: WallTime(1, 30),
        amount: amountFor(activeOne.secondary),
      ),
    ]),
    CivilDate(2026, 10, 1),
  );
  final repeatSkip = await store.actDaily(
    commandId: 'scale-skip-active1-repeat',
    row: await rowFor(activeOne, activeOne.secondary, CivilDate(2026, 10, 25)),
    kind: DailyActionKind.skip,
  );
  skips.add(repeatSkip);
  // A saved skip on the existing daily plan for adult 2. Its expectation type
  // must stay medicine after that item's live type is renamed later.
  final savedTypeSkip = await store.actDaily(
    commandId: 'scale-skip-active1-saved-type',
    row: await rowFor(activeOne, activeOne.primary, CivilDate(2026, 10, 17)),
    kind: DailyActionKind.skip,
  );
  skips.add(savedTypeSkip);
  // An undone skip remains in the audit but must not appear in the timeline.
  final undoneRow = await rowFor(
    adults[2],
    adults[2].primary,
    CivilDate(2026, 10, 16),
  );
  final undone = await store.actDaily(
    commandId: 'scale-skip-undone',
    row: undoneRow,
    kind: DailyActionKind.skip,
  );
  await store.undoDaily(
    commandId: 'scale-skip-undone-undo',
    row: await rowFor(adults[2], adults[2].primary, CivilDate(2026, 10, 16)),
    action: undone,
  );

  // Combined groups: 20 parent rows, two components each. Some are recent
  // enough to be on the first page; one is corrected to a new time and one is
  // wholly voided while keeping its parent time.
  final groups = <CombinedUseResult>[];
  CombinedUseResult? correctedGroup;
  CombinedUseResult? voidedGroup;
  for (var i = 0; i < 20; i++) {
    final adult = adults[i % adults.length];
    final at = i < 10
        ? _recentDay.add(Duration(hours: 23, minutes: i))
        : _recentDay.subtract(Duration(days: 30 + i, hours: 12));
    final group = await store.recordCombined(
      CombinedUseCommand(
        commandId: 'scale-combined-$i',
        expectedGeneration: store.generation,
        personId: adult.profile.id,
        expectedPersonRevision: 1,
        actualAt: at,
        components: [
          CombinedUseComponent(
            itemId: adult.primary.id,
            expectedItemRevision: 1,
            enteredAmount: '1.000',
          ),
          CombinedUseComponent(
            itemId: adult.secondary.id,
            expectedItemRevision: 1,
            enteredAmount: '1',
          ),
        ],
      ),
    );
    groups.add(group);
    if (i == 0) {
      correctedGroup = await store.correctCombined(
        CombinedCorrectionCommand(
          commandId: 'scale-combined-corrected',
          actionId: group.actionId,
          personId: adult.profile.id,
          expectedPersonRevision: 1,
          expectedGeneration: store.generation,
          actualAt: DateTime.utc(2026, 10, 20, 10),
          components: [
            for (final record in group.records)
              CombinedCorrectionComponent(
                recordId: record.id,
                expectedRevision: 1,
                physicalCorrection: null,
              ),
          ],
        ),
      );
    }
    if (i == 1) {
      voidedGroup = await store.correctCombined(
        CombinedCorrectionCommand(
          commandId: 'scale-combined-voided',
          actionId: group.actionId,
          personId: adult.profile.id,
          expectedPersonRevision: 1,
          expectedGeneration: store.generation,
          voided: true,
          components: [
            for (final record in group.records)
              CombinedCorrectionComponent(
                recordId: record.id,
                expectedRevision: 1,
                physicalCorrection: null,
              ),
          ],
        ),
      );
    }
  }

  // Taken daily actions: the administration must appear once, with plan
  // context, and never as a second skipped entry.
  final taken = <UseRecord>[];
  for (final (index, date) in [(2, 17), (4, 16)]) {
    final adult = adults[index];
    final row = await rowFor(adult, adult.primary, CivilDate(2026, 10, date));
    final action = await store.actDaily(
      commandId: 'scale-taken-${adult.profile.id}',
      row: row,
      kind: DailyActionKind.taken,
      actualAt: _recentDay.add(Duration(hours: 23, minutes: 55 + taken.length)),
    );
    taken.add(
      (await store.timeline(
        TimelineQuery(
          filter: TimelineFilter(scope: FeedScope.person(adult.profile.id)),
          displayZone: _zone,
          limit: 1,
        ),
      )).entries.whereType<RecordTimelineEntry>().single.record,
    );
    if (action.recordId == null) throw StateError('scale_taken_missing');
  }

  await store.close();

  // Bulk rows are inserted directly after the store has closed. Only the
  // existing current-revision tables are touched; no triggers are bypassed
  // because none of the relevant immutable-history triggers cover INSERT on
  // administration/revision. Every row still has a current revision and a
  // revision_source FK.
  final raw = _openRaw(path);
  final existing =
      raw.select('SELECT COUNT(*) AS count FROM administration').single['count']
          as int;
  final bulkCount = _totalAdministrations - existing - 1;
  if (bulkCount < 90000) throw StateError('scale_bulk_too_small');
  final recentCount = (bulkCount * 82 / 100).floor();
  final recentCumulative = _cumulative(adults, recent: true);
  final historyCumulative = _cumulative(adults, recent: false);
  final head = raw.prepare('INSERT INTO administration VALUES (?,?,?,1,?)');
  final revision = raw.prepare(
    'INSERT INTO revision(record,person,revision,name,form,unit,type,amount,entered,actual,entered_at,voided) VALUES (?,?,1,?,?,?,?,?,?,?,?,?)',
  );
  final source = raw.prepare('INSERT INTO revision_source VALUES (?,?,?)');
  final tieAt = groups[2].records.first.actualAt.microsecondsSinceEpoch;
  try {
    raw.execute('BEGIN');
    for (var i = 0; i < bulkCount; i++) {
      final recent = i < recentCount;
      final adult =
          adults[_pick(
            recent ? recentCumulative : historyCumulative,
            recent ? i : i - recentCount,
          )];
      final item = i % 5 == 0 ? adult.secondary : adult.primary;
      final id = 'scale-rec-${i.toString().padLeft(6, '0')}';
      final int actual;
      if (recent) {
        actual = i < 120 ? tieAt : _recentDayMicros + (i % 82000) * 1000000;
      } else {
        final j = i - recentCount;
        actual =
            _recentDayMicros -
            (1 + j % 730) * _dayMicros +
            ((j * 37) % 86400) * 1000000;
      }
      final voided = i % 997 == 0;
      head.execute([id, adult.profile.id, item.id, actual]);
      revision.execute([
        id,
        adult.profile.id,
        item.name,
        item.form,
        item.unit,
        item.type,
        125000,
        '0.125000',
        actual,
        actual + 10,
        voided ? 1 : 0,
      ]);
      source.execute([
        id,
        1,
        adult.profile.id == meId ? 'selfReported' : 'recordedOnBehalf',
      ]);
    }
    raw.execute('COMMIT');
  } finally {
    head.close();
    revision.close();
    source.close();
    raw.close();
  }

  timer.reset();
  store = await RecordStore.open(path: path, key: _key, isNew: false);
  measurements['populated_reopen_us'] = timer.elapsedMicroseconds;
  measurements['administrations_before_type_row'] = await _rawCount(
    path,
    'SELECT COUNT(*) AS count FROM administration',
  );
  measurements['revisions'] = await _rawCount(
    path,
    'SELECT COUNT(*) AS count FROM revision',
  );
  measurements['combined_groups'] = groups.length;
  measurements['combined_components'] = groups.fold<int>(
    0,
    (sum, group) => sum + group.records.length,
  );

  // Change the live item type after its history was saved, then write one new
  // record. Old revisions and the old skip expectation must remain medicine.
  final liveType = adults[1].primary;
  await store.renameItemType(
    commandId: 'scale-rename-type',
    typeId: liveType.typeId!,
    expectedRevision: 1,
    name: 'medicine-renamed',
    personId: adults[1].profile.id,
    expectedPersonRevision: 1,
  );
  final typeChangedRecord = await store.record(
    commandId: 'scale-new-renamed-type-record',
    itemId: liveType.id,
    amount: '1.000',
    actualAt: DateTime.utc(2026, 10, 20, 12),
    personId: adults[1].profile.id,
  );
  measurements['administrations'] = await _rawCount(
    path,
    'SELECT COUNT(*) AS count FROM administration',
  );

  // Current-revision correction and void on ordinary rows chosen from the
  // newest page. Neither changes the administration count.
  final newest = await store.records(personId: meId, limit: 20);
  final ordinary = newest
      .where((r) => r.combinedActionId == null && !r.isVoided)
      .toList();
  if (ordinary.length < 2) throw StateError('scale_target_missing');
  final voidedRecord = await store.voidRecord(
    commandId: 'scale-void-ordinary',
    recordId: ordinary[0].id,
    expectedRevision: ordinary[0].revision,
  );
  final correctedRecord = await store.correct(
    commandId: 'scale-correct-ordinary',
    recordId: ordinary[1].id,
    expectedRevision: ordinary[1].revision,
    amount: '2.000',
    actualAt: DateTime.utc(2026, 10, 20, 9),
  );

  for (final profile in archived) {
    final current = await store.profileById(profile.id);
    await store.archiveProfile(
      commandId: 'scale-archive-${profile.id}',
      personId: profile.id,
      expectedRevision: current!.revision,
    );
  }

  measurements['bulk_rows'] = bulkCount;
  measurements['recent_bulk_rows'] = recentCount;
  measurements['historical_bulk_rows'] = bulkCount - recentCount;
  measurements['archived_adults'] = archived.length;
  measurements['active_adults'] = active.length;
  measurements['skips'] = skips.length;
  measurements['type_changed_record_id'] = typeChangedRecord.id;
  measurements['voided_record_id'] = voidedRecord.id;
  measurements['corrected_record_id'] = correctedRecord.id;

  return _ScaleFixture(
    directory: directory,
    path: path,
    store: store,
    adults: adults,
    active: active,
    archived: archived,
    groups: groups,
    correctedGroup: correctedGroup!,
    voidedGroup: voidedGroup!,
    events: events,
    typeChangedRecord: typeChangedRecord,
    voidedRecord: voidedRecord,
    correctedRecord: correctedRecord,
    skips: skips,
    lateSkip: lateSkip,
    repeatSkip: repeatSkip,
    savedTypeSkip: savedTypeSkip,
    undoneSkip: undone,
    measurements: measurements,
  );
}

List<int> _cumulative(List<_AdultScale> adults, {required bool recent}) {
  final values = <int>[];
  var total = 0;
  for (final adult in adults) {
    total += recent ? adult.recentWeight : adult.historyWeight;
    values.add(total);
  }
  return values;
}

int _pick(List<int> cumulative, int index) {
  final slot = index % cumulative.last;
  for (var i = 0; i < cumulative.length; i++) {
    if (slot < cumulative[i]) return i;
  }
  return cumulative.length - 1;
}

Database _openRaw(String path) {
  final db = sqlite3.open(path);
  db.execute("PRAGMA cipher='chacha20'");
  final hex = _key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  db.execute('PRAGMA key="x\'$hex\'"');
  db.execute('PRAGMA foreign_keys=ON');
  db.execute('PRAGMA busy_timeout=5000');
  return db;
}

Future<int> _rawCount(String path, String sql) async {
  final db = _openRaw(path);
  try {
    return db.select(sql).single['count'] as int;
  } finally {
    db.close();
  }
}

String _sortKey(TimelineEntry entry) => entry.id.sortKey;

Future<List<TimelineEntry>> _readAll(
  RecordStore store,
  TimelineQuery query, {
  int maxPages = 600,
}) async {
  final entries = <TimelineEntry>[];
  var current = query;
  for (var pageNumber = 0; pageNumber < maxPages; pageNumber++) {
    final page = await store.timeline(current);
    expect(
      page.entries.length,
      lessThanOrEqualTo(current.limit),
      reason: 'page exceeds its requested limit',
    );
    entries.addAll(page.entries);
    if (!page.hasMore) {
      expect(page.next, isNull);
      return entries;
    }
    expect(page.next, isNotNull);
    current = current.withCursor(page.next!);
  }
  fail('page loop exceeded $maxPages pages');
}

String _recordBranch({
  required String predicate,
  required String status,
  String feed = 'administration a',
}) {
  const join =
      'revision r ON r.record=a.id AND r.person=a.person AND r.revision=a.revision LEFT JOIN revision_quantity q ON q.record=r.record AND q.revision=r.revision';
  return "SELECT a.id,a.person,a.actual AS at,'r:'||a.id AS key,'record' AS kind,CASE r.voided WHEN 1 THEN 'voided' ELSE 'recorded' END AS status FROM $feed JOIN $join WHERE $predicate$status AND NOT EXISTS(SELECT 1 FROM combined_member cm WHERE cm.record=a.id)";
}

String _combinedBranch({
  required String scope,
  required String predicate,
  required String status,
  String feed = 'combined_action g',
}) {
  const join =
      'revision r ON r.record=a.id AND r.person=a.person AND r.revision=a.revision LEFT JOIN revision_quantity q ON q.record=r.record AND q.revision=r.revision';
  return "SELECT g.id,g.person,g.actual AS at,'c:'||g.id AS key,'combined' AS kind,CASE (SELECT r.voided FROM combined_member m JOIN administration a ON a.id=m.record JOIN revision r ON r.record=a.id AND r.revision=a.revision WHERE m.action=g.id LIMIT 1) WHEN 1 THEN 'voided' ELSE 'recorded' END AS status FROM $feed WHERE $scope AND EXISTS(SELECT 1 FROM combined_member cm INDEXED BY sqlite_autoindex_combined_member_2 CROSS JOIN administration a ON a.id=cm.record AND a.person=cm.person JOIN $join WHERE cm.action=g.id AND cm.person=g.person AND $predicate$status)";
}

String _legacySkipBranch({required bool everyone, required String predicate}) {
  final index = everyone
      ? 'history_expectation_global_time'
      : 'history_expectation_time';
  return "SELECT d.id,d.person,e.occurs_at AS at,'s:'||d.id AS key,'skipped' AS kind,'skipped' AS status FROM daily_expectation e INDEXED BY $index CROSS JOIN daily_action d ON d.bucket=e.id AND d.person=e.person WHERE d.kind='skip' AND d.undone=0 AND $predicate";
}

String _skipBranch({required bool everyone, required String predicate}) {
  final index = everyone
      ? 'history_skip_global_time'
      : 'history_skip_person_time';
  final owner = everyone
      ? 'd.person IN (SELECT id FROM person WHERE archived=0)'
      : 'd.person=?';
  return "SELECT d.id,d.person,d.occurs_at AS at,'s:'||d.id AS key,'skipped' AS kind,'skipped' AS status FROM daily_action d INDEXED BY $index CROSS JOIN daily_expectation e ON e.id=d.bucket AND e.person=d.person WHERE d.kind='skip' AND d.undone=0 AND $owner AND $predicate";
}

String _outer(String branch) =>
    'SELECT * FROM ($branch) ORDER BY at DESC,id LIMIT 51';

String _everyoneRecordPredicate() =>
    'a.person IN (SELECT id FROM person WHERE archived=0)';

String _personRecordPredicate() => 'a.person=?';

List<String> _plan(Database db, String sql, [List<Object?> args = const []]) =>
    db
        .select('EXPLAIN QUERY PLAN $sql', args)
        .map((row) => row['detail'] as String)
        .toList();

String _planText(List<String> plan) => plan.join(' | ');

bool _hasFullTableScan(List<String> plan) {
  for (final detail in plan) {
    final upper = detail.toUpperCase();
    if (!upper.startsWith('SCAN ')) continue;
    if (upper.contains(' USING ')) continue;
    if (upper.contains('CONSTANT ROW')) continue;
    return true;
  }
  return false;
}

bool _hasTempBTree(List<String> plan) =>
    _planText(plan).toUpperCase().contains('TEMP B-TREE');

int _childReadShape(TimelinePage page) {
  var reads = 0;
  if (page.entries.any((entry) => entry is RecordTimelineEntry)) {
    reads += 1; // current records plus their taken-action plan context
  }
  if (page.entries.any((entry) => entry is CombinedTimelineEntry)) {
    reads += 1; // membership rows plus the matched subset
  }
  if (page.entries.any((entry) => entry is SkippedTimelineEntry)) {
    reads += 1; // expectation/action rows
  }
  return reads;
}

Future<void> _expectEntryOwnership(TimelineEntry entry) async {
  switch (entry) {
    case RecordTimelineEntry(:final record):
      expect(entry.personId, record.personId);
      expect(
        record.combinedActionId,
        isNull,
        reason: 'combined components must not also be record entries',
      );
    case CombinedTimelineEntry(:final components):
      expect(components.length, inInclusiveRange(2, 16));
      expect(
        components.map((component) => component.position).toList(),
        orderedEquals(
          [...components.map((component) => component.position)]..sort(),
        ),
      );
      for (final component in components) {
        expect(component.record.personId, entry.personId);
        expect(component.record.actualAt, entry.occurredAt);
        expect(
          component.record.isVoided,
          entry.status == TimelineEntryStatus.voided,
        );
      }
    case SkippedTimelineEntry(:final action, :final context):
      expect(entry.personId, context.expectation.identity.personId);
      expect(action.kind, DailyActionKind.skip);
      expect(action.isUndone, isFalse);
      expect(action.recordId, isNull);
  }
}

void main() {
  test('skip timestamp ties require action ordering before the page limit', () {
    // SQL-only adversarial fixture, separate from the encrypted 100k fixture.
    // The real table/index declarations hold 5,000 skips with expectation
    // identities ordered opposite to their action identities.
    final db = sqlite3.openInMemory();
    try {
      for (final sql in dailySchemaV6.where(
        (sql) =>
            sql.startsWith('CREATE TABLE daily_expectation(') ||
            sql.startsWith('CREATE TABLE daily_action('),
      )) {
        db.execute(sql);
      }
      for (final sql in historySchemaV17.where(
        (sql) =>
            sql.startsWith('ALTER TABLE daily_expectation ') ||
            sql.startsWith('CREATE INDEX history_expectation_') ||
            sql.startsWith('CREATE INDEX history_skip '),
      )) {
        db.execute(sql);
      }
      db.execute('CREATE TABLE person(id TEXT PRIMARY KEY,archived INTEGER)');
      db.execute("INSERT INTO person VALUES ('owner',0)");
      final expectation = db.prepare(
        "INSERT INTO daily_expectation(id,plan,person,date,snapshot,revision,occurs_at) VALUES (?,'plan','owner','2026-10-19','{}',1,?)",
      );
      final action = db.prepare(
        "INSERT INTO daily_action VALUES (?,?,'owner','skip',NULL,1,0,1,0)",
      );
      try {
        db.execute('BEGIN');
        for (var i = 0; i < 5000; i++) {
          final bucket = 'bucket-${(4999 - i).toString().padLeft(4, '0')}';
          expectation.execute([bucket, i < 4900 ? 200 : 100]);
          action.execute(['action-${i.toString().padLeft(4, '0')}', bucket]);
        }
        db.execute('COMMIT');
      } finally {
        expectation.close();
        action.close();
      }
      for (final everyone in [false, true]) {
        final branch = _legacySkipBranch(
          everyone: everyone,
          predicate: everyone
              ? 'e.person IN (SELECT id FROM person WHERE archived=0)'
              : "e.person='owner'",
        );
        final oracle = db.select(
          'SELECT * FROM ($branch) ORDER BY at DESC,key ASC',
        );
        final expected = oracle.map((row) => row['key']).toList();
        final seen = <Object?>[];
        int? at;
        String? key;
        while (seen.length < expected.length) {
          final page = db.select(
            'SELECT * FROM ($branch) ${at == null ? '' : 'WHERE at<? OR (at=? AND key>?)'} ORDER BY at DESC,id LIMIT 51',
            at == null ? [] : [at, at, key],
          );
          expect(page, isNotEmpty);
          final visible = page.take(50).toList();
          seen.addAll(visible.map((row) => row['key']));
          at = visible.last['at'] as int;
          key = visible.last['key'] as String;
        }
        expect(seen, orderedEquals(expected));
        expect(seen.toSet(), hasLength(5000));
        expect(
          _planText(_plan(db, _outer(branch))),
          contains('TEMP B-TREE FOR LAST TERM OF ORDER BY'),
          reason: 'timestamp order alone does not supply action-ID tie order',
        );
      }
      final prematurelyLimited = db.select('''
SELECT key FROM (
  SELECT e.occurs_at AS at,d.id,'s:'||d.id AS key,e.id AS expectation_id
  FROM daily_expectation e INDEXED BY history_expectation_time
  CROSS JOIN daily_action d ON d.bucket=e.id AND d.person=e.person
  WHERE e.person='owner' AND d.kind='skip' AND d.undone=0
  ORDER BY at DESC,expectation_id ASC LIMIT 51
) ORDER BY at DESC,id LIMIT 50
''');
      final exactFirst = db
          .select(
            _outer(
              _legacySkipBranch(everyone: false, predicate: "e.person='owner'"),
            ),
          )
          .take(50)
          .map((row) => row['key'])
          .toList();
      expect(
        prematurelyLimited.map((row) => row['key']).toList(),
        isNot(orderedEquals(exactFirst)),
        reason: 'limiting expectations before sorting action ties loses rows',
      );

      // Exercise the real v18 SQL against the same populated v17 tables.
      for (final sql in historySchemaV18) {
        db.execute(sql);
      }
      for (final everyone in [false, true]) {
        final index = everyone
            ? 'history_skip_global_time'
            : 'history_skip_person_time';
        final owner = everyone
            ? 'd.person IN (SELECT id FROM person WHERE archived=0)'
            : "d.person='owner'";
        final proposed =
            '''
SELECT d.occurs_at AS at,d.id,'s:'||d.id AS key
FROM daily_action d INDEXED BY $index
CROSS JOIN daily_expectation e ON e.id=d.bucket AND e.person=d.person
WHERE d.kind='skip' AND d.undone=0 AND $owner
ORDER BY d.occurs_at DESC,d.id LIMIT 51
''';
        expect(_hasTempBTree(_plan(db, proposed)), isFalse);
        expect(
          db.select(proposed).take(50).map((row) => row['key']),
          orderedEquals(exactFirst),
        );
      }
    } finally {
      db.close();
    }
  });

  late _ScaleFixture fixture;
  var fixtureBuilt = false;

  group('History 10-adult/100k skewed fixture', () {
    setUpAll(() async {
      try {
        fixture = await _buildFixture();
      } catch (error, stack) {
        stderr.writeln('HISTORY_SCALE_BUILD_ERROR $error\n$stack');
        rethrow;
      }
      fixtureBuilt = true;
      stdout.writeln(
        'HISTORY_SCALE_FIXTURE ${jsonEncode(fixture.measurements)}',
      );
    });

    tearDownAll(() async {
      if (!fixtureBuilt) return;
      stdout.writeln(
        'HISTORY_SCALE_MEASUREMENTS ${jsonEncode(fixture.measurements)}',
      );
      await fixture.close();
    });

    test('everyone first page is bounded, active-only and owned', () async {
      final store = fixture.store;
      expect(fixture.measurements['administrations'], _totalAdministrations);
      expect(fixture.archived.length, 7);
      expect(fixture.active.length, 3);
      final query = TimelineQuery(
        filter: TimelineFilter(),
        displayZone: _zone,
        limit: 50,
      );
      final watch = Stopwatch()..start();
      final page = await store.timeline(query);
      watch.stop();
      fixture.measurements['everyone_first_page_us'] =
          watch.elapsedMicroseconds;
      expect(page.entries.length, 50);
      expect(page.hasMore, isTrue);
      expect(page.entries, isNotEmpty);
      final activeIds = fixture.active.map((profile) => profile.id).toSet();
      final archivedIds = fixture.archived.map((profile) => profile.id).toSet();
      var combinedSeen = 0;
      var skipSeen = 0;
      var planContextSeen = 0;
      for (final entry in page.entries) {
        expect(activeIds, contains(entry.personId));
        expect(archivedIds, isNot(contains(entry.personId)));
        await _expectEntryOwnership(entry);
        if (entry is CombinedTimelineEntry) combinedSeen++;
        if (entry is SkippedTimelineEntry) skipSeen++;
        if (entry is RecordTimelineEntry && entry.planContext != null) {
          planContextSeen++;
        }
      }
      expect(combinedSeen, greaterThan(0));
      expect(skipSeen, greaterThan(0));
      expect(planContextSeen, greaterThan(0));
      expect(_childReadShape(page), lessThanOrEqualTo(3));
      final db = _openRaw(fixture.path);
      try {
        final expected = db
            .select('${_unionParentsSql(everyone: true)} LIMIT 50')
            .map((row) => row['key'] as String)
            .toList();
        expect(
          page.entries.map(_sortKey).toList(),
          orderedEquals(expected),
          reason: 'Everyone first page must match the merged parent order',
        );
      } finally {
        db.close();
      }
      fixture.measurements['everyone_first_page_entries'] = page.entries.length;
      fixture.measurements['everyone_first_page_combined'] = combinedSeen;
      fixture.measurements['everyone_first_page_skipped'] = skipSeen;
      fixture.measurements['everyone_first_page_plan_contexts'] =
          planContextSeen;
      fixture.measurements['everyone_first_page_child_reads'] = _childReadShape(
        page,
      );
    });

    test('person and archived scopes keep fixed ownership and current revisions', () async {
      final store = fixture.store;
      final me = fixture.active.first;
      final archived = fixture.archived.last;

      final mePage = await store.timeline(
        TimelineQuery(
          filter: TimelineFilter(scope: FeedScope.person(me.id)),
          displayZone: _zone,
          limit: 50,
        ),
      );
      expect(mePage.entries, isNotEmpty);
      for (final entry in mePage.entries) {
        expect(entry.personId, me.id);
        await _expectEntryOwnership(entry);
      }

      // Everyone excludes a low-volume archived adult; that adult's own feed
      // still returns records read-only under the fixed owner.
      final everyoneKeys = <String>{};
      var everyoneQuery = TimelineQuery(
        filter: TimelineFilter(),
        displayZone: _zone,
        limit: 50,
      );
      for (var i = 0; i < 4; i++) {
        final page = await store.timeline(everyoneQuery);
        for (final entry in page.entries) {
          everyoneKeys.add(_sortKey(entry));
          expect(entry.personId, isNot(archived.id));
        }
        if (!page.hasMore) break;
        everyoneQuery = everyoneQuery.withCursor(page.next!);
      }
      final archivedPage = await store.timeline(
        TimelineQuery(
          filter: TimelineFilter(scope: FeedScope.person(archived.id)),
          displayZone: _zone,
          limit: 50,
        ),
      );
      expect(archivedPage.entries, isNotEmpty);
      for (final entry in archivedPage.entries) {
        expect(entry.personId, archived.id);
        await _expectEntryOwnership(entry);
        expect(everyoneKeys, isNot(contains(_sortKey(entry))));
      }

      // Batch verification of current revisions and ownership.
      final recordIds = <String>{};
      for (final entry in [...mePage.entries, ...archivedPage.entries]) {
        switch (entry) {
          case RecordTimelineEntry(:final record):
            recordIds.add(record.id);
          case CombinedTimelineEntry(:final components):
            recordIds.addAll(
              components.map((component) => component.record.id),
            );
          case SkippedTimelineEntry():
            break;
        }
      }
      final db = _openRaw(fixture.path);
      try {
        final ids = recordIds.toList();
        for (var offset = 0; offset < ids.length; offset += 500) {
          final chunk = ids.skip(offset).take(500).toList();
          final marks = List.filled(chunk.length, '?').join(',');
          final rows = db.select(
            'SELECT a.id,a.person,a.revision,r.voided FROM administration a JOIN revision r ON r.record=a.id AND r.person=a.person AND r.revision=a.revision WHERE a.id IN ($marks)',
            chunk,
          );
          expect(rows.length, chunk.length);
          for (final row in rows) {
            final owner = row['person'] as String;
            expect(
              owner == me.id || owner == archived.id,
              isTrue,
              reason: 'current row owner mismatch',
            );
          }
        }
        expect(
          db.select('PRAGMA foreign_key_check'),
          isEmpty,
          reason: 'fixture must preserve database integrity',
        );
        final missing =
            db
                    .select(
                      'SELECT COUNT(*) AS count FROM administration a LEFT JOIN revision r ON r.record=a.id AND r.person=a.person AND r.revision=a.revision WHERE r.record IS NULL',
                    )
                    .single['count']
                as int;
        expect(missing, 0);
      } finally {
        db.close();
      }
      fixture.measurements['archived_person_first_page_entries'] =
          archivedPage.entries.length;
    });

    test('keyset pages are complete, ordered and duplicate-free', () async {
      final store = fixture.store;
      final archived = fixture.archived.last;
      final query = TimelineQuery(
        filter: TimelineFilter(scope: FeedScope.person(archived.id)),
        displayZone: _zone,
        limit: 25,
      );
      final watch = Stopwatch()..start();
      final entries = await _readAll(store, query);
      watch.stop();
      fixture.measurements['archived_person_all_pages_us'] =
          watch.elapsedMicroseconds;
      fixture.measurements['archived_person_entries'] = entries.length;
      expect(entries, isNotEmpty);
      final keys = entries.map(_sortKey).toList();
      expect(keys.toSet().length, keys.length, reason: 'duplicate identity');
      for (var i = 1; i < entries.length; i++) {
        final previous = entries[i - 1];
        final current = entries[i];
        final byTime = current.occurredAt.compareTo(previous.occurredAt);
        expect(byTime, lessThanOrEqualTo(0));
        if (byTime == 0) {
          expect(
            current.id.sortKey.compareTo(previous.id.sortKey),
            greaterThan(0),
            reason: 'equal instants must order by prefixed identity',
          );
        }
      }

      final db = _openRaw(fixture.path);
      try {
        final expected = db
            .select(_unionParentsSql(everyone: false), [archived.id])
            .map((row) => row['key'] as String)
            .toList();
        expect(keys, orderedEquals(expected));
        expect(entries.length, expected.length);
      } finally {
        db.close();
      }

      // A middle cursor must return the next older slice exactly once.
      final first = await store.timeline(query);
      expect(first.entries.length, 25);
      final second = await store.timeline(query.withCursor(first.next!));
      expect(second.entries, isNotEmpty);
      expect(
        second.entries.first.occurredAt.isAfter(first.entries.last.occurredAt),
        isFalse,
      );
      expect(
        second.entries
            .map(_sortKey)
            .toSet()
            .intersection(first.entries.map(_sortKey).toSet()),
        isEmpty,
      );
      fixture.measurements['archived_person_pages'] = (entries.length / 25)
          .ceil();
    });

    test(
      'combined groups stay whole and parent time follows components',
      () async {
        final store = fixture.store;
        final corrected = await store.historyEntry(
          TimelineEntryId.combined(fixture.correctedGroup.actionId),
          personId: fixture.correctedGroup.personId,
        );
        expect(corrected, isA<CombinedTimelineEntry>());
        final correctedEntry = corrected! as CombinedTimelineEntry;
        expect(correctedEntry.occurredAt, DateTime.utc(2026, 10, 20, 10));
        expect(correctedEntry.components.length, 2);
        for (final component in correctedEntry.components) {
          expect(component.record.actualAt, correctedEntry.occurredAt);
          expect(component.record.revision, 2);
          expect(component.record.isVoided, isFalse);
        }

        final voided = await store.historyEntry(
          TimelineEntryId.combined(fixture.voidedGroup.actionId),
          personId: fixture.voidedGroup.personId,
        );
        expect(voided, isA<CombinedTimelineEntry>());
        final voidedEntry = voided! as CombinedTimelineEntry;
        expect(voidedEntry.status, TimelineEntryStatus.voided);
        expect(voidedEntry.components.length, 2);
        for (final component in voidedEntry.components) {
          expect(component.record.isVoided, isTrue);
          expect(component.record.actualAt, voidedEntry.occurredAt);
        }

        // Page the corrected group's owner and ensure the parent appears once.
        final owner = fixture.correctedGroup.personId;
        final entries = await _readAll(
          store,
          TimelineQuery(
            filter: TimelineFilter(
              scope: FeedScope.person(owner),
              fromInstant: DateTime.utc(2026, 10, 20, 8),
              beforeInstant: DateTime.utc(2026, 10, 20, 11),
            ),
            displayZone: _zone,
            limit: 50,
          ),
        );
        final combined = entries.whereType<CombinedTimelineEntry>().toList();
        final ids = combined.map((entry) => entry.actionId).toList();
        expect(ids.toSet().length, ids.length);
        for (final entry in combined) {
          await _expectEntryOwnership(entry);
        }
        expect(
          combined.any(
            (entry) => entry.actionId == fixture.correctedGroup.actionId,
          ),
          isTrue,
        );
        fixture.measurements['corrected_group_components'] =
            correctedEntry.components.length;
        fixture.measurements['voided_group_components'] =
            voidedEntry.components.length;
      },
    );

    test('skips, taken actions and events keep plan/event context', () async {
      final store = fixture.store;
      final me = fixture.active.first;
      final activeOne = fixture.active[1];

      // The late skip is a timed skip; the repeated-clock skip is date-only.
      final meEntries = await _readAll(
        store,
        TimelineQuery(
          filter: TimelineFilter(
            scope: FeedScope.person(me.id),
            fromInstant: DateTime.utc(2026, 10, 19, 22, 57),
            beforeInstant: DateTime.utc(2026, 10, 20),
          ),
          displayZone: _zone,
          limit: 50,
        ),
      );
      final timed = meEntries.whereType<SkippedTimelineEntry>().where(
        (entry) => entry.action.id == fixture.lateSkip.id,
      );
      expect(timed, isNotEmpty);
      expect(timed.first.dateOnly, isFalse);
      expect(timed.first.planZone, _zone);

      final repeatEntries = await _readAll(
        store,
        TimelineQuery(
          filter: TimelineFilter(
            scope: FeedScope.person(activeOne.id),
            status: TimelineStatus.skipped,
          ),
          displayZone: _zone,
          limit: 50,
        ),
      );
      final repeated = repeatEntries.whereType<SkippedTimelineEntry>().where(
        (entry) => entry.action.id == fixture.repeatSkip.id,
      );
      expect(repeated, isNotEmpty);
      expect(repeated.first.dateOnly, isTrue);
      expect(repeated.first.timeNeedsReview, isTrue);

      // A taken daily action is one RecordTimelineEntry with plan context.
      final takenAdult = fixture.active[2];
      final takenWindow = await _readAll(
        store,
        TimelineQuery(
          filter: TimelineFilter(
            scope: FeedScope.person(takenAdult.id),
            fromInstant: DateTime.utc(2026, 10, 19, 23, 54),
            beforeInstant: DateTime.utc(2026, 10, 19, 23, 57),
          ),
          displayZone: _zone,
          limit: 25,
        ),
      );
      final planContexts = takenWindow
          .whereType<RecordTimelineEntry>()
          .where((entry) => entry.planContext != null)
          .toList();
      expect(planContexts, isNotEmpty);
      final takenIds = planContexts.map((entry) => entry.record.id).toSet();
      expect(
        takenWindow.whereType<SkippedTimelineEntry>().where(
          (entry) => takenIds.contains(entry.action.recordId),
        ),
        isEmpty,
      );

      // The undone skip is absent from the timeline but retains an audit row.
      final undone = await store.dailyActionSource(
        fixture.undoneSkip.id,
        personId: fixture.active[2].id,
      );
      expect(undone, isNotNull);
      expect(undone!.action.isUndone, isTrue);
      expect((await store.dailyActionAudit(fixture.undoneSkip.id)).length, 1);
      final allForUndone = await _readAll(
        store,
        TimelineQuery(
          filter: TimelineFilter(
            scope: FeedScope.person(fixture.active[2].id),
            status: TimelineStatus.skipped,
          ),
          displayZone: _zone,
          limit: 50,
        ),
      );
      expect(
        allForUndone.any(
          (entry) =>
              entry is SkippedTimelineEntry &&
              entry.action.id == fixture.undoneSkip.id,
        ),
        isFalse,
      );

      // Overlapping event memberships deduplicate actuals rather than
      // duplicating a record once per event.
      final eventIds = [fixture.events[0].id, fixture.events[1].id];
      final eventEntries = await _readAll(
        store,
        TimelineQuery(
          filter: TimelineFilter(
            scope: FeedScope.person(me.id),
            fromInstant: DateTime.utc(2026, 9, 1),
            beforeInstant: DateTime.utc(2026, 10, 5),
            eventIds: eventIds,
          ),
          displayZone: _zone,
          limit: 50,
        ),
      );
      final eventRecordIds = eventEntries
          .whereType<RecordTimelineEntry>()
          .map((entry) => entry.record.id)
          .toList();
      expect(eventRecordIds.toSet().length, eventRecordIds.length);
      expect(eventEntries, isNotEmpty);
      final options = await store.historyEventOptions(
        scope: FeedScope.person(me.id),
      );
      expect(options.options.map((option) => option.id), containsAll(eventIds));
      fixture.measurements['event_filter_entries'] = eventEntries.length;
      fixture.measurements['event_filter_record_entries'] =
          eventRecordIds.length;
    });

    test('saved type changes and voids retain current history', () async {
      final store = fixture.store;
      final activeOne = fixture.active[1];
      final item = fixture.adults[1].primary;

      final db = _openRaw(fixture.path);
      final int oldMedicine;
      final int newRenamedType;
      final String expectationType;
      try {
        oldMedicine =
            db.select(
                  'SELECT COUNT(*) AS count FROM administration a JOIN revision r ON r.record=a.id AND r.person=a.person AND r.revision=a.revision WHERE a.person=? AND a.item=? AND r.type=?',
                  [activeOne.id, item.id, 'medicine'],
                ).single['count']
                as int;
        newRenamedType =
            db.select(
                  'SELECT COUNT(*) AS count FROM administration a JOIN revision r ON r.record=a.id AND r.person=a.person AND r.revision=a.revision WHERE a.person=? AND a.item=? AND r.type=?',
                  [activeOne.id, item.id, 'medicine-renamed'],
                ).single['count']
                as int;
        expectationType =
            db.select(
                  "SELECT item_type FROM daily_expectation WHERE person=? AND item_id=? AND item_type='medicine' LIMIT 1",
                  [activeOne.id, item.id],
                ).single['item_type']
                as String;
      } finally {
        db.close();
      }
      expect(oldMedicine, greaterThan(1000));
      expect(newRenamedType, 1);
      expect(expectationType, 'medicine');

      final typeWatch = Stopwatch()..start();
      final oldPage = await store.timeline(
        TimelineQuery(
          filter: TimelineFilter(
            scope: FeedScope.person(activeOne.id),
            itemId: item.id,
            typeIds: ['medicine'],
          ),
          displayZone: _zone,
          limit: 50,
        ),
      );
      typeWatch.stop();
      fixture.measurements['type_filtered_first_page_us'] =
          typeWatch.elapsedMicroseconds;
      expect(oldPage.entries, isNotEmpty);
      for (final entry in oldPage.entries) {
        switch (entry) {
          case RecordTimelineEntry(:final record):
            expect(record.type, 'medicine');
          case CombinedTimelineEntry(:final components):
            final matched = components.where((c) => c.matched).toList();
            expect(matched, isNotEmpty);
            expect(matched.every((c) => c.record.type == 'medicine'), isTrue);
            expect(
              components.length,
              2,
              reason: 'the whole combined group stays visible',
            );
          case SkippedTimelineEntry():
            break;
        }
      }
      final newPage = await store.timeline(
        TimelineQuery(
          filter: TimelineFilter(
            scope: FeedScope.person(activeOne.id),
            itemId: item.id,
            typeIds: ['medicine-renamed'],
          ),
          displayZone: _zone,
          limit: 50,
        ),
      );
      expect(newPage.entries.length, 1);
      expect(newPage.entries.single, isA<RecordTimelineEntry>());
      expect(
        (newPage.entries.single as RecordTimelineEntry).record.id,
        fixture.typeChangedRecord.id,
      );
      expect(
        (await store.timeline(
              TimelineQuery(
                filter: TimelineFilter(
                  scope: FeedScope.person(activeOne.id),
                  status: TimelineStatus.skipped,
                  typeIds: ['medicine'],
                ),
                displayZone: _zone,
              ),
            )).entries
            .whereType<SkippedTimelineEntry>()
            .map((entry) => entry.action.id),
        contains(fixture.savedTypeSkip.id),
      );

      final voided = await store.timeline(
        TimelineQuery(
          filter: TimelineFilter(
            scope: FeedScope.person(meId),
            status: TimelineStatus.voided,
          ),
          displayZone: _zone,
          limit: 50,
        ),
      );
      expect(voided.entries, isNotEmpty);
      for (final entry in voided.entries) {
        expect(entry.status, TimelineEntryStatus.voided);
        if (entry is RecordTimelineEntry) {
          expect(entry.record.isVoided, isTrue);
        }
        if (entry is CombinedTimelineEntry) {
          expect(
            entry.components.every((component) => component.record.isVoided),
            isTrue,
          );
        }
      }
      final recorded = await store.timeline(
        TimelineQuery(
          filter: TimelineFilter(
            scope: FeedScope.person(meId),
            status: TimelineStatus.recorded,
          ),
          displayZone: _zone,
          limit: 50,
        ),
      );
      expect(recorded.entries, isNotEmpty);
      for (final entry in recorded.entries) {
        expect(entry.status, isNot(TimelineEntryStatus.voided));
        expect(entry, isNot(isA<SkippedTimelineEntry>()));
      }

      final voidedHistory = await store.historyEntry(
        TimelineEntryId.record(fixture.voidedRecord.id),
        personId: meId,
      );
      expect(voidedHistory, isA<RecordTimelineEntry>());
      final voidedHistoryRecord =
          (voidedHistory! as RecordTimelineEntry).record;
      expect(voidedHistoryRecord.revision, fixture.voidedRecord.revision);
      expect(voidedHistoryRecord.isVoided, isTrue);
      final correctedEntry = await store.historyEntry(
        TimelineEntryId.record(fixture.correctedRecord.id),
        personId: meId,
      );
      expect(correctedEntry, isA<RecordTimelineEntry>());
      final correctedRecord = (correctedEntry! as RecordTimelineEntry).record;
      expect(correctedRecord.revision, fixture.correctedRecord.revision);
      expect(correctedRecord.actualAt, DateTime.utc(2026, 10, 20, 9));
      expect(correctedRecord.enteredAmount, '2.000');
      fixture.measurements['old_medicine_records'] = oldMedicine;
      fixture.measurements['new_renamed_type_records'] = newRenamedType;
    });

    test('filtered first pages record host-only query time', () async {
      final store = fixture.store;
      final me = fixture.active.first;
      final item = fixture.adults.first.primary;
      Future<void> measure(String name, TimelineQuery query) async {
        final watch = Stopwatch()..start();
        final page = await store.timeline(query);
        watch.stop();
        fixture.measurements['${name}_us'] = watch.elapsedMicroseconds;
        expect(page.entries.length, lessThanOrEqualTo(query.limit));
      }

      await measure(
        'person_first_page',
        TimelineQuery(
          filter: TimelineFilter(scope: FeedScope.person(me.id)),
          displayZone: _zone,
          limit: 50,
        ),
      );
      await measure(
        'date_first_page',
        TimelineQuery(
          filter: TimelineFilter(
            scope: FeedScope.person(me.id),
            fromInstant: _recentDay,
            beforeInstant: _recentDay.add(const Duration(days: 1)),
          ),
          displayZone: _zone,
          limit: 50,
        ),
      );
      await measure(
        'item_first_page',
        TimelineQuery(
          filter: TimelineFilter(
            scope: FeedScope.person(me.id),
            itemId: item.id,
          ),
          displayZone: _zone,
          limit: 50,
        ),
      );
      await measure(
        'voided_first_page',
        TimelineQuery(
          filter: TimelineFilter(
            scope: FeedScope.person(me.id),
            status: TimelineStatus.voided,
          ),
          displayZone: _zone,
          limit: 50,
        ),
      );
      await measure(
        'recorded_first_page',
        TimelineQuery(
          filter: TimelineFilter(
            scope: FeedScope.person(me.id),
            status: TimelineStatus.recorded,
          ),
          displayZone: _zone,
          limit: 50,
        ),
      );
      await measure(
        'skipped_first_page',
        TimelineQuery(
          filter: TimelineFilter(
            scope: FeedScope.person(me.id),
            status: TimelineStatus.skipped,
          ),
          displayZone: _zone,
          limit: 50,
        ),
      );
      await measure(
        'event_first_page',
        TimelineQuery(
          filter: TimelineFilter(
            scope: FeedScope.person(me.id),
            eventIds: [fixture.events[0].id, fixture.events[1].id],
          ),
          displayZone: _zone,
          limit: 50,
        ),
      );
    });

    test('actual query plans stay indexed and bounded', () async {
      final activeOne = fixture.active[1];
      final me = fixture.active.first;
      final db = _openRaw(fixture.path);
      final plans = <String, List<String>>{};
      try {
        plans['record_person'] = _plan(
          db,
          _outer(
            _recordBranch(predicate: _personRecordPredicate(), status: ''),
          ),
          [me.id],
        );
        plans['record_everyone'] = _plan(
          db,
          _outer(
            _recordBranch(
              predicate: _everyoneRecordPredicate(),
              status: '',
              feed: 'administration a INDEXED BY administration_everyone',
            ),
          ),
        );
        plans['record_date_person'] = _plan(
          db,
          _outer(
            _recordBranch(
              predicate:
                  '${_personRecordPredicate()} AND a.actual>=? AND a.actual<?',
              status: '',
            ),
          ),
          [me.id, _recentDayMicros, _recentDayMicros + _dayMicros],
        );
        plans['record_item_person'] = _plan(
          db,
          _outer(
            _recordBranch(
              predicate: '${_personRecordPredicate()} AND a.item=?',
              status: '',
            ),
          ),
          [me.id, fixture.adults.first.primary.id],
        );
        plans['record_type_person'] = _plan(
          db,
          _outer(
            _recordBranch(
              predicate: '${_personRecordPredicate()} AND r.type IN (?)',
              status: '',
              feed: 'administration a INDEXED BY administration_feed',
            ),
          ),
          [activeOne.id, 'medicine'],
        );
        plans['record_voided_person'] = _plan(
          db,
          _outer(
            _recordBranch(
              predicate: _personRecordPredicate(),
              status: ' AND r.voided=1',
            ),
          ),
          [me.id],
        );
        plans['combined_person'] = _plan(
          db,
          _outer(
            _combinedBranch(
              scope: 'g.person=?',
              predicate: 'a.person=?',
              status: '',
              feed: 'combined_action g INDEXED BY history_combined_person',
            ),
          ),
          [me.id, me.id],
        );
        plans['combined_everyone'] = _plan(
          db,
          _outer(
            _combinedBranch(
              scope: 'g.person IN (SELECT id FROM person WHERE archived=0)',
              predicate: 'a.person IN (SELECT id FROM person WHERE archived=0)',
              status: '',
              feed: 'combined_action g INDEXED BY history_combined_time',
            ),
          ),
        );
        plans['combined_date_person'] = _plan(
          db,
          _outer(
            _combinedBranch(
              scope: 'g.person=?',
              predicate: 'a.person=? AND a.actual>=? AND a.actual<?',
              status: '',
              feed: 'combined_action g INDEXED BY history_combined_person',
            ),
          ),
          [me.id, me.id, _recentDayMicros, _recentDayMicros + _dayMicros],
        );
        plans['skip_person'] = _plan(
          db,
          _outer(_skipBranch(everyone: false, predicate: 'e.person=?')),
          [me.id, me.id],
        );
        plans['skip_everyone'] = _plan(
          db,
          _outer(
            _skipBranch(
              everyone: true,
              predicate: 'e.person IN (SELECT id FROM person WHERE archived=0)',
            ),
          ),
        );
        for (final everyone in [false, true]) {
          final branch = _skipBranch(
            everyone: everyone,
            predicate: everyone
                ? 'e.person IN (SELECT id FROM person WHERE archived=0)'
                : 'e.person=?',
          );
          plans['skip_${everyone ? 'everyone' : 'person'}_cursor'] = _plan(
            db,
            'SELECT * FROM ($branch) WHERE at<=? AND (at<? OR (at=? AND key>?)) ORDER BY at DESC,id LIMIT 51',
            [
              if (!everyone) ...[me.id, me.id],
              _recentDayMicros,
              _recentDayMicros,
              _recentDayMicros,
              'r:cross-kind-cursor',
            ],
          );
        }
        plans['calendar_day_person'] = _plan(
          db,
          'SELECT status,COUNT(*) AS count FROM (${_recordBranch(predicate: '${_personRecordPredicate()} AND a.actual>=? AND a.actual<?', status: '')}) GROUP BY status',
          [me.id, _recentDayMicros, _recentDayMicros + _dayMicros],
        );
        plans['calendar_cells_person'] = _plan(
          db,
          'WITH cells(day,lo,hi,lower_day,upper_day) AS (VALUES (?,?,?,?,?)) SELECT c.day,COUNT(*) AS count FROM cells c JOIN administration a INDEXED BY administration_feed ON a.actual>=c.lo AND a.actual<c.hi JOIN revision r ON r.record=a.id AND r.person=a.person AND r.revision=a.revision WHERE a.person=? AND NOT EXISTS(SELECT 1 FROM combined_member cm WHERE cm.record=a.id) GROUP BY c.day',
          [
            '2026-10-19',
            _recentDayMicros,
            _recentDayMicros + _dayMicros,
            '2026-10-19',
            '2026-10-20',
            me.id,
          ],
        );
        final meGroups = [
          fixture.groups[0].actionId,
          fixture.groups[10].actionId,
        ];
        const combinedMatchesSql =
            'SELECT c.action,c.position,a.id FROM combined_member c INDEXED BY sqlite_autoindex_combined_member_2 JOIN administration a ON a.id=c.record AND a.person=c.person JOIN revision r ON r.record=a.id AND r.person=a.person AND r.revision=a.revision LEFT JOIN revision_quantity q ON q.record=r.record AND q.revision=r.revision WHERE c.action IN (?,?) AND a.person=?';
        plans['combined_matches_person'] = _plan(db, combinedMatchesSql, [
          ...meGroups,
          me.id,
        ]);
        final matchWatch = Stopwatch()..start();
        final matchRows = db.select(combinedMatchesSql, [
          ...meGroups,
          me.id,
        ]).length;
        matchWatch.stop();
        fixture.measurements['combined_match_read_us'] =
            matchWatch.elapsedMicroseconds;
        fixture.measurements['combined_match_rows'] = matchRows;

        final recordBranchSql = _outer(
          _recordBranch(predicate: 'a.person=?', status: ''),
        );
        final recordWatch = Stopwatch()..start();
        final recordRows = db.select(recordBranchSql, [me.id]).length;
        recordWatch.stop();
        fixture.measurements['record_branch_person_us'] =
            recordWatch.elapsedMicroseconds;
        fixture.measurements['record_branch_person_rows'] = recordRows;

        final combinedBranchSql = _outer(
          _combinedBranch(
            scope: 'g.person=?',
            predicate: 'a.person=?',
            status: '',
            feed: 'combined_action g INDEXED BY history_combined_person',
          ),
        );
        final combinedWatch = Stopwatch()..start();
        final combinedRows = db.select(combinedBranchSql, [
          me.id,
          me.id,
        ]).length;
        combinedWatch.stop();
        fixture.measurements['combined_branch_person_us'] =
            combinedWatch.elapsedMicroseconds;
        fixture.measurements['combined_branch_person_rows'] = combinedRows;

        final typeBranchSql = _outer(
          _recordBranch(
            predicate: 'a.person=? AND r.type IN (?)',
            status: '',
            feed: 'administration a INDEXED BY administration_feed',
          ),
        );
        final typeWatch = Stopwatch()..start();
        final typeRows = db.select(typeBranchSql, [
          activeOne.id,
          'medicine',
        ]).length;
        typeWatch.stop();
        fixture.measurements['record_branch_type_person_us'] =
            typeWatch.elapsedMicroseconds;
        fixture.measurements['record_branch_type_person_rows'] = typeRows;
        for (final entry in plans.entries) {
          stdout.writeln(
            'HISTORY_SCALE_PLAN ${entry.key} ${_planText(entry.value)}',
          );
        }
        fixture.measurements['query_plans'] = plans;
        expect(
          _planText(plans['record_person']!),
          contains('administration_feed'),
        );
        expect(
          _planText(plans['record_everyone']!),
          contains('administration_everyone'),
        );
        expect(
          _hasTempBTree(plans['record_everyone']!),
          isFalse,
          reason:
              'the Everyone feed must read the ordered global index without '
              'sorting: ${_planText(plans['record_everyone']!)}',
        );
        expect(
          _planText(plans['record_date_person']!),
          contains('administration_feed'),
        );
        expect(
          _planText(plans['record_item_person']!),
          contains('administration_item_feed'),
        );
        expect(
          _planText(plans['record_type_person']!),
          contains('administration_feed'),
        );
        expect(
          _planText(plans['record_type_person']!),
          isNot(startsWith('SEARCH r USING INDEX history_recorded_type')),
          reason: 'a person type page must not drive from every adult type row',
        );
        expect(
          _hasTempBTree(plans['record_type_person']!),
          isFalse,
          reason:
              'the person type feed supplies actual order: '
              '${_planText(plans['record_type_person']!)}',
        );
        expect(
          _planText(plans['record_voided_person']!),
          contains('administration_feed'),
        );
        expect(
          _planText(plans['combined_person']!),
          contains('history_combined_person'),
        );
        expect(
          _planText(plans['combined_person']!),
          isNot(contains('administration_feed')),
          reason:
              'the combined branch must start from the group identity, not '
              "the person's whole administration history: "
              '${_planText(plans['combined_person']!)}',
        );
        fixture.measurements['combined_person_uses_person_index'] = _planText(
          plans['combined_person']!,
        ).contains('history_combined_person');
        expect(
          _planText(plans['combined_everyone']!),
          contains('history_combined_time'),
        );
        expect(
          _planText(plans['combined_date_person']!),
          contains('history_combined_person'),
        );
        expect(
          _planText(plans['combined_date_person']!),
          isNot(contains('administration_feed')),
          reason:
              'a date-filtered combined page must still start from the group '
              'identity: ${_planText(plans['combined_date_person']!)}',
        );
        expect(
          _planText(plans['skip_person']!),
          contains('history_skip_person_time'),
        );
        expect(
          _planText(plans['skip_everyone']!),
          contains('history_skip_global_time'),
        );
        expect(
          _planText(plans['calendar_cells_person']!),
          contains('administration_feed'),
          reason:
              'one calendar cell must use the ordered feed range: '
              '${_planText(plans['calendar_cells_person']!)}',
        );
        final matchPlan = _planText(plans['combined_matches_person']!);
        expect(matchPlan, contains('combined_member'));
        expect(
          matchPlan,
          isNot(contains('administration_feed')),
          reason:
              'page membership reads must be keyed by the page group IDs: '
              '$matchPlan',
        );
        expect(
          matchPlan.indexOf('combined_member'),
          lessThan(matchPlan.indexOf('administration')),
        );
        for (final name in [
          'record_person',
          'record_everyone',
          'record_date_person',
          'record_item_person',
          'record_type_person',
          'record_voided_person',
          'combined_person',
          'combined_everyone',
          'combined_date_person',
          'skip_person',
          'skip_everyone',
          'calendar_day_person',
        ]) {
          expect(
            _hasFullTableScan(plans[name]!),
            isFalse,
            reason:
                '$name plan contains a full table scan: '
                '${_planText(plans[name]!)}',
          );
        }
        // The readiness contract permits a bounded merge but not an unbounded
        // sort of full-history rows. Record the actual temp-b-tree signal.
        fixture.measurements['query_plan_temp_b_tree'] = {
          for (final entry in plans.entries)
            entry.key: _hasTempBTree(entry.value),
        };
        expect(_hasTempBTree(plans['skip_person']!), isFalse);
        expect(_hasTempBTree(plans['skip_everyone']!), isFalse);
        for (final scope in ['person', 'everyone']) {
          final plan = plans['skip_${scope}_cursor']!;
          expect(_hasTempBTree(plan), isFalse);
          expect(_planText(plan), contains('occurs_at<?'));
          expect(
            _planText(plan),
            contains(
              'history_skip_${scope == 'person' ? 'person' : 'global'}_time',
            ),
          );
        }
        // Schema18 supplies the complete skip occurrence/action-ID order.
        fixture.measurements['query_plan_contract'] = <String, Object?>{
          'record_everyone_uses_global_feed': _planText(
            plans['record_everyone']!,
          ).contains('administration_everyone'),
          'record_everyone_ordered_without_temp_btree': !_hasTempBTree(
            plans['record_everyone']!,
          ),
          'record_type_person_uses_person_feed': _planText(
            plans['record_type_person']!,
          ).contains('administration_feed'),
          'record_type_person_ordered_without_temp_btree': !_hasTempBTree(
            plans['record_type_person']!,
          ),
          'combined_person_uses_person_index': _planText(
            plans['combined_person']!,
          ).contains('history_combined_person'),
          'combined_date_person_uses_person_index': _planText(
            plans['combined_date_person']!,
          ).contains('history_combined_person'),
          'skip_person_ordered_without_temp_btree': !_hasTempBTree(
            plans['skip_person']!,
          ),
          'combined_matches_drives_from_page_members':
              matchPlan.indexOf('combined_member') <
              matchPlan.indexOf('administration'),
        };
      } finally {
        db.close();
      }
    });

    test('calendar and batched child reads remain bounded', () async {
      final store = fixture.store;
      final archived = fixture.archived.first;
      final dates = [
        for (var i = 0; i < 42; i++) CivilDate(2026, 10, 1).addDays(i - 5),
      ];
      final watch = Stopwatch()..start();
      final calendar = await store.calendar(
        TimelineQuery(
          filter: TimelineFilter(scope: FeedScope.person(archived.id)),
          displayZone: _zone,
        ),
        dates: dates,
      );
      watch.stop();
      fixture.measurements['calendar_42_cells_us'] = watch.elapsedMicroseconds;
      expect(calendar.cells.length, 42);
      expect(calendar.overflow, isFalse);
      final skipDay = calendar.cells.firstWhere(
        (cell) => cell.date.toString() == '2026-10-18',
      );
      expect(skipDay.skipped, 1);
      expect(skipDay.total, greaterThanOrEqualTo(1));

      // The reader issues one parent read and a fixed set of batched child
      // reads. Store-internal statement counting is not exposed by
      // RecordStore; this counts the reader's bounded SQL shape for a page
      // containing every kind.
      final page = await store.timeline(
        TimelineQuery(filter: TimelineFilter(), displayZone: _zone, limit: 50),
      );
      final reads = _childReadShape(page);
      expect(reads, lessThanOrEqualTo(3));
      expect(
        reads,
        3,
        reason:
            'a page with records, combined groups and skips uses exactly '
            'three batched child reads',
      );
      expect(
        reads,
        lessThan(page.entries.length),
        reason: 'child reads must not be one per parent',
      );
      fixture.measurements['calendar_42_cells'] = calendar.cells.length;
      fixture.measurements['calendar_skip_day'] = skipDay.skipped;
      fixture.measurements['calendar_statements'] =
          1; // one bounded aggregate over all 42 cell ranges
      fixture.measurements['page_child_read_shape'] = reads;
      fixture.measurements['page_child_reads_at_most_three'] = reads <= 3;
      fixture.measurements['page_parent_entries'] = page.entries.length;
    });

    test('limit bounds and default page size are enforced', () async {
      final store = fixture.store;
      expect(
        () => TimelineQuery(
          filter: TimelineFilter(),
          displayZone: _zone,
          limit: 0,
        ),
        throwsA(isA<TimelineQueryException>()),
      );
      expect(
        () => TimelineQuery(
          filter: TimelineFilter(),
          displayZone: _zone,
          limit: 51,
        ),
        throwsA(isA<TimelineQueryException>()),
      );
      final defaultPage = await store.timeline(
        TimelineQuery(
          filter: TimelineFilter(scope: FeedScope.person(meId)),
          displayZone: _zone,
        ),
      );
      expect(defaultPage.entries.length, lessThanOrEqualTo(25));
      final maxPage = await store.timeline(
        TimelineQuery(filter: TimelineFilter(), displayZone: _zone, limit: 50),
      );
      expect(maxPage.entries.length, 50);
    });
  });
}

String _unionParentsSql({required bool everyone}) {
  final scope = everyone
      ? 'IN (SELECT id FROM person WHERE archived=0)'
      : '= ?1';
  return '''
SELECT at,key FROM (
  SELECT a.actual AS at,'r:'||a.id AS key
  FROM administration a JOIN revision r
    ON r.record=a.id AND r.person=a.person AND r.revision=a.revision
  WHERE a.person $scope
    AND NOT EXISTS(SELECT 1 FROM combined_member cm WHERE cm.record=a.id)
  UNION ALL
  SELECT g.actual,'c:'||g.id
  FROM combined_action g WHERE g.person $scope
  UNION ALL
  SELECT e.occurs_at,'s:'||d.id
  FROM daily_expectation e CROSS JOIN daily_action d
    ON d.bucket=e.id AND d.person=e.person
  WHERE d.kind='skip' AND d.undone=0 AND e.person $scope
)
ORDER BY at DESC,key ASC
''';
}
