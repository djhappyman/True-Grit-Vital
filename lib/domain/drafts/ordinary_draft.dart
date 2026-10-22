import 'dart:convert';

/// Only ordinary entry fields belong here. Passwords and platform credentials
/// have no representation in this deliberately closed snapshot format.
enum DraftKind {
  item,
  dose,
  correction,
  profile,
  dailyPlan,
  pausePlan,
  phasePlan,
  itemType,
  stockContainer,
  stockAdjustment,
  productLabel,
  combinedDose,
  combinedCorrection,
  siteEdit,
  event,
  usePeriod,
  eventReview,
  attachmentRename,
  labPanel,
  supportingObservation,
  supportingVoid,
  itemDetails,
}

final class OrdinaryDraft {
  OrdinaryDraft({
    required this.id,
    required this.generation,
    required this.operationId,
    required this.kind,
    required this.personId,
    required this.personRevision,
    required this.targetId,
    required this.targetRevision,
    required Map<String, String> fields,
    this.submitted = false,
  }) : fields = Map.unmodifiable(fields) {
    final allowed = switch (kind) {
      DraftKind.supportingVoid => {'isVoided'},
      DraftKind.itemDetails => {'instructions', 'notes'},
      DraftKind.attachmentRename => {'name', 'frozen'},
      DraftKind.labPanel ||
      DraftKind.supportingObservation => {'payload', 'frozen'},
      DraftKind.event => {
        'id',
        'name',
        'notes',
        'zone',
        'type',
        'plannedStart',
        'plannedEnd',
        'actualStart',
        'actualEnd',
        'completed',
        'memberships',
        'frozen',
        'reviewedFingerprint',
        'reviewGuard',
      },
      DraftKind.usePeriod => {
        'id',
        'item',
        'start',
        'end',
        'kind',
        'firstEver',
        'frozen',
      },
      DraftKind.eventReview => {
        'review',
        'item',
        'decision',
        'frozen',
        'clock',
        'reviewedAt',
        'stopReview',
      },
      DraftKind.combinedDose || DraftKind.combinedCorrection => {
        'components',
        'instant',
        'date',
        'time',
        'frozen',
        'voided',
      },
      DraftKind.siteEdit => {'site'},
      DraftKind.item => {
        'name',
        'form',
        'unit',
        'type',
        'typeId',
        'typeRevision',
        'query',
        'catalogue',
        'productEnabled',
        'productComponents',
      },
      DraftKind.itemType => {'name'},
      DraftKind.productLabel => {'productComponents', 'productRevision'},
      DraftKind.stockContainer => {
        'label',
        'unit',
        'strength',
        'strengthKnown',
        'productLabel',
        'productComponents',
        'concentration',
        'opening',
        'openingKnown',
        'threshold',
        'refill',
        'lot',
        'expiry',
        'capacity',
      },
      DraftKind.stockAdjustment => {
        'kind',
        'amount',
        'unknown',
        'reason',
        'clearThreshold',
        'lot',
        'expiry',
        'capacity',
      },
      DraftKind.dose || DraftKind.correction => {
        'amount',
        'site',
        'siteOpen',
        'date',
        'time',
        'instant',
        'container',
        'containerRevision',
        'baseContainer',
        'baseRevision',
        'keep',
        'stockCorrection',
        'labelOnly',
        'labelStrength',
        'labelConcentration',
        'enteredUnit',
        'amountEdited',
        'productUse',
        'intervalClockSample',
        'productLabel',
        'notes',
        'contextTags',
      },
      DraftKind.phasePlan => {
        'planId',
        'versionId',
        'phases',
        'originPhases',
        'endMode',
        'endValue',
        'endZone',
        'overrides',
        'reviewedAt',
        'reviewedZone',
        'intervalClockSample',
        'originalDate',
        'targetInstant',
        'overrideAmount',
        'selectedIdentity',
        'selectedExpectation',
        'collisionRows',
        'collisionReviewed',
        'windowEnd',
        'windowAnchor',
        'targetZone',
      },
      DraftKind.pausePlan => {
        'planId',
        'versionId',
        'pauseInstant',
        'resumeChoice',
        'restartAnchor',
        'intervalClockSample',
        'reviewedAt',
        'reviewedZone',
      },
      DraftKind.dailyPlan => {
        'blockEnabled',
        'blockOn',
        'blockOff',
        'blockAnchor',
        'planId',
        'versionId',
        'mode',
        'basis',
        'start',
        'end',
        'count',
        'amount',
        'home',
        'instructions',
        'slots',
        'calendarPattern',
        'calendarSelector',
        'calendarMissing',
        'calendarWeekdays',
        'calendarWeekday',
        'calendarOrdinal',
        'calendarAnchor',
        'calendarInterval',
        'calendarDay',
        'calendarError',
        'intervalMode',
        'intervalDuration',
        'intervalAnchor',
        'intervalSegment',
        'intervalReminder',
        'intervalClockSample',
      },
      DraftKind.profile => {
        'name',
        'report',
        'relationship',
        'notes',
        'adult',
        'action',
      },
    };
    if (id.isEmpty ||
        operationId.isEmpty ||
        fields.keys.any((k) => !allowed.contains(k)) ||
        fields.entries.any(
          (entry) =>
              entry.value.length >
              (kind == DraftKind.phasePlan &&
                      (entry.key == 'phases' ||
                          entry.key == 'overrides' ||
                          entry.key == 'originPhases' ||
                          entry.key == 'selectedExpectation' ||
                          entry.key == 'collisionRows' ||
                          entry.key == 'collisionReviewed')
                  ? 2000000
                  : (kind == DraftKind.labPanel ||
                                kind == DraftKind.supportingObservation) &&
                            entry.key == 'payload' ||
                        entry.key == 'components' ||
                        entry.key == 'frozen' ||
                        entry.key == 'memberships' ||
                        entry.key == 'reviewGuard' ||
                        entry.key == 'reviewedFingerprint' ||
                        entry.key == 'stopReview' ||
                        entry.key == 'review'
                  ? 2000000
                  : entry.key == 'productUse'
                  ? 70000
                  : kind == DraftKind.dailyPlan && entry.key == 'instructions'
                  ? 8000
                  : ((kind == DraftKind.dailyPlan && entry.key == 'slots' ||
                            kind == DraftKind.item &&
                                entry.key == 'catalogue' ||
                            entry.key == 'productComponents' ||
                            entry.key == 'productLabel')
                        ? 32000
                        : 4000)),
        ) ||
        personRevision != null && personRevision! < 1 ||
        targetRevision != null && targetRevision! < 1) {
      throw const FormatException('draft_fields');
    }
    if (kind == DraftKind.supportingVoid &&
        (personId == null ||
            personRevision == null ||
            targetId == null ||
            targetRevision == null ||
            (fields['isVoided'] != 'true' && fields['isVoided'] != 'false'))) {
      // A recovery intent is meaningful only with its exact captured identity.
      throw const FormatException('draft_identity');
    }
  }
  final String id, generation, operationId;
  final DraftKind kind;
  final String? personId, targetId;
  final int? personRevision, targetRevision;
  final Map<String, String> fields;
  final bool submitted;

