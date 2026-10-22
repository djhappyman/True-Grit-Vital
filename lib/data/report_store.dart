part of 'record_store.dart';

/// Captured source plus the attachment pins that keep referenced versions alive
/// until generation and validation end. Always release [pins] in a finally.
final class ReportCapture {
  ReportCapture({required this.snapshot, required this.pins, this.releasePins});
  final ReportSnapshot snapshot;
  final List<AttachmentPin> pins;
  final Future<void> Function()? releasePins;
}

extension ReportStore on RecordStore {
  /// Reads one coherent SQLite statement of current revisions inside the
  /// selected period. The statement is the cutoff: later writes are not mixed
  /// into this snapshot.
  ///
  /// [maxRecords] bounds R01 summary work. Exceeding it returns a truthful
  /// limit failure instead of silently truncating totals.
  ///
  /// [maxSupportingOmissions] is a small internal counting budget for records
  /// excluded by their unknown or partial collection date. Exceeding it
  /// reports the omission as uncounted, never a fabricated zero.
  Future<ReportCapture> captureReport({
    required ReportSelection selection,
    required DateTime Function() now,
    ReportCancellation cancellation = const NeverCancelled(),
    int maxRecords = 10000,
    int maxAttachments = 50,
    int maxSupportingOmissions = 500,
  }) async {
    _requireWritable();
    return _db.transaction(
      () => _captureReport(
        selection: selection,
        now: now,
        cancellation: cancellation,
        maxRecords: maxRecords,
        maxAttachments: maxAttachments,
        maxSupportingOmissions: maxSupportingOmissions,
      ),
    );
  }

