part of 'record_store.dart';

/// The factual plan configuration of one substance at the queried instant.
/// Status is never an adherence judgement and never a clinical state.
enum SubstancePlanStatus { active, paused, asNeeded }

/// Whole-collection filters over the statuses above. They may overlap because
/// an item can carry more than one current plan configuration.
enum SubstanceStatusFilter { all, active, paused, asNeeded, unscheduled }

/// One item's current plan configuration. An empty [statuses] set with
/// [unresolved] false means that no plan applies now: no plan is stored, or
/// every stored plan is future-only or ended. [unresolved] means the stored
/// dates or zone could not be evaluated, so the item is deliberately left out
/// of Active, Paused, As needed and Unscheduled rather than being guessed.
final class SubstancePlanPresence {
  const SubstancePlanPresence({required this.statuses, this.unresolved = false});
  const SubstancePlanPresence.none()
    : statuses = const <SubstancePlanStatus>{},
      unresolved = false;
  const SubstancePlanPresence.unresolved()
    : statuses = const <SubstancePlanStatus>{},
      unresolved = true;
  final Set<SubstancePlanStatus> statuses;
  final bool unresolved;
  bool get hasCurrentPlan => statuses.isNotEmpty;
  bool get isUnscheduled => statuses.isEmpty && !unresolved;
}

/// Totals for every status filter under the same name, type and time
/// snapshot. The counts may overlap; they are not adherence percentages.
final class SubstanceStatusCounts {
  const SubstanceStatusCounts({
    required this.all,
    required this.active,
    required this.paused,
    required this.asNeeded,
    required this.unscheduled,
    required this.unresolved,
  });
  const SubstanceStatusCounts.empty()
    : all = 0,
      active = 0,
      paused = 0,
      asNeeded = 0,
      unscheduled = 0,
      unresolved = 0;
  final int all, active, paused, asNeeded, unscheduled, unresolved;
  int count(SubstanceStatusFilter filter) => switch (filter) {
    SubstanceStatusFilter.all => all,
    SubstanceStatusFilter.active => active,
    SubstanceStatusFilter.paused => paused,
    SubstanceStatusFilter.asNeeded => asNeeded,
    SubstanceStatusFilter.unscheduled => unscheduled,
  };
}

/// One evaluated collection snapshot. [orderedIds] preserves the stored name
/// order used by the list. Every id has an entry in [statuses], including an
/// empty set for an item without a current plan. [unresolved] contains the
/// items whose stored plan could not be evaluated.
final class SubstanceStatusSnapshot {
  SubstanceStatusSnapshot({
    required Iterable<String> orderedIds,
    required Map<String, Set<SubstancePlanStatus>> statuses,
    required this.unresolved,
    required this.counts,
  }) : orderedIds = List.unmodifiable(orderedIds),
       statuses = Map.unmodifiable({
         for (final entry in statuses.entries)
           entry.key: Set.unmodifiable(entry.value),
       });
  SubstanceStatusSnapshot.empty()
    : orderedIds = const <String>[],
      statuses = const <String, Set<SubstancePlanStatus>>{},
      unresolved = const <String>{},
      counts = const SubstanceStatusCounts.empty();
  final List<String> orderedIds;
  final Map<String, Set<SubstancePlanStatus>> statuses;
  final Set<String> unresolved;
  final SubstanceStatusCounts counts;

  Set<SubstancePlanStatus> statusesFor(String itemId) =>
      statuses[itemId] ?? const <SubstancePlanStatus>{};
  bool isUnresolved(String itemId) => unresolved.contains(itemId);