  /// The exact confirmed void or restore request, kept as closed fields rather
  /// than a mutable copy of the record. Resume reconstruction must never infer
  /// the intended action from the record's current state.
  factory OrdinaryDraft.supportingVoid({
    required String id,
    required String operationId,
    required String generation,
    required String personId,
    required int personRevision,
    required String recordId,
    required int recordRevision,
    required bool isVoided,
  }) => OrdinaryDraft(
    id: id,
    generation: generation,
    operationId: operationId,
    kind: DraftKind.supportingVoid,
    personId: personId,
    personRevision: personRevision,
    targetId: recordId,
    targetRevision: recordRevision,
    fields: {'isVoided': isVoided.toString()},
  );

  String get route => switch (kind) {
    DraftKind.supportingVoid => '/supporting/$personId/$targetId?resume=$id',
    DraftKind.attachmentRename => '/attachment/$targetId/rename',
    DraftKind.labPanel || DraftKind.supportingObservation =>
      targetId == null
          ? '/supporting/$personId/${kind == DraftKind.labPanel ? 'add-panel' : 'add-observation'}'
          : '/supporting/$personId/$targetId/edit',
    DraftKind.event =>
      targetId == null
          ? '/event-create?person=$personId'
          : '/event/$targetId/edit',
    DraftKind.usePeriod =>
      '/use/$personId/${fields['item']}/edit${targetId == null ? '' : '?period=$targetId'}',
    DraftKind.eventReview =>
      '/event/$targetId/decision${(fields['item'] ?? '').isEmpty ? '' : '?item=${fields['item']}'}',
    DraftKind.siteEdit => '/site/$personId/$targetId',
    DraftKind.combinedDose => '/combined/$personId',
    DraftKind.combinedCorrection =>
      '/combined/$personId/edit/$targetId${fields['voided'] == 'true' ? '?undo=true' : ''}',
    DraftKind.item => '/create?person=$personId',
    DraftKind.itemDetails => '/substance/$targetId/details',
    DraftKind.productLabel => '/products/$personId/label/$targetId',
    DraftKind.itemType =>
      '/types/$personId/edit${targetId == null ? '' : '?type=$targetId'}',
    DraftKind.stockContainer => '/stock/$personId/create?item=$targetId',
    DraftKind.stockAdjustment =>
      '/stock/$personId/adjust/$targetId${fields['kind'] == 'notices'
          ? '?notices=true'
          : fields['kind'] == 'details'
          ? '?details=true'
          : ''}',
    DraftKind.dose => '/record/$targetId',
    DraftKind.correction => '/correct/$targetId?person=$personId',
    DraftKind.dailyPlan => '/schedule/$targetId?plan=${fields['planId']}',
    DraftKind.pausePlan => '/pause/$targetId?plan=${fields['planId']}',
    DraftKind.phasePlan => '/phases/$targetId?plan=${fields['planId']}',
    DraftKind.profile => targetId == null ? '/people/add' : '/people/$targetId',
  };
  String encode() => jsonEncode({'fields': fields, 'submitted': submitted});
  factory OrdinaryDraft.decode(Map<String, Object?> row) {
    final value = jsonDecode(row['snapshot'] as String) as Map<String, dynamic>;
    return OrdinaryDraft(
      id: row['id'] as String,
      generation: row['generation'] as String,
      operationId: row['operation'] as String,
      kind: DraftKind.values.byName(row['kind'] as String),
      personId: row['person'] as String?,
      personRevision: row['person_revision'] as int?,
      targetId: row['target'] as String?,
      targetRevision: row['target_revision'] as int?,
      fields: Map<String, String>.from(value['fields'] as Map),
      submitted: value['submitted'] == true,
    );
  }
}
