part of 'record_store.dart';

/// Structured export capture.
///
/// This extension reads the selected adult's doses, supporting records and all
/// their saved revisions inside one transaction. Formatting, preview and
/// handoff then use only the returned immutable document. No live query is
/// repeated while a preview is reviewed or a file is delivered.
extension ExportRecordStore on RecordStore {
  Future<ExportDocument> captureExport(
    ExportSelection selection, {
    ExportCancellation? cancellation,
  }) async {
    // The app lock suspends reads that could expose record content.
    _requireWritable();
    selection.limits.check();
    cancellation?.throwIfCancelled();
    final zone = DisplayTime().resolveZone(selection.zoneId);
    if (zone.isFallback) throw const ExportUnavailable('export_zone');
    final start = DisplayTime().dayBounds(selection.fromDay, zone.zoneId);
    final end = DisplayTime().dayBounds(selection.beforeDay, zone.zoneId);

    return _db.transaction(() async {
      final person = await _rows('SELECT * FROM person WHERE id=?', [
        selection.personId,
      ]);
      if (person.isEmpty) throw const ExportUnavailable('export_person');
      final profile = _profile(person.single);
      final generatedAt = DateTime.now().toUtc();
      final doses = selection.includes(ExportContent.doses)
          ? await _captureDoses(selection, start.start, end.start, cancellation)
          : <ExportDoseRevision>[];
      final supporting = selection.includes(ExportContent.supporting)
          ? await _captureSupporting(
              selection,
              start.start,
              end.start,
              cancellation,
            )
          : <ExportSupportingRevision>[];
      cancellation?.throwIfCancelled();
      final undated = selection.includes(ExportContent.supporting)
          ? await _countUnpositionedSupporting(selection)
          : null;
      return ExportDocument(
        selection: selection,
        generatedAt: generatedAt,
        personName: profile.name,
        reportName: profile.reportName,
        recordSchemaVersion: _db.schemaVersion,
        doses: doses,
        supporting: supporting,
        undatedCollection: undated,
      );
    });
  }

  /// Bounded, snapshot-coherent count of this person's supporting records that
  /// cannot be positioned in the selected range.
  ///
  /// The dedicated partial index stops the scan at the bound; a reached bound
  /// is reported as uncounted instead of a fabricated number. The queried rows
  /// never enter the returned document.
  Future<ExportUndatedOmission> _countUnpositionedSupporting(
    ExportSelection selection,
  ) async {
    final rows = await _rows(
      'SELECT id FROM supporting_record WHERE person=? AND collection_at IS NULL AND collection_day IS NULL LIMIT ?',
      [selection.personId, selection.limits.maxSupportingRecords + 1],
    );
    return rows.length > selection.limits.maxSupportingRecords
        ? const ExportUndatedOmission.uncounted()
        : ExportUndatedOmission.counted(rows.length);
  }

  Future<List<ExportDoseRevision>> _captureDoses(
    ExportSelection selection,
    DateTime start,
    DateTime endExclusive,
    ExportCancellation? cancellation,
  ) async {
    final limits = selection.limits;
    final current = await _rows(
      'SELECT id,revision FROM administration WHERE person=? AND actual>=? AND actual<? ORDER BY actual DESC,id LIMIT ?',
      [
        selection.personId,
        start.microsecondsSinceEpoch,
        endExclusive.microsecondsSinceEpoch,
        limits.maxDoseRecords + 1,
      ],
    );
    if (current.length > limits.maxDoseRecords) {
      throw const ExportLimitException('export_dose_records');
    }
    final currentRevisions = <String, int>{
      for (final row in current) row['id'] as String: row['revision'] as int,
    };
    final result = <Map<String, Object?>>[];
    final ids = currentRevisions.keys.toList();
    for (var offset = 0; offset < ids.length; offset += limits.chunk) {
      cancellation?.throwIfCancelled();
      final chunk = ids.skip(offset).take(limits.chunk).toList();
      final marks = List.filled(chunk.length, '?').join(',');
      final rows = await _rows(
        '''SELECT a.id,a.item,a.actual AS current_actual,a.revision AS current_revision,r.*,s.source,c.catalogue_snapshot,q.numerator AS actual_n,q.denominator AS actual_d,q.unit AS actual_unit,q.entered AS original_entry,q.entered_unit AS original_unit,q.strength AS quantity_strength,q.replacement AS quantity_replacement,x.snapshot AS product_snapshot,(SELECT label FROM site_event WHERE record=a.id AND person=a.person AND record_revision<=r.revision ORDER BY sequence DESC LIMIT 1) AS site_label,(SELECT action FROM combined_member WHERE record=a.id AND person=a.person) AS combined_action FROM administration a JOIN revision r ON r.record=a.id AND r.person=a.person LEFT JOIN revision_source s ON s.record=r.record AND s.revision=r.revision LEFT JOIN revision_catalogue c ON c.record=r.record AND c.revision=r.revision LEFT JOIN revision_quantity q ON q.record=r.record AND q.revision=r.revision LEFT JOIN revision_product x ON x.record=r.record AND x.revision=r.revision WHERE a.person=? AND a.id IN ($marks) LIMIT ?''',
        [
          selection.personId,
          ...chunk,
          limits.maxDoseRevisions - result.length + 1,
        ],
      );
      result.addAll(rows);
      if (result.length > limits.maxDoseRevisions) {
        throw const ExportLimitException('export_dose_revisions');
      }
    }
    result.sort((a, b) {
      final time = (b['current_actual'] as int).compareTo(
        a['current_actual'] as int,
      );
      if (time != 0) return time;
      final id = (a['id'] as String).compareTo(b['id'] as String);
      if (id != 0) return id;
      return (a['revision'] as int).compareTo(b['revision'] as int);
    });
    final revisions = <ExportDoseRevision>[];
    final details = selection.includeNotes
        ? await _itemDetailsFor(
            result.map((row) => row['item'] as String),
            selection.personId,
          )
        : const <String, SubstanceDetail>{};
    var estimated = 4096;
    for (final row in result) {
      cancellation?.throwIfCancelled();
      final detail = details[row['item'] as String];
      final revision = ExportDoseRevision.fromRecord(
        _record(row),
        currentRevision: row['current_revision'] as int,
        itemInstructions: detail?.instructions,
        itemNotes: detail?.notes,
        includeNotes: selection.includeNotes,
      );
      estimated += utf8.encode(jsonEncode(revision.toJson())).length + 2;
      if (estimated > limits.maxBytes) {
        throw const ExportLimitException('export_bytes');
      }
      revisions.add(revision);
    }
    return revisions;
  }

