import '../../ui/vital_ui.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/storage.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../profiles/profile_pages.dart';
import '../recording/record_pages.dart';

final itemTypesProvider = StreamProvider.autoDispose
    .family<List<PersonalItemType>, ({String personId, int offset})>(
      retry: (_, _) => null,
      (ref, query) async* {
        yield* (await ref.watch(recordStoreProvider.future)).watchItemTypes(
          personId: query.personId,
          offset: query.offset,
          limit: 51,
        );
      },
    );
final itemTypeProvider = StreamProvider.autoDispose
    .family<PersonalItemType?, ({String personId, String typeId})>(
      retry: (_, _) => null,
      (ref, query) async* {
        yield* (await ref.watch(recordStoreProvider.future))
            .watchItemTypeById(query.typeId, personId: query.personId);
      },
    );

class ItemTypesPage extends ConsumerStatefulWidget {
  const ItemTypesPage({super.key, required this.personId});
  final String personId;
  @override
  ConsumerState<ItemTypesPage> createState() => _ItemTypesPageState();
}

class _ItemTypesPageState extends ConsumerState<ItemTypesPage> {
  int offset = 0;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final owner = ref
        .watch(profilesProvider)
        .value
        ?.where((p) => p.id == widget.personId)
        .firstOrNull;
    if (owner == null || owner.isArchived) {
      return EntryPage(children: [Text(t.profileUnavailable)]);
    }
    return EntryPage(
      children: [
        Heading(t.itemTypes),
        Text(t.profileOwner(ownerLabel(ref, t, widget.personId))),
        Text(t.itemTypesHelp),
        const SizedBox(height: 16),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: VitalButton(
            onPressed: () => context.push('/types/${widget.personId}/edit'),
            child: Text(t.create),
          ),
        ),
        const SizedBox(height: 16),
        ref
            .watch(
              itemTypesProvider((personId: widget.personId, offset: offset)),
            )
            .when(
              loading: () => Text(t.loadingRecords),
              error: (_, _) => LoadFailure(
                onRetry: () => ref.invalidate(
                  itemTypesProvider((
                    personId: widget.personId,
                    offset: offset,
                  )),
                ),
              ),
              data: (types) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (types.isEmpty) Text(t.itemTypesEmpty),
                  for (final type in types.take(50))
                    Padding(
                      key: ValueKey(type.id),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(type.name),
                          const SizedBox(height: 8),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 48),
                              child: VitalButton.secondary(
                                onPressed: () => context.push(
                                  '/types/${widget.personId}/edit?type=${type.id}',
                                ),
                                child: Text(t.itemTypeRename),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (offset > 0)
                        VitalButton.secondary(
                          onPressed: () => setState(() => offset -= 50),
                          child: Text(t.previous),
                        ),
                      if (types.length > 50)
                        VitalButton.secondary(
                          onPressed: () => setState(() => offset += 50),
                          child: Text(t.next),
                        ),
                    ],
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class ItemTypeForm extends ConsumerStatefulWidget {
  const ItemTypeForm({super.key, required this.personId, this.typeId});
  final String personId;
  final String? typeId;
  @override
  ConsumerState<ItemTypeForm> createState() => _ItemTypeFormState();
}

class _ItemTypeFormState extends DurableFormState<ItemTypeForm> {
  final name = TextEditingController();
  AdultProfile? owner;
  PersonalItemType? target;
  bool initialised = false;
  @override
  DraftKind get entryKind => DraftKind.itemType;
  @override
  String? get entryPerson => widget.personId;
  @override
  int? get entryPersonRevision => owner?.revision;
  @override
  String? get entryTarget => widget.typeId;
  @override
  int? get entryTargetRevision => target?.revision;
  @override
  Map<String, String> captureEntry() => {'name': name.text};
  @override
  void restoreEntry(Map<String, String> fields) {
    name.text = fields['name'] ?? '';
  }

  @override
  void initState() {
    super.initState();
    name.addListener(entryChanged);
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  String? recoverableCommandFailure(Object error) =>
      error is CommandConflict && error.code == 'type_exists'
      ? AppLocalizations.of(context).itemTypeExists
      : null;
  Future<void> save() async {
    final t = AppLocalizations.of(context), value = name.text.trim();
    if (value.isEmpty || value.length > 500) {
      setState(() => error = t.nameRequired);
      return;
    }
    await commit((command) async {
      final store = await ref.read(recordStoreProvider.future);
      if (widget.typeId == null) {
        await store.createItemType(
          commandId: command,
          personId: widget.personId,
          expectedPersonRevision: capturedPersonRevision,
          name: value,
        );
      } else {
        await store.renameItemType(
          commandId: command,
          personId: widget.personId,
          typeId: widget.typeId!,
          expectedPersonRevision: capturedPersonRevision,
          expectedRevision: capturedTargetRevision!,
          name: value,
        );
      }
    }, successPath: '/types/${widget.personId}');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context),
        people = ref.watch(profilesProvider);
    if (!people.hasValue) return EntryPage(children: [Text(t.loadingRecords)]);
    owner ??= people.value!.where((p) => p.id == widget.personId).firstOrNull;
    if (owner == null || !people.value!.any((p) => p.id == owner!.id)) {
      dirty = false;
      return EntryPage(children: [Text(t.profileUnavailable)]);
    }
    PersonalItemType? current;
    if (widget.typeId != null) {
      final result = ref.watch(
        itemTypeProvider((personId: widget.personId, typeId: widget.typeId!)),
      );
      if (result.hasError) {
        return EntryPage(
          children: [
            LoadFailure(
              onRetry: () => ref.invalidate(
                itemTypeProvider((
                  personId: widget.personId,
                  typeId: widget.typeId!,
                )),
              ),
            ),
          ],
        );
      }
      if (!result.hasValue) {
        return EntryPage(children: [Text(t.loadingRecords)]);
      }
      current = result.value;
      if (current == null) {
        dirty = false;
        return EntryPage(children: [Text(t.draftUnavailable)]);
      }
    }
    if (!initialised) {
      initialised = true;
      target = current;
      name.text = target?.name ?? '';
    }
    if (!prepareDraft()) return EntryPage(children: [Text(t.loadingRecords)]);
    final valid =
        people.value!.any(
          (p) =>
              p.id == widget.personId &&
              !p.isArchived &&
              p.revision == capturedPersonRevision,
        ) &&
        (widget.typeId == null || current!.revision == capturedTargetRevision);
    return wrap([
      Heading(widget.typeId == null ? t.itemTypeNew : t.itemTypeEdit),
      Text(t.profileOwner(ownerLabel(ref, t, widget.personId))),
      Text(t.itemTypesHelp),
      if (widget.typeId != null) Text(t.itemTypeRenameHelp),
      if (!valid) Text(t.conflictFailure),
      const SizedBox(height: 16),
      LabelledInput(
        label: t.itemTypeName,
        controller: name,
        enabled: valid && !busy && !uncertain,
        error: error == t.nameRequired ? error : null,
      ),
      ?failure(),
      VitalButton(
        onPressed: busy || conflict || (!valid && !uncertain) ? null : save,
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
