import 'schedule_requirement.dart';

/// Authored text and optional structured labels from the immutable plan
/// version linked to a saved action.
///
/// This is historical context, not a recommendation or evidence that the
/// instruction was followed. A standalone dose has no such link.
final class SavedPlanInstruction {
  const SavedPlanInstruction({
    required this.planId,
    required this.versionId,
    required this.text,
    this.requirements,
  });

  final String planId, versionId, text;
  final ScheduleRequirement? requirements;

  Map<String, Object?> toJson() => {
    'planId': planId,
    'versionId': versionId,
    'text': text,
    if (requirements != null) 'requirements': requirements!.toJson(),
  };
}
