import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/app_lock.dart';
import '../../app/display_preferences.dart';
import '../../app/exports.dart';
import '../../app/settings_toggle_row.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import '../profiles/profile_pages.dart';
import '../recording/record_pages.dart';

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
  late final _zone = ref.read(displayZoneProvider);
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

  ExportController get _controller =>
      ref.read(exportControllerProvider(widget.location).notifier);

  @override
  void initState() {
    super.initState();
    final display = DisplayTime();
    final today = display.instant(DateTime.now().toUtc(), _zone).civilDate;
    _from.text = _seed['from'] ?? today.addDays(-29).toString();
    _before.text = _seed['before'] ?? today.addDays(1).toString();
    _from.addListener(_changed);
    _before.addListener(_changed);
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
    _controller.edit();
    setState(() => _selectionError = null);
  }

  void _preview(AppLocalizations t) {
    try {
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
          zoneId: _zone,
          contents: _contents,
          format: _format,
          includeNotes: _notes,
        ),
      );
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
              LabelledInput(label: t.exportFrom, controller: _from),
              LabelledInput(label: t.exportBefore, controller: _before),
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
                },
              ),
              Text(t.exportFormatHelp),
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
            Text(t.exportSupportingCount(preview.supportingRecords)),
            Text(t.exportSupportingResultCount(preview.supportingResults)),
            if (undatedMessage != null) Text(undatedMessage),
            Text(t.exportByteCount(preview.byteCount)),
            Text(t.exportFileName(artifact.fileName)),
            Text(t.exportChecksumLabel),
            SelectableText(artifact.sha256),
            Text(t.exportExactArtifact),
          ],
        ),
        VitalSection(
          title: Text(t.exportPreview),
          children: [
            VitalSurface(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  preview.excerpt,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
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
