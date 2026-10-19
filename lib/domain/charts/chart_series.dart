import 'dart:convert';

import '../products/products.dart';
import '../stock/exact_amount.dart';
import 'chart_limits.dart';
import 'chart_support.dart';

/// What one chart series counts.
///
/// A physical product contributes its own volume series and, separately, one
/// series per labelled ingredient. The two kinds are never summed.
enum ChartSubjectKind { item, ingredient }

/// The counted identity inside one person's chart.
final class ChartSubject {
  ChartSubject.item(String itemId) : this._(ChartSubjectKind.item, itemId);

  ChartSubject.ingredient(String ingredientId)
    : this._(ChartSubjectKind.ingredient, ingredientId);

  ChartSubject._(this.kind, this.id) {
    chartRequireText(id, 'chart_subject');
  }

  final ChartSubjectKind kind;
  final String id;

  Map<String, Object?> toJson() => {'kind': kind.name, 'id': id};

  @override
  bool operator ==(Object other) =>
      other is ChartSubject && kind == other.kind && id == other.id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => '${kind.name}:$id';
}

/// One chart series identity: person, subject and saved actual unit.
///
/// Unit identity is the saved actual unit. Entered or original units never
/// enter this key, so `mg`, `ml` and `count` cannot be folded into one total.
/// The person is part of the key, so a multi-adult view cannot sum two adults.
final class ChartSeriesKey implements Comparable<ChartSeriesKey> {
  factory ChartSeriesKey({
    required String personId,
    required ChartSubject subject,
    required String unit,
  }) {
    chartRequireText(personId, 'chart_owner');
    chartRequireText(unit, 'chart_unit', maxLength: 64);
    return ChartSeriesKey._(personId: personId, subject: subject, unit: unit);
  }

  const ChartSeriesKey._({
    required this.personId,
    required this.subject,
    required this.unit,
  });

  final String personId;
  final ChartSubject subject;
  final String unit;

  /// Canonical identity for hashing and grouping. Not app copy.
  String get identity => jsonEncode({
    'person': personId,
    'kind': subject.kind.name,
    'subject': subject.id,
    'unit': unit,
  });

  @override
  int compareTo(ChartSeriesKey other) {
    final byPerson = personId.compareTo(other.personId);
    if (byPerson != 0) return byPerson;
    final byKind = subject.kind.index.compareTo(other.subject.kind.index);
    if (byKind != 0) return byKind;
    final bySubject = subject.id.compareTo(other.subject.id);
    if (bySubject != 0) return bySubject;
    return unit.compareTo(other.unit);
  }

  @override
  bool operator ==(Object other) =>
      other is ChartSeriesKey &&
      personId == other.personId &&
      subject == other.subject &&
      unit == other.unit;

  @override
  int get hashCode => Object.hash(personId, subject, unit);

  @override
  String toString() => identity;
}

/// Exact source identity of one current administration revision.
///
/// A combined group contributes one observation per current component record,
/// never an extra parent observation. [combinedActionId] keeps the group
/// context for inspection without changing the counted amount.
final class ChartSourceRef implements Comparable<ChartSourceRef> {
  factory ChartSourceRef({
    required String recordId,
    required int revision,
    String? combinedActionId,
  }) {
    chartRequireText(recordId, 'chart_source');
    if (revision < 1) throw const ChartModelException('chart_source_revision');
    chartRequireOptionalText(combinedActionId, 'chart_combined');
    return ChartSourceRef._(
      recordId: recordId,
      revision: revision,
      combinedActionId: combinedActionId,
    );
  }

  const ChartSourceRef._({
    required this.recordId,
    required this.revision,
    required this.combinedActionId,
  });

  final String recordId;
  final int revision;
  final String? combinedActionId;

  String get sortKey => 'r:$recordId';

  @override
  int compareTo(ChartSourceRef other) {
    final byId = recordId.compareTo(other.recordId);
    return byId != 0 ? byId : revision.compareTo(other.revision);
  }

  @override
  bool operator ==(Object other) =>
      other is ChartSourceRef &&
      recordId == other.recordId &&
      revision == other.revision &&
      combinedActionId == other.combinedActionId;

  @override
  int get hashCode => Object.hash(recordId, revision, combinedActionId);

  @override
  String toString() => '$sortKey@$revision';
}

/// One current administration revision supplied to the chart model.
///
/// The adapter supplies the current revision only. Corrections appear as a new
/// revision of the same source, never as a second chart contribution.
///
/// [amount] and [unit] are the saved actual amount and unit. [enteredAmountText]
/// and [enteredUnit] retain the original entry separately and never contribute
/// to a total. [product], when present, is the complete saved label and exact
/// volume for that administration; ingredient points are derived from it.
final class ChartObservation {
  factory ChartObservation({
    required ChartSourceRef source,
    required String personId,
    required String itemId,
    required String itemName,
    required ExactAmount amount,
    required String unit,
    required DateTime occurredAt,
    String? enteredAmountText,
    String? enteredUnit,
    String? typeId,
    String? typeName,
    ProductAdministrationSnapshot? product,
    bool isVoided = false,
  }) {
    chartRequireText(personId, 'chart_owner');
    chartRequireText(itemId, 'chart_item');
    chartRequireText(itemName, 'chart_item_name', maxLength: 500);
    chartRequireText(unit, 'chart_unit', maxLength: 64);
    chartRequireUtc(occurredAt, 'observation_range');
    if (amount <= ExactAmount.zero) {
      throw const ChartModelException('chart_amount');
    }
    if ((enteredAmountText == null) != (enteredUnit == null)) {
      throw const ChartModelException('chart_entered_pair');
    }
    final entered = enteredAmountText;
    if (entered != null) {
      chartRequireText(enteredUnit!, 'chart_unit', maxLength: 64);
      try {
        ExactAmount.parseEntry(entered);
      } on FormatException {
        throw const ChartModelException('chart_entered_amount');
      } on RangeError {
        throw const ChartModelException('chart_entered_amount');
      }
    }
    chartRequireOptionalText(typeId, 'chart_type');
    chartRequireOptionalText(typeName, 'chart_type_name', maxLength: 500);
    if (product != null) {
      if (unit != 'ml') {
        throw const ChartModelException('chart_product_unit');
      }
      if (product.volume != amount) {
        throw const ChartModelException('chart_product_volume');
      }
      if (product.label.personId != personId ||
          product.label.itemId != itemId) {
        throw const ChartModelException('chart_product_owner');
      }
    }
    return ChartObservation._(
      source: source,
      personId: personId,
      itemId: itemId,
      itemName: itemName,
      amount: amount,
      unit: unit,
      occurredAt: occurredAt,
      enteredAmountText: enteredAmountText,
      enteredUnit: enteredUnit,
      typeId: typeId,
      typeName: typeName,
      product: product,
      isVoided: isVoided,
    );
  }

