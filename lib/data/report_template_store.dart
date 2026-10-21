part of 'record_store.dart';

/// Captures the template-specific body for R02 and R03 through the same
/// person-scoped report snapshot, pins and cutoff used by R01.
///
/// The base capture reads one coherent set of current revisions. Template
/// source reads (plan occurrences, skipped actions, event memberships) use
/// the same SQLite transaction and are bounded; exceeding a bound is a typed failure,
/// never a silent short report.
extension ReportTemplateStore on RecordStore {
  Future<ReportCapture> captureTemplateReport({
    required ReportSelection selection,
    required DateTime Function() now,
    ReportCancellation cancellation = const NeverCancelled(),
    int maxRecords = 10000,
    int maxSkips = 5000,
    int maxPlanRows = 20000,
    int maxHistoryEntries = 10000,
  }) async {
    _requireWritable();
    return _db.transaction(
      () => _captureTemplateReport(
        selection: selection,
        now: now,
        cancellation: cancellation,
        maxRecords: maxRecords,
        maxSkips: maxSkips,
        maxPlanRows: maxPlanRows,
        maxHistoryEntries: maxHistoryEntries,
      ),
    );
  }

  Future<ReportCapture> _captureTemplateReport({
    required ReportSelection selection,
    required DateTime Function() now,
    required ReportCancellation cancellation,
    required int maxRecords,
    required int maxSkips,
    required int maxPlanRows,
    required int maxHistoryEntries,
  }) async {
    if (selection.template == ReportTemplateId.r01SubstanceSummary) {
      return captureReport(
        selection: selection,
        now: now,
        cancellation: cancellation,
        maxRecords: maxRecords,
      );
    }
    final base = await captureReport(
      selection: selection,
      now: now,
      cancellation: cancellation,
      maxRecords: maxRecords,
    );
    try {
      final zone = selection.displayZone;
      final display = DisplayTime();
      final start = display.dayBounds(selection.fromDate, zone).start;
      final before = display.dayBounds(selection.beforeDate, zone).start;
      final itemList = await _reportItems(
        selection.personId,
        cancellation: cancellation,
      );
      final items = [
        for (final item in itemList)
          ReportItemDescriptor(
            itemId: item.id,
            name: item.name,
            form: item.form,
            type: item.type,
            unit: item.unit,
          ),
      ];
      if (cancellation.isCancelled) throw const ReportCancelled();

      switch (selection.template) {
        case ReportTemplateId.r01SubstanceSummary:
          return base;
        case ReportTemplateId.r02DetailedHistory:
          final skipped = selection.includeSkipped
              ? await _skippedEntries(
                  personId: selection.personId,
                  from: start,
                  before: before,
                  zone: zone,
                  maxSkips: maxSkips,
                  cancellation: cancellation,
                )
              : const <SkippedTimelineEntry>[];
          final plan = selection.includeUnrecorded
              ? await _planRows(
                  personId: selection.personId,
                  from: selection.fromDate,
                  before: selection.beforeDate,
                  zone: zone,
                  maxRows: maxPlanRows,
                  cancellation: cancellation,
                )
              : const _PlanRows(rows: [], complete: true, issue: null);
          final data = ReportHistoryData.build(
            snapshot: base.snapshot,
            items: items,
            skipped: skipped,
            dailyRows: plan.rows,
            planCoverageComplete: plan.complete,
            planIssue: plan.issue,
            maxEntries: maxHistoryEntries,
          );
          return ReportCapture(
            snapshot: base.snapshot.withTemplateData(data),
            pins: base.pins,
            releasePins: base.releasePins,
          );
        case ReportTemplateId.r03EventReview:
          final eventId = selection.eventId;
          if (eventId == null) {
            throw const ReportSelectionFailure('report_event');
          }
          final event = await eventById(eventId);
          if (event == null) {
            throw const ReportSelectionFailure('report_event_missing');
          }
          if (event.personId != selection.personId) {
            throw const ReportSelectionFailure('report_owner');
          }
          if (!eventSelectionCovers(event, selection)) {
            throw const ReportSelectionFailure('report_event_range');
          }
          if (cancellation.isCancelled) throw const ReportCancelled();
          const pageSize = 500;
          final actuals = <UseRecord>[];
          var offset = 0;
          while (true) {
            if (cancellation.isCancelled) throw const ReportCancelled();
            final page = await eventActuals(
              [eventId],
              limit: pageSize,
              offset: offset,
            );
            actuals.addAll(page);
            if (actuals.length > maxRecords) {
              throw const ReportSelectionFailure('report_source_limit');
            }
            if (page.length < pageSize) break;
            offset += pageSize;
          }
          final actualIds = {for (final record in actuals) record.id};
          final scopedRecords = [
            for (final record in base.snapshot.records)
              if (actualIds.contains(record.id)) record,
          ];
          final recordIds = scopedRecords.map((record) => record.id).toSet();
          final itemIds = scopedRecords.map((record) => record.itemId).toSet();
          final scopedAttachments = base.snapshot.attachments
              .where(
                (attachment) => switch (attachment.targetKind) {
                  'record' => recordIds.contains(attachment.targetId),
                  'item' => itemIds.contains(attachment.targetId),
                  'supporting' => selection.includeSupporting,
                  _ => false,
                },
              )
              .toList();
          final attachmentIds = scopedAttachments
              .map((attachment) => attachment.id)
              .toSet();
          await _releaseReportPins(
            base.pins.where(
              (pin) => !attachmentIds.contains(pin.attachment.id),
            ),
          );
          final scopedItemIds = scopedRecords
              .map((record) => record.itemId)
              .toSet();
          final snapshot = ReportSnapshot.build(
            selection: selection,
            cutoff: base.snapshot.cutoff,
            person: base.snapshot.person,
            records: scopedRecords,
            supporting: base.snapshot.supporting,
            attachments: scopedAttachments,
            supportingTruncated: base.snapshot.supportingTruncated,
            itemDetails: {
              for (final entry in base.snapshot.itemDetails.entries)
                if (scopedItemIds.contains(entry.key)) entry.key: entry.value,
            },
            supportingOmission: base.snapshot.supportingOmission,
          );
          final skipped = await _skippedEntries(
            personId: selection.personId,
            from: start,
            before: before,
            zone: zone,
            maxSkips: maxSkips,
            cancellation: cancellation,
          );
          final plan = await _planRows(
            personId: selection.personId,
            from: selection.fromDate,
            before: selection.beforeDate,
            zone: zone,
            maxRows: maxPlanRows,
            cancellation: cancellation,
          );
          final clock = IanaClock();
          var scopeComplete = plan.complete;
          bool inEvent(String itemId, DateTime at) {
            try {
              return event.includes(
                ownerId: selection.personId,
                itemId: itemId,
                actualAt: at,
                clock: clock,
              );
            } catch (_) {
              scopeComplete = false;
              return false;
            }
          }

          final eventSkips = [
            for (final skip in skipped)
              if (inEvent(skip.itemId, skip.occurredAt)) skip,
          ];
          final eventRows = [
            for (final row in plan.rows)
              if (row.plannedCount - row.takenCount - row.skippedCount > 0 &&
                  inEvent(
                    row.expectation.itemId,
                    row.expectation.instant ??
                        DisplayTime()
                            .dayBounds(
                              row.expectation.effectiveDate ??
                                  row.expectation.identity.originalDate,
                              row.expectation.zoneId,
                            )
                            .start,
                  ))
                row,
          ];
          var periodsComplete = true;
          final periods = <RecordedUsePeriod>[];
          final memberItems = event.memberships
              .map((membership) => membership.itemId)
              .toSet();
          for (final itemId in memberItems) {
            if (selection.itemIds.isNotEmpty &&
                !selection.itemIds.contains(itemId)) {
              continue;
            }
            if (cancellation.isCancelled) throw const ReportCancelled();
            try {
              final rows = await _rows(
                'SELECT snapshot FROM use_period WHERE person=? AND item=? ORDER BY id LIMIT ?',
                [selection.personId, itemId, 10001 - periods.length],
              );
              if (rows.length + periods.length > 10000) {
                periodsComplete = false;
                break;
              }
              periods.addAll(
                rows.map(
                  (row) => RecordedUsePeriod.fromJson(
                    _eventObject(row['snapshot'] as String),
                  ),
                ),
              );
            } catch (_) {
              periodsComplete = false;
            }
          }
          final data = ReportEventData.build(
            snapshot: snapshot,
            event: event,
            items: items,
            usePeriods: periods,
            skipped: eventSkips,
            unresolved: eventRows,
            usePeriodsComplete: periodsComplete,
            scopeComplete: scopeComplete,
            maxEntries: maxHistoryEntries,
          );
          return ReportCapture(
            snapshot: snapshot.withTemplateData(data),
            pins: base.pins
                .where((pin) => attachmentIds.contains(pin.attachment.id))
                .toList(),
            releasePins: base.releasePins,
          );
      }
    } catch (_) {
      await _releaseReportPins(base.pins);
      rethrow;
    }
  }