  Future<ReportCapture> _captureReport({
    required ReportSelection selection,
    required DateTime Function() now,
    required ReportCancellation cancellation,
    required int maxRecords,
    required int maxAttachments,
    required int maxSupportingOmissions,
  }) async {
    if (maxRecords < 1 ||
        maxRecords > 100000 ||
        maxAttachments < 0 ||
        maxSupportingOmissions < 0 ||
        maxSupportingOmissions > 10000) {
      throw const ReportSelectionFailure('report_limit');
    }
    if (cancellation.isCancelled) throw const ReportCancelled();
    final profile = await profileById(selection.personId);
    if (profile == null) {
      throw const ReportSelectionFailure('report_person_missing');
    }
    if (profile.isArchived) {
      throw const ReportSelectionFailure('report_person_archived');
    }
    final display = DisplayTime();
    final zone = display.resolveZone(selection.displayZone);
    if (zone.isFallback) {
      throw const ReportSelectionFailure('report_zone_unavailable');
    }
    final start = display.dayBounds(selection.fromDate, zone.zoneId).start;
    final before = display.dayBounds(selection.beforeDate, zone.zoneId).start;
    if (!before.isAfter(start)) {
      throw const ReportSelectionFailure('report_range');
    }
    final generatedAt = now().toUtc();
    final selectedItems = selection.itemIds.toList()..sort();
    final itemClause = selectedItems.isEmpty
        ? ''
        : ' AND a.item IN (${List.filled(selectedItems.length, '?').join(',')})';
    if (cancellation.isCancelled) throw const ReportCancelled();
    final rows = await _rows(
      '${RecordStore._current} WHERE a.person=? AND a.actual>=? AND a.actual<? AND r.voided=0$itemClause ORDER BY a.actual,a.id LIMIT ?',
      [
        selection.personId,
        start.microsecondsSinceEpoch,
        before.microsecondsSinceEpoch,
        ...selectedItems,
        maxRecords + 1,
      ],
    );
    if (cancellation.isCancelled) throw const ReportCancelled();
    if (rows.length > maxRecords) {
      throw const ReportSelectionFailure('report_source_limit');
    }
    final records = <ReportRecord>[];
    final stockSources = selection.includeStock
        ? await _reportStockSources(
            selection.personId,
            rows.map((row) => row['id'] as String),
          )
        : const <String, ReportStockSource>{};
    final planInstructions = selection.includeNotes
        ? await _savedPlanInstructions(
            selection.personId,
            rows.map((row) => row['id'] as String),
            records: true,
          )
        : const <String, SavedPlanInstruction>{};
    for (final row in rows) {
      final record = _record(row);
      if (record.personId != selection.personId) {
        throw const ReportSelectionFailure('report_owner');
      }
      records.add(
        ReportRecord.fromUseRecord(
          record,
          includeNotes: selection.includeNotes,
          stockSource: stockSources[record.id],
          planInstruction: planInstructions[record.id],
        ),
      );
      if (cancellation.isCancelled) throw const ReportCancelled();
    }

    final supporting = <ReportSupportingEntry>[];
    var supportingTruncated = false;
    ReportSupportingOmission? supportingOmission;
    if (selection.includeSupporting) {
      final page = await supportingRecords(
        SupportingQuery(
          personId: selection.personId,
          dateBasis: SupportingDateBasis.collection,
          fromDate: selection.fromDate,
          beforeDate: selection.beforeDate,
          includeUnknownDates: false,
          includeVoided: false,
          limit: 50,
          displayZone: zone.zoneId,
        ),
      );
      supportingTruncated = page.hasMore;
      for (final revision in page.entries) {
        final snapshot = revision.snapshot;
        supporting.add(
          ReportSupportingEntry(
            id: revision.id.id,
            title: snapshot.title,
            kind: snapshot.kind,
            collectionDate: snapshot.collectionDate,
            reportDate: snapshot.reportDate,
            notes: selection.includeNotes ? snapshot.notes : null,
            accessionNumber: snapshot.provenance.accessionNumber,
            reportIdentifier: snapshot.provenance.reportIdentifier,
            values: [
              for (final result in snapshot.results)
                ReportSupportingValue(
                  name: result.markerName,
                  value: result.value.originalText ?? 'Unknown',
                  unit: result.unit,
                  referenceRange: result.referenceRange?.originalText,
                  category: result.category,
                  accessionNumber: (result.provenance ?? snapshot.provenance)
                      .accessionNumber,
                  reportIdentifier: (result.provenance ?? snapshot.provenance)
                      .reportIdentifier,
                ),
            ],
          ),
        );
      }
      if (cancellation.isCancelled) throw const ReportCancelled();
      // The same snapshot reads one bounded count of current records that the
      // selected collection-date window cannot position. The partial index
      // stops at the bound; only identities are read, never content.
      final unpositioned = await _rows(
        'SELECT id FROM supporting_record WHERE person=? AND voided=0 AND collection_at IS NULL AND collection_day IS NULL LIMIT ?',
        [selection.personId, maxSupportingOmissions + 1],
      );
      supportingOmission = unpositioned.length > maxSupportingOmissions
          ? const ReportSupportingOmission.uncounted()
          : ReportSupportingOmission.counted(unpositioned.length);
      if (cancellation.isCancelled) throw const ReportCancelled();
    }

    final pins = <AttachmentPin>[];
    final attachmentRefs = <ReportAttachmentRef>[];
    final itemDetails = <String, ReportItemDetail>{};
    if (selection.includeNotes) {
      final captured = await _itemDetailsFor(
        records.map((record) => record.itemId),
        selection.personId,
      );
      for (final entry in captured.entries) {
        itemDetails[entry.key] = ReportItemDetail(
          instructions: entry.value.instructions,
          notes: entry.value.notes,
        );
      }
      if (cancellation.isCancelled) throw const ReportCancelled();
    }
    if (selection.includeAttachments) {
      final itemIds = records.map((record) => record.itemId).toSet();
      final recordIds = records.map((record) => record.id).toSet();
      final supportingIds = supporting.map((entry) => entry.id).toSet();
      final candidates = <AttachmentRecord>[];
      var offset = 0;
      while (candidates.length <= maxAttachments) {
        final page = await attachments(
          personId: selection.personId,
          limit: 100,
          offset: offset,
        );
        for (final attachment in page) {
          final relevant = switch (attachment.targetKind) {
            AttachmentTargetKind.record => recordIds.contains(
              attachment.targetId,
            ),
            AttachmentTargetKind.item => itemIds.contains(attachment.targetId),
            AttachmentTargetKind.supporting => supportingIds.contains(
              attachment.targetId,
            ),
          };
          if (relevant) candidates.add(attachment);
        }
        if (page.length < 100 || candidates.length > maxAttachments) break;
        offset += 100;
        if (cancellation.isCancelled) throw const ReportCancelled();
      }
      if (candidates.length > maxAttachments) {
        throw const ReportSelectionFailure('report_attachment_limit');
      }
      try {
        for (final attachment in candidates) {
          if (cancellation.isCancelled) throw const ReportCancelled();
          final pin = await pinAttachment(
            id: attachment.id,
            generation: attachment.generation,
            expectedRevision: attachment.revision,
            purpose: 'report',
            // The lease protects live files; its lifetime is independent of
            // the timestamp captured for the report.
            expiresAt: DateTime.now().toUtc().add(const Duration(hours: 24)),
          );
          pins.add(pin);
          attachmentRefs.add(
            ReportAttachmentRef(
              id: attachment.id,
              name: attachment.name,
              versionId: attachment.versionId,
              sha256: attachment.inspection?.sha256 ?? '',
              byteCount: attachment.inspection?.byteCount ?? 0,
              pinned: true,
              targetKind: attachment.targetKind.name,
              targetId: attachment.targetId,
            ),
          );
        }
      } catch (_) {
        await _releaseReportPins(pins);
        rethrow;
      }
    }

    try {
      final currentProfile = await profileById(selection.personId);
      final currentGeneration = (await _rows('SELECT generation FROM dataset'))
          .single['generation'];
      if (currentProfile == null ||
          currentProfile.revision != profile.revision ||
          currentGeneration != generation) {
        throw const ReportSelectionFailure('report_source_changed');
      }
      final snapshot = ReportSnapshot.build(
        selection: selection,
        cutoff: ReportCutoff(
          generatedAt: generatedAt,
          datasetGeneration: generation,
          personRevision: profile.revision,
          schemaVersion: _db.schemaVersion,
        ),
        person: ReportPerson(
          id: profile.id,
          name: profile.name,
          reportName: profile.reportName,
          relationship: profile.relationship,
        ),
        records: records,
        supporting: supporting,
        attachments: attachmentRefs,
        supportingTruncated: supportingTruncated,
        itemDetails: itemDetails,
        supportingOmission: supportingOmission,
      );
      return ReportCapture(
        snapshot: snapshot,
        pins: List.unmodifiable(pins),
        releasePins: () => _releaseReportPins(pins),
      );
    } catch (_) {
      await _releaseReportPins(pins);
      rethrow;
    }
  }

