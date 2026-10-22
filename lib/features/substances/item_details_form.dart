import '../products/product_widgets.dart' show productLabelProvider;
import 'substance_profile_editor.dart';

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
  final name = TextEditingController(), form = TextEditingController();
  int? itemRevision;
  final instructions = TextEditingController();
  final notes = TextEditingController();
  late final profileEditor = SubstanceProfileEditorData(entryChanged);
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
    'name': name.text,
    'form': form.text,
    'itemRevision': '$itemRevision',
    'instructions': instructions.text,
    'notes': notes.text,
    'profile': profileEditor.encode(),
  };

  @override
  void restoreEntry(Map<String, String> fields) {
    if (fields['name'] case final value?) name.text = value;
    if (fields['form'] case final value?) form.text = value;
    itemRevision = int.tryParse(fields['itemRevision'] ?? '') ?? itemRevision;
    instructions.text = fields['instructions'] ?? '';
    notes.text = fields['notes'] ?? '';
    if (fields['profile'] case final encoded?) profileEditor.restore(encoded);
  }

  @override
  void dispose() {
    name.dispose();
    form.dispose();
    profileEditor.dispose();
    instructions.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final t = AppLocalizations.of(context);
    if (name.text.trim().isEmpty) {
      setState(() => error = t.nameRequired);
      return;
    }
    if (form.text.trim().isEmpty) form.text = t.dashboardUnknownForm;
    if (name.text.length > 2048 || form.text.length > 2048) {
      setState(() => error = t.dashboardIdentityTooLong);
      return;
    }
    if (instructions.text.length > 8000 || notes.text.length > 8000) {
      setState(() => error = t.featureSetupDetailsTooLong);
      return;
    }
    SubstanceProfile? profile;
    try {
      profile = profileEditor.read(
        blend:
            ref
                .read(
                  productLabelProvider((personId: meId, itemId: widget.itemId)),
                )
                .value !=
            null,
      );
    } catch (_) {
      setState(() => error = t.substanceProfileInvalid);
      return;
    }
    await commit(
      (command) async {
        await (await ref.read(recordStoreProvider.future)).saveItemDetail(
          commandId: command,
          expectedGeneration: capturedGeneration,
          itemId: widget.itemId,
          name: name.text,
          form: form.text,
          expectedItemRevision: itemRevision,
          expectedRevision: capturedTargetRevision,
          expectedPersonRevision: capturedPersonRevision,
          instructions: instructions.text,
          notes: notes.text,
          profile: profile,
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
    final product = ref.watch(
      productLabelProvider((personId: meId, itemId: widget.itemId)),
    );
    if (people.hasError ||
        current.hasError ||
        detail.hasError ||
        product.hasError) {
      return EntryPage(
        children: [
          LoadFailure(
            onRetry: () {
              ref.invalidate(profilesProvider);
              ref.invalidate(itemLookupProvider(widget.itemId));
              ref.invalidate(itemDetailProvider(widget.itemId));
              ref.invalidate(
                productLabelProvider((personId: meId, itemId: widget.itemId)),
              );
            },
          ),
        ],
      );
    }
    if (!people.hasValue ||
        !current.hasValue ||
        !detail.hasValue ||
        !product.hasValue) {
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
      name.text = item.name;
      form.text = item.form;
      itemRevision = item.revision;
      name.addListener(entryChanged);
      form.addListener(entryChanged);
      detailRevision = detail.value?.revision;
      instructions.text = detail.value?.instructions ?? '';
      notes.text = detail.value?.notes ?? '';
      profileEditor.initialise(detail.value?.profile);
      instructions.addListener(entryChanged);
      notes.addListener(entryChanged);
      initialised = true;
    }
    if (!prepareDraft()) return EntryPage(children: [Text(t.loadingRecords)]);
    final valid =
        !liveOwner.isArchived &&
        liveOwner.revision == capturedPersonRevision &&
        detail.value?.revision == capturedTargetRevision &&
        item.revision == itemRevision;
    final enabled = valid && !busy && !uncertain && !conflict;
    return wrap([
      Heading(t.featureSetupDetails),
      LabelledInput(
        label: t.dashboardName,
        controller: name,
        enabled: enabled,
        error: error == t.nameRequired ? error : null,
      ),
      LabelledInput(label: t.formLabel, controller: form, enabled: enabled),
      Text(t.dashboardEditHelp, style: VitalType.metadata),
      Text(
        t.featureSetupDetailsFormHelp,
        style: VitalType.metadata.copyWith(
          color: Theme.of(context).colorScheme.mutedForeground,
        ),
      ),
      const SizedBox(height: 16),
      SubstanceProfileEditor(
        data: profileEditor,
        blend: product.value != null,
        enabled: enabled,
        onChanged: () => setState(() {
          if (profileEditor.form case final selected?) {
            form.text = selected == SubstanceForm.other
                ? profileEditor.other.text
                : substanceFormLabel(t, selected);
          }
        }),
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
