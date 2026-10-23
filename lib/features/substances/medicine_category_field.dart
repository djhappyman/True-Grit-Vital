import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/app_lock.dart';
import '../../app/storage.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import '../recording/record_pages.dart' show LabelledInput;

final _medicineCategoriesProvider = StreamProvider.autoDispose
    .family<List<PersonalItemType>, String>(retry: (_, _) => null, (
      ref,
      personId,
    ) async* {
      final store = await ref.watch(recordStoreProvider.future);
      await for (final first in store.watchItemTypes(
        personId: personId,
        limit: 500,
      )) {
        final types = [...first];
        var page = first;
        while (page.length == 500) {
          page = await store.itemTypes(
            personId: personId,
            limit: 500,
            offset: types.length,
          );
          types.addAll(page);
        }
        yield types;
      }
    });

/// Personal grouping reuses the existing saved type and guarded item command.
/// A new name is part of the item draft until the medicine is saved.
class MedicineCategoryField extends ConsumerWidget {
  const MedicineCategoryField({
    super.key,
    required this.personId,
    required this.value,
    required this.enabled,
    required this.onSelected,
  });
  final String personId, value;
  final bool enabled;
  final void Function(String name, PersonalItemType? type) onSelected;

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    if (!enabled || ref.read(appLockProvider).locked) return;
    final lock = ref.read(appLockProvider);
    final generation = ref.read(recordStoreProvider).value?.generation;
    final name = await showVitalDialog<String>(
      context: context,
      builder: (_) => const _CategoryNameDialog(),
    );
    if (!context.mounted ||
        name == null ||
        !identical(ref.read(appLockProvider), lock) ||
        ref.read(appLockProvider).locked ||
        ref.read(recordStoreProvider).value?.generation != generation) {
      return;
    }
    final current = context.widget;
    if (current is! MedicineCategoryField ||
        !current.enabled ||
        current.value != value) {
      return;
    }
    final types = ref.read(_medicineCategoriesProvider(personId)).value ?? [];
    final existing = types
        .where((type) => type.name.toLowerCase() == name.toLowerCase())
        .firstOrNull;
    final preset = _choices(AppLocalizations.of(context))
        .where((choice) => choice.$1.toLowerCase() == name.toLowerCase())
        .firstOrNull;
    onSelected(existing?.name ?? preset?.$1 ?? name, existing);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context), c = VitalColors(context);
    final choices = _choices(t);
    final types = ref.watch(_medicineCategoriesProvider(personId));
    final saved = types.value ?? const <PersonalItemType>[];
    final selected = value == t.dashboardMedicineType ? '' : value;
    final names = <String>{
      '',
      ...choices.map((choice) => choice.$1),
      ...saved
          .where((type) => type.name != t.dashboardMedicineType)
          .map((type) => type.name),
      if (selected.isNotEmpty) selected,
    }.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.medicineCategory, style: VitalType.label),
        const SizedBox(height: 4),
        Text(
          t.medicineCategoryHelp,
          style: VitalType.metadata.copyWith(color: c.muted),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: VitalSelect<String>(
            label: t.medicineCategory,
            value: selected,
            values: names,
            enabled: enabled && types.hasValue,
            labelOf: (name) => name.isEmpty ? t.medicineCategoryNone : name,
            selectedLabelOf: (name) => !types.hasValue
                ? t.loadingRecords
                : name.isEmpty
                ? t.medicineCategoryChoose
                : choices
                          .where((choice) => choice.$1 == name)
                          .firstOrNull
                          ?.$3 ??
                      name,
            subtitleOf: (name) => name.isEmpty
                ? t.medicineCategoryNoneHint
                : choices
                          .where((choice) => choice.$1 == name)
                          .firstOrNull
                          ?.$2 ??
                      t.medicineCategoryCustomHint,
            onChanged: (name) {
              final actual = name.isEmpty ? t.dashboardMedicineType : name;
              onSelected(
                actual,
                saved.where((type) => type.name == actual).firstOrNull,
              );
            },
            footerBuilder: (popupContext) => Padding(
              padding: const EdgeInsets.only(top: 12),
              child: VitalButton.secondary(
                leading: const Icon(LucideIcons.plus, size: 18),
                onPressed: !enabled
                    ? null
                    : () {
                        SelectPopupHandle.of(popupContext).close();
                        _create(context, ref);
                      },
                child: Text(t.medicineCategoryCreate),
              ),
            ),
          ),
        ),
        if (types.hasError)
          VitalButton.secondary(
            onPressed: () =>
                ref.invalidate(_medicineCategoriesProvider(personId)),
            child: Text(t.retry),
          ),
      ],
    );
  }
}

