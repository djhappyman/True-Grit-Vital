import '../../ui/vital_ui.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/storage.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../profiles/profile_pages.dart';
import '../recording/record_pages.dart';
import 'product_widgets.dart';

class ProductLabelPanel extends ConsumerWidget {
  const ProductLabelPanel({super.key, required this.item});
  final SubstanceItem item;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (item.unit != 'ml') return const SizedBox.shrink();
    final t = AppLocalizations.of(context);
    final key = (personId: item.personId, itemId: item.id);
    return ref
        .watch(productLabelProvider(key))
        .when(
          loading: () => Text(t.loadingRecords),
          error: (_, _) => LoadFailure(
            onRetry: () => ref.invalidate(productLabelProvider(key)),
          ),
          data: (label) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Heading(t.productLabelHeading),
              if (label == null)
                Text(t.productNoLabel)
              else
                ProductLabelView(label: label),
              Text(t.productLabelHelp),
              VitalButton.secondary(
                onPressed: () =>
                    context.push('/products/${item.personId}/label/${item.id}'),
                child: Text(t.productLabelAction),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
  }
}

class ProductLabelForm extends ConsumerStatefulWidget {
  const ProductLabelForm({
    super.key,
    required this.personId,
    required this.itemId,
  });
  final String personId, itemId;
  @override
  ConsumerState<ProductLabelForm> createState() => _ProductLabelFormState();
}

class _ProductLabelFormState extends DurableFormState<ProductLabelForm> {
  late final editor = ProductEditorData(entryChanged);
  AdultProfile? owner;
  SubstanceItem? item;
  int? productRevision;
  bool initialised = false;
  @override
  DraftKind get entryKind => DraftKind.productLabel;
  @override
  String? get entryPerson => widget.personId;
  @override
  int? get entryPersonRevision => owner?.revision;
  @override
  String? get entryTarget => widget.itemId;
  @override
  int? get entryTargetRevision => item?.revision;
  @override
  Map<String, String> captureEntry() => {
    'productComponents': editor.encode(),
    'productRevision': productRevision?.toString() ?? '',
  };
  @override
  void restoreEntry(Map<String, String> fields) {
    editor.restore(fields['productComponents'] ?? '[]');
    productRevision = int.tryParse(fields['productRevision'] ?? '');
  }

  @override
  void dispose() {
    editor.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final t = AppLocalizations.of(context);
    late final List<ProductComponent> components;
    try {
      components = editor.components();
    } catch (_) {
      setState(() => error = t.productIngredientInvalid);
      return;
    }
    await commit((command) async {
      await (await ref.read(recordStoreProvider.future)).saveProductLabel(
        commandId: command,
        personId: widget.personId,
        expectedPersonRevision: capturedPersonRevision!,
        expectedGeneration: capturedGeneration!,
        itemId: widget.itemId,
        expectedItemRevision: capturedTargetRevision!,
        expectedProductRevision: productRevision ?? 0,
        components: components,
      );
    }, successPath: '/item/${widget.itemId}');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context),
        people = ref.watch(profilesProvider),
        current = ref.watch(itemLookupProvider(widget.itemId)),
        label = ref.watch(
          productLabelProvider((
            personId: widget.personId,
            itemId: widget.itemId,
          )),
        );
    if (people.hasError || current.hasError || label.hasError) {
      return EntryPage(
        children: [
          LoadFailure(
            onRetry: () {
              ref.invalidate(profilesProvider);
              ref.invalidate(itemLookupProvider(widget.itemId));
              ref.invalidate(
                productLabelProvider((
                  personId: widget.personId,
                  itemId: widget.itemId,
                )),
              );
            },
          ),
        ],
      );
    }
    if (!people.hasValue || !current.hasValue || !label.hasValue) {
      return EntryPage(children: [Text(t.loadingRecords)]);
    }
    final liveOwner = people.value!
        .where((p) => p.id == widget.personId)
        .firstOrNull;
    if (liveOwner == null ||
        current.value == null ||
        current.value!.personId != widget.personId ||
        current.value!.unit != 'ml') {
      dirty = false;
      return EntryPage(children: [Text(t.draftUnavailable)]);
    }
    if (!initialised) {
      owner = liveOwner;
      item = current.value;
      productRevision = label.value?.revision;
      editor.initialise(label.value?.components);
      initialised = true;
    }
    if (!prepareDraft()) return EntryPage(children: [Text(t.loadingRecords)]);
    final valid =
        !liveOwner.isArchived &&
        liveOwner.revision == capturedPersonRevision &&
        current.value!.revision == capturedTargetRevision &&
        label.value?.revision == productRevision;
    final enabled = valid && !busy && !uncertain && !conflict;
    return wrap([
      Heading(t.productLabelHeading),
      Text(t.profileOwner(ownerLabel(ref, t, widget.personId))),
      Text(item!.name),
      Text(t.productLabelHelp),
      if (!valid) Text(t.conflictFailure),
      ProductComponentEditor(
        data: editor,
        enabled: enabled,
        error: error == t.productIngredientInvalid ? error : null,
        onChanged: () => setState(() {}),
      ),
      ?failure(),
      VitalButton(
        onPressed: !busy && (uncertain || (valid && !conflict)) ? save : null,
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
