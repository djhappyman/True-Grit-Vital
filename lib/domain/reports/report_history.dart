import '../history/display_time.dart';
import '../history/timeline_entry.dart';
import '../records.dart';
import '../scheduling/daily_plan.dart';
import '../scheduling/stored_daily.dart';
import '../stock/exact_amount.dart';
import 'report_model.dart';
import 'report_selection.dart';
import 'report_template_data.dart';

/// One ledger row. Recorded, corrected, skipped and not-recorded states stay
/// separate; a skipped or unrecorded row never carries an amount.
enum ReportLedgerStatus { recorded, corrected, skipped, notRecorded }

/// One captured ledger row for R02.
///
/// [occurredAt] is the actual taken time for administrations and the planned
/// time for skipped or not-recorded rows. [entryAt] is when the administration
/// was saved, never a substitute for the taken time.
final class ReportLedgerEntry {
  ReportLedgerEntry({
    required this.id,
    required this.itemId,
    required this.name,
    required this.form,
    required this.type,
    required this.unit,
    required this.status,
    required this.occurredAt,
    required this.dateOnly,
    required this.timeNeedsReview,
    this.amount,
    this.product,
    this.entryAt,
    this.revision = 0,
    this.source = RecordSource.unspecified,
    this.planName,
    this.site,
    this.notes,
    this.contextTags = const [],
    this.identityComplete = true,
  }) {
    if (id.isEmpty ||
        itemId.isEmpty ||
        name.trim().isEmpty ||
        !occurredAt.isUtc ||
        (status == ReportLedgerStatus.skipped ||
                status == ReportLedgerStatus.notRecorded) &&
            amount != null ||
        status != ReportLedgerStatus.skipped &&
            status != ReportLedgerStatus.notRecorded &&
            amount == null) {
      throw const ReportSelectionFailure('report_history_entry');
    }
  }

  /// Current-revision administration. A revision above one is a correction.
  factory ReportLedgerEntry.fromRecord(ReportRecord record) =>
      ReportLedgerEntry(
        id: 'r:${record.id}',
        itemId: record.itemId,
        name: record.name,
        form: record.form,
        type: record.type,
        unit: record.unit,
        status: record.revision > 1
            ? ReportLedgerStatus.corrected
            : ReportLedgerStatus.recorded,
        occurredAt: record.actualAt,
        dateOnly: false,
        timeNeedsReview: false,
        amount: record.amount,
        product: record.product,
        entryAt: record.enteredAt,
        revision: record.revision,
        source: record.source,
        site: record.site,
        notes: record.notes,
        contextTags: record.contextTags,
      );
  final String id, itemId, name, form, type, unit;
  final ReportLedgerStatus status;
  final DateTime occurredAt;
  final bool dateOnly, timeNeedsReview, identityComplete;
  final ExactAmount? amount;
  final ReportProduct? product;
  final DateTime? entryAt;
  final int revision;
  final RecordSource source;
  final String? planName, site;
  final String? notes;
  final List<String> contextTags;

  String get typeLabel => type.trim().isEmpty ? 'Uncategorised' : type;
}

