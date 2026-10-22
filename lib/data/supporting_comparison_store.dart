part of 'record_store.dart';

/// Complete store-backed earlier-value selection for one viewed supporting
/// result.
///
/// The database filters candidates by the exact comparison identity and date,
/// then loads only the newest comparable day. No page cap or arbitrary record
/// lookback hides an older comparable result. The established domain function
/// still owns same-day ambiguity and exact change formatting, so its behaviour
/// remains the single comparison contract. The SQL reads current revisions only.
extension SupportingComparisonStore on RecordStore {
  /// Resolves one earlier comparison live. A correction, void, restore or new
  /// save refreshes the same stream; a lock or replaced dataset closes it.
  Stream<SupportingEarlierComparison> watchSupportingEarlierComparison({
    required String personId,
    required String recordId,
    required int recordRevision,
    required String resultId,
    required String displayZone,
  }) => _watch(
    () => supportingEarlierComparisonFor(
      personId: personId,
      recordId: recordId,
      recordRevision: recordRevision,
      resultId: resultId,
      displayZone: displayZone,
    ),
  );

  Future<SupportingEarlierComparison> supportingEarlierComparisonFor({
    required String personId,
    required String recordId,
    required int recordRevision,
    required String resultId,
    required String displayZone,
  }) async {
    _requireWritable();
    return _db.transaction(() async {
      final viewed = await supportingRecord(
        personId,
        recordId,
        revision: recordRevision,
      );
      if (viewed == null) {
        throw const CommandConflict('supporting_revision');
      }
      LabResultSnapshot? viewedResult;
      for (final candidate in viewed.snapshot.results) {
        if (candidate.id == resultId) {
          viewedResult = candidate;
          break;
        }
      }
      if (viewedResult == null) {
        return const SupportingEarlierComparison(
          status: SupportingEarlierStatus.incompatible,
        );
      }
      final date = viewed.snapshot.collectionDate;
      final viewedDay = switch (date.precision) {
        SupportingDatePrecision.day => date.civilDate,
        SupportingDatePrecision.exact =>
          DisplayTime().instant(date.instant!, displayZone).civilDate,
        SupportingDatePrecision.unknown ||
        SupportingDatePrecision.partial => null,
      };
      if (viewedDay == null) {
        return const SupportingEarlierComparison(
          status: SupportingEarlierStatus.incomplete,
        );
      }
      final key = SupportingComparisonKey.forResult(viewed, viewedResult);
      final exact = viewedResult.value.isExactNumeric;
      final qualitative =
          viewedResult.value.kind == SupportingValueKind.qualitative;
      if (!key.certain || !(exact || qualitative)) {
        return const SupportingEarlierComparison(
          status: SupportingEarlierStatus.incompatible,
        );
      }

      // Compare the effective source identities exactly as the domain key
      // does: a result override replaces the parent provenance as a whole, an
      // explicit identifier wins over saved source words, and nothing is
      // trimmed, case-folded or fuzzy-matched.
      String effective(String field) =>
          "(CASE WHEN json_type(r.snapshot,'\$.provenance')='object' "
          "THEN json_extract(r.snapshot,'\$.provenance.$field') "
          "ELSE json_extract(v.snapshot,'\$.snapshot.provenance.$field') END)";
      String identity(String idField, String textField) {
        final id = effective(idField), text = effective(textField);
        return "(CASE WHEN trim(COALESCE($id,''))<>'' THEN 'id:'||$id "
            "WHEN trim(COALESCE($text,''))<>'' THEN 'text:'||$text "
            'ELSE NULL END)';
      }

      final valueMatch = exact
          ? "r.value_kind='numeric' AND json_extract(r.snapshot,'\$.value.qualifier')='exact'"
          : "r.value_kind='qualitative'";
      final match =
          's.person=? AND s.voided=0 AND s.id<>? AND s.kind=? '
          'AND r.metric=? AND r.unit IS ? '
          'AND ${identity('laboratoryId', 'laboratoryName')} IS ? '
          'AND ${identity('methodId', 'methodText')} IS ? '
          'AND ${identity('specimenId', 'specimenText')} IS ? '
          'AND $valueMatch';
      final matchArgs = <Object?>[
        personId,
        recordId,
        viewed.kind.name,
        viewedResult.metricId,
        viewedResult.unit,
        key.laboratoryId,
        key.methodId,
        key.specimenId,
      ];
      const joins =
          ' FROM supporting_result r INDEXED BY supporting_result_metric'
          ' JOIN supporting_record s'
          ' ON s.id=r.record AND s.person=r.person AND s.revision=r.revision'
          ' JOIN supporting_revision v'
          ' ON v.record=s.id AND v.person=s.person AND v.revision=s.revision';

      // Only a strictly earlier exact instant may share the viewed display
      // day. A day-only viewed date cannot establish a clock, so its whole day
      // is excluded from the exact branch.
      final exactCap = date.precision == SupportingDatePrecision.exact
          ? date.instant!.microsecondsSinceEpoch
          : DisplayTime()
                .dayBounds(viewedDay, displayZone)
                .start
                .microsecondsSinceEpoch;
      final exactRows = await _rows(
        'SELECT s.id,s.collection_at AS at$joins WHERE $match '
        'AND s.collection_at IS NOT NULL AND s.collection_at<? '
        'ORDER BY s.collection_at DESC,s.id LIMIT 1',
        [...matchArgs, exactCap],
      );
      final civilRows = await _rows(
        'SELECT s.id,s.collection_day AS day$joins WHERE $match '
        'AND s.collection_at IS NULL AND s.collection_day IS NOT NULL '
        'AND s.collection_day<? '
        'ORDER BY s.collection_day DESC,s.id LIMIT 1',
        [...matchArgs, viewedDay.toString()],
      );
      final exactDay = exactRows.isEmpty
          ? null
          : DisplayTime()
                .instant(
                  DateTime.fromMicrosecondsSinceEpoch(
                    exactRows.single['at'] as int,
                    isUtc: true,
                  ),
                  displayZone,
                )
                .civilDate;
      final civilDay = civilRows.isEmpty
          ? null
          : CivilDate.parse(civilRows.single['day'] as String);

      // The domain algorithm always prefers the newest qualifying day and only
      // that day can make the pair ambiguous. Loading that one day keeps the
      // result complete without reading the metric's lifetime into memory.
      CivilDate? branchDay;
      var exactBranch = false;
      if (exactDay != null &&
          (civilDay == null || exactDay.compareTo(civilDay) > 0)) {
        branchDay = exactDay;
        exactBranch = true;
      } else if (civilDay != null &&
          (exactDay == null || civilDay.compareTo(exactDay) > 0)) {
        branchDay = civilDay;
      } else if (exactDay != null && exactDay == civilDay) {
        // An exact and a day-only candidate share the newest day. The domain
        // contract calls that pair ambiguous rather than inventing a clock.
        return const SupportingEarlierComparison(
          status: SupportingEarlierStatus.incomplete,
        );
      } else {
        return const SupportingEarlierComparison(
          status: SupportingEarlierStatus.none,
        );
      }

      final bounds = DisplayTime().dayBounds(branchDay, displayZone);
      final branch = exactBranch
          ? 's.collection_at IS NOT NULL AND s.collection_at>=? '
                'AND s.collection_at<? AND s.collection_at<?'
          : 's.collection_at IS NULL AND s.collection_day=?';
      final branchArgs = exactBranch
          ? <Object?>[
              bounds.start.microsecondsSinceEpoch,
              bounds.endExclusive.microsecondsSinceEpoch,
              exactCap,
            ]
          : <Object?>[branchDay.toString()];
      final rows = await _rows(
        'SELECT DISTINCT v.snapshot$joins WHERE $match AND $branch',
        [...matchArgs, ...branchArgs],
      );
      final candidates = [
        for (final row in rows)
          SupportingRevision.fromJson(
            _supportingObject(jsonDecode(row['snapshot'] as String)),
          ),
      ];
      _requireWritable();
      return supportingEarlierComparison(
        viewed: viewed,
        result: viewedResult,
        candidates: candidates,
        displayZone: displayZone,
      );
    });
  }
}
