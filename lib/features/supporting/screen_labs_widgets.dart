import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/display_preferences.dart';
import '../../app/supporting.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/stitch_ui.dart';
import '../../ui/vital_ui.dart';
import 'screen_labs_latest.dart';
import 'supporting_sparkline.dart';
import 'supporting_widgets.dart';

/// Small accent eyebrow with an optional factual right-hand value or action.
class ScreenLabsSectionHeader extends StatelessWidget {
  const ScreenLabsSectionHeader({
    super.key,
    required this.title,
    this.trailing,
  });
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = StitchColors(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title.toUpperCase(),
              style: StitchType.small.copyWith(
                color: colors.accent,
                fontWeight: FontWeight.w600,
                letterSpacing: .6,
              ),
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: DefaultTextStyle.merge(
              textAlign: TextAlign.end,
              style: StitchType.small.copyWith(color: colors.muted),
              child: trailing!,
            ),
          ),
        ],
      ],
    );
  }
}

/// The newest result for one marker with its exact unit, range, source date and
/// a comparable previous value. No clinical class, target or risk wording.
class ScreenLabsLatestCard extends ConsumerWidget {
  const ScreenLabsLatestCard({
    super.key,
    required this.value,
    required this.person,
    required this.returnLocation,
  });
  final ScreenLabsLatestValue value;
  final String person, returnLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context), colors = StitchColors(context);
    final result = value.result, record = value.record;
    final dateLabel = record.kind == SupportingRecordKind.labPanel
        ? t.supportingCollection
        : t.supportingMeasured;
    final missing = result.value.kind == SupportingValueKind.missing;
    final unit = result.unit;
    final provenance = result.provenance ?? record.snapshot.provenance;
    final entered = supportingEnteredValue(t, result);
    final previous = value.previousResult;
    final change = result.value.isExactNumeric && previous != null
        ? screenLabsChange(
            result.value.exactAmount!,
            previous.value.exactAmount!,
          )
        : null;
    return StitchSurface(
      radius: VitalLayout.sectionRadius,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            label: t.screenLabsLatestSemantics(
              result.originalMarkerText,
              entered,
              unit ?? t.supportingUnitMissing,
              result.referenceRange?.originalText ?? t.supportingRangeMissing,
              t.supportingDateLabel(
                dateLabel,
                supportingDateLabel(
                  context,
                  ref,
                  record.snapshot.collectionDate,
                ),
              ),
              record.snapshot.title,
              provenance.laboratoryName ??
                  provenance.laboratoryId ??
                  t.supportingUnknown,
              result.sourceFlag ?? t.supportingUnknown,
            ),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StitchIcon(LucideIcons.flaskConical, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(result.markerName, style: StitchType.name),
                            if (result.originalMarkerText != result.markerName)
                              Text(
                                result.originalMarkerText,
                                style: StitchType.caption.copyWith(
                                  color: colors.muted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) => Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth,
                          ),
                          child: Text(
                            entered,
                            style: missing
                                ? StitchType.body.copyWith(color: colors.muted)
                                : result.value.kind ==
                                      SupportingValueKind.qualitative
                                ? VitalType.quantity
                                : VitalType.metric,
                          ),
                        ),
                        if (!missing && unit != null)
                          Text(
                            unit,
                            style: StitchType.label.copyWith(
                              color: colors.muted,
                            ),
                          ),
                        if (unit == null)
                          Text(
                            t.supportingUnitMissing,
                            style: StitchType.caption.copyWith(
                              color: colors.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    t.supportingDateLabel(
                      dateLabel,
                      supportingDateLabel(
                        context,
                        ref,
                        record.snapshot.collectionDate,
                      ),
                    ),
                    style: StitchType.caption.copyWith(color: colors.muted),
                  ),
                  if (supportingDateSourceLabel(
                        context,
                        ref,
                        record.snapshot.collectionDate,
                      )
                      case final source?)
                    Text(
                      source,
                      style: StitchType.caption.copyWith(color: colors.muted),
                    ),
                  Text(
                    t.screenLabsFromRecord(record.snapshot.title),
                    style: StitchType.caption.copyWith(color: colors.muted),
                  ),
                  if (missing && unit != null)
                    Text(
                      t.supportingDateLabel(t.supportingUnit, unit),
                      style: StitchType.caption.copyWith(color: colors.muted),
                    ),
                  if (provenance.laboratoryName ?? provenance.laboratoryId
                      case final lab?)
                    Text(
                      t.supportingDateLabel(t.supportingLab, lab),
                      style: StitchType.caption.copyWith(color: colors.muted),
                    ),
                  if (result.referenceRange case final range?)
                    Text(
                      t.supportingDateLabel(
                        t.supportingRange,
                        range.originalText,
                      ),
                      style: StitchType.caption.copyWith(color: colors.muted),
                    ),
                  if (result.sourceFlag case final flag?)
                    Text(
                      t.supportingDateLabel(t.supportingFlag, flag),
                      style: StitchType.caption.copyWith(color: colors.muted),
                    ),
                ],
              ),
            ),
          ),
          if (value.sparkline case final series? when series.hasPoints) ...[
            const SizedBox(height: 10),
            ScreenLabsSparkline(series: series, unit: unit),
          ],
          if (previous != null) ...[
            const SizedBox(height: 10),
            StitchSurface(
              inset: true,
              radius: 12,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        t.screenLabsPreviousValue(
                          supportingValueLabel(t, previous),
                        ),
                        style: StitchType.caption.copyWith(color: colors.muted),
                      ),
                      if (change != null)
                        VitalBadge(
                          t.screenLabsChange(
                            unit == null ? change : '$change $unit',
                          ),
                          compact: true,
                        ),
                    ],
                  ),
                  if (value.previousRecord case final earlier?)
                    Text(
                      t.supportingDateLabel(
                        dateLabel,
                        supportingDateLabel(
                          context,
                          ref,
                          earlier.snapshot.collectionDate,
                        ),
                      ),
                      style: StitchType.caption.copyWith(color: colors.muted),
                    ),
                ],
              ),
            ),
          ],
          for (final link in value.links) ...[
            const SizedBox(height: 4),
            Text(
              t.screenLabsLinked(link.name),
              style: StitchType.caption.copyWith(color: colors.muted),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Semantics(
                label: t.screenLabsOpenLinked(link.name),
                child: StitchButton(
                  quiet: true,
                  compact: true,
                  icon: LucideIcons.tags,
                  onPressed: () => context.push(
                    link.kind == SupportingContextKind.item
                        ? '/item/${link.id}'
                        : '/event/${link.id}',
                  ),
                  child: Text(t.supportingOpen),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StitchButton(
                compact: true,
                icon: LucideIcons.activity,
                onPressed: () => context.push(
                  Uri(
                    path: '/supporting/$person/trends',
                    queryParameters: {
                      'metric': result.metricId,
                      'kind': record.kind.name,
                    },
                  ).toString(),
                ),
                child: Text(t.supportingTrends),
              ),
              StitchButton(
                compact: true,
                onPressed: () => context.push(
                  Uri(
                    path: '/supporting/$person/${record.id.id}',
                    queryParameters: {'return': returnLocation},
                  ).toString(),
                ),
                child: Text(t.supportingOpen),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One saved panel or observation with its real result count, dates, source
/// laboratory and protected file state. Values stay in the detail page.
class ScreenLabsRecordCard extends ConsumerWidget {
  const ScreenLabsRecordCard({
    super.key,
    required this.record,
    required this.person,
    required this.returnLocation,
    required this.basis,
    this.primary = false,
  });
  final SupportingRevision record;
  final String person, returnLocation;
  final SupportingDateBasis basis;
  final bool primary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context), colors = StitchColors(context);
    final snapshot = record.snapshot;
    final panel = record.kind == SupportingRecordKind.labPanel;
    final laboratory =
        snapshot.provenance.laboratoryName ??
        snapshot.provenance.laboratoryId ??
        t.supportingUnknown;
    // Show the date this page is actually ordered by, so "Newest first" stays
    // truthful when a different date basis is chosen.
    final (dateHeading, dateValue) = switch (basis) {
      SupportingDateBasis.report => (
        t.supportingReport,
        supportingDateLabel(context, ref, snapshot.reportDate),
      ),
      SupportingDateBasis.entry => (
        t.supportingEntry,
        displayStamp(
          context,
          ref,
          record.enteredAt,
          zoneId: 'UTC',
          includeSeconds: true,
        ),
      ),
      SupportingDateBasis.collection => (
        panel ? t.supportingCollection : t.supportingMeasured,
        supportingDateLabel(context, ref, snapshot.collectionDate),
      ),
    };
    final sourceFile =
        [
          snapshot.provenance,
          ...snapshot.results
              .map((result) => result.provenance)
              .whereType<SupportingProvenance>(),
        ].any(
          (source) => source.sourceReferences.any(
            (reference) => reference.kind == SupportingSourceKind.attachment,
          ),
        );
    return StitchSurface(
      radius: VitalLayout.sectionRadius,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(snapshot.title, style: StitchType.name)),
              if (record.isVoided) ...[
                const SizedBox(width: 8),
                VitalBadge(t.supportingVoided, compact: true),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              VitalBadge(
                t.screenLabsResultsCount(snapshot.results.length),
                compact: true,
              ),
              if (sourceFile) VitalBadge(t.screenLabsSourceFile, compact: true),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            t.supportingDateLabel(dateHeading, dateValue),
            style: StitchType.caption.copyWith(color: colors.muted),
          ),
          Text(
            t.supportingDateLabel(t.supportingLab, laboratory),
            style: StitchType.caption.copyWith(color: colors.muted),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StitchButton(
                primary: primary,
                compact: true,
                onPressed: () => context.push(
                  Uri(
                    path: '/supporting/$person/${record.id.id}',
                    queryParameters: {'return': returnLocation},
                  ).toString(),
                ),
                child: Text(t.supportingOpen),
              ),
              StitchButton(
                compact: true,
                onPressed: () =>
                    context.push('/files/$person/supporting/${record.id.id}'),
                child: Text(t.attachments),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ScreenLabsPrivacyCard extends StatelessWidget {
  const ScreenLabsPrivacyCard({super.key});
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), colors = StitchColors(context);
    return StitchSurface(
      radius: VitalLayout.sectionRadius,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StitchIcon(LucideIcons.shieldCheck, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(t.screenLabsPrivacyTitle, style: StitchType.name),
                ),
                const SizedBox(height: 4),
                Text(
                  t.screenLabsPrivacyBody,
                  style: StitchType.caption.copyWith(color: colors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A local, factual filter summary. No hidden active filters.
class ScreenLabsFilterBadges extends StatelessWidget {
  const ScreenLabsFilterBadges({
    super.key,
    required this.basis,
    required this.from,
    required this.before,
    required this.includeUnknown,
    required this.includeVoided,
  });
  final SupportingDateBasis basis;
  final CivilDate? from, before;
  final bool includeUnknown, includeVoided;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final badges = <String>[
      if (basis == SupportingDateBasis.report) t.screenLabsBasisReport,
      if (basis == SupportingDateBasis.entry) t.screenLabsBasisEntry,
      if (from != null && before != null)
        t.chartRangeSummary(from.toString(), before.toString())
      else if (from != null)
        t.screenLabsRangeFrom(from.toString())
      else if (before != null)
        t.screenLabsRangeBefore(before.toString()),
      if (!includeUnknown) t.screenLabsUnknownExcluded,
      if (includeVoided) t.screenLabsVoidedIncluded,
    ];
    if (badges.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [for (final badge in badges) VitalBadge(badge, compact: true)],
    );
  }
}
