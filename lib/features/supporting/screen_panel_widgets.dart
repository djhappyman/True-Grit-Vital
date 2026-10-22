import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/app_lock.dart';
import '../../app/storage.dart';
import '../../app/display_preferences.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/stitch_ui.dart';
import '../../ui/vital_ui.dart';
import 'supporting_widgets.dart';

typedef ScreenPanelAttachmentRequest = ({String personId, String id});

/// One viewed result's complete earlier-comparable lookup. The store selects
/// candidates by the exact comparison identity and newest earlier day, so the
/// page never receives a page of unrelated panels.
typedef ScreenPanelEarlierRequest = ({
  String personId,
  String id,
  int revision,
  String resultId,
  String displayZone,
});

final screenPanelEarlierProvider = StreamProvider.autoDispose
    .family<SupportingEarlierComparison, ScreenPanelEarlierRequest>(
      retry: (_, _) => null,
      (ref, request) async* {
        if (ref.watch(appLockProvider.select((state) => state.locked))) {
          yield const SupportingEarlierComparison(
            status: SupportingEarlierStatus.none,
          );
          return;
        }
        final store = await ref.watch(recordStoreProvider.future);
        try {
          await for (final comparison in store.watchSupportingEarlierComparison(
            personId: request.personId,
            recordId: request.id,
            recordRevision: request.revision,
            resultId: request.resultId,
            displayZone: request.displayZone,
          )) {
            yield comparison;
          }
        } on CommandConflict catch (error) {
          if (error.code != 'app_locked') rethrow;
        }
      },
    );

/// Bounded saved files for one supporting record. The list is used only for
/// the checksums that were actually recorded when each file was saved.
final screenPanelAttachmentsProvider = StreamProvider.autoDispose
    .family<List<AttachmentRecord>, ScreenPanelAttachmentRequest>((
      ref,
      request,
    ) async* {
      if (ref.watch(appLockProvider.select((state) => state.locked))) {
        yield const <AttachmentRecord>[];
        return;
      }
      final store = await ref.watch(recordStoreProvider.future);
      yield* store.watchAttachments(
        personId: request.personId,
        targetKind: AttachmentTargetKind.supporting,
        targetId: request.id,
        limit: 25,
      );
    });

/// The saved name for a linked event. Items reuse the existing app lookup
/// provider because the event page imports this feature.
final screenPanelEventProvider = StreamProvider.autoDispose
    .family<EventRecord?, String>((ref, id) async* {
      if (ref.watch(appLockProvider.select((state) => state.locked))) {
        yield null;
        return;
      }
      final store = await ref.watch(recordStoreProvider.future);
      yield* store.watchEventById(id);
    });

enum ScreenPanelResultFilter { all, withRange, withoutRange }

class ScreenPanelHero extends StatelessWidget {
  const ScreenPanelHero({
    super.key,
    required this.title,
    required this.kindLabel,
    required this.laboratory,
    required this.collectionLabel,
    required this.dateLabel,
    required this.reportLabel,
    required this.revision,
    required this.resultCount,
    required this.voided,
    this.dateSource,
  });

  final String title, kindLabel, dateLabel;
  final String? laboratory, reportLabel, dateSource;
  final String collectionLabel;
  final int revision, resultCount;
  final bool voided;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final colors = VitalColors(context);
    return StitchSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              VitalBadge(kindLabel, compact: true),
              if (laboratory != null)
                Text(
                  laboratory!,
                  style: VitalType.metadata.copyWith(color: colors.muted),
                ),
              if (voided)
                VitalBadge(t.supportingVoided, tone: VitalTone.warning),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            header: true,
            child: Text(title, style: VitalType.detailTitle),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                t.supportingDateLabel(dateLabel, collectionLabel),
                style: VitalType.metadata.copyWith(color: colors.muted),
              ),
              Text(
                '·',
                style: VitalType.metadata.copyWith(color: colors.muted),
              ),
              if (reportLabel != null) ...[
                Text(
                  t.supportingDateLabel(t.supportingReport, reportLabel!),
                  style: VitalType.metadata.copyWith(color: colors.muted),
                ),
                Text(
                  '·',
                  style: VitalType.metadata.copyWith(color: colors.muted),
                ),
              ],
              Text(
                t.supportingRevisionLabel(revision),
                style: VitalType.metadata.copyWith(color: colors.muted),
              ),
            ],
          ),
          if (dateSource != null) ...[
            const SizedBox(height: 4),
            Text(
              dateSource!,
              style: VitalType.metadata.copyWith(color: colors.muted),
            ),
          ],
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  MediaQuery.textScalerOf(context).scale(1) > 1.4 ||
                  constraints.maxWidth < 240;
              final tiles = [
                ScreenPanelStat(
                  label: t.supportingResults,
                  value: '$resultCount',
                  detail: t.screenPanelRecorded,
                ),
                ScreenPanelStat(
                  label: t.screenPanelRevision,
                  value: '$revision',
                  detail: t.screenPanelSaved,
                ),
              ];
              return stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        tiles.first,
                        const SizedBox(height: 8),
                        tiles.last,
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: tiles.first),
                        const SizedBox(width: 12),
                        Expanded(child: tiles.last),
                      ],
                    );
            },
          ),
        ],
      ),
    );
  }
}