  /// The exact container linked by the record's own `actualUse` movement.
  ///
  /// The lookup never derives a container from balances, strength or another
  /// movement. A missing link stays absent. The movement's record is unique, so
  /// a defensive duplicate removes the entry rather than choosing a container.
  Future<Map<String, ReportStockSource>> _reportStockSources(
    String personId,
    Iterable<String> recordIds,
  ) async {
    final ids = recordIds.toList()..sort();
    final result = <String, ReportStockSource>{};
    final seen = <String>{};
    const chunkSize = 400;
    for (var offset = 0; offset < ids.length; offset += chunkSize) {
      final end = offset + chunkSize < ids.length
          ? offset + chunkSize
          : ids.length;
      final chunk = ids.sublist(offset, end);
      final marks = List.filled(chunk.length, '?').join(',');
      final rows = await _rows(
        '''SELECT sm.record AS record_id,sc.id AS container_id,sc.label AS container_label,sc.unit AS container_unit,sc.lot AS container_lot,sc.expiry_date AS container_expiry,sc.capacity_n AS capacity_n,sc.capacity_d AS capacity_d FROM stock_movement sm JOIN stock_container sc ON sc.id=sm.container AND sc.person=sm.person WHERE sm.person=? AND sm.kind='actualUse' AND sm.record IN ($marks) ORDER BY sm.record''',
        [personId, ...chunk],
      );
      for (final row in rows) {
        final recordId = row['record_id'] as String;
        if (!seen.add(recordId)) {
          result.remove(recordId);
          continue;
        }
        result[recordId] = ReportStockSource(
          containerId: row['container_id'] as String,
          label: row['container_label'] as String,
          unit: row['container_unit'] as String,
          lot: row['container_lot'] as String?,
          expiryDate: switch (row['container_expiry']) {
            final String value when value.isNotEmpty => CivilDate.parse(value),
            _ => null,
          },
          capacity: _storedPair(row, 'capacity_n', 'capacity_d'),
        );
      }
    }
    return result;
  }

  Future<void> _releaseReportPins(Iterable<AttachmentPin> pins) async {
    for (final pin in pins) {
      try {
        await releaseAttachmentPin(pin);
      } catch (_) {
        // The pin expires after 24 hours; the capture failure remains primary.
      }
    }
  }
}