  Future<List<SubstanceItem>> _reportItems(
    String personId, {
    required ReportCancellation cancellation,
  }) async {
    const pageSize = 500;
    final items = <SubstanceItem>[];
    var offset = 0;
    while (true) {
      if (cancellation.isCancelled) throw const ReportCancelled();
      final page = await this.items(
        scope: FeedScope.person(personId),
        limit: pageSize,
        offset: offset,
      );
      items.addAll(page);
      if (items.length > 5000) {
        throw const ReportSelectionFailure('report_item_limit');
      }
      if (page.length < pageSize) return items;
      offset += pageSize;
    }
  }

  Future<List<SkippedTimelineEntry>> _skippedEntries({
    required String personId,
    required DateTime from,
    required DateTime before,
    required String zone,
    required int maxSkips,
    required ReportCancellation cancellation,
  }) async {
    final entries = <SkippedTimelineEntry>[];
    TimelineQuery query = TimelineQuery(
      filter: TimelineFilter(
        scope: FeedScope.person(personId),
        fromInstant: from,
        beforeInstant: before,
        status: TimelineStatus.skipped,
      ),
      displayZone: zone,
      limit: TimelineLimits.maxPageSize,
    );
    while (true) {
      if (cancellation.isCancelled) throw const ReportCancelled();
      final page = await timeline(query);
      for (final entry in page.entries) {
        if (entry is SkippedTimelineEntry) entries.add(entry);
      }
      if (entries.length > maxSkips) {
        throw const ReportSelectionFailure('report_skip_limit');
      }
      final next = page.next;
      if (next == null) return entries;
      query = TimelineQuery(
        filter: query.filter,
        displayZone: zone,
        limit: TimelineLimits.maxPageSize,
        cursor: next,
      );
    }
  }

  Future<_PlanRows> _planRows({
    required String personId,
    required CivilDate from,
    required CivilDate before,
    required String zone,
    required int maxRows,
    required ReportCancellation cancellation,
  }) async {
    final rows = <DailyRow>[];
    var complete = true;
    String? issue;
    var cursor = from;
    while (cursor.compareTo(before) < 0) {
      if (cancellation.isCancelled) throw const ReportCancelled();
      var end = cursor.addDays(366);
      if (end.compareTo(before) > 0) end = before;
      final page = await dailyRows(
        scope: FeedScope.person(personId),
        from: cursor,
        toExclusive: end,
        observedZone: zone,
        maxPlans: 1000,
        maxRows: maxRows,
      );
      rows.addAll(page.rows);
      complete = complete && page.complete;
      issue ??= page.issue?.name;
      if (rows.length > maxRows) {
        throw const ReportSelectionFailure('report_plan_limit');
      }
      cursor = end;
    }
    return _PlanRows(rows: rows, complete: complete, issue: issue);
  }
}

final class _PlanRows {
  const _PlanRows({
    required this.rows,
    required this.complete,
    required this.issue,
  });
  final List<DailyRow> rows;
  final bool complete;
  final String? issue;
}