class ScreenPanelStat extends StatelessWidget {
  const ScreenPanelStat({
    super.key,
    required this.label,
    required this.value,
    required this.detail,
  });

  final String label, value, detail;

  @override
  Widget build(BuildContext context) {
    final colors = VitalColors(context);
    return StitchSurface(
      inset: true,
      radius: VitalLayout.sectionRadius,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: VitalType.micro.copyWith(color: colors.muted)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(value, style: VitalType.quantity),
              Text(
                detail,
                style: VitalType.micro.copyWith(color: colors.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ScreenPanelFilters extends StatelessWidget {
  const ScreenPanelFilters({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.allLabel,
    required this.rangeLabel,
    required this.noRangeLabel,
  });

  final ScreenPanelResultFilter selected;
  final ValueChanged<ScreenPanelResultFilter> onChanged;
  final String allLabel, rangeLabel, noRangeLabel;

  Widget _option(ScreenPanelResultFilter value, String label) {
    final isSelected = value == selected;
    void action() => onChanged(value);
    return MergeSemantics(
      child: Semantics(
        selected: isSelected,
        inMutuallyExclusiveGroup: true,
        child: StitchButton(
          primary: isSelected,
          compact: true,
          onPressed: action,
          child: Text(label),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      _option(ScreenPanelResultFilter.all, allLabel),
      if (rangeLabel.isNotEmpty)
        _option(ScreenPanelResultFilter.withRange, rangeLabel),
      if (noRangeLabel.isNotEmpty)
        _option(ScreenPanelResultFilter.withoutRange, noRangeLabel),
    ],
  );
}

class ScreenPanelResultCard extends StatelessWidget {
  const ScreenPanelResultCard({
    super.key,
    required this.result,
    required this.onTrends,
    this.comparison,
  });

  final LabResultSnapshot result;
  final VoidCallback onTrends;
  final Widget? comparison;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final colors = VitalColors(context);
    final range = result.referenceRange;
    final flag = result.sourceFlag;
    final markerName = result.markerName;
    final semantics = [
      t.supportingResultSemantics(
        result.originalMarkerText,
        supportingEnteredValue(t, result),
        result.unit ?? t.supportingUnitMissing,
        range?.originalText ?? t.supportingRangeMissing,
      ),
      if (flag != null) t.supportingDateLabel(t.supportingFlag, flag),
      ?range?.applicabilityText,
    ].join(' ');
    return StitchSurface(
      radius: VitalLayout.sectionRadius,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            label: semantics,
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final heading = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            result.originalMarkerText,
                            style: VitalType.record,
                          ),
                          if (markerName != result.originalMarkerText) ...[
                            const SizedBox(height: 2),
                            Text(
                              markerName,
                              style: VitalType.metadata.copyWith(
                                color: colors.muted,
                              ),
                            ),
                          ],
                        ],
                      );
                      final badge = flag == null
                          ? null
                          : VitalBadge(
                              t.supportingDateLabel(t.supportingFlag, flag),
                              tone: VitalTone.neutral,
                              compact: true,
                            );
                      final stacked =
                          MediaQuery.textScalerOf(context).scale(1) > 1.4 ||
                          constraints.maxWidth < 240;
                      if (badge == null) return heading;
                      if (stacked) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [heading, const SizedBox(height: 6), badge],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: heading),
                          const SizedBox(width: 8),
                          badge,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    supportingValueLabel(t, result),
                    style: result.value.kind == SupportingValueKind.missing
                        ? VitalType.record.copyWith(color: colors.muted)
                        : VitalType.quantity,
                  ),
                  if (result.unit == null) ...[
                    const SizedBox(height: 4),
                    Text(
                      t.supportingUnitMissing,
                      style: VitalType.metadata.copyWith(color: colors.muted),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    range == null
                        ? t.supportingRangeMissing
                        : t.supportingDateLabel(
                            t.supportingRange,
                            range.originalText,
                          ),
                    style: VitalType.metadata.copyWith(color: colors.muted),
                  ),
                  if (range?.applicabilityText case final applicability?) ...[
                    const SizedBox(height: 4),
                    Text(
                      applicability,
                      style: VitalType.metadata.copyWith(color: colors.muted),
                    ),
                  ],
                ],
              ),
            ),
          ),
          ?comparison,
          if (result.provenance case final provenance?) ...[
            const SizedBox(height: 12),
            SupportingProvenanceView(provenance: provenance),
          ],
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: StitchButton(
              icon: LucideIcons.activity,
              compact: true,
              onPressed: onTrends,
              child: Text(t.supportingTrends),
            ),
          ),
        ],
      ),
    );
  }
}

