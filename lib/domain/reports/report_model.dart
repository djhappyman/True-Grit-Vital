import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../history/display_time.dart';
import '../records.dart';
import '../products/products.dart';
import '../supporting/supporting.dart';
import 'report_selection.dart';
import 'report_template_data.dart';

/// One captured, current-revision dose. Voided revisions never enter a report.
final class ReportRecord {
  ReportRecord({
    required this.id,
    required this.itemId,
    required this.name,
    required this.form,
    required this.type,
    required this.amount,
    required this.unit,
    required this.actualAt,
    required this.enteredAt,
    required this.revision,
    required this.source,
    this.product,
    this.site,
    this.notes,
    this.contextTags = const [],
  }) {
    if (amount <= ExactAmount.zero ||
        !actualAt.isUtc ||
        !enteredAt.isUtc ||
        revision < 1) {
      throw const ReportSelectionFailure('report_record');
    }
  }
  factory ReportRecord.fromUseRecord(
    UseRecord record, {
    bool includeNotes = false,
  }) => ReportRecord(
    id: record.id,
    itemId: record.itemId,
    name: record.name,
    form: record.form,
    type: record.type,
    amount: record.actualAmount,
    unit: record.actualUnit,
    actualAt: record.actualAt,
    enteredAt: record.enteredAt,
    revision: record.revision,
    source: record.source,
    site: record.siteLabel,
    notes: includeNotes ? record.notes : null,
    contextTags: record.contextTags,
    product: record.product == null
        ? null
        : ReportProduct.fromSnapshot(record.product!, record.actualUnit),
  );
  final String id, itemId, name, form, type, unit;
  final String? site;
  final String? notes;
  final List<String> contextTags;
  final ExactAmount amount;
  final DateTime actualAt, enteredAt;
  final int revision;
  final RecordSource source;
  final ReportProduct? product;

  String get itemIdentity => jsonEncode([type, itemId, name, form, unit]);
}

/// Ready-mixed consumption stays separate from its ingredient amounts.
final class ReportProduct {
  ReportProduct({
    required this.volumeUnit,
    required Iterable<ReportProductIngredient> ingredients,
  }) : ingredients = List.unmodifiable(ingredients) {
    if (volumeUnit.isEmpty || this.ingredients.isEmpty) {
      throw const ReportSelectionFailure('report_product');
    }
  }
  factory ReportProduct.fromSnapshot(
    ProductAdministrationSnapshot snapshot,
    String volumeUnit,
  ) => ReportProduct(
    volumeUnit: volumeUnit,
    ingredients: snapshot.components.map(
      (ProductComponentAmount component) => ReportProductIngredient(
        ingredientId: component.component.ingredientId,
        name: component.component.name,
        unit: component.component.massUnit,
        amount: component.amount,
        strength: component.component.concentrationText == null
            ? null
            : '${component.component.concentrationText} '
                  '${component.component.massUnit}/'
                  '${component.component.volumeUnit}',
      ),
    ),
  );
  final String volumeUnit;
  final List<ReportProductIngredient> ingredients;

  String get identity => jsonEncode([
    volumeUnit,
    for (final ingredient in ingredients)
      [
        ingredient.ingredientId,
        ingredient.name,
        ingredient.unit,
        ingredient.strength,
      ],
  ]);
}

final class ReportProductIngredient {
  const ReportProductIngredient({
    required this.ingredientId,
    required this.name,
    required this.unit,
    required this.amount,
    this.strength,
  });
  final String ingredientId, name, unit;
  final String? strength;
  final ExactAmount? amount;
}

final class ReportSupportingEntry {
  ReportSupportingEntry({
    required this.id,
    required this.title,
    required this.kind,
    required this.collectionDate,
    this.reportDate,
    this.notes,
    required Iterable<ReportSupportingValue> values,
  }) : values = List.unmodifiable(values);
  final String id, title;
  final SupportingRecordKind kind;
  final SupportingDate collectionDate;
  final SupportingDate? reportDate;
  final String? notes;
  final List<ReportSupportingValue> values;
}

