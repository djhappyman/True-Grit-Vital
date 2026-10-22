part of 'record_store.dart';

extension PlanInstructionOutputStore on RecordStore {
  /// Resolves only explicit saved action links. The occurrence's frozen
  /// version identity selects the immutable audit, never today's plan or the
  /// plan that happens to cover a corrected dose time.
  Future<Map<String, SavedPlanInstruction>> _savedPlanInstructions(
    String personId,
    Iterable<String> identities, {
    required bool records,
  }) async {
    final ids = identities.toSet().toList()..sort();
    final result = <String, SavedPlanInstruction>{};
    for (var offset = 0; offset < ids.length; offset += 400) {
      final chunk = ids.skip(offset).take(400).toList();
      final marks = List.filled(chunk.length, '?').join(',');
      final key = records ? 'a.record' : 'a.id';
      final rows = await _rows(
        '''SELECT $key AS target,v.snapshot AS plan_snapshot,e.snapshot AS occurrence_snapshot,p.item AS plan_item
FROM daily_action a
JOIN daily_expectation e ON e.id=a.bucket AND e.person=a.person
JOIN daily_plan p ON p.id=e.plan AND p.person=e.person
JOIN daily_version_audit v ON v.id=json_extract(e.snapshot,'\$.version') AND v.plan=e.plan AND v.person=e.person
${records ? 'JOIN administration r ON r.id=a.record AND r.person=a.person AND r.item=p.item' : ''}
WHERE a.person=? AND a.kind=? AND $key IN ($marks)
${records ? '' : 'AND a.undone=0'} ORDER BY $key''',
        [personId, records ? 'taken' : 'skip', ...chunk],
      );
      final seen = <String>{};
      for (final row in rows) {
        final target = row['target'] as String;
        // Invalid duplicate evidence must not silently choose a version.
        if (!seen.add(target)) {
          throw const CommandConflict('plan_instruction_identity');
        }
        final plan = decodeDailyPlan(
          dailyObject(row['plan_snapshot'] as String),
        );
        final occurrence = decodeDailyExpectation(
          dailyObject(row['occurrence_snapshot'] as String),
        );
        if (plan.personId != personId ||
            occurrence.identity.personId != personId ||
            plan.planId != occurrence.identity.planId ||
            plan.versionId != occurrence.versionId ||
            plan.itemId != occurrence.itemId ||
            plan.itemId != row['plan_item']) {
          throw const CommandConflict('plan_instruction_identity');
        }
        if (plan.instructions.isNotEmpty) {
          result[target] = SavedPlanInstruction(
            planId: plan.planId,
            versionId: plan.versionId,
            text: plan.instructions,
          );
        }
      }
    }
    return result;
  }
}
