import 'plan_requirement_badges.dart';
import 'plan_timing_fields.dart' show PlanTimingSummary;
import '../../app/display_preferences.dart';
import '../../ui/vital_ui.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/storage.dart';
import '../../data/record_store.dart';
import '../../domain/scheduling/interval_resolver.dart';
import '../../l10n/app_localizations.dart';
import '../recording/record_pages.dart';
import 'plan_form.dart';

/// Raw fields survive lock/reopen; calculated previews are always regenerated.
class IntervalFormFields {
  final duration = TextEditingController(), anchor = TextEditingController();
  String segment = newCommandId();
  IntervalMode mode = IntervalMode.fixedPlanned;
  bool reminderEnabled = false;
  ElapsedInterval? _original;
  List<TextEditingController> get controllers => [duration, anchor];
  Map<String, String> capture() => {
    'intervalMode': mode.name,
    'intervalDuration': duration.text,
    'intervalAnchor': anchor.text,
    'intervalSegment': segment,
    'intervalReminder': '$reminderEnabled',
  };
  void restore(Map<String, String> fields) {
    mode =
        IntervalMode.values
            .where((v) => v.name == fields['intervalMode'])
            .firstOrNull ??
        IntervalMode.fixedPlanned;
    duration.text = fields['intervalDuration'] ?? '';
    anchor.text = fields['intervalAnchor'] ?? '';
    segment = fields['intervalSegment'] ?? segment;
    reminderEnabled = fields['intervalReminder'] == 'true';
  }

  void load(ElapsedInterval interval) {
    _original = interval;
    duration.text = interval.duration.hoursText;
    anchor.text = interval.plannedAnchor?.toIso8601String() ?? '';
    mode = interval.mode;
    reminderEnabled = interval.reminderEnabled;
    // Candidate preserves this segment unless the reviewed timing changes.
  }

  ElapsedInterval candidate(PlannedAmount amount) {
    DateTime? instant;
    if (mode == IntervalMode.fixedPlanned) {
      final text = anchor.text.trim();
      // Require an explicit offset. DateTime.parse otherwise uses this device's
      // zone, which would silently change the reviewed planned anchor.
      if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(text)) {
        throw const FormatException('interval_anchor_offset');
      }
      final offset = RegExp(r'[+-](\d{2}):(\d{2})$').firstMatch(text);
      if (offset != null &&
          (int.parse(offset[1]!) > 23 || int.parse(offset[2]!) > 59)) {
        throw const FormatException();
      }
      instant = DateTime.parse(text).toUtc();
      // Reject DateTime.parse's normalisation of overflowing calendar fields.
      final day = CivilDate.parse(text.substring(0, 10));
      if (day.toString() != text.substring(0, 10)) {
        throw const FormatException();
      }
      final clock = RegExp(
        r'T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,6})?)?(?:Z|[+-]\d{2}:\d{2})$',
      ).firstMatch(text);
      if (clock == null ||
          int.parse(clock[1]!) > 23 ||
          int.parse(clock[2]!) > 59 ||
          int.parse(clock[3] ?? '0') > 59) {
        throw const FormatException();
      }
    }
    final parsed = ExactElapsed.parseHours(duration.text.trim());
    final original = _original;
    final preserve =
        original != null &&
        original.mode == mode &&
        original.duration.microseconds == parsed.microseconds &&
        original.plannedAnchor == instant;
    return ElapsedInterval(
      segmentId: preserve ? original.segmentId : segment,
      duration: parsed,
      mode: mode,
      amount: amount,
      plannedAnchor: instant,
      reminderEnabled: reminderEnabled,
    );
  }

  void dispose() {
    duration.dispose();
    anchor.dispose();
  }
}