final class ReportSupportingValue {
  const ReportSupportingValue({
    required this.name,
    required this.value,
    this.unit,
    this.referenceRange,
  });
  final String name;
  final String value;
  final String? unit, referenceRange;
}

/// Authored substance text captured only when private notes are selected.
final class ReportItemDetail {
  const ReportItemDetail({this.instructions = '', this.notes = ''});
  final String instructions, notes;
  bool get isEmpty => instructions.isEmpty && notes.isEmpty;
}

/// Truthful disclosure of the supporting records left out of the selected
/// collection-date window because their collection date is unknown or partial.
///
/// Nothing about an omitted record's content enters the snapshot. A reached
/// counting bound reports [count] null instead of a fabricated number.
final class ReportSupportingOmission {
  const ReportSupportingOmission.counted(int this.count) : assert(count >= 0);
  const ReportSupportingOmission.uncounted() : count = null;

  /// Number of omitted current records, or null when they were not counted.
  final int? count;

  /// Stable identity input. Only a positive or uncounted result changes the
  /// reviewed wording, so an exact zero leaves the artifact identity unchanged.
  List<Object?>? get identityToken => count == null
      ? const ['supporting-collection-date', 'uncounted']
      : count! > 0
      ? ['supporting-collection-date', 'counted', count]
      : null;
}

final class ReportAttachmentRef {
  const ReportAttachmentRef({
    required this.id,
    required this.name,
    required this.versionId,
    required this.sha256,
    required this.byteCount,
    required this.pinned,
    this.targetKind,
    this.targetId,
  });
  final String id, name, versionId, sha256;
  final int byteCount;
  final bool pinned;
  final String? targetKind, targetId;
}

final class ReportPerson {
  const ReportPerson({
    required this.id,
    required this.name,
    this.reportName,
    this.relationship,
  });
  final String id, name;
  final String? reportName, relationship;
  String get displayName => reportName != null && reportName!.trim().isNotEmpty
      ? reportName!.trim()
      : name;
}

/// A complete source model for one reviewed artifact.
final class ReportSnapshot {
  ReportSnapshot._({
    required this.selection,
    required this.cutoff,
    required this.person,
    required Iterable<ReportRecord> records,
    required Iterable<ReportSupportingEntry> supporting,
    required Iterable<ReportAttachmentRef> attachments,
    required this.supportingTruncated,
    Map<String, ReportItemDetail> itemDetails = const {},
    this.supportingOmission,
    this.templateData,
  }) : records = List.unmodifiable(records),
       supporting = List.unmodifiable(supporting),
       attachments = List.unmodifiable(attachments),
       itemDetails = Map.unmodifiable(itemDetails),
       totals = ReportTotals.build(records);

  factory ReportSnapshot.build({
    required ReportSelection selection,
    required ReportCutoff cutoff,
    required ReportPerson person,
    required Iterable<ReportRecord> records,
    Iterable<ReportSupportingEntry> supporting = const [],
    Iterable<ReportAttachmentRef> attachments = const [],
    bool supportingTruncated = false,
    Map<String, ReportItemDetail> itemDetails = const {},
    ReportSupportingOmission? supportingOmission,
    ReportTemplateData? templateData,
  }) {
    if (person.id != selection.personId) {
      throw const ReportSelectionFailure('report_owner');
    }
    if (templateData != null && templateData.template != selection.template) {
      throw const ReportSelectionFailure('report_template_data');
    }
    if (supportingOmission != null && !selection.includeSupporting) {
      throw const ReportSelectionFailure('report_supporting_omission');
    }
    if (itemDetails.isNotEmpty && !selection.includeNotes) {
      throw const ReportSelectionFailure('report_item_details');
    }
    final all = records.toList();
    final recordItems = all.map((record) => record.itemId).toSet();
    if (itemDetails.keys.any((itemId) => !recordItems.contains(itemId))) {
      throw const ReportSelectionFailure('report_item_details');
    }
    return ReportSnapshot._(
      selection: selection,
      cutoff: cutoff,
      person: person,
      records: all,
      supporting: supporting,
      attachments: attachments,
      supportingTruncated: supportingTruncated,
      itemDetails: itemDetails,
      supportingOmission: supportingOmission,
      templateData: templateData,
    );
  }

