import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/charts/charts.dart';
import 'package:true_grit_vital/domain/scheduling/iana_clock.dart';

void main() {
  late Directory directory;
  late RecordStore store;
  late SubstanceItem item;
  late String path;
  final key = List.generate(32, (i) => i + 1);
  final from = DateTime.utc(2026, 10, 1), before = DateTime.utc(2026, 11, 1);
  final at = DateTime.utc(2026, 10, 19, 8);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-chart-data-');
    path = '${directory.path}/records.db';
    store = await RecordStore.open(path: path, key: key, isNew: true);
    item = await store.createItem(
      commandId: 'item',
      name: 'Saved medicine',
      form: 'tablet',
      unit: 'mg',
      type: 'Medicine',
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  Database contextRaw() {
    final db = sqlite3.open(path);
    db.execute("PRAGMA cipher='chacha20'");
    db.execute(
      'PRAGMA key="x\'${key.map((v) => v.toRadixString(16).padLeft(2, '0')).join()}\'"',
    );
    db.execute('PRAGMA foreign_keys=ON');
    return db;
  }

  ChartSourceRequest source([String person = meId]) => ChartSourceRequest(
    personId: person,
    fromInstant: from,
    beforeInstant: before,
  );
  ChartDrilldownRequest drill({
    String? id,
    bool ingredient = false,
    String unit = 'mg',
    int limit = 1,
    TimelineStatus status = TimelineStatus.all,
    String person = meId,
  }) => ChartDrilldownRequest(
    series: ChartSeriesKey(
      personId: person,
      subject: ingredient
          ? ChartSubject.ingredient(id ?? 'a')
          : ChartSubject.item(id ?? item.id),
      unit: unit,
    ),
    fromInstant: from,
    beforeInstant: before,
    displayZone: 'Europe/London',
    limit: limit,
    status: status,
  );
  Future<UseRecord> record(
    String id, {
    SubstanceItem? it,
    DateTime? time,
    String amount = '1',
    String person = meId,
  }) => store.record(
    commandId: id,
    itemId: (it ?? item).id,
    personId: person,
    amount: amount,
    actualAt: time ?? at,
  );
  List<ProductComponent> parts({
    String first = 'a',
    String? concentration = '3',
  }) => [
    ProductComponent(
      ingredientId: first,
      name: 'Saved ingredient $first',
      concentrationText: concentration,
    ),
    ProductComponent(
      ingredientId: 'b',
      name: 'Saved ingredient b',
      concentrationText: '7',
    ),
  ];
  Future<SubstanceItem> product(
    String id, {
    String first = 'a',
    String? concentration = '3',
  }) => store.createItem(
    commandId: id,
    name: 'Product $id',
    form: 'liquid',
    unit: 'ml',
    type: 'Medicine',
    productComponents: parts(first: first, concentration: concentration),
  );
  Future<ProductUseInput> use(SubstanceItem p, {String volume = '0.5'}) async =>
      ProductUseInput(
        expectedGeneration: store.generation,
        label: (await store.productLabel(personId: meId, itemId: p.id))!,
        enteredVolume: EnteredStockAmount(volume, 'ml'),
      );
  Future<UseRecord> takeProduct(
    String id,
    SubstanceItem p, {
    DateTime? time,
    String volume = '0.5',
  }) async => store.recordProduct(
    commandId: id,
    personId: meId,
    expectedPersonRevision: 1,
    itemId: p.id,
    actualAt: time ?? at,
    use: await use(p, volume: volume),
  );
  Matcher cursorError(String code) => throwsA(
    isA<TimelineCursorException>().having((e) => e.code, 'code', code),
  );

  test('source reads current revisions once, preserves voids, units, owner and exact entries', () async {
    final first = await record('first', amount: '0.125000');
    await store.correct(
      commandId: 'correct',
      recordId: first.id,
      expectedRevision: 1,
      amount: '0.500000',
      actualAt: at,
    );
    final voided = await record('void');
    await store.voidRecord(
      commandId: 'void-command',
      recordId: voided.id,
      expectedRevision: 1,
    );
    final liquid = await store.createItem(
      commandId: 'liquid',
      name: 'Liquid',
      form: 'liquid',
      unit: 'ml',
      type: 'Medicine',
    );
    await record('ml', it: liquid, amount: '0.5');
    final adult = await store.createProfile(
      commandId: 'adult',
      name: 'Other adult',
      adultConfirmed: true,
    );
    final otherItem = await store.createItem(
      commandId: 'other-item',
      personId: adult.id,
      name: 'Other medicine',
      form: 'tablet',
      unit: 'mg',
      type: 'Medicine',
    );
    await record('other', it: otherItem, person: adult.id);
    await record(
      'before',
      time: from.subtract(const Duration(microseconds: 1)),
    );
    await record('exclusive', time: before);
    final batch = await RecordStoreChartSource(store).read(source());
    expect(batch.truncated, isFalse);
    expect(batch.schemaVersion, 19);
    expect(batch.datasetGeneration, store.generation);
    expect(batch.observationCount, 3);
    final corrected = batch.observations.singleWhere(
      (o) => o.source.recordId == first.id,
    );
    expect(corrected.source.revision, 2);
    expect(corrected.enteredAmountText, '0.500000');
    expect(corrected.amount, ExactAmount.parseEntry('0.5'));
    expect(batch.observations.where((o) => o.isVoided).length, 1);
    expect(batch.observations.map((o) => o.unit).toSet(), {'mg', 'ml'});
    expect(
      (await store.chartObservations(source(adult.id)))
          .observations
          .single
          .personId,
      adult.id,
    );
  });

  test(
    'saved actual unit stays separate from the original replacement entry',
    () async {
      LabelledStrength strength(int value) => LabelledStrength(
        ingredientId: 'active',
        label: '$value mg/ml',
        mgPerMl: ExactAmount.parseEntry('$value'),
      );
      final r = await store.record(
        commandId: 'replacement',
        itemId: item.id,
        amount: '0.5',
        actualAt: at,
        stockUse: StockUseInput(
          expectedGeneration: store.generation,
          entered: EnteredStockAmount('0.5', 'ml'),
          strength: strength(7),
          replacement: StockReplacement(
            oldStrength: strength(3),
            newStrength: strength(7),
            keep: FixedReplacementAmount.milligrams,
          ),
        ),
      );
      final observation = (await store.chartObservations(source()))
          .observations
          .single;
      expect(observation.source.recordId, r.id);
      expect(observation.amount, ExactAmount.parseEntry('1.5'));
      expect(observation.unit, 'mg');
      expect(observation.enteredAmountText, '0.5');
      expect(observation.enteredUnit, 'ml');
      expect(
        (await store.chartDrilldown(drill())).entries.single.id.value,
        r.id,
      );
      expect((await store.chartDrilldown(drill(unit: 'ml'))).entries, isEmpty);
    },
  );

  test(
    'context uses saved civil zones and exact pauses without inventing phases',
    () async {
      await store.saveDailyPlan(
        commandId: 'context-plan',
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
        plan: DailyPlanVersion(
          personId: meId,
          itemId: item.id,
          planId: 'context-plan',
          versionId: 'context-v1',
          start: CivilDate(2026, 10, 3),
          endExclusive: CivilDate(2026, 10, 25),
          timing: DailyCount(
            1,
            PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
          ),
          zoneBasis: FixedHome('Europe/London'),
          pauses: [
            PlanPause(
              start: DateTime.utc(2026, 10, 10, 8),
              resume: DateTime.utc(2026, 10, 12, 9),
            ),
          ],
        ),
      );
      final event = EventRecord(
        id: 'context-event',
        personId: meId,
        name: 'Saved cycle',
        eventType: 'cycle',
        zoneId: 'Europe/London',
        revision: 1,
        plannedStart: EventDate.day(CivilDate(2026, 10, 2)),
        plannedEnd: EventDate.day(CivilDate(2026, 10, 24)),
        memberships: [
          EventMembership(
            id: 'context-member',
            itemId: item.id,
            personId: meId,
            effectiveFrom: from,
            revision: 1,
          ),
        ],
      );
      final command = SaveEventCommand(
        commandId: 'context-event',
        expectedRevision: null,
        generation: store.generation,
        event: event,
      );
      await store.saveEvent(
        command,
        membershipReview: await store.previewEventMembership(command),
      );
      final query = ChartQuery(
        personId: meId,
        viewport: ChartViewport(
          fromInstant: from,
          beforeInstant: before,
          displayZone: 'UTC',
          bucketSize: ChartBucketSize.day,
        ),
        focus: drill().series,
      );
      final context = await store.chartContext(query);
      expect(context.complete, isTrue);
      expect(context.annotations.map((a) => a.kind).toSet(), {
        ChartAnnotationKind.planChanged,
        ChartAnnotationKind.pauseStart,
        ChartAnnotationKind.pauseEnd,
        ChartAnnotationKind.eventStart,
        ChartAnnotationKind.eventEnd,
        ChartAnnotationKind.planEnd,
      });
      final positioned = ChartAnnotationSet.bounded(
        viewport: query.viewport,
        personId: meId,
        annotations: context.annotations,
      );
      expect(positioned.visible, hasLength(6));
      expect(
        context.annotations
            .where((a) => a.kind == ChartAnnotationKind.eventStart)
            .single
            .label,
        'Saved cycle',
      );
      expect(await store.records(), isEmpty);
      final wrong = await store.createItem(
        commandId: 'unrelated',
        name: 'Unrelated',
        form: 'tablet',
        unit: 'mg',
        type: 'Medicine',
      );
      final unrelated = await store.chartContext(
        ChartQuery(
          personId: meId,
          viewport: query.viewport,
          focus: ChartSeriesKey(
            personId: meId,
            subject: ChartSubject.item(wrong.id),
            unit: 'mg',
          ),
        ),
      );
      expect(unrelated.annotations, isEmpty);
    },
  );

  test(
    'phase boundaries and finite inclusive end retain saved semantics',
    () async {
      final phase = DailyPlanVersion(
        personId: meId,
        itemId: item.id,
        planId: 'phased-plan',
        versionId: 'phase-v1',
        start: CivilDate(2026, 10, 3),
        effectiveFrom: DateTime.utc(2026, 10, 19, 8),
        effectiveUntil: DateTime.utc(2026, 10, 19, 10),
        timing: DailyCount(
          1,
          PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
        ),
        zoneBasis: FixedHome('Europe/London'),
      );
      final old = await store.saveDailyPlan(
        commandId: 'phased-initial',
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
        plan: phase,
      );
      final review = await store.previewPhasePlan(
        plan: old,
        proposed: PhasePlan(
          phases: [phase],
          end: PlanEnd.onDate(
            lastDate: CivilDate(2026, 10, 24),
            zoneId: 'Europe/London',
            clock: IanaClock(),
          ),
        ),
        now: from,
        observedZone: 'Europe/London',
      );
      await store.savePhasePlan(commandId: 'finite-phase', review: review);
      final context = await store.chartContext(
        ChartQuery(
          personId: meId,
          viewport: ChartViewport(
            fromInstant: from,
            beforeInstant: before,
            displayZone: 'UTC',
            bucketSize: ChartBucketSize.day,
          ),
        ),
      );
      expect(context.complete, isTrue);
      expect(
        context.annotations.any(
          (a) => a.kind == ChartAnnotationKind.phaseStart,
        ),
        isTrue,
      );
      final end = context.annotations
          .where((a) => a.kind == ChartAnnotationKind.planEnd)
          .single;
      expect(end.at.isDateOnly, isTrue);
      expect(end.at.civilDate, CivilDate(2026, 10, 24));
      expect(end.at.zoneId, 'Europe/London');
      expect(
        context.annotations.where((a) => a.kind == ChartAnnotationKind.planEnd),
        hasLength(1),
      );
      expect(
        context.annotations
            .singleWhere((a) => a.kind == ChartAnnotationKind.phaseEnd)
            .at
            .instant,
        DateTime.utc(2026, 10, 19, 10),
      );
      final intradayViewport = ChartViewport(
        fromInstant: DateTime.utc(2026, 10, 19, 8),
        beforeInstant: DateTime.utc(2026, 10, 19, 10),
        displayZone: 'UTC',
        bucketSize: ChartBucketSize.day,
      );
      final intraday = await store.chartContext(
        ChartQuery(personId: meId, viewport: intradayViewport),
      );
      expect(intraday.complete, isTrue);
      expect(
        ChartAnnotationSet.bounded(
          viewport: intradayViewport,
          personId: meId,
          annotations: intraday.annotations,
        ).visible.map((a) => a.kind),
        [ChartAnnotationKind.planChanged, ChartAnnotationKind.phaseStart],
      );
    },
  );

  test('intraday-only saved boundaries use integer instants and half-open viewports', () async {
    final ending = at.add(const Duration(hours: 2));
    await store.saveDailyPlan(
      commandId: 'intraday',
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      plan: DailyPlanVersion(
        personId: meId,
        itemId: item.id,
        planId: 'intraday',
        versionId: 'intraday-v1',
        start: CivilDate(2026, 9, 1),
        effectiveFrom: at,
        effectiveUntil: ending,
        pauses: [PlanPause(start: at, resume: ending)],
        timing: DailyCount(
          1,
          PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
        ),
        zoneBasis: FixedHome('Europe/London'),
      ),
    );
    final query = ChartQuery(
      personId: meId,
      viewport: ChartViewport(
        fromInstant: at,
        beforeInstant: ending,
        displayZone: 'Pacific/Auckland',
        bucketSize: ChartBucketSize.day,
      ),
      focus: drill().series,
    );
    final first = await store.chartContext(query);
    expect(first.complete, isTrue);
    expect(
      first.annotations
          .singleWhere((a) => a.kind == ChartAnnotationKind.planChanged)
          .at
          .instant,
      at,
    );
    expect(
      first.annotations
          .singleWhere((a) => a.kind == ChartAnnotationKind.planEnd)
          .at
          .instant,
      ending,
    );
    final visible = ChartAnnotationSet.bounded(
      viewport: query.viewport,
      personId: meId,
      annotations: first.annotations,
    );
    expect(visible.visible.map((a) => a.kind), [
      ChartAnnotationKind.planChanged,
      ChartAnnotationKind.pauseStart,
    ]);
    expect(first.annotations.every((a) => a.label == null), isTrue);
    await store.close();
    final raw = sqlite3.open(path);
    raw.execute("PRAGMA cipher='chacha20'");
    raw.execute(
      'PRAGMA key="x\'${key.map((v) => v.toRadixString(16).padLeft(2, '0')).join()}\'"',
    );
    raw.execute("UPDATE item SET name='Changed live name' WHERE id=?", [
      item.id,
    ]);
    raw.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final renamed = await store.chartContext(query);
    expect(
      renamed.annotations
          .map((a) => [a.kind.name, a.sourceId, a.at.instant, a.label])
          .toList(),
      first.annotations
          .map((a) => [a.kind.name, a.sourceId, a.at.instant, a.label])
          .toList(),
    );
  });

  test('effective-until alone selects a version whose civil start is outside range', () async {
    await store.saveDailyPlan(
      commandId: 'until-only',
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      plan: DailyPlanVersion(
        personId: meId,
        itemId: item.id,
        planId: 'until-only',
        versionId: 'until-only-v1',
        start: CivilDate(2026, 9, 1),
        effectiveFrom: DateTime.utc(2026, 9, 1),
        effectiveUntil: at,
        timing: DailyCount(
          1,
          PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
        ),
        zoneBasis: FixedHome('Europe/London'),
      ),
    );
    final viewport = ChartViewport(
      fromInstant: at,
      beforeInstant: at.add(const Duration(hours: 1)),
      displayZone: 'UTC',
      bucketSize: ChartBucketSize.day,
    );
    final context = await store.chartContext(
      ChartQuery(personId: meId, viewport: viewport),
    );
    expect(context.complete, isTrue);
    final visible = ChartAnnotationSet.bounded(
      viewport: viewport,
      personId: meId,
      annotations: context.annotations,
    );
    expect(visible.visible.single.kind, ChartAnnotationKind.planEnd);
    expect(visible.visible.single.at.instant, at);
  });

  test('saved intraday revisions retain coincident close open and pause boundaries', () async {
    await store.close();
    File(path).deleteSync();
    final raw = contextRaw();
    raw.execute(
      File('test/data/fixtures/record_store_v12.sql').readAsStringSync(),
    );
    raw.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final boundary = DateTime.fromMicrosecondsSinceEpoch(
      1792411200000000,
      isUtc: true,
    );
    final viewport = ChartViewport(
      fromInstant: boundary,
      beforeInstant: boundary.add(const Duration(hours: 1)),
      displayZone: 'Pacific/Auckland',
      bucketSize: ChartBucketSize.day,
    );
    final context = await store.chartContext(
      ChartQuery(personId: 'other', viewport: viewport),
    );
    expect(context.complete, isTrue);
    final visible = ChartAnnotationSet.bounded(
      viewport: viewport,
      personId: 'other',
      annotations: context.annotations,
    ).visible;
    expect(
      visible
          .singleWhere(
            (a) =>
                a.kind == ChartAnnotationKind.planChanged &&
                a.at.instant == boundary,
          )
          .sourceId,
      'calendar-v3',
    );
    expect(
      visible
          .singleWhere((a) => a.kind == ChartAnnotationKind.planEnd)
          .sourceId,
      'calendar-v2',
    );
    expect(
      visible.where((a) => a.kind == ChartAnnotationKind.pauseEnd),
      hasLength(2),
    );
    expect(visible.where((a) => a.at.instant == boundary), hasLength(4));
    final savedDate = visible.singleWhere((a) => a.at.isDateOnly);
    expect(savedDate.kind, ChartAnnotationKind.planChanged);
    expect(savedDate.sourceId, 'calendar-v2');
    expect(savedDate.at.civilDate, CivilDate(2026, 10, 19));
    expect(savedDate.at.zoneId, 'Europe/London');
  });

  test(
    'ordinary finite end remains a saved civil day across the DST fold',
    () async {
      await store.saveDailyPlan(
        commandId: 'ordinary-end',
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
        plan: DailyPlanVersion(
          personId: meId,
          itemId: item.id,
          planId: 'ordinary-end',
          versionId: 'ordinary-end-v1',
          start: CivilDate(2026, 9, 1),
          endExclusive: CivilDate(2026, 10, 26),
          timing: DailyCount(
            1,
            PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
          ),
          zoneBasis: FixedHome('Europe/London'),
        ),
      );
      final query = ChartQuery(
        personId: meId,
        viewport: ChartViewport(
          fromInstant: DateTime.utc(2026, 10, 25, 1),
          beforeInstant: DateTime.utc(2026, 10, 25, 2),
          displayZone: 'UTC',
          bucketSize: ChartBucketSize.day,
        ),
      );
      final context = await store.chartContext(query);
      expect(context.complete, isTrue);
      final visible = ChartAnnotationSet.bounded(
        viewport: query.viewport,
        personId: meId,
        annotations: context.annotations,
      );
      final end = visible.visible.single;
      expect(end.kind, ChartAnnotationKind.planEnd);
      expect(end.at.civilDate, CivilDate(2026, 10, 25));
      expect(end.at.zoneId, 'Europe/London');
      expect(end.at.instant, isNull);
      expect(
        context.annotations.where(
          (a) => a.kind == ChartAnnotationKind.phaseEnd,
        ),
        isEmpty,
      );
    },
  );

  test('unpositionable event and unsupported saved plan declare incomplete context', () async {
    await store.saveDailyPlan(
      commandId: 'unknown-plan',
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      plan: DailyPlanVersion(
        personId: meId,
        itemId: item.id,
        planId: 'unknown-plan',
        versionId: 'unknown-plan-v1',
        start: CivilDate(2026, 9, 1),
        timing: DailyCount(
          1,
          PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
        ),
        zoneBasis: FixedHome('Europe/London'),
      ),
    );
    await store.close();
    final raw = contextRaw();
    raw.execute(
      "UPDATE daily_version SET snapshot=json_set(snapshot,'\$.effectiveFrom','unknown') WHERE id='unknown-plan-v1'",
    );
    final event = EventRecord(
      id: 'unknown-event',
      personId: meId,
      name: 'Saved unknown boundary',
      eventType: 'cycle',
      zoneId: 'Europe/London',
      revision: 1,
      plannedStart: EventDate(
        precision: EventDatePrecision.month,
        value: '2026-10',
      ),
      memberships: [],
    );
    raw.execute('INSERT INTO event_record VALUES (?,?,?,?)', [
      event.id,
      meId,
      1,
      jsonEncode(event.toJson()),
    ]);
    raw.execute('INSERT INTO event_history_bounds VALUES (?,?,NULL,NULL,0)', [
      event.id,
      meId,
    ]);
    raw.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final context = await store.chartContext(
      ChartQuery(
        personId: meId,
        viewport: ChartViewport(
          fromInstant: at,
          beforeInstant: at.add(const Duration(hours: 1)),
          displayZone: 'UTC',
          bucketSize: ChartBucketSize.day,
        ),
      ),
    );
    expect(context.complete, isFalse);
    expect(context.annotations, isEmpty);
  });

  test('following-local civil context is explicitly incomplete without a saved historic zone', () async {
    await store.saveDailyPlan(
      commandId: 'local-plan',
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      plan: DailyPlanVersion(
        personId: meId,
        itemId: item.id,
        planId: 'local-plan',
        versionId: 'local-v1',
        start: CivilDate(2026, 10, 3),
        timing: DailyCount(
          1,
          PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
        ),
        zoneBasis: const FollowingLocal(),
      ),
    );
    final context = await store.chartContext(
      ChartQuery(
        personId: meId,
        viewport: ChartViewport(
          fromInstant: from,
          beforeInstant: before,
          displayZone: 'Europe/London',
          bucketSize: ChartBucketSize.day,
        ),
      ),
    );
    expect(context.complete, isFalse);
    expect(context.annotations, isEmpty);
  });

  test(
    'skipped plans supply no chart observations or drilldown source rows',
    () async {
      final day = CivilDate(2026, 10, 19);
      await store.saveDailyPlan(
        commandId: 'plan',
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
        plan: DailyPlanVersion(
          personId: meId,
          itemId: item.id,
          planId: 'plan',
          versionId: 'v1',
          start: day,
          timing: DailyCount(
            1,
            PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
          ),
          zoneBasis: FixedHome('Europe/London'),
        ),
      );
      final rows = await store.dailyRows(
        from: day,
        toExclusive: day.addDays(1),
        observedZone: 'Europe/London',
      );
      await store.actDaily(
        commandId: 'skip',
        row: rows.rows.single,
        kind: DailyActionKind.skip,
      );
      expect((await store.chartObservations(source())).observations, isEmpty);
      expect(
        (await store.chartDrilldown(drill(status: TimelineStatus.skipped)))
            .entries,
        isEmpty,
      );
      expect((await store.chartDrilldown(drill())).entries, isEmpty);
    },
  );

  test('combined chart input has components once and parent source page stays complete', () async {
    final other = await store.createItem(
      commandId: 'second',
      name: 'Second',
      form: 'liquid',
      unit: 'ml',
      type: 'Medicine',
    );
    final combined = await store.recordCombined(
      CombinedUseCommand(
        commandId: 'combined',
        expectedGeneration: store.generation,
        personId: meId,
        expectedPersonRevision: 1,
        actualAt: at,
        components: [
          CombinedUseComponent(
            itemId: item.id,
            expectedItemRevision: 1,
            enteredAmount: '0.25',
          ),
          CombinedUseComponent(
            itemId: other.id,
            expectedItemRevision: 1,
            enteredAmount: '0.5',
          ),
        ],
      ),
    );
    final batch = await store.chartObservations(source());
    expect(batch.observationCount, 2);
    expect(
      batch.observations.every(
        (o) => o.source.combinedActionId == combined.actionId,
      ),
      isTrue,
    );
    final page = await store.chartDrilldown(drill());
    final group = page.entries.single as CombinedTimelineEntry;
    expect(group.components.length, 2);
    expect(group.matchedRecordIds, [combined.records.first.id]);
  });

  test('ingredient predicate uses saved labels in ml before limiting and ignores latest label', () async {
    final p = await product('product');
    final old = await takeProduct('old', p);
    await store.saveProductLabel(
      commandId: 'change-label',
      personId: meId,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      itemId: p.id,
      expectedItemRevision: p.revision,
      expectedProductRevision: 1,
      components: parts(first: 'c'),
    );
    await takeProduct('new', p, time: at.add(const Duration(minutes: 1)));
    for (var i = 0; i < 4; i++) {
      await record('unrelated-$i', time: at.add(Duration(minutes: i + 2)));
    }
    final page = await store.chartDrilldown(drill(ingredient: true));
    final entry = page.entries.single as RecordTimelineEntry;
    expect(entry.record.id, old.id);
    expect(entry.record.actualUnit, 'ml');
    expect(entry.record.product!.label.components.first.ingredientId, 'a');
    expect(page.next, isNull);
    expect(
      (await store.chartDrilldown(drill(ingredient: true, id: 'c')))
          .entries
          .length,
      1,
    );
  });

  test(
    'unknown ingredient remains incomplete and saved product snapshot is exact',
    () async {
      final p = await product('unknown', concentration: null);
      await takeProduct('dose', p);
      final batch = await store.chartObservations(source());
      expect(
        batch.observations.single.product!.volume,
        ExactAmount.parseEntry('0.5'),
      );
      final query = ChartQuery(
        personId: meId,
        viewport: ChartViewport(
          fromInstant: from,
          beforeInstant: before,
          displayZone: 'Europe/London',
          bucketSize: ChartBucketSize.day,
        ),
      );
      final model = ChartModel.build(query: query, batch: batch, generation: 1);
      final series = model.series.singleWhere(
        (s) => s.key.subject == ChartSubject.ingredient('a'),
      );
      expect(series.total.exactTotal, isNull);
      expect(series.total.unknownContributions, 1);
      expect(series.total.knownSubtotal, ExactAmount.zero);
      expect(
        (await store.chartDrilldown(drill(ingredient: true))).entries.length,
        1,
      );
    },
  );

  test(
    'ingredient groups keep all sources and identify only matching components',
    () async {
      final p = await product('a-product');
      final unrelated = await product('c-product', first: 'c');
      final result = await store.recordCombined(
        CombinedUseCommand(
          commandId: 'products',
          expectedGeneration: store.generation,
          personId: meId,
          expectedPersonRevision: 1,
          actualAt: at,
          components: [
            CombinedUseComponent(
              itemId: p.id,
              expectedItemRevision: 1,
              enteredAmount: '0.5',
              productUse: await use(p),
            ),
            CombinedUseComponent(
              itemId: unrelated.id,
              expectedItemRevision: 1,
              enteredAmount: '0.5',
              productUse: await use(unrelated),
            ),
          ],
        ),
      );
      final group =
          (await store.chartDrilldown(drill(ingredient: true))).entries.single
              as CombinedTimelineEntry;
      expect(group.components.length, 2);
      expect(group.matchedRecordIds, [result.records.first.id]);
    },
  );

  test('request-bound cursor pages tied records once and expires across subjects, schema and dataset', () async {
    final p = await product('product');
    await takeProduct('one', p);
    await takeProduct('two', p);
    final request = drill(ingredient: true);
    final first = await store.chartDrilldown(request);
    final cursor = ChartDrilldownCursor.decode(first.next!.encode());
    final second = await store.chartDrilldown(request, cursor: cursor);
    expect(
      {
        ...first.entries.map((e) => e.id.sortKey),
        ...second.entries.map((e) => e.id.sortKey),
      }.length,
      2,
    );
    expect(second.next, isNull);
    expect(first.requestIdentity, request.identity);
    expect(
      request.timelineQuery.identity,
      drill(ingredient: true, id: 'b').timelineQuery.identity,
    );
    await expectLater(
      store.chartDrilldown(drill(ingredient: true, id: 'b'), cursor: cursor),
      cursorError('cursor_expired'),
    );
    final envelope = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(cursor.encode()))),
    ) as Map<String, dynamic>;
    final nested = jsonDecode(
      utf8.decode(
        base64Url.decode(base64Url.normalize(envelope['timeline'] as String)),
      ),
    ) as Map<String, dynamic>;
    nested['s'] = 999;
    envelope['timeline'] = base64Url
        .encode(utf8.encode(jsonEncode(nested)))
        .replaceAll('=', '');
    final wrongSchema = ChartDrilldownCursor.decode(
      base64Url.encode(utf8.encode(jsonEncode(envelope))).replaceAll('=', ''),
    );
    await expectLater(
      store.chartDrilldown(request, cursor: wrongSchema),
      cursorError('cursor_expired'),
    );
    await store.close();
    final replacement = await RecordStore.open(
      path: '${directory.path}/replacement.db',
      key: key,
      isNew: true,
    );
    try {
      await expectLater(
        replacement.chartDrilldown(request, cursor: cursor),
        cursorError('cursor_expired'),
      );
    } finally {
      await replacement.close();
    }
    expect(
      () => ChartDrilldownCursor.decode('invalid'),
      cursorError('cursor_malformed'),
    );
  });

  test(
    'voided status is paged explicitly and suspended reads stay private',
    () async {
      final r = await record('void');
      await store.voidRecord(
        commandId: 'void-change',
        recordId: r.id,
        expectedRevision: 1,
      );
      expect(
        (await store.chartDrilldown(drill(status: TimelineStatus.recorded)))
            .entries,
        isEmpty,
      );
      expect(
        (await store.chartDrilldown(drill(status: TimelineStatus.voided)))
            .entries
            .single
            .status,
        TimelineEntryStatus.voided,
      );
      final pendingRead = store.chartObservations(source());
      store.suspendWrites(true);
      await expectLater(pendingRead, throwsA(isA<CommandConflict>()));
      await expectLater(
        store.chartObservations(source()),
        throwsA(isA<CommandConflict>()),
      );
      await expectLater(
        store.chartDrilldown(drill()),
        throwsA(isA<CommandConflict>()),
      );
    },
  );
  test(
    'source watcher replaces a complete snapshot after a correction',
    () async {
      final r = await record('watched');
      final snapshots = StreamIterator(store.watchChartObservations(source()));
      try {
        expect(await snapshots.moveNext(), isTrue);
        expect(snapshots.current.observations.single.source.revision, 1);
        await store.correct(
          commandId: 'watched-correction',
          recordId: r.id,
          expectedRevision: 1,
          amount: '2',
          actualAt: at,
        );
        expect(await snapshots.moveNext(), isTrue);
        expect(snapshots.current.observations.length, 1);
        expect(snapshots.current.observations.single.source.revision, 2);
        expect(
          snapshots.current.observations.single.amount,
          ExactAmount.parseEntry('2'),
        );
      } finally {
        await snapshots.cancel();
      }
    },
  );

  test(
    'tied combined and single parents page once with a changed page size',
    () async {
      final single = await record('single');
      final group = await store.recordCombined(
        CombinedUseCommand(
          commandId: 'group',
          expectedGeneration: store.generation,
          personId: meId,
          expectedPersonRevision: 1,
          actualAt: at,
          components: [
            CombinedUseComponent(
              itemId: item.id,
              expectedItemRevision: 1,
              enteredAmount: '1',
            ),
            CombinedUseComponent(
              itemId: item.id,
              expectedItemRevision: 1,
              enteredAmount: '2',
            ),
          ],
        ),
      );
      final first = await store.chartDrilldown(drill());
      expect(first.entries.single.id.value, group.actionId);
      final next = await store.chartDrilldown(
        drill(limit: 2),
        cursor: first.next,
      );
      expect(next.entries.single.id.value, single.id);
      expect(next.next, isNull);
    },
  );

  test('dense saved pause boundaries stop at the context cap and declare incomplete', () async {
    await store.saveDailyPlan(
      commandId: 'dense-pauses',
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      plan: DailyPlanVersion(
        personId: meId,
        itemId: item.id,
        planId: 'dense-pauses',
        versionId: 'dense-pauses-v1',
        start: CivilDate(2026, 10, 1),
        timing: DailyCount(
          1,
          PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
        ),
        zoneBasis: FixedHome('UTC'),
        pauses: [
          for (var i = 0; i < 2001; i++)
            PlanPause(
              start: from.add(Duration(minutes: i * 2)),
              resume: from.add(Duration(minutes: i * 2 + 1)),
            ),
        ],
      ),
    );
    final context = await store.chartContext(
      ChartQuery(
        personId: meId,
        viewport: ChartViewport(
          fromInstant: from,
          beforeInstant: before,
          displayZone: 'UTC',
          bucketSize: ChartBucketSize.day,
        ),
      ),
    );
    expect(context.complete, isFalse);
    expect(context.annotations, hasLength(4000));
    expect(
      context.annotations.map((a) => '${a.kind.name}:${a.sourceId}').toSet(),
      hasLength(4000),
    );
  });

  test('context boundary reads declare overflow instead of presenting a truncated set as complete', () async {
    await store.close();
    final raw = sqlite3.open(path);
    raw.execute("PRAGMA cipher='chacha20'");
    final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    raw.execute('PRAGMA key="x\'$hex\'"');
    raw.execute('PRAGMA foreign_keys=ON');
    final eventInsert = raw.prepare(
      'INSERT INTO event_record VALUES (?,?,?,?)',
    );
    final boundsInsert = raw.prepare(
      'INSERT INTO event_history_bounds VALUES (?,?,?,?,?)',
    );
    try {
      raw.execute('BEGIN');
      for (var index = 0; index < 1001; index++) {
        final id = 'bounded-event-$index';
        final event = EventRecord(
          id: id,
          personId: meId,
          name: 'Saved cycle $index',
          eventType: 'cycle',
          zoneId: 'UTC',
          revision: 1,
          plannedStart: EventDate.exact(at),
          memberships: [],
        );
        eventInsert.execute([id, meId, 1, jsonEncode(event.toJson())]);
        boundsInsert.execute([id, meId, at.microsecondsSinceEpoch, null, 1]);
      }
      raw.execute('COMMIT');
    } finally {
      eventInsert.close();
      boundsInsert.close();
      raw.close();
    }
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final query = ChartQuery(
      personId: meId,
      viewport: ChartViewport(
        fromInstant: from,
        beforeInstant: before,
        displayZone: 'UTC',
        bucketSize: ChartBucketSize.day,
      ),
    );
    final context = await store.chartContext(query);
    expect(context.complete, isFalse);
    expect(context.annotations, hasLength(1000));
    final visible = ChartAnnotationSet.bounded(
      viewport: query.viewport,
      personId: meId,
      annotations: context.annotations,
    );
    expect(visible.visible, hasLength(200));
    expect(visible.hiddenCount, 800);
  });

  test('100k encrypted rows stay bounded, exact and reject overflow without sampling', () async {
    await record('template');
    await store.close();
    final raw = sqlite3.open(path);
    raw.execute("PRAGMA cipher='chacha20'");
    final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    raw.execute('PRAGMA key="x\'$hex\'"');
    raw.execute('PRAGMA foreign_keys=ON');
    final template = raw.select('SELECT * FROM revision').single;
    final columns = template.keys.toList();
    final insertRevision = raw.prepare(
      'INSERT INTO revision (${columns.join(',')}) VALUES (${List.filled(columns.length, '?').join(',')})',
    );
    final insertParent = raw.prepare(
      'INSERT INTO administration(id,person,item,revision,actual) VALUES (?,?,?,?,?)',
    );
    final start = DateTime.utc(2026, 1, 1);
    final fixtureTimer = Stopwatch()..start();
    try {
      raw.execute('BEGIN');
      for (var i = 0; i < 100000; i++) {
        final id = 'chart-fixture-${i.toString().padLeft(6, '0')}';
        final time = start.add(Duration(seconds: i)).microsecondsSinceEpoch;
        insertParent.execute([id, meId, item.id, 1, time]);
        final values = Map<String, Object?>.from(template);
        values['record'] = id;
        values['actual'] = time;
        insertRevision.execute(columns.map((c) => values[c]).toList());
      }
      raw.execute('COMMIT');
    } finally {
      insertParent.close();
      insertRevision.close();
      raw.close();
    }
    fixtureTimer.stop();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final timer = Stopwatch()..start();
    final seen = <String>{};
    var sum = ExactAmount.zero;
    final readTimes = <int>[];
    for (var i = 0; i < 10; i++) {
      final lower = start.add(Duration(seconds: i * 10000));
      final upper = start.add(Duration(seconds: (i + 1) * 10000));
      final request = ChartSourceRequest(
        personId: meId,
        fromInstant: lower,
        beforeInstant: upper,
      );
      final readTimer = Stopwatch()..start();
      final batch = await store.chartObservations(request);
      readTimes.add(readTimer.elapsedMilliseconds);
      expect(batch.truncated, isFalse);
      expect(batch.observationCount, 10000);
      expect(
        batch.observations.every((o) => seen.add(o.source.recordId)),
        isTrue,
      );
      final query = ChartQuery(
        personId: meId,
        viewport: ChartViewport(
          fromInstant: lower,
          beforeInstant: upper,
          displayZone: 'Europe/London',
          bucketSize: ChartBucketSize.day,
        ),
      );
      final model = ChartModel.build(query: query, batch: batch, generation: i);
      sum += model.series.single.total.exactTotal!;
    }
    expect(seen.length, 100000);
    expect(sum, ExactAmount.parseEntry('100000'));
    final overflow = await store.chartObservations(
      ChartSourceRequest(
        personId: meId,
        fromInstant: start,
        beforeInstant: start.add(const Duration(seconds: 100000)),
      ),
    );
    expect(overflow.truncated, isTrue);
    expect(overflow.observations, isEmpty);
    final query = ChartQuery(
      personId: meId,
      viewport: ChartViewport(
        fromInstant: overflow.fromInstant,
        beforeInstant: overflow.beforeInstant,
        displayZone: 'Europe/London',
        bucketSize: ChartBucketSize.day,
      ),
    );
    expect(
      () => ChartModel.build(query: query, batch: overflow, generation: 1),
      throwsA(
        isA<ChartRangeException>().having(
          (e) => e.code,
          'code',
          'range_too_large',
        ),
      ),
    );
    final drillRequest = ChartDrilldownRequest(
      series: ChartSeriesKey(
        personId: meId,
        subject: ChartSubject.item(item.id),
        unit: 'mg',
      ),
      fromInstant: start,
      beforeInstant: start.add(const Duration(seconds: 100000)),
      displayZone: 'Europe/London',
      limit: 50,
    );
    final drillTimer = Stopwatch()..start();
    final newest = await store.chartDrilldown(drillRequest);
    expect(newest.entries.length, 50);
    expect(newest.entries.first.id.value, 'chart-fixture-099999');
    final lateTimelineCursor = TimelineCursor.at(
      occurredAt: start.add(const Duration(seconds: 10)),
      sortKey: 'r:chart-fixture-000010',
      query: drillRequest.timelineQuery,
      schemaVersion: 19,
      datasetGeneration: store.generation,
    );
    final lateCursor = ChartDrilldownCursor.decode(
      base64Url
          .encode(
            utf8.encode(
              jsonEncode({
                'v': 1,
                'request': drillRequest.identity,
                'timeline': lateTimelineCursor.encode(),
              }),
            ),
          )
          .replaceAll('=', ''),
    );
    final oldest = await store.chartDrilldown(drillRequest, cursor: lateCursor);
    expect(oldest.entries.map((entry) => entry.id.value), [
      for (var i = 9; i >= 0; i--)
        'chart-fixture-${i.toString().padLeft(6, '0')}',
    ]);
    expect(oldest.next, isNull);
    final drillMs = drillTimer.elapsedMilliseconds;
    stdout.writeln(
      'CHART_STORE_100K ${jsonEncode({'rows': seen.length, 'fixtureMs': fixtureTimer.elapsedMilliseconds, 'readAndFoldMs': timer.elapsedMilliseconds, 'firstAndLateDrillMs': drillMs, 'boundedReadMs': readTimes, 'exactTotal': sum.toString(), 'overflowRejected': true})}',
    );
  });
}