class IntervalEditor extends StatelessWidget {
  const IntervalEditor({
    super.key,
    required this.fields,
    required this.enabled,
    required this.onChanged,
  });
  final IntervalFormFields fields;
  final bool enabled;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.intervalBasis),
        VitalSelect<IntervalMode>(
          label: t.intervalBasis,
          value: fields.mode,
          values: IntervalMode.values,
          labelOf: (mode) => mode == IntervalMode.fixedPlanned
              ? t.intervalFixed
              : t.intervalActual,
          enabled: enabled,
          onChanged: (mode) {
            fields.mode = mode;
            onChanged();
          },
        ),
        const SizedBox(height: 16),
        Text(
          fields.mode == IntervalMode.fixedPlanned
              ? t.intervalFixedHelp
              : t.intervalActualHelp,
        ),
        LabelledInput(
          key: const ValueKey('intervalDuration'),
          label: t.intervalDuration,
          helper: t.intervalDurationHelp,
          controller: fields.duration,
          enabled: enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        if (fields.mode == IntervalMode.fixedPlanned)
          LabelledInput(
            picker: VitalPickerKind.instant,
            key: const ValueKey('intervalAnchor'),
            label: t.intervalAnchor,
            helper: t.intervalAnchorHelp,
            controller: fields.anchor,
            enabled: enabled,
            keyboardType: TextInputType.datetime,
          ),
      ],
    );
  }
}

final intervalSourcesProvider = StreamProvider.autoDispose
    .family<List<IntervalSource>, ({String planId, String personId})>((
      ref,
      query,
    ) async* {
      final store = await ref.watch(recordStoreProvider.future);
      await for (final _ in store.watchRecords(
        scope: FeedScope.person(query.personId),
        limit: 1,
      )) {
        yield await store.intervalSources(
          planId: query.planId,
          personId: query.personId,
        );
      }
    });

class IntervalPlanPreview extends ConsumerWidget {
  const IntervalPlanPreview({
    super.key,
    required this.plan,
    required this.observedZone,
  });
  final DailyPlanVersion plan;
  final String observedZone;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final sources = ref.watch(
      intervalSourcesProvider((planId: plan.planId, personId: plan.personId)),
    );
    return sources.when(
      loading: () => Text(t.loadingRecords),
      error: (_, _) => LoadFailure(
        onRetry: () => ref.invalidate(
          intervalSourcesProvider((
            planId: plan.planId,
            personId: plan.personId,
          )),
        ),
      ),
      data: (sources) {
        final result = IntervalResolver().current(
          plan,
          now: DateTime.now().toUtc(),
          observedZone: observedZone,
          sources: sources,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            Heading(t.planPreview),
            PlanTimingSummary(policy: plan.timingPolicy),
            if (plan.requirements != null) ...[
              Heading(t.screenScheduleRequirements),
              PlanRequirementBadges(requirements: plan.requirements),
            ],
            if (plan.onOff case final block?) ...[
              Text(
                t.pauseBlockSummary(
                  block.onDays,
                  block.offDays,
                  block.anchor.toString(),
                ),
              ),
              Text(t.pauseIntersection),
            ],
            if (plan.pauses.any((p) => p.contains(DateTime.now().toUtc())))
              Text(t.pauseState),
            if (!result.complete)
              Text(t.planCalculationIssue)
            else if (result.issue == IntervalIssue.noAnchor) ...[
              Text(t.intervalNoAnchor),
              Text(t.intervalNoAnchorHelp),
              VitalButton.secondary(
                onPressed: () => context.push('/record/${plan.itemId}'),
                child: Text(t.record),
              ),
            ] else if (result.next == null) ...[
              Text(t.planNoNext),
              if ((plan.timing as ElapsedInterval).mode ==
                      IntervalMode.qualifyingActual &&
                  plan.pauses.isNotEmpty) ...[
                Text(t.pauseActualHelp),
                VitalButton.secondary(
                  onPressed: () => context.push('/item/${plan.itemId}'),
                  child: Text(t.review),
                ),
                VitalButton.secondary(
                  onPressed: () => context.push(
                    '/schedule/${plan.itemId}?plan=${plan.planId}',
                  ),
                  child: Text(t.edit),
                ),
              ],
            ] else ...[
              Text(
                t.intervalNext(
                  displayStamp(context, ref, result.next!.instant!),
                ),
              ),
              Text(expectationLabel(context, ref, t, result.next!)),
            ],
          ],
        );
      },
    );
  }
}