  final ReportSelection selection;
  final ReportCutoff cutoff;
  final ReportPerson person;
  final List<ReportRecord> records;
  final List<ReportSupportingEntry> supporting;
  final List<ReportAttachmentRef> attachments;
  final bool supportingTruncated;

  /// Authored instructions and private notes for recorded items. Empty unless
  /// [ReportSelection.includeNotes] was selected at capture.
  final Map<String, ReportItemDetail> itemDetails;

  /// Truthful count of omitted unknown/partial collection dates. Set exactly
  /// when supporting context is selected; null when it is not.
  final ReportSupportingOmission? supportingOmission;

  /// R02/R03 body captured with this cutoff. Null for R01.
  final ReportTemplateData? templateData;
  final ReportTotals totals;

  /// Attaches template-specific body data while preserving every other
  /// captured field. Rejects a payload for a different template.
  ReportSnapshot withTemplateData(ReportTemplateData? data) {
    if (data != null && data.template != selection.template) {
      throw const ReportSelectionFailure('report_template_data');
    }
    return ReportSnapshot._(
      selection: selection,
      cutoff: cutoff,
      person: person,
      records: records,
      supporting: supporting,
      attachments: attachments,
      supportingTruncated: supportingTruncated,
      itemDetails: itemDetails,
      supportingOmission: supportingOmission,
      templateData: data,
    );
  }

  /// Operator-chosen report identity, then the profile's saved report name.
  String? get reportIdentity {
    final chosen = selection.reportName?.trim();
    if (chosen != null && chosen.isNotEmpty) return chosen;
    final saved = person.reportName?.trim();
    return saved == null || saved.isEmpty ? null : saved;
  }

  /// Stable, non-identifying artifact identity for repeated page identity.
  String get artifactId {
    final digest = sha256.convert(
      utf8.encode(
        jsonEncode([
          selection.identity,
          cutoff.toJson(),
          if (supportingOmission?.identityToken != null)
            supportingOmission!.identityToken,
        ]),
      ),
    );
    return digest.toString().substring(0, 12);
  }

  String get _neutralStem => switch (selection.template) {
    ReportTemplateId.r01SubstanceSummary => 'vital-substance-summary',
    ReportTemplateId.r02DetailedHistory => 'vital-detailed-history',
    ReportTemplateId.r03EventReview => 'vital-event-review',
  };

  String get neutralFileName =>
      '$_neutralStem-${selection.fromDate}-${selection.beforeDate}-$artifactId.pdf';

  String get textFileName =>
      '$_neutralStem-${selection.fromDate}-${selection.beforeDate}-$artifactId.txt';

  /// Deterministic structured alternative used by accessible preview and .txt.
  String structuredText({required bool use24Hour}) =>
      ReportText.build(snapshot: this, use24Hour: use24Hour);

  /// The newest captured records by recorded actual time, newest first.
  ///
  /// Recency comes from [ReportRecord.actualAt], never from the caller's list
  /// position or [ReportRecord.enteredAt], so an unsorted snapshot still
  /// reports the truly latest doses. Records that share an actual instant list
  /// the lower record identity and revision first, keeping a tied selection
  /// identical for equivalent snapshots. The source list is never reordered.
  List<ReportRecord> recentRecords({int limit = 100}) {
    if (limit < 1) throw RangeError.value(limit, 'limit');
    final ordered = records.toList()
      ..sort((a, b) {
        final byActual = b.actualAt.compareTo(a.actualAt);
        if (byActual != 0) return byActual;
        final byIdentity = a.id.compareTo(b.id);
        return byIdentity != 0 ? byIdentity : a.revision.compareTo(b.revision);
      });
    return ordered.length <= limit ? ordered : ordered.sublist(0, limit);
  }
}

final class ReportItemTotal {
  const ReportItemTotal({
    required this.itemId,
    required this.name,
    required this.form,
    required this.unit,
    required this.total,
    required this.count,
    required this.limitReached,
  });
  final String itemId, name, form, unit;
  final ExactAmount? total;
  final int count;
  final bool limitReached;
}