class _CategoryNameDialog extends ConsumerStatefulWidget {
  const _CategoryNameDialog();
  @override
  ConsumerState<_CategoryNameDialog> createState() =>
      _CategoryNameDialogState();
}

class _CategoryNameDialogState extends ConsumerState<_CategoryNameDialog> {
  final name = TextEditingController();
  late final lock = ref.read(appLockProvider);
  late final generation = ref.read(recordStoreProvider).value?.generation;
  String? error;
  @override
  void initState() {
    super.initState();
    lock;
    generation;
  }

  void _dismiss() {
    final route = ModalRoute.of(context);
    if (route != null && route.isActive) {
      Navigator.of(context).removeRoute(route);
    }
  }

  void _submit() {
    if (ref.read(appLockProvider).locked ||
        !identical(ref.read(appLockProvider), lock) ||
        ref.read(recordStoreProvider).value?.generation != generation) {
      _dismiss();
      return;
    }
    final value = name.text.trim(), t = AppLocalizations.of(context);
    if (value.isEmpty || value.length > 500) {
      setState(
        () =>
            error = value.isEmpty ? t.nameRequired : t.medicineCategoryNameLong,
      );
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    ref.listen(appLockProvider, (before, after) {
      if (after.locked && before?.locked != true) _dismiss();
    });
    ref.listen(recordStoreProvider.select((state) => state.value?.generation), (
      before,
      after,
    ) {
      if (before != null && before != after) _dismiss();
    });
    return VitalDialog(
      title: Text(t.medicineCategoryNew),
      content: LabelledInput(
        label: t.dashboardName,
        controller: name,
        error: error,
      ),
      actions: [
        VitalButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.cancel),
        ),
        VitalButton(onPressed: _submit, child: Text(t.create)),
      ],
    );
  }
}

List<(String, String, String)> _choices(AppLocalizations t) => [
  (t.medicineCategoryPain, t.medicineCategoryPainHint, t.medicineCategoryPain),
  (
    t.medicineCategoryAllergy,
    t.medicineCategoryAllergyHint,
    t.medicineCategoryAllergy,
  ),
  (
    t.medicineCategoryHeart,
    t.medicineCategoryHeartHint,
    t.medicineCategoryHeartShort,
  ),
  (
    t.medicineCategoryDiabetes,
    t.medicineCategoryDiabetesHint,
    t.medicineCategoryDiabetesShort,
  ),
  (
    t.medicineCategoryDigestion,
    t.medicineCategoryDigestionHint,
    t.medicineCategoryDigestionShort,
  ),
  (
    t.medicineCategoryMood,
    t.medicineCategoryMoodHint,
    t.medicineCategoryMoodShort,
  ),
  (
    t.medicineCategoryInfections,
    t.medicineCategoryInfectionsHint,
    t.medicineCategoryInfections,
  ),
  (
    t.medicineCategoryBreathing,
    t.medicineCategoryBreathingHint,
    t.medicineCategoryBreathingShort,
  ),
  (
    t.medicineCategoryVitamins,
    t.medicineCategoryVitaminsHint,
    t.medicineCategoryVitaminsShort,
  ),
  (
    t.medicineCategoryPeds,
    t.medicineCategoryPedsHint,
    t.medicineCategoryPedsShort,
  ),
];
