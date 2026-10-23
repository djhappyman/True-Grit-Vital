import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/app_lock.dart';
import '../../app/device_zone.dart';
import '../../app/display_preferences.dart';
import '../../app/exports.dart';
import '../../app/settings_toggle_row.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import '../profiles/profile_pages.dart';
import '../recording/record_pages.dart';
import 'export_range.dart';

/// The device clock used to derive shortcut ranges. Tests replace it.
final exportNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// S18 structured export: one adult, one deliberate date range, named content.
///
/// The reviewed preview is built from the exact bytes Save delivers. Editing
/// the selection discards that artifact instead of silently reusing it.
class ExportPage extends ConsumerStatefulWidget {
  const ExportPage({super.key, required this.location});
  final String location;
  @override
  ConsumerState<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends ConsumerState<ExportPage> {
  late final _seed = Uri.parse(widget.location).queryParameters;
  String get _zone => ref.read(displayZoneProvider);
  late final _from = TextEditingController(text: _seed['from'] ?? '');
  late final _before = TextEditingController(text: _seed['before'] ?? '');
  static const _person = meId;
  late ExportFormat _format =
      ExportFormat.values
          .where((value) => value.name == _seed['format'])
          .firstOrNull ??
      ExportFormat.json;
  late Set<ExportContent> _contents = _seed['content'] == null
      ? {ExportContent.doses, ExportContent.supporting}
      : {
          for (final value in _seed['content']!.split(','))
            ?ExportContent.values.where((v) => v.name == value).firstOrNull,
        };
  late bool _notes = _seed['notes'] == 'true';
  String? _selectionError;
  ExportRangeShortcut? _shortcut;
  ExportRangeFailure? _rangeFailure;
  bool _applyingShortcut = false;
  int _inputEpoch = 0;

  bool get _canEdit {
    if (!mounted) return false;
    final state = ref.read(exportControllerProvider(widget.location));
    return mounted &&
        !ref.read(appLockProvider).locked &&
        !state.building &&
        !state.saving &&
        !state.reviewing &&
        ModalRoute.of(context)?.isCurrent != false;
  }

  String _currentZone() {
    final observed = ref.read(observedDeviceZoneProvider);
    if (observed.isLoading ||
        observed.hasError ||
        observed.value?.zoneId == null) {
      throw const ExportRangeException(ExportRangeFailure.zoneUnavailable);
    }
    return _zone;
  }

  ExportController get _controller =>
      ref.read(exportControllerProvider(widget.location).notifier);

  @override
  void initState() {
    super.initState();
    final seededFrom = _seed['from'];
    final seededBefore = _seed['before'];
    _from.text = seededFrom ?? '';
    _before.text = seededBefore ?? '';
    _from.addListener(_changed);
    _before.addListener(_changed);
    if (seededFrom == null || seededBefore == null) {
      unawaited(_initialiseRange());
    }
  }

  Future<void> _initialiseRange() async {
    final inputEpoch = _inputEpoch;
    try {
      await ref.read(observedDeviceZoneProvider.future);
      if (!mounted || inputEpoch != _inputEpoch || !_canEdit) return;
      final today = exportCivilToday(
        ref.read(exportNowProvider)(),
        _currentZone(),
      );
      final range = exportShortcutRange(today, ExportRangeShortcut.thirtyDays);
      _applyingShortcut = true;
      try {
        if (_seed['from'] == null) _from.text = range.from.toString();
        if (_seed['before'] == null) _before.text = range.before.toString();
      } finally {
        _applyingShortcut = false;
      }
      setState(() {
        _rangeFailure = null;
        if (_seed['from'] == null && _seed['before'] == null) {
          _shortcut = ExportRangeShortcut.thirtyDays;
        }
      });
    } catch (error) {
      if (!mounted || inputEpoch != _inputEpoch || !_canEdit) return;
      setState(
        () => _rangeFailure = error is ExportRangeException
            ? error.failure
            : ExportRangeFailure.zoneUnavailable,
      );
    }
  }

  @override
  void dispose() {
    _from.removeListener(_changed);
    _before.removeListener(_changed);
    _from.dispose();
    _before.dispose();
    super.dispose();
  }

  void _changed() {
    if (!_canEdit) return;
    _controller.edit();
    setState(() {
      _selectionError = null;
      if (!_applyingShortcut) {
        _inputEpoch++;
        _shortcut = null;
        _rangeFailure = null;
      }
    });
  }

  void _applyShortcut(ExportRangeShortcut shortcut) {
    if (!_canEdit) return;
    try {
      final today = exportCivilToday(
        ref.read(exportNowProvider)(),
        _currentZone(),
      );
      final range = exportShortcutRange(today, shortcut);
      // Field listeners fire synchronously and would otherwise clear the
      // just-chosen shortcut while the range is being applied.
      _applyingShortcut = true;
      try {
        _from.text = range.from.toString();
        _before.text = range.before.toString();
      } finally {
        _applyingShortcut = false;
      }
      setState(() {
        _shortcut = shortcut;
        _rangeFailure = null;
        _selectionError = null;
      });
      _controller.edit();
    } on ExportRangeException catch (error) {
      setState(() {
        _rangeFailure = error.failure;
        _selectionError = null;
      });
    }
  }

  String? _rangeFailureText(AppLocalizations t) => switch (_rangeFailure) {
    ExportRangeFailure.zoneUnavailable => t.exportZone,
    ExportRangeFailure.rangeUnavailable => t.batch15T06RangeUnavailable,
    null => null,
  };

  Widget _shortcutButton(AppLocalizations t, ExportRangeShortcut shortcut) {
    final active = _shortcut == shortcut;
    final (:label, :description) = switch (shortcut) {
      ExportRangeShortcut.thirtyDays => (
        label: t.featureVaultThirty,
        description: t.featureVaultThirtyLabel,
      ),
      ExportRangeShortcut.ninetyDays => (
        label: t.featureVaultNinety,
        description: t.featureVaultNinetyLabel,
      ),
      ExportRangeShortcut.year => (
        label: t.featureVaultYear,
        description: t.featureVaultYearLabel,
      ),
    };
    void apply() => _applyShortcut(shortcut);
    return Semantics(
      container: true,
      button: true,
      selected: active,
      inMutuallyExclusiveGroup: true,
      label: description,
      onTap: apply,
      excludeSemantics: true,
      child: active
          ? VitalButton(onPressed: apply, child: Text(label))
          : VitalButton.secondary(onPressed: apply, child: Text(label)),
    );
  }

  void _preview(AppLocalizations t) {
    if (!_canEdit) return;
    try {
      final zone = _currentZone();
      final from = CivilDate.parse(_from.text.trim());
      final before = CivilDate.parse(_before.text.trim());
      if (_contents.isEmpty) {
        setState(() => _selectionError = t.exportChooseContent);
        return;
      }
      _controller.generate(
        ExportSelection(
          personId: _person,
          fromDay: from,
          beforeDay: before,
          zoneId: zone,
          contents: _contents,
          format: _format,
          includeNotes: _notes,
        ),
      );
    } on ExportRangeException catch (error) {
      setState(() => _rangeFailure = error.failure);
    } on ExportLimitException {
      setState(() => _selectionError = t.exportTooLarge);
    } on ArgumentError {
      setState(() => _selectionError = t.exportInvalidRange);
    } catch (_) {
      setState(() => _selectionError = t.exportInvalidRange);
    }
  }

  String _error(AppLocalizations t, String code) => switch (code) {
    'cancelled' => t.exportCancelled,
    'export_days' ||
    'export_dose_records' ||
    'export_dose_revisions' ||
    'export_supporting_records' ||
    'export_supporting_results' ||
    'export_bytes' => t.exportTooLarge,
    'export_zone' => t.exportZone,
    'export_person' => t.profileUnavailable,
    'locked' => t.exportLocked,
    'export_handoff_unavailable' => t.exportUnavailable,
    'export_handoff_cancelled' => t.exportHandoffCancelled,
    'export_handoff_failed' => t.exportSaveFailed,
    _ => t.exportFailed,
  };

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    ref.watch(observedDeviceZoneProvider);
    if (ref.watch(appLockProvider.select((state) => state.locked))) {
      return EntryPage(
        children: [Heading(t.exportTitle), Text(t.exportLocked)],
      );
    }
    final people = ref.watch(profilesProvider);
    final state = ref.watch(exportControllerProvider(widget.location));
    final handoff = ref.watch(exportHandoffProvider);
    if (!people.hasValue) {
      return EntryPage(
        children: [Heading(t.exportTitle), Text(t.loadingRecords)],
      );
    }
    final available = people.requireValue;
    if (available.isEmpty || !available.any((person) => person.id == _person)) {
      return EntryPage(
        children: [Heading(t.exportTitle), Text(t.profileUnavailable)],
      );
    }
    final selectedPerson = available.firstWhere(
      (person) => person.id == _person,
    );
    final artifact = state.artifact;
    return EntryPage(
      children: [
        Heading(t.exportTitle),
        if (state.building)
          VitalSection(
            title: Text(t.exportPreparing),
            children: [
              Semantics(liveRegion: true, child: Text(t.exportPreparingHelp)),
              VitalButton.secondary(
                onPressed: _controller.cancel,
                child: Text(t.exportCancel),
              ),
            ],
          )
        else if (artifact != null && state.reviewing)
          _buildPreview(t, state, artifact, handoff)
        else ...[
          Text(t.exportSelectionHelp),
          VitalSection(
            title: Text(t.exportRange),
            children: [
              VitalDateRangeField(
                start: _from,
                end: _before,
                startLabel: t.exportFrom,
                endLabel: t.exportBefore,
                endExclusive: true,
              ),
              Text(t.batch15T06DateShortcuts, style: VitalType.label),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final shortcut in ExportRangeShortcut.values)
                    _shortcutButton(t, shortcut),
                ],
              ),
              if (_rangeFailureText(t) case final failure?)
                Semantics(liveRegion: true, child: Text(failure)),
              if (!ref.watch(observedDeviceZoneProvider).isLoading &&
                  !ref.watch(observedDeviceZoneProvider).hasError &&
                  ref.watch(observedDeviceZoneProvider).value?.zoneId != null)
                Text(t.exportRangeHelp(_zone)),
            ],
          ),
          VitalSection(
            title: Text(t.exportContent),
            children: [
              SettingsToggleRow(
                label: t.exportDoses,
                description: t.exportDosesHelp,
                value: _contents.contains(ExportContent.doses),
                reduceMotion: MediaQuery.disableAnimationsOf(context),
                onChanged: (value) {
                  setState(() {
                    if (value) {
                      _contents = {..._contents, ExportContent.doses};
                    } else {
                      _contents = {..._contents}..remove(ExportContent.doses);
                    }
                  });
                  _changed();
                },
              ),
              SettingsToggleRow(
                label: t.exportSupporting,
                description: t.exportSupportingHelp,
                value: _contents.contains(ExportContent.supporting),
                reduceMotion: MediaQuery.disableAnimationsOf(context),
                onChanged: (value) {
                  setState(() {
                    if (value) {
                      _contents = {..._contents, ExportContent.supporting};
                    } else {
                      _contents = {..._contents}
                        ..remove(ExportContent.supporting);
                    }
                  });
                  _changed();
                },
              ),
              Text(t.exportPrivateHelp),
            ],
          ),
          VitalSection(
            title: Text(t.exportPrivacy),
            children: [
              SettingsToggleRow(
                label: t.exportNotes,
                description: t.exportNotesHelp,
                value: _notes,
                reduceMotion: MediaQuery.disableAnimationsOf(context),
                onChanged: (value) {
                  _notes = value;
                  _changed();
                },
              ),
              Text(t.exportSinglePerson(selectedPerson.name)),
            ],
          ),
          VitalSection(
            title: Text(t.exportFormat),
            children: [
              VitalSegments<ExportFormat>(
                values: ExportFormat.values,
                selected: _format,
                onChanged: (value) {
                  _format = value;
                  _changed();
                },
                label: (value) => switch (value) {
                  ExportFormat.json => t.exportFormatJson,
                  ExportFormat.csv => t.exportFormatCsv,
                  ExportFormat.fhir => t.finishR03FormatFhir,
                },
              ),
              Text(
                _format == ExportFormat.fhir
                    ? t.finishR03FormatHelp
                    : t.exportFormatHelp,
              ),
            ],
          ),
          if (_selectionError != null)
            Semantics(liveRegion: true, child: Text(_selectionError!)),
          if (state.errorCode != null)
            Semantics(
              liveRegion: true,
              child: Text(_error(t, state.errorCode!)),
            ),
          VitalButton(
            onPressed: () => _preview(t),
            child: Text(t.exportPreview),
          ),
        ],
      ],
    );
  }

  Widget _fhirReview(AppLocalizations t, FhirExportSummary fhir) =>
      VitalSection(
        title: Text(t.finishR03FhirHeading),
        children: [
          Text(t.finishR03FhirVersion),
          Text(t.finishR03Patient),
          Text(t.finishR03Medication),
          Text(t.finishR03Grouping),
          Text(t.finishR03TextCodes),
          Text(t.finishR03Utc),
          Text(t.finishR03StatementCount(fhir.medicationStatements)),
          if (fhir.skippedStatements > 0)
            Text(t.finishR03SkipCount(fhir.skippedStatements)),
          if (fhir.observations > 0)
            Text(t.finishR03ObservationCount(fhir.observations)),
          if (fhir.dateOnlyTimes > 0)
            Text(t.finishR03DateOnlyCount(fhir.dateOnlyTimes)),
          if (fhir.uncertainTimes > 0)
            Text(t.finishR03UncertainCount(fhir.uncertainTimes)),
          if (fhir.voidedRecords > 0)
            Text(t.finishR03VoidedCount(fhir.voidedRecords)),
          if (fhir.supersededRevisions > 0)
            Text(t.finishR03SupersededCount(fhir.supersededRevisions)),
          if (fhir.exactTextQuantities > 0)
            Text(t.finishR03TextQuantityCount(fhir.exactTextQuantities)),
          if (fhir.missingValues > 0)
            Text(t.finishR03MissingCount(fhir.missingValues)),
          if (fhir.unresolvedReplacements > 0)
            Text(t.finishR03UnresolvedCount(fhir.unresolvedReplacements)),
          if (fhir.reportDatesWithoutInstant > 0)
            Text(t.finishR03ReportDateCount(fhir.reportDatesWithoutInstant)),
          Text(t.finishR03Omissions),
          Text(t.finishR03Provenance),
          Text(t.finishR03Files),
        ],
      );

  Widget _buildPreview(
    AppLocalizations t,
    ExportViewState state,
    ExportArtifact artifact,
    ExportHandoff handoff,
  ) {
    final preview = artifact.preview;
    final omission = preview.undatedCollection;
    final String? undatedMessage = omission == null
        ? null
        : !omission.counted
        ? t.exportUndatedUncounted
        : (omission.records ?? 0) > 0
        ? t.exportUndatedExcluded(omission.records!)
        : null;
    final contents = [
      if (preview.contents.contains(ExportContent.doses)) t.exportDoses,
      if (preview.contents.contains(ExportContent.supporting))
        t.exportSupporting,
    ].join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VitalSection(
          title: Text(t.exportReview),
          children: [
            Text(preview.personName),
            Text(
              t.exportDateRange(
                preview.fromDay.toString(),
                preview.beforeDay.toString(),
              ),
            ),
            Text(t.exportZoneLabel(preview.zoneId)),
            Text(t.exportContentLabel(contents)),
            Text(
              preview.notesIncluded
                  ? t.exportNotesIncluded
                  : t.exportNotesExcluded,
            ),
            Text(t.exportDoseCount(preview.doseRecords)),
            Text(t.exportRevisionCount(preview.doseRevisions)),
            Text(t.featureContextExportSkipCount(preview.skippedActions)),
            Text(t.exportSupportingCount(preview.supportingRecords)),
            Text(t.exportSupportingResultCount(preview.supportingResults)),
            if (preview.contents.contains(ExportContent.supporting))
              Text(t.featureLabsMetadataHelp),
            if (undatedMessage != null) Text(undatedMessage),
            Text(t.exportByteCount(preview.byteCount)),
            Text(t.exportFileName(artifact.fileName)),
            Text(t.exportChecksumLabel),
            SelectableText(artifact.sha256),
            Text(t.exportExactArtifact),
          ],
        ),
        if (preview.fhir case final fhir?) _fhirReview(t, fhir),
        VitalSection(
          title: Text(t.exportPreview),
          children: [
            VitalSurface(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(preview.excerpt, style: VitalType.code),
              ),
            ),
          ],
        ),
        if (state.delivery case final delivery?)
          Semantics(
            liveRegion: true,
            child: Text(
              delivery == ExportDelivery.shared
                  ? t.exportShared
                  : t.exportSaved,
            ),
          ),
        if (state.errorCode != null)
          Semantics(liveRegion: true, child: Text(_error(t, state.errorCode!))),
        if (state.saving) ...[
          Text(t.exportSaving),
          VitalButton.secondary(
            onPressed: _controller.cancel,
            child: Text(t.exportCancel),
          ),
        ] else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              VitalButton(
                onPressed:
                    state.stage == ExportStage.preview && handoff.isAvailable
                    ? _controller.save
                    : null,
                child: Text(t.exportSave),
              ),
              VitalButton.secondary(
                onPressed: _controller.edit,
                child: Text(t.exportChange),
              ),
            ],
          ),
        if (!handoff.isAvailable) Text(t.exportUnavailable),
      ],
    );
  }
}