final class ReportProductIngredientTotal {
  const ReportProductIngredientTotal({
    required this.name,
    required this.unit,
    required this.knownSubtotal,
    required this.complete,
    required this.count,
    this.strength,
  });
  final String name, unit;
  final String? strength;
  final ExactAmount? knownSubtotal;
  final bool complete;
  final int count;
}

final class ReportProductTotal {
  ReportProductTotal({
    required this.itemId,
    required this.name,
    required this.form,
    required this.volumeUnit,
    required this.volume,
    required this.administrations,
    required Iterable<ReportProductIngredientTotal> ingredients,
    required this.limitReached,
  }) : ingredients = List.unmodifiable(ingredients);
  final String itemId, name, form, volumeUnit;
  final ExactAmount? volume;
  final int administrations;
  final List<ReportProductIngredientTotal> ingredients;
  final bool limitReached;
}

final class ReportTypeGroup {
  ReportTypeGroup({
    required this.type,
    required Iterable<ReportItemTotal> items,
    required Iterable<ReportProductTotal> products,
  }) : items = List.unmodifiable(items),
       products = List.unmodifiable(products);
  final String type;
  final List<ReportItemTotal> items;
  final List<ReportProductTotal> products;
  int get itemCount => items.length + products.length;
}

/// Exact aggregates that never combine unlike units or product strengths.
final class ReportTotals {
  ReportTotals._({
    required Iterable<ReportTypeGroup> groups,
    required this.recordCount,
    required this.itemCount,
    required this.typeCount,
    required this.limitReached,
  }) : groups = List.unmodifiable(groups);

  factory ReportTotals.build(Iterable<ReportRecord> records) {
    const maxBits = 65536;
    final simple = <String, _ItemAccumulator>{};
    final products = <String, _ProductAccumulator>{};
    var count = 0, limited = false;
    bool tooBig(ExactAmount value) =>
        value.numerator.bitLength > maxBits ||
        value.denominator.bitLength > maxBits;
    for (final record in records) {
      count++;
      if (record.product != null) {
        final product = record.product!;
        final key = jsonEncode([
          record.type,
          record.itemId,
          record.name,
          record.form,
          product.identity,
        ]);
        final accumulator = products.putIfAbsent(
          key,
          () => _ProductAccumulator(
            record.type,
            record.itemId,
            record.name,
            record.form,
            product.volumeUnit,
            product.ingredients,
          ),
        );
        accumulator.add(record.amount, product.ingredients);
        if (accumulator.limitReached) limited = true;
        continue;
      }
      final accumulator = simple.putIfAbsent(
        record.itemIdentity,
        () => _ItemAccumulator(
          record.itemId,
          record.name,
          record.form,
          record.unit,
          record.type,
        ),
      );
      accumulator.add(record.amount);
      if (accumulator.limitReached) limited = true;
    }
    final grouped = <String, List<ReportItemTotal>>{};
    for (final accumulator in simple.values) {
      final total = accumulator.total;
      if (total != null && tooBig(total)) {
        accumulator.limitReached = true;
        accumulator.total = null;
        limited = true;
      }
      grouped
          .putIfAbsent(accumulator.type, () => [])
          .add(accumulator.totalItem);
    }
    final groupedProducts = <String, List<ReportProductTotal>>{};
    for (final accumulator in products.values) {
      groupedProducts
          .putIfAbsent(accumulator.type, () => [])
          .add(accumulator.totalProduct);
    }
    final types = {...grouped.keys, ...groupedProducts.keys}.toList()
      ..sort(_typeCompare);
    final groups = <ReportTypeGroup>[];
    for (final type in types) {
      final items = [...(grouped[type] ?? const <ReportItemTotal>[])]
        ..sort(_itemCompare);
      final productTotals = [
        ...(groupedProducts[type] ?? const <ReportProductTotal>[]),
      ]..sort(_productCompare);
      groups.add(
        ReportTypeGroup(type: type, items: items, products: productTotals),
      );
    }
    return ReportTotals._(
      groups: groups,
      recordCount: count,
      itemCount: groups.fold(0, (total, group) => total + group.itemCount),
      typeCount: groups.length,
      limitReached: limited,
    );
  }
  final List<ReportTypeGroup> groups;
  final int recordCount, itemCount, typeCount;
  final bool limitReached;