class ScreenPanelLinkedRecord extends ConsumerWidget {
  const ScreenPanelLinkedRecord({super.key, required this.link});

  final SupportingContextLink link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final item = link.kind == SupportingContextKind.item
        ? ref.watch(itemLookupProvider(link.id))
        : null;
    final event = link.kind == SupportingContextKind.event
        ? ref.watch(screenPanelEventProvider(link.id))
        : null;
    final loading = item?.isLoading == true || event?.isLoading == true;
    final name = link.kind == SupportingContextKind.item
        ? item?.value?.name
        : event?.value?.name;
    final route = link.kind == SupportingContextKind.item
        ? '/item/${link.id}'
        : '/event/${link.id}';
    final title = name ?? (loading ? t.loadingRecords : t.screenPanelLinkGone);
    return StitchSurface(
      radius: VitalLayout.sectionRadius,
      padding: EdgeInsets.zero,
      child: VitalCompactRow(
        title: title,
        subtitle: link.kind == SupportingContextKind.item
            ? t.screenPanelSubstance
            : t.screenPanelEvent,
        icon: link.kind == SupportingContextKind.item
            ? LucideIcons.pill
            : LucideIcons.calendarDays,
        trailing: name == null
            ? null
            : const Icon(LucideIcons.chevronRight, size: 18),
        onPressed: name == null ? null : () => GoRouter.of(context).push(route),
      ),
    );
  }
}

class ScreenPanelFiles extends ConsumerStatefulWidget {
  const ScreenPanelFiles({
    super.key,
    required this.personId,
    required this.id,
    required this.enabled,
    required this.onOpenFiles,
    required this.onExport,
    this.filesFocusNode,
  });

  final String personId, id;
  final bool enabled;
  final VoidCallback onOpenFiles, onExport;
  final FocusNode? filesFocusNode;

  @override
  ConsumerState<ScreenPanelFiles> createState() => _ScreenPanelFilesState();
}

class _ScreenPanelFilesState extends ConsumerState<ScreenPanelFiles> {
  String? copiedId;
  bool copyFailed = false;

