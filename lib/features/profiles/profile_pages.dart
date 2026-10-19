import '../../ui/vital_ui.dart';

import 'package:flutter/material.dart' show showDialog;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/storage.dart';
import '../../app/settings_toggle_row.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../recording/record_pages.dart';
import '../stock/stock_widgets.dart' show stockRecordAmountNumber;

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
        .watchProfiles(includeArchived: true);
  },
);
final browsingScopeProvider = StreamProvider<FeedScope>(retry: (_, _) => null, (
  ref,
) async* {
  yield* (await ref.watch(recordStoreProvider.future)).watchBrowsingScope();
});
String personLabel(AppLocalizations t, List<AdultProfile> profiles, String id) {
  final p = profiles.where((p) => p.id == id).firstOrNull;
  if (p == null) return t.profileUnavailable;
  if (p.isMe) return p.name == 'Me' ? t.me : t.meName(p.name);
  return profiles.where((a) => a.name == p.name).length > 1
      ? t.profileReference(p.name, p.id)
      : p.name;
}

String ownerLabel(WidgetRef ref, AppLocalizations t, String id) =>
    personLabel(t, ref.watch(profilesProvider).value ?? [], id);

class ScopePage extends ConsumerStatefulWidget {
  const ScopePage({super.key, this.chooseOwner = false});
  final bool chooseOwner;
  @override
  ConsumerState<ScopePage> createState() => _ScopePageState();
}

class _ScopePageState extends ConsumerState<ScopePage> {
  bool busy = false, failed = false;
  final search = TextEditingController();
  @override
  void initState() {
    super.initState();
    search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> choose(FeedScope scope) async {
    if (widget.chooseOwner) {
      context.pushReplacement('/create?person=${scope.personId}');
      return;
    }
    setState(() {
      busy = true;
      failed = false;
    });
    try {
      await (await ref.read(recordStoreProvider.future))
          .saveBrowsingScope(scope);
      if (mounted) context.pop();
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return EntryPage(
      children: [
        Heading(widget.chooseOwner ? t.choosePerson : t.scope),
        LabelledInput(label: t.searchPeople, controller: search),
        if (failed) Semantics(liveRegion: true, child: Text(t.scopeFailure)),
        ref
            .watch(profilesProvider)
            .when(
              data: (people) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!widget.chooseOwner)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: VitalButton.secondary(
                        multiline: true,
                        onPressed: busy
                            ? null
                            : () => choose(const FeedScope.everyone()),
                        child: Text(t.everyone),
                      ),
                    ),
                  for (final p in people.where(
                    (p) =>
                        !p.isArchived &&
                        personLabel(
                          t,
                          people,
                          p.id,
                        ).toLowerCase().contains(search.text.toLowerCase()),
                  ))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: VitalButton.secondary(
                        multiline: true,
                        onPressed: busy
                            ? null
                            : () => choose(FeedScope.person(p.id)),
                        child: Text(personLabel(t, people, p.id)),
                      ),
                    ),
                ],
              ),
              error: (_, _) =>
                  LoadFailure(onRetry: () => ref.invalidate(profilesProvider)),
              loading: () => Text(t.loadingRecords),
            ),
        VitalButton.secondary(
          onPressed: () => context.push('/people'),
          child: Text(t.people),
        ),
      ],
    );
  }
}

class PeoplePage extends ConsumerWidget {
  const PeoplePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return EntryPage(
      children: [
        Heading(t.people),
        VitalButton(
          onPressed: () => context.push('/people/add'),
          child: Text(t.add),
        ),
        const SizedBox(height: 20),
        ref
            .watch(profilesProvider)
            .when(
              data: (people) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final p in people)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: VitalSurface(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(personLabel(t, people, p.id)),
                            if (p.isArchived) Text(t.archived),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                VitalButton.secondary(
                                  onPressed: () =>
                                      context.push('/people/${p.id}'),
                                  child: Text(t.edit),
                                ),
                                VitalButton.secondary(
                                  onPressed: () =>
                                      context.push('/person-history/${p.id}'),
                                  child: Text(t.history),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              error: (_, _) =>
                  LoadFailure(onRetry: () => ref.invalidate(profilesProvider)),
              loading: () => Text(t.loadingRecords),
            ),
      ],
    );
  }
}

class PersonHistory extends ConsumerWidget {
  const PersonHistory({super.key, required this.personId});
  final String personId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final notice = ref.watch(savedRecordProvider);
    return EntryPage(
      children: [
        Heading(t.history),
        Text(t.profileOwner(ownerLabel(ref, t, personId))),
        if (notice != null && notice.personId == personId)
          Semantics(
            liveRegion: true,
            child: Text(
              notice.isVoided
                  ? t.voidedContext(
                      ownerLabel(ref, t, personId),
                      notice.name,
                      stockRecordAmountNumber(t, notice),
                      notice.actualUnit,
                    )
                  : t.savedContext(
                      ownerLabel(ref, t, personId),
                      notice.name,
                      stockRecordAmountNumber(t, notice),
                      notice.actualUnit,
                    ),
            ),
          ),
        PagedRecordList(
          query: (
            itemId: null,
            actualFrom: null,
            actualBefore: null,
            limit: 51,
            offset: 0,
            scope: FeedScope.person(personId),
          ),
          emptyBody: t.historyReady,
        ),
      ],
    );
  }
}