/// Captured R02 body. Totals are not merged across unlike units or product
/// strengths; the ledger itself is never silently truncated.
final class ReportHistoryData implements ReportTemplateData {
  ReportHistoryData._({
    required Iterable<ReportLedgerEntry> entries,
    required this.planCoverageComplete,
    required this.plansTruncated,
    required this.planIssue,
    required this.itemCoverageComplete,
  }) : entries = List.unmodifiable(entries);
  factory ReportHistoryData.build({
    required ReportSnapshot snapshot,
    Iterable<ReportItemDescriptor> items = const [],
    Iterable<SkippedTimelineEntry> skipped = const [],
    Iterable<DailyRow> dailyRows = const [],
    bool planCoverageComplete = true,
    bool plansTruncated = false,
    String? planIssue,
    bool itemCoverageComplete = true,
    int maxEntries = 10000,
  }) {
    if (snapshot.selection.template != ReportTemplateId.r02DetailedHistory) {
      throw const ReportSelectionFailure('report_template_data');
    }
    if (maxEntries < 1 || maxEntries > 100000) {
      throw const ReportSelectionFailure('report_limit');
    }
    final personId = snapshot.selection.personId;
    final descriptors = {for (final item in items) item.itemId: item};
    final entries = <ReportLedgerEntry>[];
    bool selected(String itemId) =>
        snapshot.selection.itemIds.isEmpty ||
        snapshot.selection.itemIds.contains(itemId);
    void addEntry(ReportLedgerEntry entry) {
      if (entries.length >= maxEntries) {
        throw const ReportSelectionFailure('report_history_limit');
      }
      entries.add(entry);
    }

    for (final record in snapshot.records) {
      if (record.revision < 1) {
        throw const ReportSelectionFailure('report_owner');
      }
      if (!selected(record.itemId)) {
        // Totals derive from every snapshot record, so a record outside the
        // selection would put totals and ledger out of step.
        throw const ReportSelectionFailure('report_item');
      }
      addEntry(ReportLedgerEntry.fromRecord(record));
    }

    if (snapshot.selection.includeSkipped) {
      for (final skip in skipped) {
        if (skip.personId != personId) {
          throw const ReportSelectionFailure('report_owner');
        }
        if (!selected(skip.itemId)) continue;
        final descriptor = descriptors[skip.itemId];
        addEntry(
          ReportLedgerEntry(
            id: skip.id.sortKey,
            itemId: skip.itemId,
            name: descriptor?.name ?? skip.context.itemName ?? skip.itemId,
            form: descriptor?.form ?? '',
            type: descriptor?.type ?? '',
            unit: descriptor?.unit ?? '',
            status: ReportLedgerStatus.skipped,
            occurredAt: skip.occurredAt,
            dateOnly: skip.dateOnly,
            timeNeedsReview: skip.timeNeedsReview,
            planName: skip.context.planName,
            identityComplete: descriptor != null,
          ),
        );
      }
    }

    var itemCoverage = itemCoverageComplete;
    if (snapshot.selection.includeUnrecorded) {
      for (final row in dailyRows) {
        final expectation = row.expectation;
        if (expectation.identity.personId != personId) {
          throw const ReportSelectionFailure('report_owner');
        }
        if (!selected(expectation.itemId)) continue;
        final remaining = row.plannedCount - row.takenCount - row.skippedCount;
        if (remaining <= 0) continue;
        final date =
            expectation.effectiveDate ?? expectation.identity.originalDate;
        var exact = expectation.instant;
        var needsReview = false;
        if (exact == null) {
          try {
            exact = DisplayTime().dayBounds(date, expectation.zoneId).start;
          } catch (_) {
            exact = DisplayTime().dayBounds(date, 'UTC').start;
            needsReview = true;
          }
        }
        if (!exact.isBefore(snapshot.cutoff.generatedAt)) continue;
        final descriptor = descriptors[expectation.itemId];
        if (descriptor == null) itemCoverage = false;
        for (var index = 0; index < remaining; index++) {
          addEntry(
            ReportLedgerEntry(
              id: 'u:${_occurrenceKey(expectation, date)}:$index',
              itemId: expectation.itemId,
              name: descriptor?.name ?? row.itemName,
              form: descriptor?.form ?? '',
              type: descriptor?.type ?? '',
              unit: descriptor?.unit ?? expectation.amount.unit,
              status: ReportLedgerStatus.notRecorded,
              occurredAt: exact,
              dateOnly: expectation.instant == null,
              timeNeedsReview:
                  needsReview ||
                  expectation.resolution == DailyResolution.missingClock ||
                  expectation.resolution == DailyResolution.repeatedClock,
              planName: null,
              identityComplete: descriptor != null,
            ),
          );
        }
      }
    }

    entries.sort(_entryCompare);
    if (entries.length > maxEntries) {
      throw const ReportSelectionFailure('report_history_limit');
    }
    if (entries.map((entry) => entry.id).toSet().length != entries.length) {
      throw const ReportSelectionFailure('report_history_duplicate');
    }
    return ReportHistoryData._(
      entries: entries,
      planCoverageComplete: planCoverageComplete,
      plansTruncated: plansTruncated,
      planIssue: planIssue,
      itemCoverageComplete: itemCoverage,
    );
  }

  final List<ReportLedgerEntry> entries;
  final bool planCoverageComplete, plansTruncated, itemCoverageComplete;
  final String? planIssue;

