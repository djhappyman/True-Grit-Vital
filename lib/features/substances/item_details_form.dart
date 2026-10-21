import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/storage.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import '../profiles/profile_pages.dart';
import '../recording/record_pages.dart';
import 'substance_detail_providers.dart';

/// Optional authored instructions and private notes for one substance.
///
/// The form uses the same durable draft, command, revision and generation
/// guards as the other editors. It never interprets the text or turns it into
/// a dose, plan or recommendation.
class ItemDetailsForm extends ConsumerStatefulWidget {
  const ItemDetailsForm({
    super.key,
    required this.itemId,
    this.returnToSetup = false,
  });
  final String itemId;
  final bool returnToSetup;
  @override
  ConsumerState<ItemDetailsForm> createState() => _ItemDetailsFormState();
}

class _ItemDetailsFormState extends DurableFormState<ItemDetailsForm> {
  final instructions = TextEditingController();
  final notes = TextEditingController();
  AdultProfile? owner;
  int? detailRevision;
  bool initialised = false;

  @override
  DraftKind get entryKind => DraftKind.itemDetails;
  @override
  String? get entryPerson => owner?.id;
  @override
  int? get entryPersonRevision => owner?.revision;
  @override
  String? get entryTarget => widget.itemId;
  @override
  int? get entryTargetRevision => detailRevision;
  @override
  String get entryFallback => '/substance/${widget.itemId}';

  @override
  Map<String, String> captureEntry() => {
    'instructions': instructions.text,
    'notes': notes.text,
  };

  @override
  void restoreEntry(Map<String, String> fields) {
    instructions.text = fields['instructions'] ?? '';
    notes.text = fields['notes'] ?? '';
  }

  @override
  void dispose() {
    instructions.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final t = AppLocalizations.of(context);
    if (instructions.text.length > 8000 || notes.text.length > 8000) {
      setState(() => error = t.featureSetupDetailsTooLong);
      return;
    }
    await commit(
      (command) async {
        await (await ref.read(recordStoreProvider.future)).saveItemDetail(
          commandId: command,
          expectedGeneration: capturedGeneration,
          itemId: widget.itemId,
          expectedRevision: capturedTargetRevision,
          expectedPersonRevision: capturedPersonRevision,
          instructions: instructions.text,
          notes: notes.text,
        );
      },
      successPath:
          '/substance/${widget.itemId}${widget.returnToSetup ? '/setup' : ''}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final people = ref.watch(profilesProvider);
    final current = ref.watch(itemLookupProvider(widget.itemId));
    final detail = ref.watch(itemDetailProvider(widget.itemId));
    if (people.hasError || current.hasError || detail.hasError) {
      return EntryPage(
        children: [
          LoadFailure(
            onRetry: () {
              ref.invalidate(profilesProvider);
              ref.invalidate(itemLookupProvider(widget.itemId));
              ref.invalidate(itemDetailProvider(widget.itemId));
            },
          ),
        ],
      );
    }
    if (!people.hasValue || !current.hasValue || !detail.hasValue) {
      return EntryPage(children: [Text(t.loadingRecords)]);
    }
    final liveOwner = people.value!
        .where((person) => person.id == meId)
        .firstOrNull;
    final item = current.value;
    if (liveOwner == null || item == null || item.personId != meId) {
      dirty = false;
      return EntryPage(children: [Text(t.draftUnavailable)]);
    }
    if (!initialised) {
      owner = liveOwner;
      detailRevision = detail.value?.revision;
      instructions.text = detail.value?.instructions ?? '';
      notes.text = detail.value?.notes ?? '';
      instructions.addListener(entryChanged);
      notes.addListener(entryChanged);
      initialised = true;
    }
    if (!prepareDraft()) return EntryPage(children: [Text(t.loadingRecords)]);
    final valid =
        !liveOwner.isArchived &&
        liveOwner.revision == capturedPersonRevision &&
        detail.value?.revision == capturedTargetRevision;
    final enabled = valid && !busy && !uncertain && !conflict;
    return wrap([
      Heading(t.featureSetupDetails),
      Text(item.name),
      Text(
        t.featureSetupDetailsFormHelp,
        style: VitalType.metadata.copyWith(
          color: Theme.of(context).colorScheme.mutedForeground,
        ),
      ),
      const SizedBox(height: 16),
      LabelledInput(
        label: t.featureSetupInstructions,
        controller: instructions,
        enabled: enabled,
        maxLines: 5,
        helper: t.featureSetupInstructionsHelp,
      ),
      LabelledInput(
        label: t.featureSetupNotes,
        controller: notes,
        enabled: enabled,
        maxLines: 5,
        helper: t.featureSetupNotesHelp,
      ),
      if (!valid) Text(t.conflictFailure),
      ?failure(),
      VitalButton(
        onPressed: busy || (!valid && !uncertain) ? null : save,
        child: Text(
          busy
              ? t.saving
              : uncertain
              ? t.retry
              : t.featureSetupSave,
        ),
      ),
    ]);
  }
}