  int get productAdministrations => groups.fold(
    0,
    (total, group) =>
        total +
        group.products.fold(
          0,
          (subtotal, item) => subtotal + item.administrations,
        ),
  );
}

final class _ItemAccumulator {
  _ItemAccumulator(this.itemId, this.name, this.form, this.unit, this.type);
  final String itemId, name, form, unit, type;
  ExactAmount? total = ExactAmount.zero;
  int count = 0;
  bool limitReached = false;
  void add(ExactAmount amount) {
    count++;
    final current = total;
    if (current == null) return;
    final next = current + amount;
    if (next.numerator.bitLength > 65536 ||
        next.denominator.bitLength > 65536) {
      total = null;
      limitReached = true;
    } else {
      total = next;
    }
  }

  ReportItemTotal get totalItem => ReportItemTotal(
    itemId: itemId,
    name: name,
    form: form,
    unit: unit,
    total: total,
    count: count,
    limitReached: limitReached,
  );
}

final class _ProductAccumulator {
  _ProductAccumulator(
    this.type,
    this.itemId,
    this.name,
    this.form,
    this.volumeUnit,
    Iterable<ReportProductIngredient> ingredients,
  ) {
    for (final ingredient in ingredients) {
      final key = jsonEncode([
        ingredient.ingredientId,
        ingredient.name,
        ingredient.unit,
        ingredient.strength,
      ]);
      this.ingredients.putIfAbsent(
        key,
        () => _IngredientAccumulator(ingredient),
      );
    }
  }
  final String type, itemId, name, form, volumeUnit;
  final Map<String, _IngredientAccumulator> ingredients = {};
  ExactAmount? volume = ExactAmount.zero;
  int administrations = 0;
  bool limitReached = false;

  void add(ExactAmount amount, Iterable<ReportProductIngredient> ingredients) {
    administrations++;
    final current = volume;
    if (current == null) return;
    final next = current + amount;
    if (next.numerator.bitLength > 65536 ||
        next.denominator.bitLength > 65536) {
      volume = null;
      limitReached = true;
    } else {
      volume = next;
    }
    for (final ingredient in ingredients) {
      final key = jsonEncode([
        ingredient.ingredientId,
        ingredient.name,
        ingredient.unit,
        ingredient.strength,
      ]);
      final accumulator = this.ingredients.putIfAbsent(
        key,
        () => _IngredientAccumulator(ingredient),
      );
      accumulator.add(ingredient.amount);
      if (accumulator.limitReached) limitReached = true;
    }
  }

  ReportProductTotal get totalProduct => ReportProductTotal(
    itemId: itemId,
    name: name,
    form: form,
    volumeUnit: volumeUnit,
    volume: volume,
    administrations: administrations,
    ingredients: [for (final item in ingredients.values) item.total],
    limitReached: limitReached,
  );
}

final class _IngredientAccumulator {
  _IngredientAccumulator(ReportProductIngredient ingredient)
    : name = ingredient.name,
      unit = ingredient.unit,
      strength = ingredient.strength,
      complete = ingredient.amount != null,
      knownSubtotal = ingredient.amount == null ? null : ExactAmount.zero;
  final String name, unit;
  final String? strength;
  int count = 0;
  bool complete;
  ExactAmount? knownSubtotal;
  bool limitReached = false;

  void add(ExactAmount? amount) {
    count++;
    if (limitReached) return;
    if (amount == null) {
      complete = false;
      return;
    }
    final current = knownSubtotal ?? ExactAmount.zero;
    final next = current + amount;
    if (next.numerator.bitLength > 65536 ||
        next.denominator.bitLength > 65536) {
      knownSubtotal = null;
      complete = false;
      limitReached = true;
    } else {
      knownSubtotal = next;
    }
  }

  ReportProductIngredientTotal get total => ReportProductIngredientTotal(
    name: name,
    unit: unit,
    strength: strength,
    knownSubtotal: knownSubtotal,
    complete: complete && knownSubtotal != null && !limitReached,
    count: count,
  );
}

