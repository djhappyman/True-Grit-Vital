/// User-authored substance detail. Instructions and private notes are stored
/// exactly as entered; nothing here is generated, parsed or treated as advice.
final class SubstanceDetail {
  const SubstanceDetail({
    required this.itemId,
    required this.personId,
    required this.instructions,
    required this.notes,
    required this.revision,
    required this.updatedAt,
  });

  final String itemId, personId, instructions, notes;
  final int revision;
  final DateTime updatedAt;

  bool get isEmpty => instructions.isEmpty && notes.isEmpty;
}

/// Durable progress for the optional steps that follow identity creation.
///
/// A step can be completed by saving its real record or by an explicit skip.
/// The marker never creates a plan or stock row on its own.
final class ItemSetupState {
  const ItemSetupState({
    required this.itemId,
    required this.personId,
    required this.generation,
    required this.scheduleSkipped,
    required this.stockSkipped,
    required this.detailsSkipped,
    required this.completedAt,
  });

  final String itemId, personId, generation;
  final bool scheduleSkipped, stockSkipped, detailsSkipped;
  final DateTime? completedAt;

  bool get isComplete => completedAt != null;

  ItemSetupState copyWith({
    bool? scheduleSkipped,
    bool? stockSkipped,
    bool? detailsSkipped,
    DateTime? completedAt,
  }) => ItemSetupState(
    itemId: itemId,
    personId: personId,
    generation: generation,
    scheduleSkipped: scheduleSkipped ?? this.scheduleSkipped,
    stockSkipped: stockSkipped ?? this.stockSkipped,
    detailsSkipped: detailsSkipped ?? this.detailsSkipped,
    completedAt: completedAt ?? this.completedAt,
  );
}