  @override
  ReportTemplateId get template => ReportTemplateId.r02DetailedHistory;

  int count(ReportLedgerStatus status) =>
      entries.where((entry) => entry.status == status).length;

  int get recordedCount => count(ReportLedgerStatus.recorded);
  int get correctedCount => count(ReportLedgerStatus.corrected);
  int get skippedCount => count(ReportLedgerStatus.skipped);
  int get notRecordedCount => count(ReportLedgerStatus.notRecorded);
  int get administrationCount => recordedCount + correctedCount;

  List<String> get typeLabels {
    final labels = entries.map((entry) => entry.typeLabel).toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return labels;
  }

  ReportLedgerEntry? get earliest => entries.isEmpty ? null : entries.first;
  ReportLedgerEntry? get latest => entries.isEmpty ? null : entries.last;

  /// Complete message for any coverage limitation, or null when complete.
  String? get coverageNote {
    final parts = <String>[];
    if (!planCoverageComplete) {
      parts.add(
        'Some plan occurrences could not be evaluated, so not-recorded rows may be incomplete.',
      );
    }
    if (plansTruncated) {
      parts.add('Plan coverage for this period reached the report limit.');
    }
    if (!itemCoverageComplete) {
      parts.add(
        'Some planned items no longer have item details and are named from the plan only.',
      );
    }
    if (planIssue != null && planCoverageComplete && !plansTruncated) {
      parts.add(
        'Some plan occurrences need review, so this ledger may be incomplete.',
      );
    }
    return parts.isEmpty ? null : parts.join(' ');
  }

  String structuredText(ReportSnapshot snapshot, {required bool use24Hour}) {
    final selection = snapshot.selection;
    final lines = <String>[
      'Detailed history',
      '',
      'Person: ${snapshot.person.displayName}',
      if (snapshot.reportIdentity != null)
        'Report name: ${snapshot.reportIdentity}',
      'Period: ${formatCivilDate(selection.fromDate)} to '
          '${formatCivilDate(selection.beforeDate.addDays(-1))}',
      'Time zone: ${selection.displayZone}',
      'Generated: ${formatInstant(snapshot.cutoff.generatedAt, selection.displayZone, use24Hour: use24Hour)}',
      'Template: ${selection.template.id} version ${reportTemplateVersion(selection.template)}',
      'Report ID: ${snapshot.artifactId}',
      '',
      'Ledger rows: ${entries.length}',
      'Recorded: $recordedCount',
      'Corrected: $correctedCount',
      'Skipped: $skippedCount',
      'Not recorded: $notRecordedCount',
      'Included states: recorded and corrected always; skipped '
          '${selection.includeSkipped ? 'included' : 'not included'}; '
          'not recorded ${selection.includeUnrecorded ? 'included' : 'not included'}.',
      'Included types: ${typeLabels.join(', ')}',
      '',
    ];
    if (coverageNote != null) {
      lines
        ..add(coverageNote!)
        ..add('');
    }
    for (final entry in entries) {
      final time = entry.dateOnly
          ? formatCivilDate(_civil(entry.occurredAt, selection.displayZone))
          : formatInstant(
              entry.occurredAt,
              selection.displayZone,
              use24Hour: use24Hour,
            );
      final amount = entry.amount == null
          ? 'No dose recorded'
          : '${formatAmount(entry.amount!)} ${entry.unit}';
      lines.add(
        '$time · ${entry.name} · $amount · ${_statusText(entry.status)}',
      );
      if (entry.form.trim().isNotEmpty) lines.add('  Form: ${entry.form}');
      if (!entry.identityComplete) lines.add('  Type: not recorded');
      if (entry.product != null) {
        for (final ingredient in entry.product!.ingredients) {
          lines.add(
            '  Ingredient ${ingredient.name}'
            '${ingredient.strength == null ? '' : ' (${ingredient.strength})'}: '
            '${ingredient.amount == null ? 'Unknown' : '${formatAmount(ingredient.amount!)} ${ingredient.unit}'}',
          );
        }
      }
      if (entry.status == ReportLedgerStatus.corrected &&
          entry.entryAt != null) {
        lines.add(
          '  Entered ${formatInstant(entry.entryAt!, selection.displayZone, use24Hour: use24Hour)}',
        );
      }
      if (entry.site != null) lines.add('  Site: ${entry.site}');
      if (entry.contextTags.isNotEmpty) {
        lines.add('  Tags: ${entry.contextTags.join(', ')}');
      }
      if (entry.notes != null) lines.add('  Note: ${entry.notes}');
      if (entry.source != RecordSource.unspecified) {
        lines.add('  Source: ${_sourceText(entry.source)}');
      }
      if (entry.planName != null) lines.add('  Plan: ${entry.planName}');
    }
    lines
      ..add('')
      ..addAll(_compatibleTotals(snapshot))
      ..addAll(ReportText.contextLines(snapshot))
      ..add('')
      ..add(
        'Recorded rows are reported entries, not proof that a dose was taken. '
        'A not-recorded row means no dose and no explicit skip were saved for a planned occurrence. '
        'It does not prove the dose was missed.',
      );
    return lines.join('\n');
  }