int _typeCompare(String a, String b) {
  final insensitive = a.toLowerCase().compareTo(b.toLowerCase());
  return insensitive != 0 ? insensitive : a.compareTo(b);
}

int _itemCompare(ReportItemTotal a, ReportItemTotal b) {
  final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
  if (byName != 0) return byName;
  final byForm = a.form.compareTo(b.form);
  return byForm != 0 ? byForm : a.itemId.compareTo(b.itemId);
}

int _productCompare(ReportProductTotal a, ReportProductTotal b) {
  final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
  if (byName != 0) return byName;
  final byForm = a.form.compareTo(b.form);
  return byForm != 0 ? byForm : a.itemId.compareTo(b.itemId);
}

final class ReportText {
  const ReportText._();

  /// Plain notice for supporting records omitted because their collection date
  /// is unknown or partial. Null when supporting context was not selected or
  /// when no record has such a date, because neither changes the reviewed text.
  static String? supportingOmissionNotice(ReportSnapshot snapshot) {
    if (!snapshot.selection.includeSupporting) return null;
    final omission = snapshot.supportingOmission;
    if (omission == null) return null;
    final count = omission.count;
    if (count == null) {
      return 'Supporting records with unknown or partial collection dates are '
          'not shown. Their number was above the report\'s counting limit.';
    }
    if (count == 1) {
      return '1 supporting record has an unknown or partial collection date. '
          'It is not shown.';
    }
    if (count > 1) {
      return '$count supporting records have unknown or partial collection '
          'dates. They are not shown.';
    }
    return null;
  }

  /// Selected supporting records, private notes and source files for the
  /// text alternative used by R02 and R03.
  ///
  /// Every option is stated, including its omission, so the accessible text
  /// never implies that unselected content does not exist. Values keep their
  /// original unit and reference range.
  static List<String> contextLines(ReportSnapshot snapshot) {
    final selection = snapshot.selection;
    if (!selection.includeSupporting &&
        !selection.includeAttachments &&
        snapshot.itemDetails.isEmpty) {
      return const [
        'Supporting records and source files: not included.',
        'Private notes: not included.',
      ];
    }
    final lines = <String>[
      'Supporting records: ${selection.includeSupporting ? 'included' : 'not included'}.',
      'Private notes: ${selection.includeNotes ? 'included where recorded' : 'not included'}.',
      'Source files: ${selection.includeAttachments ? 'listed' : 'not included'}.',
    ];
    if (selection.includeSupporting) {
      if (snapshot.supporting.isEmpty) {
        lines.add('No supporting records fall inside this period.');
      } else {
        for (final entry in snapshot.supporting) {
          lines
            ..add('')
            ..add(
              '${entry.title} (${entry.kind == SupportingRecordKind.labPanel ? 'Lab panel' : 'Observation'})',
            )
            ..add('Measured: ${formatSupportingDate(entry.collectionDate)}');
          for (final value in entry.values) {
            lines.add(
              '${value.name}: ${value.value}'
              '${value.unit == null ? '' : ' ${value.unit}'}'
              '${value.referenceRange == null ? '' : ' (range ${value.referenceRange})'}',
            );
          }
          if (selection.includeNotes && entry.notes != null) {
            lines.add('Note: ${entry.notes}');
          }
        }
      }
      if (snapshot.supportingTruncated) {
        lines.add('Supporting context is limited to the first 50 records.');
      }
      final omission = supportingOmissionNotice(snapshot);
      if (omission != null) lines.add(omission);
    }
    final details = itemDetailLines(snapshot);
    if (details.isNotEmpty) {
      lines.add('');
      lines.addAll(details);
    }
    if (selection.includeAttachments) {
      lines.add('');
      if (snapshot.attachments.isEmpty) {
        lines.add('No source files were selected.');
      } else {
        for (final attachment in snapshot.attachments) {
          lines.add(
            'Source: ${attachment.name} · ${attachment.byteCount} bytes · ${attachment.sha256}',
          );
        }
      }
    }
    return lines;
  }

