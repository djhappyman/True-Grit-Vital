import '../../ui/vital_ui.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/storage.dart';
import '../../app/settings_toggle_row.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../recording/record_pages.dart';

final setupReadyProvider = NotifierProvider<SetupReady, bool>(SetupReady.new);

class SetupReady extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(recordStoreProvider);
    return false;
  }

  void confirm() => state = true;
}

final profilesProvider = StreamProvider<List<AdultProfile>>(
  retry: (_, _) => null,
  (ref) async* {
    yield* (await ref.watch(recordStoreProvider.future))
        .watchProfiles(includeArchived: true)
        .map((profiles) => profiles.where((profile) => profile.isMe).toList());
  },
);
String personLabel(AppLocalizations t, List<AdultProfile> profiles, String id) {
  final p = profiles.where((p) => p.id == id).firstOrNull;
  if (p == null) return t.profileUnavailable;
  return p.name == 'Me' ? t.me : p.name;
}

String ownerLabel(WidgetRef ref, AppLocalizations t, String id) =>
    personLabel(t, ref.watch(profilesProvider).value ?? [], id);

class ProfileForm extends ConsumerStatefulWidget {
  const ProfileForm({super.key});
  @override
  ConsumerState<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends DurableFormState<ProfileForm> {
  @override
  DraftKind get entryKind => DraftKind.profile;
  @override
  String? get entryPerson => original?.id;
  @override
  int? get entryPersonRevision => original?.revision;
  @override
  String? get entryTarget => original?.id;
  @override
  Map<String, String> captureEntry() => {
    'name': name.text,
    'report': report.text,
    'notes': notes.text,
    'adult': adult.toString(),
  };
  @override
  void restoreEntry(Map<String, String> fields) {
    name.text = fields['name'] ?? '';
    report.text = fields['report'] ?? '';
    notes.text = fields['notes'] ?? '';
    adult = fields['adult'] == 'true';
  }

  final name = TextEditingController(),
      report = TextEditingController(),
      notes = TextEditingController();
  AdultProfile? original;
  bool initialised = false, adult = false, details = false;
  @override
  void initState() {
    super.initState();
    for (final c in [name, report, notes]) {
      c.addListener(entryChanged);
    }
  }

  @override
  void dispose() {
    for (final c in [name, report, notes]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Future<void> leave() async {
    if (original?.isMe == true &&
        original?.adultConfirmed == false &&
        !ref.read(setupReadyProvider) &&
        !busy &&
        !uncertain) {
      setState(() => error = AppLocalizations.of(context).profileSetupHelp);
      return;
    }
    await super.leave();
  }

  Future<void> save() async {
    final t = AppLocalizations.of(context);
    if (name.text.length > 500 ||
        [report, notes].any((c) => c.text.length > 4000)) {
      setState(() => error = t.profileDetailsLimit);
      return;
    }
    if (name.text.trim().isEmpty || !adult) {
      setState(() => error = t.profileRequired);
      return;
    }
    await commit(
      (command) async {
        final store = await ref.read(recordStoreProvider.future);
        await store.editProfile(
          commandId: command,
          personId: meId,
          expectedRevision: capturedPersonRevision!,
          name: name.text.trim(),
          adultConfirmed: adult,
          reportName: report.text,
          notes: notes.text,
        );
        if (original?.isMe == true) {
          ref.read(setupReadyProvider.notifier).confirm();
        }
      },
      successPath: original?.isMe == true && original?.adultConfirmed == false
          ? '/today'
          : '/settings',
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context),
        people = ref.watch(profilesProvider);
    if (!initialised) {
      if (people.isLoading) {
        return EntryPage(children: [Text(t.loadingRecords)]);
      }
      if (people.hasError) {
        return EntryPage(
          children: [
            LoadFailure(onRetry: () => ref.invalidate(profilesProvider)),
          ],
        );
      }
      original = people.value!.where((p) => p.id == meId).firstOrNull;
      if (original == null) {
        return EntryPage(children: [Text(t.profileUnavailable)]);
      }
      if (original case final p?) {
        name.text = p.name;
        report.text = p.reportName ?? '';
        notes.text = p.notes ?? '';
        adult = p.adultConfirmed;
      }
      initialised = true;
      dirty = false;
    }
    if (original != null && !people.value!.any((p) => p.id == original!.id)) {
      dirty = false;
      return EntryPage(children: [Text(t.profileUnavailable)]);
    }
    if (!prepareDraft()) return EntryPage(children: [Text(t.loadingRecords)]);
    final stale =
        original != null &&
        !people.value!.any(
          (p) => p.id == original!.id && p.revision == capturedPersonRevision,
        );
    return wrap([
      if (stale) Text(t.profileChanged),
      Heading(t.profile),
      if (original != null)
        Text(t.profileOwner(personLabel(t, people.value ?? [], original!.id))),
      if (original?.isMe == true &&
          original?.adultConfirmed == false &&
          error != t.profileSetupHelp)
        Text(t.profileSetupHelp),
      const SizedBox(height: 16),
      LabelledInput(
        label: t.displayName,
        controller: name,
        enabled: !busy && !uncertain,
      ),
      SettingsToggleRow(
        label: t.adultConfirmed,
        description: t.adultHelper,
        value: adult,
        enabled: !busy && !uncertain,
        reduceMotion: MediaQuery.disableAnimationsOf(context),
        onChanged: (v) => setState(() {
          adult = v;
          entryChanged();
        }),
      ),
      const SizedBox(height: 16),
      VitalButton.secondary(
        onPressed: () => setState(() => details = !details),
        child: Text(t.details),
      ),
      if (details) ...[
        const SizedBox(height: 16),
        Text(t.optionalDetails),
        LabelledInput(
          label: t.reportName,
          controller: report,
          enabled: !busy && !uncertain,
        ),
        LabelledInput(
          label: t.profileNotes,
          controller: notes,
          enabled: !busy && !uncertain,
        ),
      ],
      if (error != null)
        Semantics(
          liveRegion: true,
          child: Text(conflict ? t.profileChanged : error!),
        ),
      const SizedBox(height: 16),
      VitalButton(
        onPressed: busy || conflict || (stale && !uncertain) ? null : save,
        child: Text(
          busy
              ? t.saving
              : uncertain
              ? t.retry
              : t.save,
        ),
      ),
    ]);
  }
}