  /// Ids for one filter in stored name order. Unscheduled excludes unresolved
  /// items so an unreadable plan is never reported as absent.
  Iterable<String> itemIdsFor(SubstanceStatusFilter filter) {
    if (filter == SubstanceStatusFilter.all) return orderedIds;
    if (filter == SubstanceStatusFilter.unscheduled) {
      return orderedIds.where(
        (id) => !unresolved.contains(id) && statusesFor(id).isEmpty,
      );
    }
    final status = switch (filter) {
      SubstanceStatusFilter.active => SubstancePlanStatus.active,
      SubstanceStatusFilter.paused => SubstancePlanStatus.paused,
      SubstanceStatusFilter.asNeeded => SubstancePlanStatus.asNeeded,
      SubstanceStatusFilter.all ||
      SubstanceStatusFilter.unscheduled => throw StateError('status_filter'),
    };
    return orderedIds.where((id) => statusesFor(id).contains(status));
  }
}

/// A version is inside the whole possible-date envelope, so it applies in every
/// zone at the queried instant.
bool _planEnvelopeInside(
  DailyPlanVersion plan,
  (CivilDate, CivilDate) envelope,
) =>
    plan.start.compareTo(envelope.$1) <= 0 &&
    (plan.endExclusive == null ||
        plan.endExclusive!.compareTo(envelope.$2) >= 0);

/// A version can apply in at least one possible zone at the queried instant.
bool _planEnvelopeIntersects(
  DailyPlanVersion plan,
  (CivilDate, CivilDate) envelope,
) =>
    plan.start.compareTo(envelope.$2) < 0 &&
    (plan.endExclusive == null || plan.endExclusive!.compareTo(envelope.$1) > 0);

/// Evaluates one plan's current configuration without reading or writing any
/// records. Civil start/end are inclusive/exclusive; intraday effective bounds
/// are half-open instants. Pauses are exact UTC intervals.
///
/// Calendar selection and repeating off phases are deliberately ignored here:
/// a configured scheduled plan remains Active on an off weekday. Only a real
/// pause makes it Paused. An As needed plan that is paused is Paused, not As
/// needed, while the pause lasts.
SubstancePlanPresence evaluateSubstancePlanPresence({
  required Iterable<DailyPlanVersion> versions,
  required DateTime now,
  required String? observedZone,
  required (CivilDate, CivilDate) envelope,
  PlanEnd? end,
}) {
  if (end != null && !now.isBefore(end.exclusiveInstant)) {
    return const SubstancePlanPresence.none();
  }
  final effective = versions
      .where((version) => version.includesInstant(now))
      .toList();
  if (effective.isEmpty) return const SubstancePlanPresence.none();
  final statuses = <SubstancePlanStatus>{};
  var unresolved = false;
  for (final version in effective) {
    final zoneId = switch (version.zoneBasis) {
      FixedHome(:final zoneId) => zoneId,
      FollowingLocal() => observedZone,
    };
    bool? applies;
    if (zoneId == null) {
      if (!_planEnvelopeIntersects(version, envelope)) {
        applies = false;
      } else if (_planEnvelopeInside(version, envelope)) {
        applies = true;
      } else {
        // The local date cannot be known without a zone, and the stored civil
        // bounds sit inside the possible-date envelope. Leave the item in All
        // rather than guessing a status.
        applies = null;
      }
    } else {
      try {
        applies = version.includes(IanaClock().dateAt(now, zoneId));
      } on Exception {
        applies = null;
      }
    }
    if (applies == null) {
      unresolved = true;
      continue;
    }
    if (!applies) continue;
    final paused = version.pauses.any((pause) => pause.contains(now));
    if (paused) {
      statuses.add(SubstancePlanStatus.paused);
    } else if (version.timing is AsNeeded) {
      statuses.add(SubstancePlanStatus.asNeeded);
    } else {
      statuses.add(SubstancePlanStatus.active);
    }
  }
  if (statuses.isEmpty && unresolved) {
    return const SubstancePlanPresence.unresolved();
  }
  return SubstancePlanPresence(
    statuses: Set.unmodifiable(statuses),
    unresolved: unresolved,
  );
}