  /// Shared authored-detail lines for accessible text and rendered reports.
  /// Empty unless notes were selected at capture.
  static List<String> itemDetailLines(ReportSnapshot snapshot) {
    if (!snapshot.selection.includeNotes || snapshot.itemDetails.isEmpty) {
      return const [];
    }
    final lines = <String>['Substance details'];
    for (final entry in snapshot.itemDetails.entries) {
      final record = snapshot.records
          .where((record) => record.itemId == entry.key)
          .firstOrNull;
      if (record == null) continue;
      lines.add(record.name);
      if (entry.value.instructions.isNotEmpty) {
        lines.add('Instructions: ${entry.value.instructions}');
      }
      if (entry.value.notes.isNotEmpty) {
        lines.add('Private note: ${entry.value.notes}');
      }
    }
    return lines.length == 1 ? const [] : lines;
  }

  static void _addItemDetails(
    List<String> lines,
    ReportSnapshot snapshot,
    String itemId,
    bool includeNotes,
  ) {
    if (!includeNotes) return;
    final detail = snapshot.itemDetails[itemId];
    if (detail == null) return;
    if (detail.instructions.isNotEmpty) {
      lines.add('  Instructions: ${detail.instructions}');
    }
    if (detail.notes.isNotEmpty) {
      lines.add('  Private note: ${detail.notes}');
    }
  }

  static String build({
    required ReportSnapshot snapshot,
    required bool use24Hour,
  }) {
    final selection = snapshot.selection;
    final lines = <String>[
      'Substance summary',
      '',
      'Person: ${snapshot.person.name}',
      if (snapshot.reportIdentity != null)
        'Report name: ${snapshot.reportIdentity}',
      'Period: ${formatCivilDate(selection.fromDate)} to '
          '${formatCivilDate(selection.beforeDate.addDays(-1))}',
      'Time zone: ${selection.displayZone}',
      'Generated: ${formatInstant(snapshot.cutoff.generatedAt, selection.displayZone, use24Hour: use24Hour)}',
      'Template: ${selection.template.id} version ${reportTemplateVersion(selection.template)}',
      'Report ID: ${snapshot.artifactId}',
      '',
      'Recorded doses: ${snapshot.totals.recordCount}',
      'Items: ${snapshot.totals.itemCount}',
      'Types: ${snapshot.totals.typeCount}',
      'These counts include current revisions only. Voided records are excluded.',
      'They describe recorded entries, not confirmed ingestion or missed doses.',
      '',
    ];
    if (snapshot.totals.limitReached) {
      lines.add(
        'One or more totals were too large to display. Narrow the period or item selection.',
      );
      lines.add('');
    }
    for (final group in snapshot.totals.groups) {
      lines
        ..add('Type: ${group.type}')
        ..add('');
      for (final item in group.items) {
        lines.add(
          '${item.name} · ${item.form} · ${_doseCount(item.count)} · '
          '${item.total == null ? 'Total unavailable' : 'Total ${formatAmount(item.total!)} ${item.unit}'}',
        );
        _addItemDetails(lines, snapshot, item.itemId, selection.includeNotes);
      }
      for (final product in group.products) {
        lines.add(
          '${product.name} · ${product.form} · ${_doseCount(product.administrations)} · '
          'Volume ${product.volume == null ? 'Total unavailable' : '${formatAmount(product.volume!)} ${product.volumeUnit}'}',
        );
        _addItemDetails(
          lines,
          snapshot,
          product.itemId,
          selection.includeNotes,
        );
        for (final ingredient in product.ingredients) {
          lines.add(
            '  Ingredient ${ingredient.name}: '
            '${ingredient.complete ? formatAmount(ingredient.knownSubtotal!) : 'Unknown'} '
            '${ingredient.unit}',
          );
        }
      }
      lines.add('');
    }
    lines
      ..add(
        selection.includeSupporting
            ? 'Supporting context: included'
            : 'Supporting context: not included',
      )
      ..add(
        selection.includeNotes
            ? 'Private notes: included where recorded'
            : 'Private notes: not included',
      )
      ..add(
        selection.includeAttachments
            ? 'Source files: included as a list'
            : 'Source files: not included',
      );
    if (snapshot.supportingTruncated) {
      lines.add('Supporting context is limited to the first 50 records.');
    }
    if (selection.includeSupporting) {
      for (final entry in snapshot.supporting) {
        lines
          ..add('')
          ..add(
            '${entry.title} (${entry.kind == SupportingRecordKind.labPanel ? 'Lab panel' : 'Observation'})',
          )
          ..add('Measured: ${formatSupportingDate(entry.collectionDate)}');
        for (final value in entry.values) {
          lines.add(
            '${value.name}: ${value.value}'
            '${value.unit == null ? '' : ' ${value.unit}'}'
            '${value.referenceRange == null ? '' : ' (range ${value.referenceRange})'}',
          );
        }
        if (selection.includeNotes && entry.notes != null) {
          lines.add('Note: ${entry.notes}');
        }
      }
      final omission = supportingOmissionNotice(snapshot);
      if (omission != null) {
        lines.add('');
        lines.add(omission);
      }
    }
    if (selection.includeAttachments) {
      lines.add('');
      for (final attachment in snapshot.attachments) {
        lines.add('Source: ${attachment.name} · ${attachment.sha256}');
      }
      if (snapshot.attachments.isEmpty) lines.add('No source files selected.');
    }
    final recent = snapshot.recentRecords();
    lines
      ..add('')
      ..add('Doses in period');
    for (final record in recent) {
      lines.add(
        '${formatInstant(record.actualAt, selection.displayZone, use24Hour: use24Hour)} · '
        '${record.name} · ${formatAmount(record.amount)} ${record.unit} · ${record.type}'
        '${record.contextTags.isEmpty ? '' : ' · Tags: ${record.contextTags.join(', ')}'}',
      );
      if (record.notes != null) lines.add('  Note: ${record.notes}');
    }
    if (snapshot.records.length > recent.length) {
      lines.add(
        'Showing the latest ${recent.length} of ${snapshot.records.length} doses.',
      );
    }
    lines
      ..add('')
      ..add(
        'This report lists recorded entries. It does not confirm that a dose was taken, '
        'does not prove that no dose was missed, and is not medical advice.',
      );
    return lines.join('\n');
  }
}

