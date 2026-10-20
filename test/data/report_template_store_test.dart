import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/reports/report_fonts.dart';
import 'package:true_grit_vital/reports/templates/report_template_catalog.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  late Directory dir;
  late RecordStore store;
  late SubstanceItem item;
  late SubstanceItem secondItem;
  final key = List.generate(32, (i) => i + 1);
  final now = DateTime.utc(2026, 10, 20, 12);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vital-report-t06-');
    store = await RecordStore.open(
      path: '${dir.path}/records.db',
      key: key,
      isNew: true,
    );
    item = await store.createItem(
      commandId: 'item',
      name: 'Example prescribed item',
      form: 'tablet',
      unit: 'count',
      type: 'Medicines',
    );
    secondItem = await store.createItem(
      commandId: 'item-2',
      name: 'Example supplement',
      form: 'capsule',
      unit: 'count',
      type: 'Supplements',
    );
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  PlannedAmount amount() =>
      PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'count');

  Future<void> savePlan({
    required String planId,
    required CivilDate start,
    SubstanceItem? forItem,
  }) => store.saveDailyPlan(
    commandId: 'save-$planId',
    plan: DailyPlanVersion(
      personId: meId,
      planId: planId,
      itemId: (forItem ?? item).id,
      versionId: '$planId-v1',
      start: start,
      endExclusive: start.addDays(1),
      timing: DailySlots([
        DailySlot(
          id: 'slot-$planId',
          time: WallTime(8, 0),
          amount: amount(),
          reminderEnabled: false,
        ),
      ]),
      zoneBasis: const FollowingLocal(),
      calendar: const EveryDay(),
    ),
    expectedPersonRevision: 1,
    expectedGeneration: store.generation,
    expectedPlanRevision: null,
  );

  Future<DailyRow> planRow(CivilDate date) async => (await store.dailyRows(
    from: date,
    toExclusive: date.addDays(1),
    observedZone: 'Europe/London',
  )).rows.single;

  ReportSelection selection({
    ReportTemplateId template = ReportTemplateId.r02DetailedHistory,
    String? eventId,
  }) => ReportSelection(
    template: template,
    personId: meId,
    fromDate: CivilDate(2026, 10, 18),
    beforeDate: CivilDate(2026, 10, 22),
    displayZone: 'Europe/London',
    eventId: eventId,
  );

  test(
    'captures R02 recorded, skipped and not-recorded rows with a cutoff',
    () async {
      await store.record(
        commandId: 'dose-1',
        itemId: item.id,
        amount: '1',
        actualAt: DateTime.utc(2026, 10, 20, 8),
      );
      await savePlan(planId: 'plan-skip', start: CivilDate(2026, 10, 18));
      await store.actDaily(
        commandId: 'skip-1',
        row: await planRow(CivilDate(2026, 10, 18)),
        kind: DailyActionKind.skip,
      );
      await savePlan(
        planId: 'plan-missing',
        start: CivilDate(2026, 10, 19),
        forItem: secondItem,
      );

      final capture = await store.captureTemplateReport(
        selection: selection(),
        now: () => now,
      );
      final data = capture.snapshot.templateData;
      expect(data, isA<ReportHistoryData>());
      final history = data! as ReportHistoryData;
      expect(history.recordedCount, 1);
      expect(history.skippedCount, 1);
      expect(history.notRecordedCount, 1);
      expect(history.entries.length, 3);
      expect(history.planCoverageComplete, isTrue);
      expect(capture.pins, isEmpty);
      expect(capture.snapshot.records.length, 1);

      // A later dose is outside the captured cutoff and cannot change the body.
      await store.record(
        commandId: 'dose-2',
        itemId: item.id,
        amount: '1',
        actualAt: DateTime.utc(2026, 10, 20, 9),
      );
      expect(capture.snapshot.records.length, 1);
      expect(history.entries.length, 3);
      expect(history.latest?.status, ReportLedgerStatus.recorded);
      expect(history.entries.map((entry) => entry.status).toSet(), {
        ReportLedgerStatus.recorded,
        ReportLedgerStatus.skipped,
        ReportLedgerStatus.notRecorded,
      });

      final rendered = await rendererForTemplate(
        ReportTemplateId.r02DetailedHistory,
        fontLoader: const _HostFontLoader(),
      ).render(capture.snapshot, use24Hour: true);
      expect(String.fromCharCodes(rendered.bytes.take(5)), '%PDF-');
      expect(rendered.pageCount, greaterThanOrEqualTo(1));
      expect(
        reportTextFor(capture.snapshot, use24Hour: true),
        contains('Not recorded'),
      );
    },
  );

  test('captures an event-scoped R03 and excludes unrelated use', () async {
    final event = EventRecord(
      id: 'event-1',
      personId: meId,
      name: 'Example recorded course',
      eventType: 'Course',
      zoneId: 'Europe/London',
      revision: 1,
      plannedStart: EventDate.day(CivilDate(2026, 10, 20)),
      plannedEnd: EventDate.day(CivilDate(2026, 10, 21)),
      memberships: [
        EventMembership(
          id: 'member-1',
          itemId: item.id,
          personId: meId,
          effectiveFrom: DateTime.utc(2026, 10, 20),
          revision: 1,
        ),
      ],
    );
    await store.saveEvent(
      SaveEventCommand(
        commandId: 'event-save',
        generation: store.generation,
        expectedRevision: null,
        event: event,
      ),
    );
    final inside = await store.record(
      commandId: 'inside',
      itemId: item.id,
      amount: '1',
      actualAt: DateTime.utc(2026, 10, 20, 8),
    );
    final outside = await store.record(
      commandId: 'outside',
      itemId: item.id,
      amount: '1',
      actualAt: DateTime.utc(2026, 10, 19, 8),
    );

    for (final record in [inside, outside]) {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final job = AttachmentJob(
        id: 'job-${record.id}',
        generation: store.generation,
        personId: meId,
        expectedPersonRevision: 1,
        targetKind: AttachmentTargetKind.record,
        targetId: record.id,
        targetRevision: record.revision,
        attachmentId: 'file-${record.id}',
        versionId: 'version-${record.id}',
        name: 'source-${record.id}.bin',
        createdAt: now,
      );
      await store.beginAttachment(
        BeginAttachmentCommand(commandId: 'begin-${record.id}', job: job),
      );
      await store.appendAttachmentChunk(
        commandId: 'chunk-${record.id}',
        jobId: job.id,
        generation: store.generation,
        offset: 0,
        bytes: bytes,
      );
      await store.publishAttachment(
        commandId: 'publish-${record.id}',
        jobId: job.id,
        generation: store.generation,
        inspection: AttachmentInspection(
          mediaKind: AttachmentMediaKind.other,
          byteCount: bytes.length,
          sha256: sha256.convert(bytes).toString(),
          mimeType: 'application/octet-stream',
        ),
      );
    }

    final capture = await store.captureTemplateReport(
      selection: selection(
        template: ReportTemplateId.r03EventReview,
        eventId: event.id,
      ).copyWith(includeAttachments: true),
      now: () => now,
    );
    final data = capture.snapshot.templateData;
    expect(data, isA<ReportEventData>());
    final review = data! as ReportEventData;
    expect(review.eventId, event.id);
    expect(review.ongoing, isTrue);
    expect(review.entries.length, 1);
    final member = review.members.single;
    expect(member.itemId, item.id);
    expect(member.administrations, 1);
    expect(member.useStatus, ReportUseStatus.noPeriod);
    expect(capture.snapshot.records.length, 1);
    expect(capture.snapshot.attachments.single.targetId, inside.id);
    expect(capture.pins.single.attachment.targetId, inside.id);
    await capture.releasePins!();
  });

  test('leaves R01 on the existing shared capture path', () async {
    await store.record(
      commandId: 'dose-1',
      itemId: item.id,
      amount: '1',
      actualAt: DateTime.utc(2026, 10, 20, 8),
    );
    final capture = await store.captureTemplateReport(
      selection: selection(template: ReportTemplateId.r01SubstanceSummary),
      now: () => now,
    );
    expect(capture.snapshot.templateData, isNull);
    expect(capture.snapshot.totals.recordCount, 1);
  });

  test(
    'refuses an event period that would cut off the recorded event',
    () async {
      final event = EventRecord(
        id: 'event-1',
        personId: meId,
        name: 'Example recorded course',
        eventType: 'Course',
        zoneId: 'Europe/London',
        revision: 1,
        plannedStart: EventDate.day(CivilDate(2026, 10, 17)),
        plannedEnd: EventDate.day(CivilDate(2026, 10, 19)),
        memberships: [
          EventMembership(
            id: 'member-1',
            itemId: item.id,
            personId: meId,
            effectiveFrom: DateTime.utc(2026, 10, 17),
            revision: 1,
          ),
        ],
      );
      await store.saveEvent(
        SaveEventCommand(
          commandId: 'event-save',
          generation: store.generation,
          expectedRevision: null,
          event: event,
        ),
      );
      await expectLater(
        store.captureTemplateReport(
          selection: selection(
            template: ReportTemplateId.r03EventReview,
            eventId: event.id,
          ),
          now: () => now,
        ),
        throwsA(
          isA<ReportSelectionFailure>().having(
            (error) => error.code,
            'code',
            'report_event_range',
          ),
        ),
      );
    },
  );

  test('fails truthfully for a missing event selection', () async {
    await expectLater(
      store.captureTemplateReport(
        selection: selection(template: ReportTemplateId.r03EventReview),
        now: () => now,
      ),
      throwsA(
        isA<ReportSelectionFailure>().having(
          (error) => error.code,
          'code',
          'report_event',
        ),
      ),
    );
    await expectLater(
      store.captureTemplateReport(
        selection: selection(
          template: ReportTemplateId.r03EventReview,
          eventId: 'missing',
        ),
        now: () => now,
      ),
      throwsA(
        isA<ReportSelectionFailure>().having(
          (error) => error.code,
          'code',
          'report_event_missing',
        ),
      ),
    );
  });
}

final class _HostFontLoader implements ReportFontLoader {
  const _HostFontLoader();
  @override
  Future<ReportFonts> load() async => ReportFonts(
    regular: pw.Font.helvetica(),
    bold: pw.Font.helveticaBold(),
    embedded: false,
  );
}
