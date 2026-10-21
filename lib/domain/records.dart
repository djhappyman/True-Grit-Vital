import 'dart:math';

import 'catalogue/catalogue.dart';
import 'stock/stored_stock.dart';
import 'products/products.dart';
export 'catalogue/catalogue.dart';

const meId = 'me';

String newCommandId() {
  final random = Random.secure();
  return List.generate(
    24,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

final class ExactQuantity {
  ExactQuantity._(this.scaled);
  static const maxScaled = 9000000000000000;
  final int scaled;
  factory ExactQuantity.parse(String text) {
    if (text.length > 32 || !RegExp(r'^\d+(\.\d{1,6})?$').hasMatch(text)) {
      throw const FormatException('canonical_quantity');
    }
    final parts = text.split('.');
    final value =
        BigInt.parse(parts.first) * BigInt.from(1000000) +
        BigInt.parse(parts.length == 1 ? '0' : parts[1].padRight(6, '0'));
    if (value <= BigInt.zero || value > BigInt.from(maxScaled)) {
      throw RangeError('quantity_range');
    }
    return ExactQuantity._(value.toInt());
  }
  String get canonical {
    final fraction = (scaled % 1000000)
        .toString()
        .padLeft(6, '0')
        .replaceFirst(RegExp(r'0+$'), '');
    return '${scaled ~/ 1000000}${fraction.isEmpty ? '' : '.$fraction'}';
  }
}

final class SubstanceItem {
  const SubstanceItem({
    required this.id,
    required this.personId,
    required this.name,
    required this.form,
    required this.unit,
    required this.type,
    this.alreadyCommitted = false,
    this.typeId,
    this.revision = 1,
    this.catalogueSnapshot,
  });
  final String? typeId;
  final int revision;
  final CatalogueSnapshot? catalogueSnapshot;
  final String id, personId, name, form, unit, type;
  final bool alreadyCommitted;
}

/// Optional context captured only when the person chooses it.
///
/// Tags describe the recorded dose; they are never inferred from a substance,
/// a schedule or a label. A note is free text and stays private in exports and
/// reports unless the existing notes option is selected.
final class DoseContext {
  const DoseContext({this.notes, this.contextTags = const []});
  static const empty = DoseContext();
  final String? notes;
  final List<String> contextTags;
  bool get isEmpty => notes == null && contextTags.isEmpty;
}

const maxDoseNoteLength = 2000;
const maxDoseContextTags = 12;
const maxDoseContextTagLength = 40;
const maxSkipReasonLength = 500;

String? normaliseDoseNote(String? note) {
  final trimmed = note?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  if (trimmed.length > maxDoseNoteLength) {
    throw ArgumentError('dose_note_bound');
  }
  return trimmed;
}

List<String> normaliseDoseContextTags(Iterable<String> tags) {
  final result = <String>[];
  final seen = <String>{};
  for (final raw in tags) {
    final tag = raw.trim();
    if (tag.isEmpty) continue;
    if (tag.length > maxDoseContextTagLength) {
      throw ArgumentError('dose_tag_bound');
    }
    final key = tag.toLowerCase();
    if (!seen.add(key)) continue;
    result.add(tag);
    if (result.length > maxDoseContextTags) {
      throw ArgumentError('dose_tag_count');
    }
  }
  return List.unmodifiable(result);
}

DoseContext normaliseDoseContext(DoseContext context) => DoseContext(
  notes: normaliseDoseNote(context.notes),
  contextTags: normaliseDoseContextTags(context.contextTags),
);

String? normaliseSkipReason(String? reason) {
  final trimmed = reason?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  if (trimmed.length > maxSkipReasonLength) {
    throw ArgumentError('skip_reason_bound');
  }
  return trimmed;
}

final class UseRecord {
  const UseRecord({
    required this.id,
    required this.personId,
    required this.itemId,
    required this.name,
    required this.form,
    required this.unit,
    required this.type,
    required this.enteredAmount,
    required this.actualAt,
    required this.enteredAt,
    required this.revision,
    required this.isVoided,
    this.product,
    this.siteLabel,
    this.combinedActionId,
    this.exactActualAmount,
    this.exactActualUnit,
    this.originalEntry,
    this.originalUnit,
    this.labelledStrength,
    this.replacement,
    this.alreadyCommitted = false,
    this.catalogueSnapshot,
    this.source = RecordSource.unspecified,
    this.notes,
    this.contextTags = const [],
  });
  final CatalogueSnapshot? catalogueSnapshot;
  final ProductAdministrationSnapshot? product;
  final String? siteLabel, combinedActionId;
  final String? notes;
  final List<String> contextTags;
  final RecordSource source;
  DoseContext get context =>
      DoseContext(notes: notes, contextTags: contextTags);
  final String id, personId, itemId, name, form, unit, type, enteredAmount;
  final DateTime actualAt, enteredAt;
  final int revision;
  final bool isVoided, alreadyCommitted;
  final ExactAmount? exactActualAmount;
  final String? exactActualUnit, originalEntry, originalUnit;
  final LabelledStrength? labelledStrength;
  final StockReplacement? replacement;
  ExactAmount get actualAmount =>
      exactActualAmount ?? ExactAmount.parseEntry(enteredAmount);
  String get actualUnit => exactActualUnit ?? unit;

  /// A selected replacement can remain unresolved when its strength is unknown.
  bool get replacementResolved {
    final source = replacement;
    if (source == null) return true;
    return ReplacementAmounts.calculate(
          entered: EnteredStockAmount(
            originalEntry ?? enteredAmount,
            originalUnit ?? unit,
          ),
          oldStrength: source.oldStrength,
          newStrength: source.newStrength,
          keep: source.keep,
        ) !=
        null;
  }

  /// Legacy scaled access refuses to misrepresent an exact converted actual.
  ExactQuantity get amount {
    final legacy = ExactQuantity.parse(enteredAmount);
    if (actualUnit != unit ||
        actualAmount !=
            ExactAmount(BigInt.from(legacy.scaled), BigInt.from(1000000))) {
      throw StateError('exact_actual_required');
    }
    return legacy;
  }
}

final class CommandConflict implements Exception {
  const CommandConflict(this.code);
  final String code;
  @override
  String toString() => 'CommandConflict($code)';
}

final class AdultProfile {
  const AdultProfile({
    required this.id,
    required this.name,
    required this.revision,
    required this.isArchived,
    required this.adultConfirmed,
    required this.remindersStopped,
    this.reportName,
    this.relationship,
    this.notes,
    this.alreadyCommitted = false,
  });
  final String id, name;
  final int revision;
  final bool isArchived, adultConfirmed, remindersStopped, alreadyCommitted;
  final String? reportName, relationship, notes;
  bool get isMe => id == meId;
}

final class FeedScope {
  const FeedScope.everyone() : personId = null;
  const FeedScope.me() : personId = meId;
  const FeedScope.person(this.personId) : assert(personId != null);
  final String? personId;
  bool get isEveryone => personId == null;
  @override
  bool operator ==(Object other) =>
      other is FeedScope && other.personId == personId;
  @override
  int get hashCode => personId.hashCode;
}

enum RecordSource { unspecified, selfReported, recordedOnBehalf }

final class PersonalItemType {
  const PersonalItemType({
    required this.id,
    required this.personId,
    required this.name,
    required this.revision,
    this.alreadyCommitted = false,
  });
  final String id, personId, name;
  final int revision;
  final bool alreadyCommitted;
}