String _doseCount(int count) => count == 1 ? '1 dose' : '$count doses';

String reportTemplateVersion(ReportTemplateId template) => switch (template) {
  ReportTemplateId.r01SubstanceSummary => '1.0',
  ReportTemplateId.r02DetailedHistory => '1.0',
  ReportTemplateId.r03EventReview => '1.0',
};

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String formatCivilDate(CivilDate date) =>
    '${date.day} ${_monthNames[date.month - 1]} ${date.year}';

String formatSupportingDate(SupportingDate date) => switch (date.precision) {
  SupportingDatePrecision.unknown => 'Unknown',
  SupportingDatePrecision.day => formatCivilDate(date.civilDate!),
  SupportingDatePrecision.exact => formatInstant(
    date.instant!,
    date.zoneId ?? 'UTC',
    use24Hour: true,
  ),
  SupportingDatePrecision.partial => date.originalText ?? 'Partial date',
};

String formatInstant(DateTime instant, String zone, {required bool use24Hour}) {
  final shown = DisplayTime().instant(instant, zone);
  final date = formatCivilDate(shown.civilDate);
  final hour = use24Hour
      ? shown.hour
      : (shown.hour % 12 == 0 ? 12 : shown.hour % 12);
  final minute = shown.minute.toString().padLeft(2, '0');
  final period = use24Hour ? '' : (shown.hour < 12 ? ' am' : ' pm');
  final time = use24Hour
      ? '${shown.hour.toString().padLeft(2, '0')}:$minute'
      : '$hour:$minute$period';
  return '$date, $time (${shown.zoneId})';
}

String formatAmount(ExactAmount amount) {
  final rounded = amount.roundedDecimal(places: 6);
  final trimmed = _trimDecimal(rounded);
  final exact = ExactAmount.parseEntry(trimmed) == amount;
  return exact ? trimmed : '~$trimmed';
}

String _trimDecimal(String value) {
  if (!value.contains('.')) return value;
  final trimmed = value
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
  return trimmed.isEmpty ? '0' : trimmed;
}