  Future<void> _copy(AttachmentRecord file) async {
    final hash = file.inspection?.sha256;
    if (hash == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: hash));
      if (!mounted) return;
      setState(() {
        copiedId = file.id;
        copyFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        copiedId = null;
        copyFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final colors = VitalColors(context);
    final saved = ref.watch(
      screenPanelAttachmentsProvider((
        personId: widget.personId,
        id: widget.id,
      )),
    );
    final files =
        saved.value
            ?.where((file) => file.inspection?.sha256 != null)
            .toList(growable: false) ??
        const <AttachmentRecord>[];
    return VitalPanel(
      title: t.screenPanelFileChecksums,
      description: t.screenPanelFileChecksumsHelp,
      children: [
        if (saved.hasError)
          VitalNotice(
            tone: VitalTone.danger,
            icon: LucideIcons.circleAlert,
            action: Align(
              alignment: AlignmentDirectional.centerStart,
              child: VitalButton.secondary(
                onPressed: () => ref.invalidate(
                  screenPanelAttachmentsProvider((
                    personId: widget.personId,
                    id: widget.id,
                  )),
                ),
                child: Text(t.retry),
              ),
            ),
            child: Text(t.screenPanelChecksumsUnavailable),
          )
        else if (!saved.hasValue)
          Text(t.loadingRecords)
        else if (files.isEmpty)
          Text(
            saved.value!.isEmpty
                ? t.screenPanelNoFiles
                : t.screenPanelNoChecksums,
          )
        else ...[
          for (final file in files)
            VitalSurface(
              role: VitalSurfaceRole.inset,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    t.screenPanelFileLabel(file.name),
                    style: VitalType.record,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t.exportChecksumLabel,
                    style: VitalType.micro.copyWith(color: colors.muted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    file.inspection!.sha256,
                    style: VitalType.metadata.copyWith(letterSpacing: .18),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Semantics(
                      label: t.screenPanelCopyChecksum(file.name),
                      child: StitchButton(
                        key: ValueKey('screen-panel-copy-${file.id}'),
                        compact: true,
                        onPressed: () => _copy(file),
                        child: Text(
                          copiedId == file.id
                              ? t.screenPanelCopied
                              : t.screenPanelCopy,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (!saved.hasError && (saved.value?.length ?? 0) >= 25)
          Text(
            t.screenPanelChecksumLimit,
            style: VitalType.metadata.copyWith(color: colors.muted),
          ),
        if (copyFailed)
          Semantics(
            liveRegion: true,
            child: Text(
              t.screenPanelCopyFailed,
              style: VitalType.metadata.copyWith(color: colors.danger),
            ),
          )
        else if (copiedId != null)
          Semantics(
            liveRegion: true,
            child: Text(
              t.screenPanelChecksumCopied,
              style: VitalType.metadata.copyWith(color: colors.muted),
            ),
          ),
        VitalActions(
          children: [
            StitchButton(
              primary: true,
              icon: LucideIcons.inbox,
              focusNode: widget.filesFocusNode,
              onPressed: widget.enabled ? widget.onOpenFiles : null,
              child: Text(t.attachments),
            ),
            StitchButton(
              onPressed: widget.enabled ? widget.onExport : null,
              child: Text(t.exportTitle),
            ),
          ],
        ),
        Text(
          t.screenPanelFhirUnavailable,
          style: VitalType.metadata.copyWith(color: colors.muted),
        ),
      ],
    );
  }
}

/// Shows the complete store-backed earlier comparison for one viewed result.
class ScreenPanelComparison extends ConsumerWidget {
  const ScreenPanelComparison({
    super.key,
    required this.viewed,
    required this.result,
  });
  final SupportingRevision viewed;
  final LabResultSnapshot result;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(appLockProvider.select((state) => state.locked))) {
      return const SizedBox.shrink();
    }
    final t = AppLocalizations.of(context);
    final zone = ref.watch(displayZoneProvider);
    final request = (
      personId: viewed.id.personId,
      id: viewed.id.id,
      revision: viewed.revision,
      resultId: result.id,
      displayZone: zone,
    );
    final window = ref.watch(screenPanelEarlierProvider(request));
    if (window.hasError) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.featureLabsEarlierFailure, style: VitalType.metadata),
          VitalButton.secondary(
            onPressed: () =>
                ref.invalidate(screenPanelEarlierProvider(request)),
            child: Text(t.retry),
          ),
        ],
      );
    }
    final comparison = window.value;
    if (window.isLoading || comparison == null) {
      return Text(t.featureLabsEarlierLoading, style: VitalType.metadata);
    }
    final earlier = comparison.earlier;
    final searched =
        comparison.status == SupportingEarlierStatus.found ||
        comparison.status == SupportingEarlierStatus.none;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (earlier != null) ...[
            Text(
              t.featureLabsEarlierValue(
                supportingValueLabel(t, earlier.result),
                supportingDateLabel(
                  context,
                  ref,
                  earlier.record.snapshot.collectionDate,
                ),
              ),
              style: VitalType.metadata,
            ),
            if (comparison.change case final change?)
              Text(t.featureLabsChange(change), style: VitalType.metadata)
            else if (result.value.isExactNumeric)
              Text(t.featureLabsChangeUnavailable, style: VitalType.metadata),
          ] else
            Text(switch (comparison.status) {
              SupportingEarlierStatus.incomplete =>
                t.featureLabsEarlierIncomplete,
              SupportingEarlierStatus.incompatible =>
                t.featureLabsEarlierIncompatible,
              _ => t.featurePanelNoEarlier,
            }, style: VitalType.metadata),
          if (searched) Text(t.featurePanelCoverage, style: VitalType.metadata),
        ],
      ),
    );
  }
}