  /// Exact totals that mirror the reviewed PDF's compatible totals section.
  ///
  /// Ready-mixed volume and its ingredient amounts stay separate; an unknown
  /// ingredient amount stays unknown instead of being guessed.
  List<String> _compatibleTotals(ReportSnapshot snapshot) {
    final totals = snapshot.totals;
    final lines = <String>[
      'Compatible totals',
      'Doses count recorded administrations. Ingredient rows are amounts '
          'within the same administrations, not extra doses.',
      '',
    ];
    if (totals.limitReached) {
      lines
        ..add(
          'One or more totals were too large to display. Narrow the period or item selection.',
        )
        ..add('');
    }
    for (final group in totals.groups) {
      final type = group.type.trim().isEmpty ? 'Uncategorised' : group.type;
      lines.add('Type: $type');
      for (final item in group.items) {
        lines.add(
          '${item.name} · ${item.form} · ${_doseCountText(item.count)} · '
          '${item.total == null ? 'Total unavailable' : 'Total ${formatAmount(item.total!)} ${item.unit}'}',
        );
      }
      for (final product in group.products) {
        lines.add(
          '${product.name} · ${product.form} · ${_doseCountText(product.administrations)} · '
          'Volume ${product.volume == null ? 'unavailable' : '${formatAmount(product.volume!)} ${product.volumeUnit}'}',
        );
        for (final ingredient in product.ingredients) {
          lines.add(
            '  Ingredient ${ingredient.name}'
            '${ingredient.strength == null ? '' : ' (${ingredient.strength})'}: '
            '${ingredient.complete ? '${formatAmount(ingredient.knownSubtotal!)} ${ingredient.unit}' : 'Unknown'}',
          );
        }
      }
      lines.add('');
    }
    return lines;
  }
}

String _doseCountText(int count) => count == 1 ? '1 dose' : '$count doses';

String _statusText(ReportLedgerStatus status) => switch (status) {
  ReportLedgerStatus.recorded => 'Recorded',
  ReportLedgerStatus.corrected => 'Corrected',
  ReportLedgerStatus.skipped => 'Skipped',
  ReportLedgerStatus.notRecorded => 'Not recorded',
};

String _sourceText(RecordSource source) => switch (source) {
  RecordSource.unspecified => 'Not recorded',
  RecordSource.selfReported => 'Self-reported',
  RecordSource.recordedOnBehalf => 'Recorded on behalf',
};

String _occurrenceKey(DailyExpectation expectation, CivilDate date) {
  final identity = expectation.identity;
  return [
    identity.planId,
    date.toString(),
    identity.slotId ?? 'untimed',
    identity.intervalSegmentId ?? '-',
    identity.intervalOrdinal?.toString() ?? '-',
    identity.sourceActualId ?? '-',
    identity.sourceActualRevision?.toString() ?? '-',
  ].join('|');
}

CivilDate _civil(DateTime instant, String zone) {
  try {
    return DisplayTime().instant(instant, zone).civilDate;
  } catch (_) {
    return DisplayTime().instant(instant, 'UTC').civilDate;
  }
}

int _entryCompare(ReportLedgerEntry a, ReportLedgerEntry b) {
  final byTime = a.occurredAt.compareTo(b.occurredAt);
  if (byTime != 0) return byTime;
  final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
  if (byName != 0) return byName;
  return a.id.compareTo(b.id);
}