  Future<List<ExportSupportingRevision>> _captureSupporting(
    ExportSelection selection,
    DateTime start,
    DateTime endExclusive,
    ExportCancellation? cancellation,
  ) async {
    final limits = selection.limits;
    final current = await _rows(
      'SELECT id,revision FROM (SELECT id,revision,collection_day,collection_at FROM supporting_record WHERE person=? AND collection_at IS NOT NULL AND collection_at>=? AND collection_at<? UNION ALL SELECT id,revision,collection_day,collection_at FROM supporting_record WHERE person=? AND collection_at IS NULL AND collection_day IS NOT NULL AND collection_day>=? AND collection_day<?) ORDER BY collection_day DESC,collection_at DESC,id LIMIT ?',
      [
        selection.personId,
        start.microsecondsSinceEpoch,
        endExclusive.microsecondsSinceEpoch,
        selection.personId,
        selection.fromDay.toString(),
        selection.beforeDay.toString(),
        limits.maxSupportingRecords + 1,
      ],
    );
    if (current.length > limits.maxSupportingRecords) {
      throw const ExportLimitException('export_supporting_records');
    }
    final currentRevisions = <String, int>{
      for (final row in current) row['id'] as String: row['revision'] as int,
    };
    final ids = currentRevisions.keys.toList();
    final result = <ExportSupportingRevision>[];
    final maxBytes = limits.maxBytes;
    var estimated = 4096;
    var results = 0;
    for (var offset = 0; offset < ids.length; offset += limits.chunk) {
      cancellation?.throwIfCancelled();
      final chunk = ids.skip(offset).take(limits.chunk).toList();
      final marks = List.filled(chunk.length, '?').join(',');
      String? afterId;
      var afterRevision = 0;
      while (true) {
        cancellation?.throwIfCancelled();
        final rows = await _rows(
          'SELECT s.id,v.snapshot,v.revision,s.revision AS current_revision FROM supporting_record s JOIN supporting_revision v ON v.record=s.id AND v.person=s.person WHERE s.person=? AND s.id IN ($marks) ${afterId == null ? '' : 'AND (s.id>? OR (s.id=? AND v.revision>?))'} ORDER BY s.id,v.revision LIMIT ?',
          [
            selection.personId,
            ...chunk,
            if (afterId != null) ...[afterId, afterId, afterRevision],
            limits.chunk,
          ],
        );
        for (final row in rows) {
          cancellation?.throwIfCancelled();
          estimated += utf8.encode(row['snapshot'] as String).length + 256;
          if (estimated > maxBytes) {
            throw const ExportLimitException('export_bytes');
          }
          final revision = SupportingRevision.fromJson(
            _supportingObject(jsonDecode(row['snapshot'] as String)),
          );
          results += revision.snapshot.results.length;
          if (results > limits.maxSupportingResults) {
            throw const ExportLimitException('export_supporting_results');
          }
          result.add(
            ExportSupportingRevision.fromRevision(
              revision,
              currentRevision: row['current_revision'] as int,
              includeNotes: selection.includeNotes,
            ),
          );
        }
        if (rows.length < limits.chunk) break;
        afterId = rows.last['id'] as String;
        afterRevision = rows.last['revision'] as int;
      }
    }
    // Group each record's revisions in revision order while keeping the
    // current-date ordering captured above.
    final order = <String, int>{for (var i = 0; i < ids.length; i++) ids[i]: i};
    result.sort((a, b) {
      final owner = order[a.recordId]!.compareTo(order[b.recordId]!);
      return owner != 0 ? owner : a.revision.compareTo(b.revision);
    });
    return result;
  }
}