extension SubstanceStatusRecordStore on RecordStore {
  /// Evaluates the whole eligible collection under one name, type and instant
  /// snapshot. The candidate item ids come from the same store-backed search
  /// and type predicate as [items]; plans, versions and phase ends are loaded
  /// in bounded bulk queries rather than one query per card.
  Future<SubstanceStatusSnapshot> substanceStatusSnapshot({
    String personId = meId,
    FeedScope? scope,
    String? search,
    String? typeId,
    required DateTime now,
    String? observedZone,
  }) async {
    final candidates = await _rows(
      'SELECT item.id FROM item WHERE ${_itemFilterSql(personId, scope, search, typeId)} ORDER BY item.name,item.id',
      _itemFilterArgs(personId, scope, search, typeId),
    );
    final orderedIds = [for (final row in candidates) row['id'] as String];
    if (orderedIds.isEmpty) return SubstanceStatusSnapshot.empty();
    final candidateIds = orderedIds.toSet();
    final everyone = scope?.isEveryone == true;
    final scopePerson = everyone ? null : scope?.personId ?? personId;
    final planScope = everyone
        ? 'o.archived=0'
        : 'o.archived=0 AND p.person=?';
    final planScopeArgs = <Object?>[if (!everyone) scopePerson];

    final planRows = await _rows(
      'SELECT p.id,p.person,p.item FROM daily_plan p JOIN person o ON o.id=p.person WHERE $planScope ORDER BY p.id',
      planScopeArgs,
    );
    final plansByItem = <String, List<String>>{};
    for (final row in planRows) {
      final itemId = row['item'] as String;
      if (!candidateIds.contains(itemId)) continue;
      (plansByItem[itemId] ??= <String>[]).add(row['id'] as String);
    }
    if (plansByItem.isEmpty) {
      return SubstanceStatusSnapshot(
        orderedIds: orderedIds,
        statuses: {for (final id in orderedIds) id: const <SubstancePlanStatus>{}},
        unresolved: const <String>{},
        counts: SubstanceStatusCounts(
          all: orderedIds.length,
          active: 0,
          paused: 0,
          asNeeded: 0,
          unscheduled: orderedIds.length,
          unresolved: 0,
        ),
      );
    }

    final clock = IanaClock();
    final envelope = clock.dateEnvelopeAt(now);
    final versionRows = await _rows(
      "SELECT v.plan,v.person,v.snapshot FROM daily_version v JOIN daily_plan p ON p.id=v.plan AND p.person=v.person JOIN person o ON o.id=p.person WHERE $planScope AND v.start<=? AND (v.end IS NULL OR v.end>?) AND (json_extract(v.snapshot,'\$.effectiveFrom') IS NULL OR json_extract(v.snapshot,'\$.effectiveFrom')<=?) AND (json_extract(v.snapshot,'\$.effectiveUntil') IS NULL OR json_extract(v.snapshot,'\$.effectiveUntil')>?) ORDER BY v.plan,v.start DESC,COALESCE(json_extract(v.snapshot,'\$.effectiveFrom'),-9223372036854775808) DESC,v.rowid DESC",
      [
        ...planScopeArgs,
        envelope.$2.toString(),
        envelope.$1.toString(),
        now.microsecondsSinceEpoch,
        now.microsecondsSinceEpoch,
      ],
    );
    final anyVersionRows = await _rows(
      'SELECT v.plan,COUNT(*) AS count FROM daily_version v JOIN daily_plan p ON p.id=v.plan AND p.person=v.person JOIN person o ON o.id=p.person WHERE $planScope GROUP BY v.plan',
      planScopeArgs,
    );
    final hasAnyVersion = {
      for (final row in anyVersionRows)
        row['plan'] as String: (row['count'] as int) > 0,
    };
    final versionsByPlan = <String, List<DailyPlanVersion>>{};
    final invalidPlans = <String>{};
    for (final row in versionRows) {
      final planId = row['plan'] as String;
      try {
        (versionsByPlan[planId] ??= <DailyPlanVersion>[]).add(
          decodeDailyPlan(dailyObject(row['snapshot'] as String)),
        );
      } on Object {
        invalidPlans.add(planId);
      }
    }
    final ends = <String, PlanEnd>{};
    final phaseRows = await _rows(
      'SELECT pp.plan,pp.snapshot FROM phase_plan pp JOIN daily_plan p ON p.id=pp.plan AND p.person=pp.person JOIN person o ON o.id=p.person WHERE $planScope',
      planScopeArgs,
    );
    for (final row in phaseRows) {
      final planId = row['plan'] as String;
      try {
        final end = decodePhasePlan(
          dailyObject(row['snapshot'] as String),
        ).end;
        if (end != null) ends[planId] = end;
      } on Object {
        invalidPlans.add(planId);
      }
    }

    final statuses = <String, Set<SubstancePlanStatus>>{};
    final unresolved = <String>{};
    var active = 0, paused = 0, asNeeded = 0, unscheduled = 0;
    for (final itemId in orderedIds) {
      final planIds = plansByItem[itemId] ?? const <String>[];
      final itemStatuses = <SubstancePlanStatus>{};
      var itemUnresolved = false;
      if (planIds.isEmpty) {
        // No stored routine at all: truthfully unscheduled.
      } else {
        for (final planId in planIds) {
          if (invalidPlans.contains(planId)) {
            itemUnresolved = true;
            continue;
          }
          final versions = versionsByPlan[planId];
          if (versions == null || versions.isEmpty) {
            if (hasAnyVersion[planId] == true) {
              // Versions exist but none can apply now: a deliberate phase gap,
              // a future-only plan or an ended plan.
              continue;
            }
            itemUnresolved = true;
            continue;
          }
          final presence = evaluateSubstancePlanPresence(
            versions: versions,
            now: now,
            observedZone: observedZone,
            envelope: envelope,
            end: ends[planId],
          );
          itemStatuses.addAll(presence.statuses);
          if (presence.unresolved) itemUnresolved = true;
        }
      }
      statuses[itemId] = Set.unmodifiable(itemStatuses);
      if (itemUnresolved) unresolved.add(itemId);
      if (itemStatuses.contains(SubstancePlanStatus.active)) active++;
      if (itemStatuses.contains(SubstancePlanStatus.paused)) paused++;
      if (itemStatuses.contains(SubstancePlanStatus.asNeeded)) asNeeded++;
      if (itemStatuses.isEmpty && !itemUnresolved) unscheduled++;
    }
    return SubstanceStatusSnapshot(
      orderedIds: orderedIds,
      statuses: statuses,
      unresolved: unresolved,
      counts: SubstanceStatusCounts(
        all: orderedIds.length,
        active: active,
        paused: paused,
        asNeeded: asNeeded,
        unscheduled: unscheduled,
        unresolved: unresolved.length,
      ),
    );
  }

  Stream<SubstanceStatusSnapshot> watchSubstanceStatusSnapshot({
    String personId = meId,
    FeedScope? scope,
    String? search,
    String? typeId,
    required DateTime now,
    String? observedZone,
  }) => _watch(
    () => substanceStatusSnapshot(
      personId: personId,
      scope: scope,
      search: search,
      typeId: typeId,
      now: now,
      observedZone: observedZone,
    ),
  );

  Future<List<SubstanceItem>> itemsByIds(Iterable<String> ids) async {
    final ordered = ids.toList();
    if (ordered.isEmpty) return const <SubstanceItem>[];
    final rows = await _rows(
      'SELECT * FROM item WHERE id IN (${List.filled(ordered.length, '?').join(',')})',
      ordered,
    );
    final byId = {
      for (final row in rows) row['id'] as String: _item(row),
    };
    return [for (final id in ordered) ?byId[id]];
  }

  Stream<List<SubstanceItem>> watchItemsByIds(Iterable<String> ids) =>
      _watch(() => itemsByIds(ids));
}