  const ChartObservation._({
    required this.source,
    required this.personId,
    required this.itemId,
    required this.itemName,
    required this.amount,
    required this.unit,
    required this.occurredAt,
    required this.enteredAmountText,
    required this.enteredUnit,
    required this.typeId,
    required this.typeName,
    required this.product,
    required this.isVoided,
  });

  final ChartSourceRef source;
  final String personId;
  final String itemId;
  final String itemName;

  /// Exact saved actual amount. Ingredient amounts derived from [product] use
  /// the exact saved volume and label strength.
  final ExactAmount amount;

  /// Saved actual unit. Totals are only ever folded within this unit.
  final String unit;

  /// Exact UTC administration time.
  final DateTime occurredAt;

  /// Original entry lexeme and unit, retained for inspection only.
  final String? enteredAmountText, enteredUnit;

  final String? typeId, typeName;

  /// Complete saved product label and volume. Null for a non-product item.
  final ProductAdministrationSnapshot? product;

  /// Voided administrations are retained for the source table and excluded
  /// from chart points and totals by the model.
  final bool isVoided;
}

/// One bounded, single-person observation read.
///
/// The adapter must not supply a combined parent plus its components; that
/// would double count. It supplies each current component administration once.
final class ChartObservationBatch {
  ChartObservationBatch({
    required String personId,
    required DateTime fromInstant,
    required DateTime beforeInstant,
    required this.schemaVersion,
    required String datasetGeneration,
    Iterable<ChartObservation> observations = const [],
    this.truncated = false,
  }) : personId = personId,
       fromInstant = fromInstant,
       beforeInstant = beforeInstant,
       datasetGeneration = datasetGeneration,
       observations = List.unmodifiable(observations) {
    chartRequireText(personId, 'chart_owner');
    chartRequireUtc(fromInstant, 'invalid_range');
    chartRequireUtc(beforeInstant, 'invalid_range');
    if (!beforeInstant.isAfter(fromInstant)) {
      throw const ChartRangeException('invalid_range');
    }
    if (schemaVersion < 1) {
      throw const ChartModelException('batch_schema');
    }
    chartRequireText(datasetGeneration, 'batch_generation');
    if (this.observations.length > ChartLimits.maxSourceRows) {
      throw const ChartModelException('source_rows');
    }
    final sources = <String>{};
    for (final observation in this.observations) {
      if (observation.personId != personId) {
        throw const ChartModelException('cross_person_chart');
      }
      if (observation.occurredAt.isBefore(fromInstant) ||
          !observation.occurredAt.isBefore(beforeInstant)) {
        throw const ChartModelException('observation_range');
      }
      // One observation per current administration. A stale revision of the
      // same record must not appear as a second contribution.
      if (!sources.add(observation.source.recordId)) {
        throw const ChartModelException('duplicate_source');
      }
    }
  }

  final String personId;
  final DateTime fromInstant, beforeInstant;
  final int schemaVersion;
  final String datasetGeneration;
  final List<ChartObservation> observations;

  /// The adapter stopped because more than [ChartLimits.maxSourceRows] rows
  /// would match. The model rejects this state; it never samples.
  final bool truncated;

  bool get isEmpty => observations.isEmpty;

  int get observationCount => observations.length;
}

/// A bounded read request for one person's chart source rows.
///
/// This is deliberately smaller than the History timeline query: charts read
/// one person and one half-open range. Paged source inspection reuses the
/// History cursor contract through `ChartDrilldownRequest`.
final class ChartSourceRequest {
  ChartSourceRequest({
    required this.personId,
    required DateTime fromInstant,
    required DateTime beforeInstant,
  }) : fromInstant = fromInstant,
       beforeInstant = beforeInstant {
    chartRequireText(personId, 'chart_owner');
    chartRequireUtc(fromInstant, 'invalid_range');
    chartRequireUtc(beforeInstant, 'invalid_range');
    if (!beforeInstant.isAfter(fromInstant)) {
      throw const ChartRangeException('invalid_range');
    }
  }

  final String personId;
  final DateTime fromInstant, beforeInstant;
}

/// Typed adapter implemented by a future store owner.
///
/// The chart domain owns no SQL, schema, cache or history query. An adapter
/// reads current administrations for one person and range, derives product
/// ingredient contributions only through [ChartObservation.product], and
/// reports truncation honestly.
abstract interface class ChartObservationSource {
  Future<ChartObservationBatch> read(ChartSourceRequest request);
}