class ProfileForm extends ConsumerStatefulWidget {
  const ProfileForm({super.key, this.personId});
  final String? personId;
  @override
  ConsumerState<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends DurableFormState<ProfileForm> {
  String action = '';
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
    'relationship': relationship.text,
    'notes': notes.text,
    'adult': adult.toString(),
    'action': action,
  };
  @override
  void restoreEntry(Map<String, String> fields) {
    name.text = fields['name'] ?? '';
    report.text = fields['report'] ?? '';
    relationship.text = fields['relationship'] ?? '';
    notes.text = fields['notes'] ?? '';
    adult = fields['adult'] == 'true';
    action = fields['action'] ?? '';
    if (action.isNotEmpty) pendingMutation = runAction;
  }

  Future<void> runAction(String command) async {
    final store = await ref.read(recordStoreProvider.future);
    switch (action) {
      case 'archive':
        await store.archiveProfile(
          commandId: command,
          personId: original!.id,
          expectedRevision: capturedPersonRevision!,
        );
      case 'reactivate':
        await store.reactivateProfile(
          commandId: command,
          personId: original!.id,
          expectedRevision: capturedPersonRevision!,
        );
      case 'delete':
        await store.deleteProfile(
          commandId: command,
          personId: original!.id,
          expectedRevision: capturedPersonRevision!,
        );
      default:
        throw StateError('profile_action');
    }
  }

  final name = TextEditingController(),
      report = TextEditingController(),
      relationship = TextEditingController(),
      notes = TextEditingController();
  AdultProfile? original;
  Future<void> Function(String)? pendingMutation;
  bool initialised = false, adult = false, details = false;
  @override
  void initState() {
    super.initState();
    for (final c in [name, report, relationship, notes]) {
      c.addListener(entryChanged);
    }
  }

  @override
  void dispose() {
    for (final c in [name, report, relationship, notes]) {
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
    if (pendingMutation != null) {
      await commit(pendingMutation!, successPath: '/people');
      return;
    }
    final t = AppLocalizations.of(context);
    if (name.text.length > 500 ||
        [report, relationship, notes].any((c) => c.text.length > 4000)) {
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
        if (original case final p?) {
          await store.editProfile(
            commandId: command,
            personId: p.id,
            expectedRevision: capturedPersonRevision!,
            name: name.text.trim(),
            adultConfirmed: adult,
            reportName: report.text,
            relationship: relationship.text,
            notes: notes.text,
          );
        } else {
          await store.createProfile(
            commandId: command,
            name: name.text.trim(),
            adultConfirmed: adult,
            reportName: report.text,
            relationship: relationship.text,
            notes: notes.text,
          );
        }
        if (original?.isMe == true) {
          ref.read(setupReadyProvider.notifier).confirm();
        }
      },
      successPath: original?.isMe == true && original?.adultConfirmed == false
          ? '/today'
          : '/people',
    );
  }

  Future<void> archive() async {
    final p = original!, t = AppLocalizations.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => VitalDialog(
        title: Text(p.isArchived ? t.reactivate : t.archivePerson),
        content: Text(
          p.isArchived ? t.reactivateBody(p.name) : t.archiveBody(p.name),
        ),
        actions: [
          VitalButton.secondary(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.cancel),
          ),
          VitalButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(p.isArchived ? t.reactivate : t.archive),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    action = p.isArchived ? 'reactivate' : 'archive';
    pendingMutation = runAction;
    await commit(pendingMutation!, successPath: '/people');
  }

  Future<void> delete() async {
    final p = original!, t = AppLocalizations.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => VitalDialog(
        title: Text(p.isMe ? t.deleteRecords : t.deletePerson),
        content: Text(t.deleteProfileBody(p.name)),
        actions: [
          VitalButton.secondary(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.cancel),
          ),
          VitalButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.delete),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    action = 'delete';
    pendingMutation = runAction;
    await commit(pendingMutation!, successPath: '/people');
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
      original = people.value!
          .where((p) => p.id == widget.personId)
          .firstOrNull;
      if (widget.personId != null && original == null) {
        return EntryPage(children: [Text(t.profileUnavailable)]);
      }
      if (original case final p?) {
        name.text = p.name;
        report.text = p.reportName ?? '';
        relationship.text = p.relationship ?? '';
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
      Heading(original == null ? t.addPerson : t.editPerson),
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
          label: t.relationship,
          controller: relationship,
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
      if (original != null) ...[
        const SizedBox(height: 24),
        Text(original!.isMe ? t.deleteRecords : t.deletePerson),
        VitalButton.secondary(
          onPressed: busy || uncertain || dirty || stale ? null : delete,
          child: Text(t.delete),
        ),
      ],
      if (original != null && !original!.isMe) ...[
        const SizedBox(height: 24),
        VitalButton.secondary(
          onPressed: busy || uncertain || dirty || stale ? null : archive,
          child: Text(original!.isArchived ? t.reactivate : t.archive),
        ),
      ],
    ]);
  }
}
