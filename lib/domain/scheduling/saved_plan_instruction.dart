/// Authored text from the immutable plan version linked to a saved action.
///
/// This is historical context, not a recommendation or evidence that the
/// instruction was followed. A standalone dose has no such link.
final class SavedPlanInstruction {
  const SavedPlanInstruction({
    required this.planId,
    required this.versionId,
    required this.text,
  });

  final String planId, versionId, text;

  Map<String, Object?> toJson() => {
    'planId': planId,
    'versionId': versionId,
    'text': text,
  };
}
